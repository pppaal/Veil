import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/identity/identity_key_value_backend.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_resolver.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_store.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/local_notice.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

import '../support/async_wait.dart';
import '../support/counting_crypto_adapter.dart';
import '../support/fake_relay.dart';
import '../support/mock_relay_parties.dart';
import '../support/strict_mock_crypto_adapter.dart';

const conv = 'conv-1';

String _key(String label) => base64Url.encode(utf8.encode(label)).replaceAll('=', '');

// Outbound trust on first use: atlas pinned selene's device earlier, and the
// directory now answers with something else.
void main() {
  late FakeRelay relay;
  late IdentityTrust trust;
  late CountingCryptoAdapter crypto;
  late VeilMessengerController atlas;
  late List<PendingIdentityChange> announced;

  String seleneKey() => relay.partiesByHandle['selene']!.identity.identityPublicKey;

  setUp(() async {
    relay = FakeRelay();
    seedMockParties(relay, conv, ['atlas', 'selene']);
    trust = IdentityTrust(TrustedIdentityResolver(store: TrustedIdentityStore(InMemoryIdentityKeyValueBackend())));
    crypto = CountingCryptoAdapter(StrictMockCryptoAdapter(localDeviceId: 'dev-atlas'));
    atlas = mockPartyController(relay, 'atlas', adapter: crypto, identityTrust: trust);
    addTearDown(atlas.dispose);
    announced = [];
    final subscription = atlas.identityChanges.listen(announced.add);
    addTearDown(subscription.cancel);
    await atlas.applySession(mockPartySession('atlas'));
    await trust.resolver.evaluate('user-selene', 'dev-selene', seleneKey());
  });

  void serveSelene({String? deviceId, required String identityKey}) {
    relay.bundleOverrides['selene'] = {
      ...relay.partiesByHandle['selene']!.bundleJson,
      if (deviceId != null) 'deviceId': deviceId,
      'identityPublicKey': identityKey,
    };
  }

  Future<List<String>> noticeCodes() async => [
        for (final message in atlas.messagesFor(conv))
          if (message.isLocalNotice) (await atlas.decryptMessage(message)).body,
      ];

  test('changed identity key for same device blocks send and emits notice without bootstrap', () async {
    serveSelene(identityKey: _key('server-chosen key'));

    await atlas.sendText(conversationId: conv, body: 'are you you?');
    await atlas.sendText(conversationId: conv, body: 'still asking');
    await settle();

    expect(crypto.counts.bootstrap, 0);
    expect(relay.conversations[conv]!.messages, isEmpty);
    final change = atlas.pendingIdentityChangeFor(conv)!;
    expect(change.presentedKey, _key('server-chosen key'));
    expect(change.previousKey, seleneKey());
    expect(change.requiresReverification, isFalse);
    expect(announced, hasLength(1));
    expect(await noticeCodes(), [LocalNoticeCodes.identityChanged]);
    // The issue is the conversation's, not a global banner.
    expect(atlas.errorMessage, isNull);
    expect((await trust.resolver.pinFor('user-selene', 'dev-selene'))!.identityKey, seleneKey());
  });

  test('approve then send succeeds', () async {
    serveSelene(identityKey: _key('reinstalled key'));
    await atlas.sendText(conversationId: conv, body: 'blocked');
    await settle();
    expect(atlas.pendingIdentityChangeFor(conv), isNotNull);

    await atlas.approveIdentityChange(conv);
    await atlas.sendText(conversationId: conv, body: 'after approval');
    await waitFor(() => relay.conversations[conv]!.messages.length == 1, reason: 'the send stayed blocked');

    expect(atlas.pendingIdentityChangeFor(conv), isNull);
    expect(crypto.counts.bootstrap, 1);
    expect((await trust.resolver.pinFor('user-selene', 'dev-selene'))!.identityKey, _key('reinstalled key'));
    final session = atlas.conversations.firstWhere((item) => item.id == conv).sessionState!;
    expect(session.remoteIdentityPublicKey, _key('reinstalled key'));
  });

  test('approving a change makes every chat with the contact ask the directory again', () async {
    relay.addDirect('conv-2', 'atlas', 'selene');
    await atlas.refreshConversations();
    await atlas.sendText(conversationId: 'conv-2', body: 'before the reinstall');
    await waitFor(() => relay.conversations['conv-2']!.messages.length == 1);
    // selene reinstalled; the first chat to meet her new key holds it back.
    serveSelene(identityKey: _key('reinstalled key'));
    expect(await trust.admit(conv, 'user-selene', 'dev-selene', _key('reinstalled key')), isFalse);

    await atlas.approveIdentityChange(conv);
    await atlas.sendText(conversationId: 'conv-2', body: 'after approval');
    await waitFor(() => relay.conversations['conv-2']!.messages.length == 2);

    final session = atlas.conversationById('conv-2')!.sessionState!;
    expect(session.remoteIdentityPublicKey, _key('reinstalled key'), reason: 'the session to the replaced key is gone');
  });

  test('verified contact key change requires reverification', () async {
    await trust.resolver.markVerified('user-selene', 'dev-selene', seleneKey());
    serveSelene(identityKey: _key('unverified replacement'));
    await atlas.sendText(conversationId: conv, body: 'blocked');
    await settle();

    expect(atlas.pendingIdentityChangeFor(conv)!.requiresReverification, isTrue);
    await expectLater(atlas.approveIdentityChange(conv), throwsStateError);
    expect(atlas.pendingIdentityChangeFor(conv), isNotNull);
    expect(relay.conversations[conv]!.messages, isEmpty);

    // The user compared the new safety number out of band.
    await atlas.approveIdentityChange(conv, reverified: true, reviewed: atlas.pendingIdentityChangeFor(conv));
    final pin = (await trust.resolver.pinFor('user-selene', 'dev-selene'))!;
    expect(pin.identityKey, _key('unverified replacement'));
    expect(pin.isVerified, isTrue);
    await atlas.sendText(conversationId: conv, body: 'verified again');
    await waitFor(() => relay.conversations[conv]!.messages.length == 1);
  });

  test('an approval accepts only the change the user reviewed', () async {
    await trust.resolver.markVerified('user-selene', 'dev-selene', seleneKey());
    expect(await trust.admit(conv, 'user-selene', 'dev-selene', _key('key the user compared')), isFalse);
    final reviewed = atlas.pendingIdentityChangeFor(conv)!;
    // While the user compares, the relay presents a key of its own.
    expect(await trust.admit(conv, 'user-selene', 'dev-selene', _key('relay key')), isFalse);

    await expectLater(atlas.approveIdentityChange(conv, reverified: true, reviewed: reviewed), throwsStateError);
    // A re-verification that names no key attests to nothing.
    await expectLater(atlas.approveIdentityChange(conv, reverified: true), throwsStateError);

    final pin = (await trust.resolver.pinFor('user-selene', 'dev-selene'))!;
    expect(pin.identityKey, seleneKey());
    expect(pin.isVerified, isTrue);
    expect(atlas.pendingIdentityChangeFor(conv)!.presentedKey, _key('relay key'));
    expect(announced.map((change) => change.presentedKey), [_key('key the user compared'), _key('relay key')]);
  });

  test('new device for known user produces notice', () async {
    serveSelene(deviceId: 'dev-selene-2', identityKey: _key('second phone'));

    await atlas.sendText(conversationId: conv, body: 'hello new phone');
    await waitFor(() => relay.conversations[conv]!.messages.length == 1, reason: 'an unverified contact device must not block');

    expect(atlas.pendingIdentityChangeFor(conv), isNull);
    expect(await noticeCodes(), [LocalNoticeCodes.identityNewDevice]);
    expect((await trust.resolver.pinFor('user-selene', 'dev-selene-2'))!.identityKey, _key('second phone'));
    expect(crypto.counts.bootstrap, 1);
  });

  test('one new device presented under two keys at once is admitted under one', () async {
    final admitted = await Future.wait([
      trust.admit(conv, 'user-selene', 'dev-selene-2', _key('second phone')),
      trust.admit(conv, 'user-selene', 'dev-selene-2', _key('relay twin')),
    ]);

    expect(admitted, [true, false]);
    expect((await trust.resolver.pinFor('user-selene', 'dev-selene-2'))!.identityKey, _key('second phone'));
    expect(atlas.pendingIdentityChangeFor(conv)!.presentedKey, _key('relay twin'));
  });

  test('a new device of a verified contact waits for approval', () async {
    await trust.resolver.markVerified('user-selene', 'dev-selene', seleneKey());
    serveSelene(deviceId: 'dev-selene-2', identityKey: _key('second phone'));

    await atlas.sendText(conversationId: conv, body: 'hello?');
    await settle();

    final change = atlas.pendingIdentityChangeFor(conv)!;
    expect(change.previousKey, isNull, reason: 'a new device replaces no pin');
    expect(change.requiresReverification, isTrue);
    expect(crypto.counts.bootstrap, 0);
    expect(await noticeCodes(), [LocalNoticeCodes.identityChanged]);
  });

  test('a peer system message never renders as a local notice', () async {
    final selene = mockPartyController(relay, 'selene');
    addTearDown(selene.dispose);
    await selene.applySession(mockPartySession('selene'));
    await selene.sendSystemNotice(conversationId: conv, body: LocalNoticeCodes.identityChanged);
    await waitFor(() => atlas.messagesFor(conv).isNotEmpty);

    expect(atlas.messagesFor(conv).single.isLocalNotice, isFalse);
    expect((await atlas.decryptMessage(atlas.messagesFor(conv).single)).messageKind, MessageKind.system);
  });

  test('a reaction held back by an identity change is not shown', () async {
    final selene = mockPartyController(relay, 'selene');
    addTearDown(selene.dispose);
    await selene.applySession(mockPartySession('selene'));
    await selene.sendText(conversationId: conv, body: 'react to me');
    await waitFor(() => atlas.messagesFor(conv).isNotEmpty);
    expect(await trust.admit(conv, 'user-selene', 'dev-selene', _key('server-chosen key')), isFalse);
    // The send needs the directory, which serves the refused key: a change
    // holds back only a send that would need it.
    serveSelene(identityKey: _key('server-chosen key'));

    final target = atlas.messagesFor(conv).firstWhere((message) => !message.isLocalNotice);
    await atlas.toggleReaction(target, '🎉');
    await settle();

    expect(atlas.messagesFor(conv).firstWhere((message) => message.id == target.id).reactions, isEmpty);
    expect(relay.conversations[conv]!.messages, hasLength(1));
    expect(atlas.errorMessage, isNull);
  });

  test('a relayed row under the local notice id prefix is dropped', () async {
    final selene = mockPartyController(relay, 'selene');
    addTearDown(selene.dispose);
    await selene.applySession(mockPartySession('selene'));
    await selene.sendSystemNotice(conversationId: conv, body: LocalNoticeCodes.identityChanged);
    await waitFor(() => atlas.messagesFor(conv).isNotEmpty);

    // The relay replays selene's row under an id that claims to be local,
    // live and in history.
    final forged = Map<String, dynamic>.of(relay.conversations[conv]!.messages.single)
      ..['id'] = 'notice:${LocalNoticeCodes.identityChanged}:$conv:forged'
      ..['conversationOrder'] = 2;
    relay.conversations[conv]!.messages.add(forged);
    relay.realtimeFor('atlas').deliver('message.new', forged);
    await atlas.loadConversationMessages(conv);
    await settle();

    expect(atlas.messagesFor(conv), hasLength(1));
    expect(atlas.messagesFor(conv).where((message) => message.isLocalNotice), isEmpty);
  });
}
