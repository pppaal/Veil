import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/prekey_maintenance.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';

// Two real controllers, each with its own LibCryptoAdapter, identity and
// encrypted Drift cache, talking through the fake relay. Every regression
// here was invisible to the idempotent MockCryptoAdapter: ratchet message
// keys are single-use and a sender cannot open its own frames.

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

  Future<void> deliver(
    MessengerParty from,
    MessengerParty to,
    String body, {
    String conversationId = conv,
  }) async {
    await from.controller.sendText(conversationId: conversationId, body: body);
    await waitFor(
      () => from.controller.pendingCountFor(conversationId) == 0,
      reason: '"$body" was not acked',
    );
    await waitFor(
      () async => (await to.bodies(conversationId)).contains(body),
      reason: '"$body" is not readable by ${to.device.handle}',
    );
  }

  // Syncs [party]'s copy of the conversation and opens the row that carries
  // [envelope].
  Future<DecryptedMessage> openRelayed(MessengerParty party, Map<String, dynamic> envelope) async {
    await party.controller.loadConversationMessages(conv);
    final row = party.controller.messagesFor(conv).firstWhere((m) => m.envelope.ciphertext == envelope['ciphertext']);
    final opened = await party.controller.decryptMessage(row);
    await settle();
    return opened;
  }

  test('refresh between sends keeps the session', () async {
    await deliver(alice, bob, 'm1');
    await alice.controller.refreshConversations();
    await deliver(alice, bob, 'm2');

    expect(await bob.bodies(conv), ['m1', 'm2']);
    expect(alice.crypto.counts.bootstrap, 1);
  });

  test('receiving a message between sends keeps the session', () async {
    await deliver(alice, bob, 'm1');
    await deliver(bob, alice, 'r1');
    // Lets the conversation.sync hint the reply triggers refresh alice's list.
    await settle();
    await deliver(alice, bob, 'm2');

    expect(await alice.bodies(conv), ['m1', 'r1', 'm2']);
    expect(await bob.bodies(conv), ['m1', 'r1', 'm2']);
    expect(alice.crypto.counts.bootstrap + bob.crypto.counts.bootstrap, 1);
  });

  test('app resume between sends keeps the session', () async {
    await deliver(alice, bob, 'm1');
    await alice.controller.handleAppResumed();
    await settle();
    await deliver(alice, bob, 'm2');

    expect(await bob.bodies(conv), ['m1', 'm2']);
  });

  test('token refresh keeps history and does not refetch conversations', () async {
    await deliver(alice, bob, 'kept');
    // Let the sync hint that delivery raised finish before taking a baseline.
    await settle();
    final message = bob.controller.messagesFor(conv).single;
    final shown = bob.controller.decryptMessage(message);
    final conversationFetches = bob.api.conversationFetches;
    final connects = bob.realtime.connectCount;
    bob.crypto.counts.reset();

    await bob.refreshToken();
    await settle();

    expect(bob.realtime.authUpdates, 1, reason: 'the socket takes the new token in place');
    expect(bob.realtime.connectCount, connects + 1);
    expect(bob.realtime.lastAccessToken, bob.session().accessToken);
    expect(bob.api.conversationFetches, conversationFetches);
    expect(identical(bob.controller.decryptMessage(message), shown), isTrue);
    expect(await bob.bodies(conv), ['kept']);
    expect(bob.crypto.counts.decrypt, 0);

    await deliver(alice, bob, 'after refresh');
    expect(await bob.bodies(conv), ['kept', 'after refresh']);
  });

  test('twenty alternating messages all decrypt', () async {
    final expected = <String>[];
    for (var round = 0; round < 10; round++) {
      await deliver(alice, bob, 'a$round');
      expected.add('a$round');
      await deliver(bob, alice, 'b$round');
      expected.add('b$round');
    }

    expect(await alice.bodies(conv), expected);
    expect(await bob.bodies(conv), expected);
  });

  test('own sent message renders after controller restart over the same database', () async {
    await deliver(alice, bob, 'hello from alice');
    expect(await alice.bodies(conv), ['hello from alice']);

    await alice.restart();
    await settle();

    expect(await alice.bodies(conv), ['hello from alice']);
    expect(alice.crypto.counts.decrypt, 0);
    await deliver(alice, bob, 'ratchet survived');
    expect(await bob.bodies(conv), ['hello from alice', 'ratchet survived']);
  });

  test('received body survives restart with zero crypto calls', () async {
    await deliver(alice, bob, 'remember me');

    await bob.restart();
    await settle();

    expect(await bob.bodies(conv), ['remember me']);
    expect(bob.crypto.counts.decrypt, 0);
  });

  test('group key change leaves direct bodies intact', () async {
    relay.addGroup('grp', ['alice', 'bob']);
    await alice.controller.refreshConversations();
    await bob.controller.refreshConversations();
    await deliver(alice, bob, 'direct before');
    alice.crypto.counts.reset();
    bob.crypto.counts.reset();

    // Alice's first group send creates and distributes her chain key; bob
    // picks it up when the frame arrives. Both fire a group key event.
    await deliver(alice, bob, 'group hello', conversationId: 'grp');

    expect(await bob.bodies('grp'), ['group hello']);
    expect(await alice.bodies(conv), ['direct before']);
    expect(await bob.bodies(conv), ['direct before']);
    expect(alice.crypto.counts.decrypt + bob.crypto.counts.decrypt, 0);
  });

  test('oldest of 700 messages readable after cache eviction', () async {
    await deliver(alice, bob, 'm0');
    // Lets m0's sync hints run first; otherwise alice would also pull the
    // injected frames, which never went through her outbox, and spend the
    // run failing to open her own envelopes.
    await settle();
    final bobBundle = KeyBundle(
      userId: bob.device.userId,
      deviceId: bob.device.deviceId,
      handle: bob.device.handle,
      identityPublicKey: bob.device.identity.identityPublicKey,
      signedPrekeyBundle: bob.device.identity.signedPrekeyBundle,
    );
    // Sealed with alice's live ratchet and relayed in order, without paying
    // for 699 round trips through her outbox.
    for (var index = 1; index < 700; index++) {
      final envelope = await alice.crypto.messaging.encryptMessage(
        conversationId: conv,
        senderDeviceId: alice.device.deviceId,
        recipientUserId: bob.device.userId,
        body: 'm$index',
        messageKind: MessageKind.text,
        recipientBundle: bobBundle,
      );
      relay.inject(
        senderHandle: 'alice',
        conversationId: conv,
        envelope: alice.crypto.envelopeCodec.encodeApiEnvelope(envelope),
      );
    }
    bob.crypto.counts.reset();

    await bob.controller.loadConversationMessages(conv);
    await waitFor(
      () => bob.crypto.counts.decrypt == 699,
      timeout: const Duration(seconds: 20),
      reason: 'history was not ingested',
    );
    final messages = bob.controller.messagesFor(conv);

    expect(messages, hasLength(700));
    expect((await bob.controller.decryptMessage(messages.first)).body, 'm0');
    expect((await bob.controller.decryptMessage(messages.last)).body, 'm699');
    expect(bob.crypto.counts.decrypt, 699);
  });

  test('expiry removes content row at inner time when outer expiresAt is removed', () async {
    relay.stripOuterExpiresAt = true;
    await alice.controller.sendText(
      conversationId: conv,
      body: 'self-destruct',
      disappearAfter: const Duration(seconds: 1),
    );
    await waitFor(() => alice.controller.pendingCountFor(conv) == 0);
    await waitFor(() async => (await bob.bodies(conv)).contains('self-destruct'));
    final received = bob.controller.messagesFor(conv).single;
    final sent = alice.controller.messagesFor(conv).single;
    expect(relay.conversations[conv]!.messages.single['expiresAt'], isNull);
    expect(sent.id, received.id);
    // Both copies carry the authenticated expiry, the sender's from the
    // content it stored before sealing.
    expect(received.expiresAt, isNotNull);
    expect(sent.expiresAt, isNotNull);
    expect(await bob.cache.get(received.id), isNotNull);
    expect(await alice.cache.get(sent.id), isNotNull);

    await waitFor(
      () async =>
          bob.controller.messagesFor(conv).isEmpty &&
          await bob.cache.get(received.id) == null &&
          alice.controller.messagesFor(conv).isEmpty &&
          await alice.cache.get(sent.id) == null,
      reason: 'message outlived its authenticated expiry',
    );
    expect(alice.crypto.counts.decrypt, 0);

    // The relay still serves the frame, without an expiry. After a restart
    // neither side brings it back or spends a decrypt on it.
    final fetches = alice.api.messageFetches + bob.api.messageFetches;
    await alice.restart();
    await bob.restart();
    await waitFor(() => alice.api.messageFetches + bob.api.messageFetches >= fetches + 2);
    // A copy that came back would be merged within moments of the fetch.
    await settle(const Duration(milliseconds: 100));
    expect(alice.controller.messagesFor(conv), isEmpty);
    expect(bob.controller.messagesFor(conv), isEmpty);
    expect(alice.crypto.counts.decrypt + bob.crypto.counts.decrypt, 0);
  });

  test('search returns hits without calling decrypt', () async {
    await deliver(alice, bob, 'needle in the haystack');
    await deliver(alice, bob, 'unrelated chatter');
    await settle();
    alice.crypto.counts.reset();
    bob.crypto.counts.reset();

    final needle = bob.controller.messagesFor(conv).first;
    expect(await bob.controller.searchLoadedMessageIds(conv, query: 'NEEDLE'), [needle.id]);
    expect(
      await alice.controller.searchLoadedMessageIds(conv, query: 'needle'),
      [alice.controller.messagesFor(conv).first.id],
    );
    final archive = await bob.controller.searchMessageArchive(
      query: const MessageSearchQuery(query: 'needle'),
    );
    expect(archive.items.single.messageId, needle.id);
    expect(archive.items.single.bodySnippet, contains('needle'));
    expect(alice.crypto.counts.decrypt + bob.crypto.counts.decrypt, 0);
  });

  test('leaving the chat stops auto read receipts and restores notifications', () async {
    bob.controller.setActiveConversation(conv);
    await deliver(alice, bob, 'seen');
    await waitFor(() => bob.api.markReadCalls.length == 1);
    expect(bob.notifications.shownForConversations, isEmpty);

    bob.controller.setActiveConversation(null);
    await deliver(alice, bob, 'unseen');
    await settle();

    expect(bob.api.markReadCalls, hasLength(1));
    expect(bob.notifications.shownForConversations, [conv]);
  });

  test('key bundle fetched at most once per session setup', () async {
    for (var index = 0; index < 3; index++) {
      await deliver(alice, bob, 'a$index');
    }
    await alice.controller.refreshConversations();
    await deliver(bob, alice, 'b0');
    await alice.controller.handleAppResumed();
    await settle();
    await deliver(alice, bob, 'a3');

    expect(alice.api.directoryLookups, {'bob': 1});
    // The responder pins the identity alice's handshake proved, so it never
    // asks the directory about her.
    expect(bob.api.directoryLookups, isEmpty);
    final bobView = bob.controller.conversations.firstWhere((item) => item.id == conv);
    expect(bobView.recipientBundle.identityPublicKey, alice.device.identity.identityPublicKey);
  });

  test('server identity swap blocked', () async {
    await deliver(alice, bob, 'pinned');
    // The pin outlives the app; the directory answer it was made from does not.
    await alice.restart();
    // A second conversation needs a fresh session, and the server answers
    // the lookup with a key of its own for bob's very device.
    relay.addDirect('conv-ab-2', 'alice', 'bob');
    await alice.controller.refreshConversations();
    final impostor = await LibCryptoAdapter().identity.generateDeviceIdentity(bob.device.deviceId);
    relay.bundleOverrides['bob'] = {
      ...bob.device.bundleJson,
      'identityPublicKey': impostor.identityPublicKey,
      'signedPrekeyBundle': impostor.signedPrekeyBundle,
    };
    alice.crypto.counts.reset();

    await alice.controller.sendText(conversationId: 'conv-ab-2', body: 'for bob only');
    await settle();

    expect(alice.crypto.counts.bootstrap, 0);
    expect(relay.conversations['conv-ab-2']!.messages, isEmpty);
    final change = alice.controller.pendingIdentityChangeFor('conv-ab-2')!;
    expect(change.presentedKey, impostor.identityPublicKey);
    expect(change.previousKey, bob.device.identity.identityPublicKey);
    expect(alice.controller.errorMessage, isNull, reason: 'the issue belongs to the conversation');
    expect(alice.controller.messagesFor('conv-ab-2').single.isLocalNotice, isTrue);
    // The established conversation keeps working with the pinned key.
    await deliver(alice, bob, 'still you');
  });

  test('forged inbound session rejected', () async {
    await deliver(alice, bob, 'hello bob');
    // The server opens a session to bob in alice's name, from an identity it
    // controls on alice's device id.
    final forger = LibCryptoAdapter();
    final forged = await forger.identity.generateDeviceIdentity(alice.device.deviceId);
    forger.setLocalIdentityLoader(() async => forged.identityPrivateKeyRef);
    await forger.sessions.bootstrapSession(SessionBootstrapRequest(
      conversationId: conv,
      localDeviceId: alice.device.deviceId,
      localUserId: alice.device.userId,
      remoteUserId: bob.device.userId,
      remoteDeviceId: bob.device.deviceId,
      remoteIdentityPublicKey: bob.device.identity.identityPublicKey,
      remoteSignedPrekeyBundle: bob.device.identity.signedPrekeyBundle,
    ));
    final envelope = await forger.messaging.encryptMessage(
      conversationId: conv,
      senderDeviceId: alice.device.deviceId,
      recipientUserId: bob.device.userId,
      body: 'trust me',
      messageKind: MessageKind.text,
      recipientBundle: KeyBundle(
        userId: bob.device.userId,
        deviceId: bob.device.deviceId,
        handle: 'bob',
        identityPublicKey: bob.device.identity.identityPublicKey,
        signedPrekeyBundle: bob.device.identity.signedPrekeyBundle,
      ),
    );
    relay.inject(senderHandle: 'alice', conversationId: conv, envelope: forger.envelopeCodec.encodeApiEnvelope(envelope));

    await bob.controller.loadConversationMessages(conv);
    await waitFor(() => bob.controller.pendingIdentityChangeFor(conv) != null, reason: 'the forgery was not caught');

    final forgedRow = bob.controller.messagesFor(conv).firstWhere((m) => m.envelope.ciphertext == envelope.ciphertext);
    final opened = await bob.controller.decryptMessage(forgedRow);
    expect(opened.status, DecryptStatus.identityRejected);
    expect(opened.body, isEmpty);
    expect(bob.controller.pendingIdentityChangeFor(conv)!.presentedKey, forged.identityPublicKey);
    // Nothing was installed: alice's real session still reads.
    await deliver(alice, bob, 'the real alice');
    expect(await bob.bodies(conv), containsAllInOrder(['hello bob', 'the real alice']));
    expect(await bob.bodies(conv), isNot(contains('trust me')));
  });

  test('OPK claimed and consumed exactly once', () async {
    final carol = await MessengerParty.join(
      relay,
      handle: 'carol',
      userId: 'user-carol',
      deviceId: 'dev-carol',
      maintainPrekeys: true,
    );
    addTearDown(carol.dispose);
    relay.addDirect('conv-ac', 'alice', 'carol');
    await carol.signIn();
    await waitFor(
      () => (relay.oneTimePrekeys['dev-carol']?.length ?? 0) == PrekeyMaintenance.oneTimePrekeyPoolSize,
      timeout: const Duration(seconds: 10),
      reason: 'carol never published her one-time prekeys',
    );
    await alice.controller.refreshConversations();

    await deliver(alice, carol, 'first contact', conversationId: 'conv-ac');
    await deliver(alice, carol, 'second', conversationId: 'conv-ac');
    await deliver(carol, alice, 'reply', conversationId: 'conv-ac');

    final claimed = relay.claimedOneTimePrekeys['dev-carol']!;
    expect(claimed, hasLength(1), reason: 'one session, one claim');
    expect(relay.oneTimePrekeys['dev-carol'], hasLength(PrekeyMaintenance.oneTimePrekeyPoolSize - 1));
    // Carol's handshake used it up: the private half is gone.
    expect(await carol.prekeyStore.loadOneTimePrekey(claimed.single), isNull);
    expect(await carol.prekeyStore.loadOneTimePrekey(claimed.single + 1), isNotNull);
  });

  test('a reaction travels end to end and lands on its target', () async {
    await deliver(alice, bob, 'react to me');
    await settle();
    final target = bob.controller.messagesFor(conv).single;
    final relayedBefore = relay.conversations[conv]!.messages.length;

    await bob.controller.toggleReaction(target, '🔥');
    await waitFor(() => alice.controller.messagesFor(conv).first.reactions.isNotEmpty);

    final reacted = alice.controller.messagesFor(conv).first;
    expect(reacted.reactions.single.emoji, '🔥');
    expect(reacted.reactions.single.userId, bob.device.userId);
    // The relay saw one more encrypted message and nothing it could read.
    final relayed = relay.conversations[conv]!.messages.last;
    expect(relay.conversations[conv]!.messages, hasLength(relayedBefore + 1));
    expect(relayed['messageType'], 'reaction');
    expect(jsonEncode(relayed), isNot(contains('🔥')));
    final row = alice.controller.messagesFor(conv).last;
    expect((await alice.controller.decryptMessage(row)).messageKind, MessageKind.reaction);
    expect(alice.notifications.shownForConversations, isEmpty, reason: 'a reaction is not a new message');
  });

  test('a frame for a conversation not listed yet still records the responder session', () async {
    // Carol creates a conversation with bob and writes at once; bob's first
    // word of it is her frame.
    final carol = await MessengerParty.join(relay, handle: 'carol', userId: 'user-carol', deviceId: 'dev-carol');
    addTearDown(carol.dispose);
    relay.addDirect('conv-bc', 'carol', 'bob');
    await carol.signIn();
    await deliver(carol, bob, 'hi, new here', conversationId: 'conv-bc');
    await waitFor(
      () =>
          bob.controller.conversations
              .where((item) => item.id == 'conv-bc')
              .firstOrNull
              ?.sessionState
              ?.remoteIdentityPublicKey ==
          carol.device.identity.identityPublicKey,
      reason: 'the inbound session was never recorded on the conversation',
    );

    await deliver(bob, carol, 'welcome', conversationId: 'conv-bc');
    expect(bob.crypto.counts.bootstrap, 0);
    expect(await carol.bodies('conv-bc'), ['hi, new here', 'welcome']);
  });

  test('restarted device accepts a session from a new contact', () async {
    // The relaunched adapter must still hold the identity and prekeys bob
    // published, or carol's first frame cannot be answered.
    await bob.restart();
    final carol = await MessengerParty.join(relay, handle: 'carol', userId: 'user-carol', deviceId: 'dev-carol');
    addTearDown(carol.dispose);
    relay.addDirect('conv-bc', 'carol', 'bob');
    await carol.signIn();

    await deliver(carol, bob, 'hello after your relaunch', conversationId: 'conv-bc');
    await waitFor(
      () => bob.controller.conversations.any((item) => item.id == 'conv-bc'),
      reason: 'the new conversation was never listed',
    );
    await deliver(bob, carol, 'welcome back', conversationId: 'conv-bc');
    expect(bob.crypto.counts.bootstrap, 0);
  });

  test('peer device change moves the next send to the new device', () async {
    await deliver(alice, bob, 'before the move');
    // Answered, so alice's handshake is settled and the new device's one
    // replaces it (see SessionRecord.installingInbound).
    await deliver(bob, alice, 'packing up');
    final newPhone = await MessengerParty.join(
      relay,
      handle: 'bob',
      userId: 'user-bob',
      deviceId: 'dev-bob-2',
    );
    addTearDown(newPhone.dispose);
    await newPhone.signIn();

    // The first frame from a device alice's session is not bound to is the
    // only sign she gets that bob moved.
    await newPhone.controller.sendText(conversationId: conv, body: 'new phone');
    await waitFor(() => newPhone.controller.pendingCountFor(conv) == 0);
    List<ChatMessage> relayed() => alice.controller.messagesFor(conv).where((m) => !m.isLocalNotice).toList();
    await waitFor(() => relayed().length == 3);
    await alice.controller.decryptMessage(relayed().last);
    // bob was not verified, so his new device is admitted and announced.
    await waitFor(() => alice.controller.messagesFor(conv).any((m) => m.isLocalNotice));
    await deliver(alice, newPhone, 'after the move');

    // The directory confirms the device the new session is bound to, so
    // alice answers on that session instead of forking it.
    expect(alice.api.directoryLookups, {'bob': 2});
    expect(alice.crypto.counts.bootstrap, 1);
    final session = alice.controller.conversations.firstWhere((item) => item.id == conv).sessionState!;
    expect(session.remoteDeviceId, 'dev-bob-2');
    expect(session.remoteIdentityPublicKey, newPhone.device.identity.identityPublicKey);
  });

  test('a device injected into an established conversation never gets a reply', () async {
    await deliver(alice, bob, 'hello bob');
    await deliver(bob, alice, 'hi alice');
    final ghost = await _InjectedDevice.mint('dev-ghost', owner: bob);
    ConversationSessionState session() => alice.controller.conversationById(conv)!.sessionState!;

    // bob is not verified, so a new device of his is admitted on first use
    // and announced. The conversation names it from then on: the safety
    // numbers describe the identity the engine now holds a session with.
    final injected = await ghost.handshake(relay, alice, 'ghost hello');
    expect((await openRelayed(alice, injected)).status, DecryptStatus.ok);
    expect(alice.controller.messagesFor(conv).where((m) => m.isLocalNotice), hasLength(1));
    expect(session().remoteDeviceId, 'dev-ghost');
    expect(session().remoteIdentityPublicKey, ghost.identityKey);

    // The reply goes to the device the directory serves, which is bob's.
    await deliver(alice, bob, 'secret for bob');
    expect((await ghost.open(relay.conversations[conv]!.messages.last)).isOk, isFalse);
    expect(session().remoteDeviceId, 'dev-bob');

    // Once alice verified that device, a fresh session from the injected one
    // still does not take her replies.
    final served = await alice.controller.fetchPeerKeyBundle('bob');
    expect(served.deviceId, 'dev-bob');
    await alice.pins.markVerified(bob.device.userId, served.deviceId, served.identityPublicKey);
    await openRelayed(alice, await ghost.handshake(relay, alice, 'ghost again'));
    await deliver(alice, bob, 'after verifying bob');
    expect((await ghost.open(relay.conversations[conv]!.messages.last)).isOk, isFalse);
    expect(await bob.bodies(conv), containsAllInOrder(['secret for bob', 'after verifying bob']));
  });

  test('the engine never seals to an identity the conversation did not choose', () async {
    await deliver(alice, bob, 'hello bob');
    await deliver(bob, alice, 'hi alice');
    final ghost = await _InjectedDevice.mint('dev-ghost', owner: bob);
    // The injected handshake reaches alice's engine between a send choosing
    // its recipient and sealing: the engine installs it as the sending
    // state before the conversation hears of it.
    final injected = await ghost.handshake(relay, alice, 'ghost hello');
    final opened = await alice.lib.messaging.decryptMessage(alice.lib.envelopeCodec.decodeApiEnvelope(injected));
    expect(opened.status, DecryptStatus.ok);
    expect(alice.controller.conversationById(conv)!.sessionState!.remoteDeviceId, 'dev-bob');

    await deliver(alice, bob, 'secret for bob');
    expect((await ghost.open(relay.conversations[conv]!.messages.last)).isOk, isFalse);
    expect(alice.controller.conversationById(conv)!.sessionState!.remoteDeviceId, 'dev-bob');
  });

  // Opens alice's latest message on bob's side, then the blob the relay
  // stored under the attachment id it names.
  Future<(AttachmentReference, List<int>)> openLatestAttachment() async {
    final received = await bob.controller.decryptMessage(bob.controller.messagesFor(conv).last);
    expect(received.messageKind, MessageKind.file);
    final reference = received.attachment!;
    final plaintext = await bob.crypto.messaging.decryptAttachment(
      reference: reference,
      ciphertext: relay.uploadedBlobs[reference.attachmentId]!,
      localIdentityPrivateRef: bob.device.identity.identityPrivateKeyRef,
    );
    return (reference, plaintext);
  }

  test('attachment upload carries ciphertext the peer can decrypt', () async {
    await deliver(alice, bob, 'file incoming');

    await alice.controller.sendAttachmentPlaceholder(conv, filename: 'brief.pdf');
    await waitFor(() => alice.controller.pendingCountFor(conv) == 0, reason: 'attachment not sent');
    await waitFor(() => bob.controller.messagesFor(conv).length == 2);
    final (reference, plaintext) = await openLatestAttachment();

    // The blob was sealed under the id alice proposed, and that is the id
    // the relay ticketed.
    expect(relay.uploadTickets, [reference.attachmentId]);
    final uploaded = relay.uploadedBlobs[reference.attachmentId]!;
    expect(plaintext, hasLength(2048));
    // What went up is sealed: longer than the file by at least the AEAD tag,
    // and not the file itself. Sizes are compared this loosely because the
    // reference's sizeBytes means ciphertext length in v1, plaintext in v2.
    expect(uploaded.length, greaterThan(plaintext.length));
    expect(uploaded.sublist(0, plaintext.length), isNot(equals(plaintext)));
    final sent = await alice.controller.decryptMessage(alice.controller.messagesFor(conv).last);
    expect(sent.attachment!.attachmentId, reference.attachmentId);
  });

  test('attachment after a restart over an established session skips the key directory', () async {
    await deliver(alice, bob, 'session up');
    await alice.restart();
    await settle();
    final fetches = Map<String, int>.of(alice.api.directoryLookups);

    await alice.controller.sendAttachmentPlaceholder(conv, filename: 'brief.pdf');
    await waitFor(() => alice.controller.pendingCountFor(conv) == 0, reason: 'attachment not sent');
    await waitFor(() => bob.controller.messagesFor(conv).length == 2);

    final (_, plaintext) = await openLatestAttachment();
    expect(plaintext, hasLength(2048));
    // A lookup would tell the relay whom alice is about to message.
    expect(alice.api.directoryLookups, fetches);
  });

  test('re-ticketing after the upload ticket expired reuses the sealed attachment id', () async {
    await deliver(alice, bob, 'file incoming');
    await settle();
    // The first attempt uploads but is not acknowledged, so the draft keeps
    // a ticket that has expired by the time the send is retried.
    relay.uploadTicketLifetime = Duration.zero;
    relay.failUploadCompletions = 1;

    await alice.controller.sendAttachmentPlaceholder(conv, filename: 'brief.pdf');
    final clientMessageId = alice.controller.messagesFor(conv).last.clientMessageId!;
    await waitFor(
      () => alice.controller.attachmentTransferForMessage(clientMessageId)?.phase ==
          AttachmentTransferPhase.failed,
      reason: 'first upload attempt did not fail',
    );
    relay.uploadTicketLifetime = const Duration(minutes: 10);
    await alice.controller.retryPendingMessages(conv);
    await waitFor(() => alice.controller.pendingCountFor(conv) == 0, reason: 'attachment not sent');
    await waitFor(() => bob.controller.messagesFor(conv).length == 2);

    final (reference, plaintext) = await openLatestAttachment();
    expect(relay.uploadTickets, [reference.attachmentId, reference.attachmentId]);
    expect(relay.attachments[reference.attachmentId]!.uploadStatus, 'uploaded');
    expect(plaintext, hasLength(2048));
  });
}

/// A device the server invents under [owner]'s account, with an identity
/// the server holds: every handshake it opens is genuine X3DH, only from a
/// device [owner] never had.
class _InjectedDevice {
  _InjectedDevice._(this.deviceId, this.owner, this.adapter, this.identityKey);

  static Future<_InjectedDevice> mint(String deviceId, {required MessengerParty owner}) async {
    final adapter = LibCryptoAdapter();
    final identity = await adapter.identity.generateDeviceIdentity(deviceId);
    adapter.setLocalIdentityLoader(() async => identity.identityPrivateKeyRef);
    return _InjectedDevice._(deviceId, owner, adapter, identity.identityPublicKey);
  }

  final String deviceId;
  final MessengerParty owner;
  final LibCryptoAdapter adapter;
  final String identityKey;

  /// Opens a fresh session to [peer] and relays [body] on it in [owner]'s
  /// name; returns the envelope.
  Future<Map<String, dynamic>> handshake(FakeRelay relay, MessengerParty peer, String body) async {
    final peerBundle = KeyBundle(
      userId: peer.device.userId,
      deviceId: peer.device.deviceId,
      handle: peer.device.handle,
      identityPublicKey: peer.device.identity.identityPublicKey,
      signedPrekeyBundle: peer.device.identity.signedPrekeyBundle,
    );
    await adapter.sessions.bootstrapSession(SessionBootstrapRequest(
      conversationId: conv,
      localDeviceId: deviceId,
      localUserId: owner.device.userId,
      remoteUserId: peerBundle.userId,
      remoteDeviceId: peerBundle.deviceId,
      remoteIdentityPublicKey: peerBundle.identityPublicKey,
      remoteSignedPrekeyBundle: peerBundle.signedPrekeyBundle,
    ));
    final envelope = adapter.envelopeCodec.encodeApiEnvelope(await adapter.messaging.encryptMessage(
      conversationId: conv,
      senderDeviceId: deviceId,
      recipientUserId: peerBundle.userId,
      body: body,
      messageKind: MessageKind.text,
      recipientBundle: peerBundle,
    ));
    relay.inject(senderHandle: owner.device.handle, conversationId: conv, envelope: envelope);
    return envelope;
  }

  /// What this device reads of a relayed envelope.
  Future<DecryptedMessage> open(Map<String, dynamic> relayed) =>
      adapter.messaging.decryptMessage(adapter.envelopeCodec.decodeApiEnvelope(relayed));
}
