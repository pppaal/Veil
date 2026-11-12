import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/crypto/random_source.dart';
import 'package:veil_mobile/src/core/crypto/ratchet/frame_codec.dart';
import 'package:veil_mobile/src/core/crypto/ratchet/legacy_session.dart';
import 'package:veil_mobile/src/core/crypto/ratchet/session_record.dart';
import 'package:veil_mobile/src/core/crypto/x3dh/curve25519.dart';
import 'package:veil_mobile/src/core/crypto/x3dh/identity_keys.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/local_notice.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/injected_device.dart';
import '../support/messenger_party.dart';

// A relay that lies: it plants sessions, relabels conversations, invents
// devices, flips a group's mode and forges key changes. Two real
// controllers with real LibCryptoAdapters talk through it; every test pins
// down one way it used to read messages or stall a conversation.

const conv = 'conv-ab';

void main() {
  late FakeRelay relay;
  late MessengerParty alice;
  late MessengerParty bob;

  setUp(() async {
    relay = FakeRelay();
    alice = await MessengerParty.join(relay, handle: 'alice', userId: 'user-alice', deviceId: 'dev-alice');
    bob = await MessengerParty.join(relay, handle: 'bob', userId: 'user-bob', deviceId: 'dev-bob');
    relay.addDirect(conv, 'alice', 'bob');
    await alice.signIn();
    await bob.signIn();
  });

  tearDown(() async {
    await alice.dispose();
    await bob.dispose();
  });

  Future<void> deliver(MessengerParty from, MessengerParty to, String body, {String conversationId = conv}) async {
    await from.controller.sendText(conversationId: conversationId, body: body);
    await waitFor(() => from.controller.pendingCountFor(conversationId) == 0, reason: '"$body" was not acked');
    await waitFor(
      () async => (await to.bodies(conversationId)).contains(body),
      reason: '"$body" is not readable by ${to.device.handle}',
    );
  }

  Future<DecryptedMessage> openRelayed(
    MessengerParty party,
    Map<String, dynamic> envelope, {
    String conversationId = conv,
  }) async {
    await party.controller.loadConversationMessages(conversationId);
    final row = party.controller
        .messagesFor(conversationId)
        .firstWhere((m) => m.envelope.ciphertext == envelope['ciphertext']);
    final opened = await party.controller.decryptMessage(row);
    await settle();
    return opened;
  }

  Map<String, dynamic> lastRelayed(String conversationId) => relay.conversations[conversationId]!.messages.last;

  int noticesIn(MessengerParty party, String conversationId) =>
      party.controller.messagesFor(conversationId).where((m) => m.isLocalNotice).length;

  Future<void> verify(MessengerParty party, MessengerParty contact) async {
    final served = await party.controller.fetchPeerKeyBundle(contact.device.handle);
    await party.pins.markVerified(contact.device.userId, served.deviceId, served.identityPublicKey);
  }

  /// A legacy v1 session the relay builds in [as]'s name towards [to], from
  /// nothing but [to]'s published identity: an adapter only the relay holds.
  Future<LibCryptoAdapter> plantLegacySession(MessengerParty as, MessengerParty to, String conversationId) async {
    final published = await verifyRemoteBundle(
      to.device.identity.signedPrekeyBundle,
      to.device.identity.identityPublicKey,
      now: DateTime.now(),
    ) as PrekeyBundleV2;
    final state = await initiateLegacySession(
      SessionBootstrapRequest(
        conversationId: conversationId,
        localDeviceId: as.device.deviceId,
        localUserId: as.device.userId,
        remoteUserId: to.device.userId,
        remoteDeviceId: to.device.deviceId,
        remoteIdentityPublicKey: to.device.identity.identityPublicKey,
        remoteSignedPrekeyBundle: '',
      ),
      LegacyPrekeyBundle(published.ikx),
      SecureRandomSource(),
      DateTime.now(),
    );
    final server = LibCryptoAdapter();
    await server.restoreSessionsFromSnapshots({conversationId: SessionRecord(rev: 1, current: state).toSnapshot()});
    return server;
  }

  Future<Map<String, dynamic>> relayLegacyFrame(
    LibCryptoAdapter server,
    MessengerParty as,
    String body,
    String conversationId,
  ) async {
    final forged = await server.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: as.device.deviceId,
      recipientUserId: '',
      body: body,
      messageKind: MessageKind.text,
      recipientBundle: const KeyBundle(userId: '', deviceId: '', handle: '', identityPublicKey: '', signedPrekeyBundle: ''),
    );
    expect(forged.version, envelopeVersionLegacy);
    final envelope = server.envelopeCodec.encodeApiEnvelope(forged);
    relay.inject(senderHandle: as.device.handle, conversationId: conversationId, envelope: envelope);
    return envelope;
  }

  Future<DecryptedMessage> serverReads(LibCryptoAdapter server, Map<String, dynamic> relayed) =>
      server.messaging.decryptMessage(server.envelopeCodec.decodeApiEnvelope(relayed));

  test('a legacy frame the relay plants in a fresh 1:1 opens nothing, and the reply stays v2', () async {
    await deliver(alice, bob, 'hello');
    await deliver(bob, alice, 'hi');
    await verify(alice, bob);

    const fresh = 'conv-ab-new';
    relay.addDirect(fresh, 'alice', 'bob');
    await alice.controller.refreshConversations();
    final server = await plantLegacySession(bob, alice, fresh);
    final planted = await relayLegacyFrame(server, bob, 'please reply with the code', fresh);

    final opened = await openRelayed(alice, planted, conversationId: fresh);
    expect(opened.status, DecryptStatus.sessionMissing);
    expect(opened.body, isEmpty);
    expect(alice.controller.conversationById(fresh)!.sessionState, isNull);

    await deliver(alice, bob, 'the code is 4711', conversationId: fresh);
    expect(lastRelayed(fresh)['version'], envelopeVersionV2);
    final read = await serverReads(server, lastRelayed(fresh));
    expect(read.isOk, isFalse);
    expect(read.body, isEmpty);
  });

  test('the relay cannot relabel an established 1:1 as being with another contact', () async {
    final carol = await MessengerParty.join(relay, handle: 'carol', userId: 'user-carol', deviceId: 'dev-carol');
    addTearDown(carol.dispose);
    relay.addDirect('conv-ac', 'alice', 'carol');
    await carol.signIn();
    await alice.controller.refreshConversations();
    await deliver(alice, carol, 'hi carol', conversationId: 'conv-ac');
    await verify(alice, carol);
    await deliver(alice, bob, 'hello bob');
    await deliver(bob, alice, 'hi alice');

    // The relay now lists conv-ab as alice and carol.
    relay.conversations[conv]!.memberHandles
      ..clear()
      ..addAll(['alice', 'carol']);
    await alice.controller.refreshConversations();

    final view = alice.controller.conversationById(conv)!;
    expect(view.peerHandle, 'bob');
    expect(view.recipientBundle.userId, bob.device.userId);
    expect(view.recipientBundle.identityPublicKey, bob.device.identity.identityPublicKey);
    // What it shows is what it encrypts to.
    relay.conversations[conv]!.memberHandles.add('bob');
    await deliver(alice, bob, 'still for bob');
  });

  test('a stranger the relay relabels as a verified contact stays the stranger', () async {
    final carol = await MessengerParty.join(relay, handle: 'carol', userId: 'user-carol', deviceId: 'dev-carol');
    final mallory = await MessengerParty.join(relay, handle: 'mallory', userId: 'user-mallory', deviceId: 'dev-mal');
    addTearDown(carol.dispose);
    addTearDown(mallory.dispose);
    relay.addDirect('conv-ac', 'alice', 'carol');
    await carol.signIn();
    await alice.controller.refreshConversations();
    await deliver(alice, carol, 'hi carol', conversationId: 'conv-ac');
    await verify(alice, carol);

    // A relay account writes once; alice never answers. Then the relay lists
    // that conversation as one with carol.
    relay.addDirect('conv-am', 'mallory', 'alice');
    await mallory.signIn();
    await deliver(mallory, alice, 'hey', conversationId: 'conv-am');
    relay.conversations['conv-am']!.memberHandles
      ..clear()
      ..addAll(['alice', 'carol']);
    await alice.controller.refreshConversations();

    final view = alice.controller.conversationById('conv-am')!;
    expect(view.peerHandle, 'mallory');
    expect(view.recipientBundle.userId, mallory.device.userId);
  });

  group('a 1:1 the relay leaves out of one list and lists again with a verified contact', () {
    late MessengerParty carol;
    late MessengerParty mallory;

    // Alice has verified carol. mallory, a relay account, writes 'hey' in
    // conv-am and alice never answers. The relay then leaves conv-am out of
    // one list, so alice keeps no preview of it, only its session.
    setUp(() async {
      carol = await MessengerParty.join(relay, handle: 'carol', userId: 'user-carol', deviceId: 'dev-carol');
      mallory = await MessengerParty.join(relay, handle: 'mallory', userId: 'user-mallory', deviceId: 'dev-mal');
      relay.addDirect('conv-ac', 'alice', 'carol');
      await carol.signIn();
      await alice.controller.refreshConversations();
      await deliver(alice, carol, 'hi carol', conversationId: 'conv-ac');
      await verify(alice, carol);
      relay.addDirect('conv-am', 'mallory', 'alice');
      await mallory.signIn();
      await deliver(mallory, alice, 'hey', conversationId: 'conv-am');

      final hidden = relay.conversations.remove('conv-am')!;
      await alice.controller.refreshConversations();
      expect(alice.controller.conversationById('conv-am'), isNull);
      expect(alice.lib.sessions.hasSessionFor('conv-am'), isTrue);
      relay.conversations['conv-am'] = RelayConversation(
        id: 'conv-am',
        type: 'direct',
        memberHandles: ['alice', 'carol', 'mallory'],
        createdAt: hidden.createdAt,
      )..messages.addAll(hidden.messages);
    });

    tearDown(() async {
      await carol.dispose();
      await mallory.dispose();
    });

    // Lists conv-am as alice and carol; the relay keeps mallory on it
    // behind alice's back, so mallory gets every frame sent there.
    Future<void> relistWithCarol() async {
      relay.conversations['conv-am']!.memberHandles.remove('mallory');
      await alice.controller.refreshConversations();
      relay.conversations['conv-am']!.memberHandles.add('mallory');
    }

    test('comes back as the stranger it is with', () async {
      await relistWithCarol();

      final view = alice.controller.conversationById('conv-am')!;
      expect(view.peerHandle, 'mallory');
      expect(view.recipientBundle.userId, mallory.device.userId);
      expect(await alice.bodies('conv-am'), contains('hey'));
      // What it shows is what it encrypts to, also across a restart, and it
      // keeps the session it has: the directory confirms the same peer.
      await alice.restart();
      await settle();
      expect(alice.controller.conversationById('conv-am')!.peerHandle, 'mallory');
      await deliver(alice, mallory, 'who are you?', conversationId: 'conv-am');
      final reply = alice.lib.envelopeCodec.decodeApiEnvelope(lastRelayed('conv-am'));
      expect(FrameV2.decode(b64uDecode(reply.ciphertext)).preKey, isNull);
    });

    test('without its binding, sends to the contact it shows and refuses the old peer', () async {
      // As if the binding was never recorded (an install from before it was)
      // and the cached preview was lost: only the session is left.
      await alice.keystore.scoped(SecureScope.conversationPolicy).delete('direct_peers.v1');
      await (alice.database.delete(alice.database.cachedConversations)..where((row) => row.id.equals('conv-am'))).go();
      await alice.restart();
      await relistWithCarol();
      expect(alice.controller.conversationById('conv-am')!.peerHandle, 'carol');

      await alice.controller.sendText(conversationId: 'conv-am', body: 'carol: the door code is 1234');
      await waitFor(() => alice.controller.pendingCountFor('conv-am') == 0, reason: 'the send was not acked');
      expect(lastRelayed('conv-am')['version'], envelopeVersionV2);
      await mallory.controller.loadConversationMessages('conv-am');
      await settle();
      expect(await mallory.bodies('conv-am'), isNot(contains('carol: the door code is 1234')));
      await carol.controller.refreshConversations();
      await carol.controller.loadConversationMessages('conv-am');
      await waitFor(
        () async => (await carol.bodies('conv-am')).contains('carol: the door code is 1234'),
        reason: 'carol cannot read what alice sent her',
      );

      // mallory's session no longer speaks for this conversation.
      await mallory.controller.sendText(conversationId: 'conv-am', body: 'it is carol, really');
      await waitFor(() => mallory.controller.pendingCountFor('conv-am') == 0, reason: 'mallory was not acked');
      final forged = await openRelayed(alice, lastRelayed('conv-am'), conversationId: 'conv-am');
      expect(forged.status, DecryptStatus.identityRejected);
      expect(forged.body, isEmpty);
    });
  });

  group('a device admitted before its contact was verified', () {
    test('that holds the 1:1 when the contact is verified elsewhere takes no reply, and its frames are refused',
        () async {
      await deliver(alice, bob, 'hello bob');
      await deliver(bob, alice, 'hi alice');
      final ghost = await InjectedDevice.mint('dev-ghost', owner: bob);
      expect((await openRelayed(alice, await ghost.handshake(relay, alice, 'ghost hello', conversationId: conv))).status,
          DecryptStatus.ok);
      expect(noticesIn(alice, conv), 1);
      // The directory names the ghost, and the reply goes to it: trust on
      // first use while bob is unverified.
      relay.bundleOverrides['bob'] = ghost.bundleJson;
      await alice.controller.sendText(conversationId: conv, body: 'to the ghost while bob is unverified');
      await waitFor(() => alice.controller.pendingCountFor(conv) == 0, reason: 'the send was not acked');
      expect(alice.controller.conversationById(conv)!.sessionState!.remoteDeviceId, 'dev-ghost');

      // Alice verifies dev-bob somewhere other than this chat. The directory
      // keeps naming the ghost.
      await alice.pins.markVerified('user-bob', 'dev-bob', bob.device.identity.identityPublicKey);
      final before = relay.conversations[conv]!.messages.length;
      await alice.controller.sendText(conversationId: conv, body: 'after verifying bob');
      await settle();

      expect(relay.conversations[conv]!.messages, hasLength(before));
      final held = alice.controller.pendingIdentityChangeFor(conv)!;
      expect(held.deviceId, 'dev-ghost');
      expect(held.requiresReverification, isTrue);
      expect(noticesIn(alice, conv), 2);
      final frame = await ghost.send(relay, alice, 'ghost after verification', conversationId: conv);
      expect((await openRelayed(alice, frame)).status, DecryptStatus.identityRejected);

      // Once the directory names dev-bob again, the next reply goes to bob.
      relay.bundleOverrides.remove('bob');
      await deliver(alice, bob, 'to the bob I verified');
      expect((await ghost.open(lastRelayed(conv))).isOk, isFalse);
    });

    test('takes no reply after it, through a new handshake', () async {
      await deliver(alice, bob, 'hello bob');
      await deliver(bob, alice, 'hi alice');
      final ghost = await InjectedDevice.mint('dev-ghost', owner: bob);
      final first = await ghost.handshake(relay, alice, 'ghost hello', conversationId: conv);
      expect((await openRelayed(alice, first)).status, DecryptStatus.ok);
      expect(noticesIn(alice, conv), 1);
      await deliver(alice, bob, 'secret for bob');
      await verify(alice, bob);

      // The ghost opens a fresh session and the directory calls it active.
      final again = await ghost.handshake(relay, alice, 'ghost again', conversationId: conv);
      expect((await openRelayed(alice, again)).status, DecryptStatus.identityRejected);
      relay.bundleOverrides['bob'] = ghost.bundleJson;
      await alice.controller.sendText(conversationId: conv, body: 'after verifying bob');
      await settle();

      final held = alice.controller.pendingIdentityChangeFor(conv)!;
      expect(held.deviceId, 'dev-ghost');
      expect(held.requiresReverification, isTrue);
      expect(noticesIn(alice, conv), 2);
      expect((await ghost.open(lastRelayed(conv))).isOk, isFalse);
      expect(alice.controller.conversationById(conv)!.sessionState!.remoteDeviceId, 'dev-bob');
    });

    test('takes no reply after it, through a frame on its earlier session', () async {
      await deliver(alice, bob, 'hello bob');
      await deliver(bob, alice, 'hi alice');
      final ghost = await InjectedDevice.mint('dev-ghost', owner: bob);
      expect((await openRelayed(alice, await ghost.handshake(relay, alice, 'ghost hello', conversationId: conv))).status,
          DecryptStatus.ok);
      await deliver(alice, bob, 'secret for bob');
      await verify(alice, bob);

      // No new handshake: one more frame on the session it opened before.
      await openRelayed(alice, await ghost.send(relay, alice, 'ghost on its old session', conversationId: conv));
      relay.bundleOverrides['bob'] = ghost.bundleJson;
      await alice.controller.sendText(conversationId: conv, body: 'reply after the old-session frame');
      await settle();

      expect(alice.controller.pendingIdentityChangeFor(conv)!.deviceId, 'dev-ghost');
      expect((await ghost.open(lastRelayed(conv))).isOk, isFalse);
    });

    test('in a group is announced in the 1:1 with that contact too, and held there once they are verified', () async {
      await deliver(alice, bob, 'hello bob');
      await deliver(bob, alice, 'hi alice');
      final ghost = await InjectedDevice.mint('dev-ghost', owner: bob);
      relay.addGroup('grp', ['alice', 'bob']);
      relay.extraDevices['bob'] = [ghost.bundleJson];
      await alice.controller.refreshConversations();
      await bob.controller.refreshConversations();
      await deliver(alice, bob, 'group hello', conversationId: 'grp');
      await settle();
      expect(noticesIn(alice, 'grp'), 1);
      expect(noticesIn(alice, conv), 1, reason: 'a new device is announced in every chat with its owner');

      await verify(alice, bob);
      final injected = await ghost.handshake(relay, alice, 'it is me on my tablet', conversationId: conv);
      expect((await openRelayed(alice, injected)).status, DecryptStatus.identityRejected);
      relay.bundleOverrides['bob'] = ghost.bundleJson;
      await alice.controller.sendText(conversationId: conv, body: '1:1 secret');
      await settle();

      expect(alice.controller.pendingIdentityChangeFor(conv)!.requiresReverification, isTrue);
      expect((await ghost.open(lastRelayed(conv))).isOk, isFalse);
    });
  });

  test('a Sender Keys group the relay reports as pairwise stays Sender Keys, across a restart', () async {
    relay.addGroup('grp', ['alice', 'bob']);
    await alice.controller.refreshConversations();
    await bob.controller.refreshConversations();
    await deliver(alice, bob, 'group hello', conversationId: 'grp');

    relay.conversations['grp']!.useSenderKeys = false;
    await alice.controller.refreshConversations();
    expect(alice.controller.conversationById('grp')!.useSenderKeys, isTrue);
    expect(
      alice.controller.messagesFor('grp').where((m) => m.id.startsWith('notice:${LocalNoticeCodes.senderKeysKept}')),
      hasLength(1),
    );

    final server = await plantLegacySession(bob, alice, 'grp');
    final planted = await relayLegacyFrame(server, bob, 'hi all', 'grp');
    expect((await openRelayed(alice, planted, conversationId: 'grp')).status, DecryptStatus.failed);
    final refused = await alice.controller.decryptEnvelope(alice.lib.envelopeCodec.decodeApiEnvelope(planted));
    expect(refused.failureReason, 'downgrade_rejected');

    await deliver(alice, bob, 'group secret', conversationId: 'grp');
    expect(lastRelayed('grp')['version'], 'veil-group-v1');
    expect((await serverReads(server, lastRelayed('grp'))).isOk, isFalse);

    // The pin outlives the app, whatever the relay keeps saying.
    await alice.restart();
    await settle();
    expect(alice.controller.conversationById('grp')!.useSenderKeys, isTrue);
    final refusedAgain = await alice.controller.decryptEnvelope(alice.lib.envelopeCodec.decodeApiEnvelope(planted));
    expect(refusedAgain.failureReason, 'downgrade_rejected');
    await alice.controller.sendText(conversationId: 'grp', body: 'after the restart');
    await waitFor(() => alice.controller.pendingCountFor('grp') == 0, reason: 'the group send was not acked');
    expect(lastRelayed('grp')['version'], 'veil-group-v1');
    expect((await serverReads(server, lastRelayed('grp'))).isOk, isFalse);
  });

  test('a handshake the responder cannot open does not wedge the 1:1, in either identity order', () async {
    final aliceIsLower = compareBytes(
          b64uDecode(alice.device.identity.identityPublicKey),
          b64uDecode(bob.device.identity.identityPublicKey),
        ) <
        0;
    final (low, high) = aliceIsLower ? (alice, bob) : (bob, alice);
    for (final (initiator, responder) in [(low, high), (high, low)]) {
      // Forgets directory answers from the previous round, which would
      // spare it the prekey claim below.
      await initiator.restart();
      final conversationId = 'conv-${initiator.device.handle}-first';
      relay.addDirect(conversationId, initiator.device.handle, responder.device.handle);
      await initiator.controller.refreshConversations();
      await responder.controller.refreshConversations();
      // The directory hands out a one-time prekey the responder no longer
      // holds, so it cannot open the initiator's handshake.
      final orphan = await generateX25519KeyPair(SecureRandomSource());
      relay.oneTimePrekeys[responder.device.deviceId] = [
        OneTimePrekey(keyId: 7, publicKey: b64uEncode(orphan.publicKey)),
      ];

      await initiator.controller.sendText(conversationId: conversationId, body: 'lost');
      await waitFor(() => initiator.controller.pendingCountFor(conversationId) == 0, reason: '"lost" was not acked');
      await settle();
      expect(relay.claimedOneTimePrekeys[responder.device.deviceId], [7]);
      expect(await responder.bodies(conversationId), isNot(contains('lost')));

      await deliver(responder, initiator, 'r1', conversationId: conversationId);
      await deliver(responder, initiator, 'r2', conversationId: conversationId);
      await deliver(initiator, responder, 'after the second reply', conversationId: conversationId);
      await deliver(responder, initiator, 'and back', conversationId: conversationId);
      await deliver(initiator, responder, 'still flowing', conversationId: conversationId);
      relay.claimedOneTimePrekeys.clear();
    }
  });

  test('a late frame on the session of a key the user replaced is refused and asks nothing', () async {
    await deliver(alice, bob, 'hello bob');
    await deliver(bob, alice, 'hi alice');
    // bob seals one more frame on the session alice knows; it is delayed.
    final late = bob.lib.envelopeCodec.encodeApiEnvelope(await bob.lib.messaging.encryptMessage(
      conversationId: conv,
      senderDeviceId: bob.device.deviceId,
      recipientUserId: alice.device.userId,
      body: 'sent before the reinstall',
      messageKind: MessageKind.text,
      recipientBundle: KeyBundle(
        userId: alice.device.userId,
        deviceId: alice.device.deviceId,
        handle: alice.device.handle,
        identityPublicKey: alice.device.identity.identityPublicKey,
        signedPrekeyBundle: alice.device.identity.signedPrekeyBundle,
      ),
    ));
    // bob's device comes back under a new key, and alice accepts it.
    final reinstalled = await InjectedDevice.mint(bob.device.deviceId, owner: bob);
    final first = await reinstalled.handshake(relay, alice, 'new key, same phone', conversationId: conv);
    expect((await openRelayed(alice, first)).status, DecryptStatus.identityRejected);
    await alice.controller.approveIdentityChange(conv, reviewed: alice.controller.pendingIdentityChangeFor(conv));
    final notices = noticesIn(alice, conv);

    relay.inject(senderHandle: 'bob', conversationId: conv, envelope: late);
    expect((await openRelayed(alice, late)).status, DecryptStatus.identityRejected);
    expect(alice.controller.pendingIdentityChangeFor(conv), isNull);
    expect(noticesIn(alice, conv), notices);
  });

  test('a forged key change neither stops the 1:1 nor can only be accepted', () async {
    await deliver(alice, bob, 'hello bob');
    await deliver(bob, alice, 'hi alice');
    // The relay opens a session to bob from alice's device id under a key it
    // holds.
    final forger = await InjectedDevice.mint(alice.device.deviceId, owner: alice);
    final forged = await forger.handshake(relay, bob, 'trust me', conversationId: conv);
    expect((await openRelayed(bob, forged)).status, DecryptStatus.identityRejected);
    final change = bob.controller.pendingIdentityChangeFor(conv)!;
    expect(change.presentedKey, forger.identityKey);

    // Bob's replies still reach the alice he pinned, and nothing else.
    await deliver(bob, alice, 'reply to the real alice');
    expect((await forger.open(lastRelayed(conv))).isOk, isFalse);

    // Bob keeps the current key: the change is gone, and the same forged
    // key is refused from then on without asking again.
    await bob.controller.declineIdentityChange(conv, reviewed: change);
    expect(bob.controller.pendingIdentityChangeFor(conv), isNull);
    final again = await forger.send(relay, bob, 'trust me now', conversationId: conv);
    expect((await openRelayed(bob, again)).status, DecryptStatus.identityRejected);
    expect(bob.controller.pendingIdentityChangeFor(conv), isNull);
    expect(noticesIn(bob, conv), 1);
    await deliver(bob, alice, 'still you');
    expect((await bob.pins.pinFor(alice.device.userId, alice.device.deviceId))!.identityKey,
        alice.device.identity.identityPublicKey);

    // The decline outlives the app.
    await bob.restart();
    final afterRestart = await forger.send(relay, bob, 'trust me after the restart', conversationId: conv);
    expect((await openRelayed(bob, afterRestart)).status, DecryptStatus.identityRejected);
    expect(bob.controller.pendingIdentityChangeFor(conv), isNull);
    await deliver(bob, alice, 'still you after the restart');
  });

  test('a pending identity change outlives the app', () async {
    await deliver(alice, bob, 'hello bob');
    await deliver(bob, alice, 'hi alice');
    final forger = await InjectedDevice.mint(alice.device.deviceId, owner: alice);
    expect((await openRelayed(bob, await forger.handshake(relay, bob, 'trust me', conversationId: conv))).status,
        DecryptStatus.identityRejected);
    final change = bob.controller.pendingIdentityChangeFor(conv)!;

    await bob.restart();
    await bob.trust.ready;

    final restored = bob.controller.pendingIdentityChangeFor(conv)!;
    expect(restored.presents(change.userId, change.deviceId, change.presentedKey), isTrue);
    expect(restored.previousKey, change.previousKey);
    await bob.controller.declineIdentityChange(conv, reviewed: restored);
    expect(bob.controller.pendingIdentityChangeFor(conv), isNull);
  });

  test('the identity the session sends to cannot be declined', () async {
    await deliver(alice, bob, 'hello bob');
    await deliver(bob, alice, 'hi alice');
    // A device admitted while bob was unverified takes the session; then
    // alice verifies dev-bob elsewhere, which holds the device back.
    final ghost = await InjectedDevice.mint('dev-ghost', owner: bob);
    expect((await openRelayed(alice, await ghost.handshake(relay, alice, 'ghost hello', conversationId: conv))).status,
        DecryptStatus.ok);
    relay.bundleOverrides['bob'] = ghost.bundleJson;
    await alice.controller.sendText(conversationId: conv, body: 'to the ghost while bob is unverified');
    await waitFor(() => alice.controller.pendingCountFor(conv) == 0, reason: 'the send was not acked');
    await alice.pins.markVerified('user-bob', 'dev-bob', bob.device.identity.identityPublicKey);
    await alice.controller.sendText(conversationId: conv, body: 'held back');
    await settle();
    final held = alice.controller.pendingIdentityChangeFor(conv)!;
    expect(held.deviceId, 'dev-ghost');

    expect(alice.controller.mayDeclineIdentityChange(conv), isFalse);
    await expectLater(alice.controller.declineIdentityChange(conv, reviewed: held), throwsStateError);
    expect(alice.controller.pendingIdentityChangeFor(conv), same(held));
  });
}
