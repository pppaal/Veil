import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
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

    expect(alice.api.keyBundleFetches, {'bob': 1});
    // The responder looks alice up once, when her first frame sets up its
    // session, so it has her identity key for safety numbers.
    expect(bob.api.keyBundleFetches, {'alice': 1});
    final bobView = bob.controller.conversations.firstWhere((item) => item.id == conv);
    expect(bobView.recipientBundle.identityPublicKey, alice.device.identity.identityPublicKey);
  });

  test('identity key change for same device does not rebootstrap and flags preview', () async {
    await deliver(alice, bob, 'before swap');
    final impostor = await LibCryptoAdapter().identity.generateDeviceIdentity(bob.device.deviceId);
    relay.bundleOverrides['bob'] = {
      ...bob.device.bundleJson,
      'identityPublicKey': impostor.identityPublicKey,
      'signedPrekeyBundle': impostor.signedPrekeyBundle,
    };

    final served = await alice.controller.fetchPeerKeyBundle('bob');

    expect(served.identityPublicKey, impostor.identityPublicKey);
    final preview = alice.controller.conversations.firstWhere((item) => item.id == conv);
    expect(preview.identityMismatchPending, isTrue);
    expect(preview.sessionState!.remoteIdentityPublicKey, bob.device.identity.identityPublicKey);
    // The live session still encrypts to bob's real key, so that is the key
    // the conversation keeps showing for safety numbers.
    expect(preview.recipientBundle.identityPublicKey, bob.device.identity.identityPublicKey);
    expect(alice.crypto.counts.bootstrap, 1);
    await waitFor(() async => (await alice.cache.readConversations())
        .firstWhere((item) => item.id == conv)
        .identityMismatchPending);

    await deliver(alice, bob, 'after swap');
    expect(await bob.bodies(conv), ['before swap', 'after swap']);
    expect(alice.crypto.counts.bootstrap, 1);
  });

  test('responder flags an identity key change for the initiator device', () async {
    await deliver(alice, bob, 'hello bob');
    await waitFor(
      () => bob.controller.conversations
          .firstWhere((item) => item.id == conv)
          .sessionState!
          .remoteIdentityPublicKey
          .isNotEmpty,
      reason: 'the responder never pinned the initiator identity key',
    );
    final impostor = await LibCryptoAdapter().identity.generateDeviceIdentity(alice.device.deviceId);
    relay.bundleOverrides['alice'] = {
      ...alice.device.bundleJson,
      'identityPublicKey': impostor.identityPublicKey,
      'signedPrekeyBundle': impostor.signedPrekeyBundle,
    };

    await bob.controller.fetchPeerKeyBundle('alice');

    final preview = bob.controller.conversations.firstWhere((item) => item.id == conv);
    expect(preview.identityMismatchPending, isTrue);
    expect(preview.sessionState!.remoteIdentityPublicKey, alice.device.identity.identityPublicKey);
    expect(preview.recipientBundle.identityPublicKey, alice.device.identity.identityPublicKey);
    expect(bob.crypto.counts.bootstrap, 0);
    await deliver(bob, alice, 'still you?');
    expect(await alice.bodies(conv), ['hello bob', 'still you?']);
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

  test('peer device change re-bootstraps the next send to the new device', () async {
    await deliver(alice, bob, 'before the move');
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
    await waitFor(() => alice.controller.messagesFor(conv).length == 2);
    await alice.controller.decryptMessage(alice.controller.messagesFor(conv).last);
    await alice.controller.sendText(conversationId: conv, body: 'after the move');
    await waitFor(() => alice.controller.pendingCountFor(conv) == 0);

    expect(alice.api.keyBundleFetches, {'bob': 2});
    expect(alice.crypto.counts.bootstrap, 2);
    final session = alice.controller.conversations.firstWhere((item) => item.id == conv).sessionState!;
    expect(session.remoteDeviceId, 'dev-bob-2');
    expect(session.remoteIdentityPublicKey, newPhone.device.identity.identityPublicKey);
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
    final fetches = Map<String, int>.of(alice.api.keyBundleFetches);

    await alice.controller.sendAttachmentPlaceholder(conv, filename: 'brief.pdf');
    await waitFor(() => alice.controller.pendingCountFor(conv) == 0, reason: 'attachment not sent');
    await waitFor(() => bob.controller.messagesFor(conv).length == 2);

    final (_, plaintext) = await openLatestAttachment();
    expect(plaintext, hasLength(2048));
    // A lookup would tell the relay whom alice is about to message.
    expect(alice.api.keyBundleFetches, fetches);
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
