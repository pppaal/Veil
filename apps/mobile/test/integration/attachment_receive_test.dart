import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_decrypt.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/attachment_media_service.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/media_fixtures.dart';
import '../support/messenger_party.dart';

// Receiving a photo and a file between two real devices: alice's
// LibCryptoAdapter seals the attachments and the messages that point at
// them, bob's media service fetches, checks and opens them. Nothing
// decrypted is ever written outside veil_open, and only while an open
// runs.

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
    bob.controller.media.setInUse(true);
    // A session first, by text.
    await alice.controller.sendText(conversationId: conv, body: 'hello');
    await waitFor(() => alice.controller.pendingCountFor(conv) == 0, reason: 'hello was not acked');
    await waitFor(() async => (await bob.bodies(conv)).contains('hello'), reason: 'bob never read hello');
  });

  tearDown(() async {
    await alice.dispose();
    await bob.dispose();
  });

  // Alice seals [plaintext], uploads the blob, and sends a message of
  // [kind] pointing at it; the message once bob has it.
  Future<(ChatMessage, AttachmentReference)> send(List<int> plaintext,
      {required String id, required String contentType, required MessageKind kind, String body = ''}) async {
    final sealed = await sealV2(plaintext, attachmentId: id, contentType: contentType);
    relay.putUploadedBlob(id, sealed.blob, uploaderDeviceId: alice.device.deviceId);
    final envelope = await alice.lib.messaging.encryptMessage(
      conversationId: conv,
      senderDeviceId: alice.device.deviceId,
      recipientUserId: bob.device.userId,
      body: body,
      messageKind: kind,
      recipientBundle: alice.controller.conversationById(conv)!.recipientBundle,
      attachment: sealed.reference,
    );
    final stored = relay.inject(
        senderHandle: 'alice', conversationId: conv, envelope: alice.lib.envelopeCodec.encodeApiEnvelope(envelope));
    relay.realtimeFor('bob').deliver('message.new', Map<String, dynamic>.of(stored));
    final messageId = stored['id'] as String;
    await waitFor(() => bob.controller.messagesFor(conv).any((message) => message.id == messageId),
        reason: 'bob never got it');
    final message = bob.controller.messagesFor(conv).firstWhere((message) => message.id == messageId);
    final opened = await bob.controller.decryptMessage(message);
    expect(opened.isOk, isTrue, reason: 'bob could not open the message');
    expect(opened.messageKind, kind);
    return (message, opened.attachment!);
  }

  // Every file under bob's app folders, the media folder's opaque blobs
  // aside.
  List<String> plaintextCandidates() {
    final media = p.join(bob.attachmentDirectory.path, 'support');
    return [
      for (final entity in bob.attachmentDirectory.listSync(recursive: true))
        if (entity is File && !p.isWithin(media, entity.path)) p.relative(entity.path, from: bob.attachmentDirectory.path),
    ];
  }

  test('a photo and a file sealed by alice open on bob\'s phone, byte for byte', () async {
    final photo = jpegWithMetadata(width: 120, height: 90);
    final pdf = pdfBytes('report');
    final (_, photoRef) = await send(photo,
        id: '00000000-0000-4000-8000-0000000000b1', contentType: 'image/jpeg', kind: MessageKind.image);
    final (_, fileRef) = await send(pdf,
        id: '00000000-0000-4000-8000-0000000000b2',
        contentType: 'application/pdf',
        kind: MessageKind.file,
        body: 'report.pdf');

    final media = bob.controller.media;
    // The photo came by itself; the file waits for a tap.
    await waitFor(() => media.statusOf(conv, photoRef).state == MediaState.ready, reason: 'the photo never came');
    expect(media.statusOf(conv, fileRef).state, MediaState.idle);
    expect(await media.photoBytes(conv, photoRef), photo);

    await media.download(conv, fileRef);
    expect(media.statusOf(conv, fileRef).state, MediaState.ready);
    final copy = await media.plaintextFileFor(conv, fileRef, name: 'report.pdf', purpose: MediaCopyPurpose.open);
    expect(copy, isNotNull);
    expect(File(copy!).readAsBytesSync(), pdf);

    // While the open runs, its copy is the only plaintext on the phone,
    // and it sits in its own folder under veil_open.
    expect(plaintextCandidates(), [p.relative(copy, from: bob.attachmentDirectory.path)]);
    expect(p.split(p.relative(copy, from: bob.attachmentDirectory.path)), ['tmp', 'veil_open', isNotEmpty, 'report.pdf']);
    await media.releaseCopy(copy);
    expect(plaintextCandidates(), isEmpty, reason: 'plaintext outlived the open');

    // The media folder holds only sealed blobs under opaque names.
    final blobs = Directory(p.join(bob.attachmentDirectory.path, 'support')).listSync(recursive: true).whereType<File>();
    expect(blobs, hasLength(2));
    for (final blob in blobs) {
      expect(p.basename(blob.path), matches(RegExp(r'^[0-9a-f]{64}$')));
      final bytes = blob.readAsBytesSync();
      expect(bytes.length, isNot(photo.length));
      expect(String.fromCharCodes(bytes.take(5)), isNot('%PDF-'));
    }
    expect(await digestMatches(blobs.first.path, photoRef.sha256) || await digestMatches(blobs.first.path, fileRef.sha256),
        isTrue);
  });

  // D37 across a restart: the chat goes from bob's list while his app is
  // closed (he was removed, or alice deleted her account). The first list
  // of the next start no longer has it; its blob and its row go, as they do
  // when a chat leaves while the app runs. A restart that still lists the
  // chat keeps them.
  test('a chat that left the list while the app was closed takes its blobs along at the next start', () async {
    final (_, photoRef) = await send(jpegWithMetadata(width: 120, height: 90),
        id: '00000000-0000-4000-8000-0000000000b4', contentType: 'image/jpeg', kind: MessageKind.image);
    await waitFor(() => bob.controller.media.statusOf(conv, photoRef).state == MediaState.ready,
        reason: 'the photo never came');
    final mediaDir = Directory(p.join(bob.attachmentDirectory.path, 'support', 'veil_media'));
    List<FileSystemEntity> blobs() => mediaDir.existsSync() ? mediaDir.listSync() : const [];
    expect(blobs(), hasLength(1));

    // The restart's first list has been applied once it returns; the
    // sweeps run one after another, so this one waits for the list's.
    await bob.restart();
    expect(bob.controller.conversationById(conv), isNotNull);
    await settle();
    await bob.controller.media.cleanup.sweepExpired();
    expect(await bob.mediaIndex.all(), hasLength(1), reason: 'a chat still listed lost its blob at a restart');
    expect(blobs(), hasLength(1));

    await bob.restart(whileClosed: () async => relay.conversations.remove(conv));
    await waitFor(() => bob.controller.conversationById(conv) == null, reason: 'the list still has the chat');
    await waitFor(() async => (await bob.mediaIndex.all()).isEmpty, reason: 'the blob of a chat that left was kept');
    expect(blobs(), isEmpty);
  });

  // Mallory opens a 1:1 with bob that the relay lists to bob under alice's
  // handle, and sends a photo in it: held for its account, nothing in it is
  // fetched, whoever asks.
  test('a chat held for its account fetches nothing', () async {
    const held = 'conv-bm';
    final mallory = await MessengerParty.join(relay, handle: 'mallory', userId: 'user-mallory', deviceId: 'dev-mal');
    addTearDown(mallory.dispose);
    relay
      ..listedHandles['bob'] = {'mallory': 'alice'}
      ..addDirect(held, 'mallory', 'bob');
    await mallory.signIn();
    await mallory.controller.sendText(conversationId: held, body: 'alice here, new phone');
    await waitFor(() => mallory.controller.pendingCountFor(held) == 0, reason: 'not acked');
    await bob.controller.refreshConversations();
    await bob.controller.loadConversationMessages(held);
    expect(bob.controller.peerAccountHoldFor(held), isNotNull);
    final downloads = relay.blobDownloads.length;
    final tickets = relay.downloadTicketRequests.length;

    final sealed = await sealV2(jpegWithMetadata(),
        attachmentId: '00000000-0000-4000-8000-0000000000b3', contentType: 'image/jpeg');
    relay.putUploadedBlob(sealed.reference.attachmentId, sealed.blob, uploaderDeviceId: mallory.device.deviceId);
    final envelope = await mallory.lib.messaging.encryptMessage(
      conversationId: held,
      senderDeviceId: mallory.device.deviceId,
      recipientUserId: bob.device.userId,
      body: '',
      messageKind: MessageKind.image,
      recipientBundle: mallory.controller.conversationById(held)!.recipientBundle,
      attachment: sealed.reference,
    );
    final stored = relay.inject(
        senderHandle: 'mallory', conversationId: held, envelope: mallory.lib.envelopeCodec.encodeApiEnvelope(envelope));
    relay.realtimeFor('bob').deliver('message.new', Map<String, dynamic>.of(stored));
    await settle();
    await bob.controller.loadConversationMessages(held);
    expect(bob.controller.messagesFor(held), isNotEmpty);
    expect(bob.controller.media.autoDownloadWithheld(held), isTrue);
    for (final message in bob.controller.messagesFor(held)) {
      expect(await bob.controller.media.photoBytes(held, sealed.reference, sentAt: message.sentAt), isNull);
    }
    await settle();
    expect(relay.downloadTicketRequests, hasLength(tickets));
    expect(relay.blobDownloads, hasLength(downloads));
  });
}
