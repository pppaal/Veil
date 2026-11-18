import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/errors/user_facing_error.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/attachments/domain/attachment_rules.dart';
import 'package:veil_mobile/src/features/attachments/domain/outgoing_attachment.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/attachment_media_service.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/injected_device.dart';
import '../support/media_fixtures.dart';
import '../support/messenger_party.dart';

// Sending photos and files between two real controllers (LibCryptoAdapter,
// encrypted Drift caches) over the fake relay: what is sealed, what the
// relay gets, what bob opens, the late timer stamp (D18), the order within a
// chat (D20), cancel (D19) and what keeps the sealed blob safe (D22).

const conv = 'conv-ab';

final _blobName = RegExp(r'^[0-9a-f]{64}$');

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
    await waitFor(() async => (await to.bodies(conversationId)).contains(body), reason: '"$body" did not arrive');
  }

  Future<Directory> stagingOf(MessengerParty party) => party.attachmentPaths.stagingDir();
  Future<Directory> mediaOf(MessengerParty party) => party.attachmentPaths.mediaDir();

  // [bytes] as the attach flow leaves them: a plaintext in staging.
  Future<File> stage(MessengerParty party, List<int> bytes) async =>
      File(p.join((await stagingOf(party)).path, 'staged-${DateTime.now().microsecondsSinceEpoch}'))
        ..writeAsBytesSync(bytes);

  Future<OutgoingAttachment> photo(MessengerParty party, Uint8List prepared) async =>
      OutgoingAttachment.photo(path: (await stage(party, prepared)).path, contentType: 'image/jpeg');

  Future<OutgoingAttachment> file(MessengerParty party, String name, List<int> bytes) async =>
      OutgoingAttachment.file(
        path: (await stage(party, bytes)).path,
        name: sanitizeFileName(name),
        contentType: contentTypeForName(sanitizeFileName(name)),
      );

  List<String> blobsIn(Directory media) => [
        for (final entity in media.listSync()) p.basename(entity.path),
      ];

  ChatMessage? queuedOf(MessengerParty party, {String conversationId = conv}) =>
      party.controller.messagesFor(conversationId).where((message) => message.id.startsWith('local-')).lastOrNull;

  Future<void> sent(MessengerParty party, {String conversationId = conv}) =>
      waitFor(() => party.controller.pendingCountFor(conversationId) == 0, reason: 'the attachment was not sent');

  Future<DecryptedMessage> latestAt(MessengerParty party, {String conversationId = conv}) async {
    await party.controller.loadConversationMessages(conversationId);
    return party.controller.decryptMessage(party.controller.messagesFor(conversationId).last);
  }

  // Holds the upload of what alice sends next until the returned completer
  // completes.
  Completer<void> holdUploads() => relay.uploadGate = Completer<void>();

  Future<void> uploading(MessengerParty party, String clientMessageId) => waitFor(
        () => party.controller.attachmentTransferForMessage(clientMessageId)?.phase == AttachmentTransferPhase.uploading,
        reason: 'the upload did not start',
      );

  group('a photo', () {
    test('goes as kind image with an empty body, sealed once, and bob opens the prepared bytes', () async {
      await deliver(alice, bob, 'photo next');
      final prepared = _preparedJpeg();
      final attachment = await photo(alice, prepared);
      final encryptsBefore = alice.crypto.counts.encrypt;

      expect(await alice.controller.sendAttachment(conversationId: conv, attachment: attachment), isTrue);
      // Sealed into the media folder at once: the staged plaintext is gone.
      expect(File(attachment.path).existsSync(), isFalse);
      expect((await stagingOf(alice)).listSync(), isEmpty);
      final own = await alice.controller.decryptMessage(queuedOf(alice)!);
      expect(own.messageKind, MessageKind.image);
      expect(own.body, '');
      expect(own.attachment!.algorithmHint, kAttachmentAlgorithmV2);
      expect(own.attachment!.contentType, 'image/jpeg');
      expect(own.attachment!.sizeBytes, prepared.length);
      await sent(alice);

      // One message frame per attachment, encrypted after the upload.
      expect(alice.crypto.counts.encrypt - encryptsBefore, 1);
      final reference = own.attachment!;
      expect(relay.uploadTickets, [reference.attachmentId]);
      expect(relay.uploadTicketContentTypes, ['application/octet-stream']);
      final uploaded = relay.uploadedBlobs[reference.attachmentId]!;
      final kept = await alice.controller.media.blobs.pathOf(conv, reference.attachmentId, reference.sha256);
      expect(File(kept!).readAsBytesSync(), uploaded, reason: 'the relay holds the blob the media store keeps');
      expect(_contains(uploaded, prepared), isFalse);
      for (final marker in ['Exif', 'GPS', 'staged-']) {
        expect(_contains(uploaded, ascii.encode(marker)), isFalse, reason: marker);
      }
      expect(blobsIn(await mediaOf(alice)), everyElement(matches(_blobName)));

      await waitFor(() => bob.controller.messagesFor(conv).length == 2);
      final received = await latestAt(bob);
      expect(received.messageKind, MessageKind.image);
      expect(received.body, '');
      final opened = await bob.crypto.messaging.decryptAttachment(
        reference: received.attachment!,
        ciphertext: uploaded,
        localIdentityPrivateRef: bob.device.identity.identityPrivateKeyRef,
      );
      expect(opened, prepared);
    });
  });

  group('a file', () {
    test('goes as kind file with the sanitized name, its type from the extension, and its blob stays', () async {
      await deliver(alice, bob, 'file next');
      final bytes = pdfBytes('lease');
      final attachment = await file(alice, 'Lease\u202Eagreement.pdf', bytes);
      expect(attachment.name, 'Leaseagreement.pdf');

      await alice.controller.sendAttachment(conversationId: conv, attachment: attachment);
      await sent(alice);
      await waitFor(() => bob.controller.messagesFor(conv).length == 2);

      final received = await latestAt(bob);
      expect(received.messageKind, MessageKind.file);
      expect(received.body, 'Leaseagreement.pdf');
      expect(received.attachment!.contentType, 'application/pdf');
      final reference = received.attachment!;
      final uploaded = relay.uploadedBlobs[reference.attachmentId]!;
      expect(_contains(uploaded, utf8.encode('Leaseagreement')), isFalse);
      expect(
        await bob.crypto.messaging.decryptAttachment(
          reference: reference,
          ciphertext: uploaded,
          localIdentityPrivateRef: bob.device.identity.identityPrivateKeyRef,
        ),
        bytes,
      );
      // The sender's own copy stays sealed, for its bubble.
      expect(await alice.controller.media.blobs.pathOf(conv, reference.attachmentId, reference.sha256), isNotNull);
      final own = await alice.controller.decryptMessage(alice.controller.messagesFor(conv).last);
      expect(own.messageKind, MessageKind.file);
      expect(own.body, 'Leaseagreement.pdf');
    });

    test('is sanitized again as it is sealed, whoever named it', () async {
      await deliver(alice, bob, 'raw name next');
      const raw = '  \u202Egpj.exe\u200F\u0007 ';
      final staged = await stage(alice, pdfBytes('raw'));
      await alice.controller.sendAttachment(
        conversationId: conv,
        attachment: OutgoingAttachment.file(path: staged.path, name: raw, contentType: 'application/octet-stream'),
      );
      await sent(alice);
      await waitFor(() => bob.controller.messagesFor(conv).length == 2);
      expect((await latestAt(bob)).body, sanitizeFileName(raw));
      expect(sanitizeFileName(raw), 'gpj.exe');
      expect((await alice.controller.decryptMessage(alice.controller.messagesFor(conv).last)).body, 'gpj.exe');
    });
  });

  group('the disappearing timer is stamped after the upload', () {
    // Moves the relay's clock and alice's own by [by], so the expiry clock
    // alice stamps and checks on moves with them.
    void moveClocks(Duration by) {
      relay.clockSkew += by;
      relay.deviceClockSkew['alice'] = (relay.deviceClockSkew['alice'] ?? Duration.zero) + by;
    }

    test('so a 10 s timer outlasts a 90 s upload, and the relay takes it', () async {
      await deliver(alice, bob, 'timer next');
      relay.refusePastExpiry = true;
      final gate = holdUploads();
      await alice.controller.sendAttachment(
        conversationId: conv,
        attachment: await photo(alice, _preparedJpeg()),
        disappearAfter: const Duration(seconds: 10),
      );
      final queued = queuedOf(alice)!;
      final reference = (await alice.controller.decryptMessage(queued)).attachment!;
      await uploading(alice, queued.clientMessageId!);

      moveClocks(const Duration(seconds: 90));
      await alice.controller.handleAppResumed();
      await settle();
      // Nothing about it carried an expiry yet, so nothing went.
      final still = queuedOf(alice);
      expect(still?.clientMessageId, queued.clientMessageId);
      expect(still!.expiresAt, isNull);
      expect((await alice.controller.decryptMessage(still)).messageKind, MessageKind.image);
      expect(await alice.controller.media.blobs.pathOf(conv, reference.attachmentId, reference.sha256), isNotNull);

      final released = alice.controller.expiryNow();
      gate.complete();
      await sent(alice);

      final stored = relay.conversations[conv]!.messages.last;
      final outer = DateTime.parse(stored['expiresAt'] as String);
      final expected = released.add(const Duration(seconds: 10));
      expect(outer.difference(expected).inMilliseconds.abs(), lessThan(1000));
      await waitFor(() => bob.controller.messagesFor(conv).length == 2);
      final inner = (await latestAt(bob)).expiresAt!;
      expect(inner.difference(expected).inMilliseconds.abs(), lessThan(1000));
      // The bubble and the blob's index entry carry the same stamp.
      expect(alice.controller.messagesFor(conv).last.expiresAt, isNotNull);
      final entry = (await alice.controller.media.blobs.entries()).single;
      expect(entry.expiresAt!.difference(expected).inMilliseconds.abs(), lessThan(1000));
    });

    // D18 for texts: D20 makes a text wait behind an upload in its chat, so
    // a timer stamped when it was queued could pass before it is posted.
    ChatMessage? queuedText(MessengerParty party) => party.controller
        .messagesFor(conv)
        .where((message) => message.id.startsWith('local-') && message.envelope.messageKind == MessageKind.text)
        .lastOrNull;

    test('a text sent behind a photo in a 10 s chat outlasts a 90 s upload, is stamped when it is posted, and arrives',
        () async {
      await deliver(alice, bob, 'timer next');
      relay.refusePastExpiry = true;
      final gate = holdUploads();
      await alice.controller.sendAttachment(
        conversationId: conv,
        attachment: await photo(alice, _preparedJpeg()),
        disappearAfter: const Duration(seconds: 10),
      );
      await alice.controller
          .sendText(conversationId: conv, body: 'look at this', disappearAfter: const Duration(seconds: 10));
      await settle();
      expect(alice.controller.pendingCountFor(conv), 2, reason: 'the text waits behind the upload (D20)');
      final waiting = queuedText(alice)!;
      expect(waiting.expiresAt, isNull, reason: 'a text that waits carries no expiry until it is posted');
      expect((await alice.controller.decryptMessage(waiting)).body, 'look at this');
      final stored = (await alice.cache.readPendingMessages())
          .singleWhere((record) => record.clientMessageId == waiting.clientMessageId);
      expect(stored.envelope.expiresAt, isNull);
      expect(stored.disappearAfterSeconds, 10);

      moveClocks(const Duration(seconds: 90));
      await alice.controller.handleAppResumed();
      await settle();
      // The expiry sweeps ran: the text is still in the chat and queued.
      expect(queuedText(alice)?.clientMessageId, waiting.clientMessageId, reason: 'the text left the chat unsent');
      expect((await alice.controller.decryptMessage(queuedText(alice)!)).body, 'look at this');
      expect(alice.controller.pendingCountFor(conv), 2);

      final released = alice.controller.expiryNow();
      gate.complete();
      await sent(alice);
      await waitFor(() async => (await bob.bodies(conv)).contains('look at this'),
          reason: 'the text queued behind the upload never reached bob');
      expect(alice.controller.errorMessage, isNull);
      final relayed = relay.conversations[conv]!.messages.last;
      final outer = DateTime.parse(relayed['expiresAt'] as String);
      final expected = released.add(const Duration(seconds: 10));
      expect(outer.difference(expected).inMilliseconds.abs(), lessThan(1000), reason: 'stamped when it was posted');
      final inner = (await latestAt(bob)).expiresAt!;
      expect(inner.difference(expected).inMilliseconds.abs(), lessThan(1000));
      final mine = alice.controller.messagesFor(conv).last;
      expect((await alice.controller.decryptMessage(mine)).body, 'look at this');
      expect(mine.expiresAt, isNotNull, reason: 'the sent text took its timer');
    });

    test('a text waiting for its stamp survives a restart and is stamped when it is posted', () async {
      await deliver(alice, bob, 'restart timer next');
      holdUploads();
      await alice.controller.sendAttachment(conversationId: conv, attachment: await file(alice, 'h.pdf', pdfBytes('h')));
      await uploading(alice, queuedOf(alice)!.clientMessageId!);
      await alice.controller
          .sendText(conversationId: conv, body: 'after the restart', disappearAfter: const Duration(minutes: 5));
      await settle();
      final textId = queuedText(alice)!.clientMessageId;

      await alice.restart(whileClosed: () async {
        relay.uploadGate = null;
        final text = (await alice.cache.readPendingMessages()).singleWhere((record) => record.attachmentUploadDraft == null);
        expect(text.disappearAfterSeconds, 300);
        expect(text.envelope.ciphertext, isEmpty, reason: 'it was sealed before it was posted');
      });
      final restartedAt = alice.controller.expiryNow();
      await sent(alice);
      await waitFor(() async => (await bob.bodies(conv)).contains('after the restart'));
      final relayed = relay.conversations[conv]!.messages.singleWhere((message) => message['clientMessageId'] == textId);
      final outer = DateTime.parse(relayed['expiresAt'] as String);
      expect(outer.isAfter(restartedAt.add(const Duration(minutes: 5)).subtract(const Duration(seconds: 2))), isTrue);
    });

    test('a timed text with nothing ahead of it is sealed and stamped when it is queued, as before', () async {
      await deliver(alice, bob, 'plain timer next');
      await alice.controller.sendText(conversationId: conv, body: 'right away', disappearAfter: const Duration(minutes: 1));
      await waitFor(() async => (await bob.bodies(conv)).contains('right away'));
      expect(alice.controller.messagesFor(conv).last.expiresAt, isNotNull);
    });

    test('on the relay clock, in the inner payload and the envelope', () async {
      await deliver(alice, bob, 'day timer next');
      relay.clockSkew = const Duration(minutes: 30);
      alice.api.serverClock.observe(HttpDate.format(relay.now()));
      await alice.controller.sendAttachment(
        conversationId: conv,
        attachment: await file(alice, 'notes.txt', utf8.encode('notes')),
        disappearAfter: const Duration(days: 1),
      );
      await sent(alice);

      final expected = relay.now().add(const Duration(days: 1));
      final outer = DateTime.parse(relay.conversations[conv]!.messages.last['expiresAt'] as String);
      expect(outer.difference(expected).inSeconds.abs(), lessThan(5));
      await waitFor(() => bob.controller.messagesFor(conv).length == 2);
      final inner = (await latestAt(bob)).expiresAt!;
      expect(inner.difference(expected).inSeconds.abs(), lessThan(5));
    });
  });

  group('order is kept within a chat, not across chats', () {
    test('a text to another chat goes while an upload is held; one to the same chat waits for it', () async {
      final carol = await MessengerParty.join(relay, handle: 'carol', userId: 'user-carol', deviceId: 'dev-carol');
      addTearDown(carol.dispose);
      relay.addDirect('conv-ac', 'alice', 'carol');
      await carol.signIn();
      await alice.controller.refreshConversations();
      await deliver(alice, bob, 'a first');
      await deliver(alice, carol, 'b first', conversationId: 'conv-ac');

      final gate = holdUploads();
      await alice.controller.sendAttachment(conversationId: conv, attachment: await file(alice, 'a.pdf', pdfBytes('a')));
      await uploading(alice, queuedOf(alice)!.clientMessageId!);
      await alice.controller.sendText(conversationId: conv, body: 'after the file');

      await deliver(alice, carol, 'to the other chat', conversationId: 'conv-ac');
      expect(alice.controller.pendingCountFor(conv), 2, reason: 'the text overtook the upload in its own chat');

      gate.complete();
      await sent(alice);
      final relayed = relay.conversations[conv]!;
      final last = relayed.messages.sublist(relayed.messages.length - 2);
      expect(relayed.attachmentIds[last.first['id']], isNotNull, reason: 'the file went first');
      expect(relayed.attachmentIds[last.last['id']], isNull);
      await waitFor(() async => (await bob.bodies(conv)).contains('after the file'));
    });
  });

  group('cancel removes the message', () {
    test('during the upload: nothing is left, the relay is told, and a restart brings nothing back', () async {
      await deliver(alice, bob, 'cancel next');
      final relayedBefore = relay.conversations[conv]!.messages.length;
      holdUploads();
      final attachment = await photo(alice, _preparedJpeg());
      await alice.controller.sendAttachment(conversationId: conv, attachment: attachment);
      final queued = queuedOf(alice)!;
      final id = queued.clientMessageId!;
      final reference = (await alice.controller.decryptMessage(queued)).attachment!;
      await uploading(alice, id);

      await alice.controller.cancelPendingAttachment(id);
      await alice.controller.retryPendingMessages(conv);
      await settle();

      void expectGone() {
        expect(alice.controller.messagesFor(conv).where((message) => message.clientMessageId == id), isEmpty);
        expect(alice.controller.pendingCountFor(conv), 0);
        expect(alice.controller.attachmentTransferForMessage(id), isNull);
      }

      expectGone();
      expect(await alice.cache.readPendingMessages(), isEmpty);
      expect(await alice.cache.get(localMessageContentKey(id)), isNull);
      expect(blobsIn(await mediaOf(alice)), isEmpty);
      expect(relay.attachments[reference.attachmentId]!.uploadStatus, 'failed');
      expect(relay.conversations[conv]!.messages, hasLength(relayedBefore));

      relay.uploadGate = null;
      await alice.restart();
      await settle();
      expectGone();
      expect(relay.conversations[conv]!.messages, hasLength(relayedBefore));
    });

    test('while the cache refuses to drop its record: blob and content still go, and a restart sends nothing', () async {
      await deliver(alice, bob, 'cancel, refused next');
      final relayedBefore = relay.conversations[conv]!.messages.length;
      holdUploads();
      await alice.controller.sendAttachment(conversationId: conv, attachment: await photo(alice, _preparedJpeg()));
      final id = queuedOf(alice)!.clientMessageId!;
      await uploading(alice, id);

      alice.cache.failPendingRemovals = 1;
      await expectLater(alice.controller.cancelPendingAttachment(id), throwsStateError);
      expect(alice.controller.messagesFor(conv).where((message) => message.clientMessageId == id), isEmpty);
      expect(await alice.cache.get(localMessageContentKey(id)), isNull);
      expect(blobsIn(await mediaOf(alice)), isEmpty);
      expect(await alice.cache.readPendingMessages(), hasLength(1), reason: 'the refused delete left its record');

      // The record left behind is dropped at the next start: nothing of it
      // reaches bob, and it does not come back on alice's phone.
      relay.uploadGate = null;
      await alice.restart();
      await alice.controller.retryPendingMessages(conv);
      await settle(const Duration(seconds: 1));
      expect(relay.uploadedBlobs, isEmpty);
      expect(relay.conversations[conv]!.messages, hasLength(relayedBefore));
      expect(blobsIn(await mediaOf(alice)), isEmpty);
      expect(alice.controller.messagesFor(conv).where((message) => message.clientMessageId == id), isEmpty);
      expect(await alice.cache.readPendingMessages(), isEmpty, reason: 'the record left behind was not dropped');
    });

    test('of a photo whose post failed after its upload, while the cache refuses to drop its record: '
        'the relay deletes the blob, and a restart neither sends nor shows it', () async {
      await deliver(alice, bob, 'posted later');
      final relayedBefore = relay.conversations[conv]!.messages.length;
      final gate = holdUploads();
      await alice.controller.sendAttachment(conversationId: conv, attachment: await photo(alice, _preparedJpeg()));
      final queued = queuedOf(alice)!;
      final id = queued.clientMessageId!;
      final reference = (await alice.controller.decryptMessage(queued)).attachment!;
      await uploading(alice, id);
      // The post after the upload is refused for good: bob blocked alice meanwhile.
      relay.blocks.putIfAbsent('user-bob', () => {})['user-alice'] = relay.now();
      gate.complete();
      relay.uploadGate = null;
      await waitFor(() => alice.controller.messagesFor(conv).any((m) => m.clientMessageId == id && m.hasFailed),
          reason: 'the post did not fail');
      expect(alice.controller.attachmentTransferForMessage(id)?.canCancel, isTrue, reason: 'no cross on it');
      expect(relay.uploadedBlobs, contains(reference.attachmentId));
      relay.blocks['user-bob']!.remove('user-alice');

      alice.cache.failPendingRemovals = 1;
      await expectLater(alice.controller.cancelPendingAttachment(id), throwsStateError);
      expect(alice.controller.messagesFor(conv).where((message) => message.clientMessageId == id), isEmpty);
      expect(relay.attachments[reference.attachmentId]!.uploadStatus, 'failed');
      expect(relay.uploadedBlobs, isNot(contains(reference.attachmentId)), reason: 'bob could still download it');
      expect(await alice.cache.readPendingMessages(), hasLength(1), reason: 'the refused delete left its record');

      await alice.restart();
      await alice.controller.retryPendingMessages(conv);
      await settle(const Duration(seconds: 1));
      expect(relay.conversations[conv]!.messages, hasLength(relayedBefore), reason: 'the removed photo was sent');
      expect(alice.controller.messagesFor(conv).where((message) => message.clientMessageId == id), isEmpty,
          reason: 'the removed photo came back after a restart');
      expect(await alice.cache.readPendingMessages(), isEmpty);
    });

    test('of an own photo shown while it uploads: its decrypted bytes leave memory with its blob (D36)', () async {
      alice.controller.media.setInUse(true);
      await deliver(alice, bob, 'shown next');
      holdUploads();
      final prepared = _preparedJpeg();
      await alice.controller.sendAttachment(conversationId: conv, attachment: await photo(alice, prepared));
      final queued = queuedOf(alice)!;
      final id = queued.clientMessageId!;
      final reference = (await alice.controller.decryptMessage(queued)).attachment!;
      await uploading(alice, id);
      // The bubble shows the own photo under the scrim, decrypted from its blob.
      expect(await alice.controller.media.photoBytes(conv, reference), prepared);
      expect(alice.controller.media.cachedPhotoBytes(conv, reference), isNotNull);

      await alice.controller.cancelPendingAttachment(id);
      await settle();
      expect(blobsIn(await mediaOf(alice)), isEmpty);
      expect(alice.controller.media.cachedPhotoBytes(conv, reference), isNull,
          reason: 'the decrypted photo of a cancelled message stayed in memory after its blob went');
      expect(alice.controller.media.statusOf(conv, reference).state, isNot(MediaState.ready));
    });

    test('of a failed attachment', () async {
      await deliver(alice, bob, 'failure next');
      relay.failUploads = 1;
      await alice.controller.sendAttachment(conversationId: conv, attachment: await file(alice, 'b.pdf', pdfBytes('b')));
      final id = queuedOf(alice)!.clientMessageId!;
      await waitFor(
        () => alice.controller.attachmentTransferForMessage(id)?.phase == AttachmentTransferPhase.failed,
        reason: 'the upload did not fail',
      );
      expect(alice.controller.attachmentTransferForMessage(id)!.canCancel, isTrue);

      await alice.controller.cancelPendingAttachment(id);
      await settle();
      expect(alice.controller.messagesFor(conv).where((message) => message.clientMessageId == id), isEmpty);
      expect(await alice.cache.readPendingMessages(), isEmpty);
      expect(blobsIn(await mediaOf(alice)), isEmpty);
    });

    test('racing a transient upload failure: still removed, never "Not sent"', () async {
      await deliver(alice, bob, 'race next');
      final gate = holdUploads();
      await alice.controller.sendAttachment(conversationId: conv, attachment: await file(alice, 'c.pdf', pdfBytes('c')));
      final id = queuedOf(alice)!.clientMessageId!;
      await uploading(alice, id);

      gate
        ..future.ignore()
        ..completeError(VeilApiException('The server is unreachable.', code: 'network_unavailable'));
      final cancel = alice.controller.cancelPendingAttachment(id);
      await cancel;
      await settle(const Duration(seconds: 1));

      expect(alice.controller.messagesFor(conv).where((message) => message.clientMessageId == id), isEmpty);
      expect(alice.controller.messagesFor(conv).where((message) => message.hasFailed), isEmpty);
      expect(alice.controller.errorMessage, isNull, reason: 'the failure was shown for a cancelled message');
      expect(await alice.cache.readPendingMessages(), isEmpty);
      expect(blobsIn(await mediaOf(alice)), isEmpty);
    });
  });

  test('cancel while the upload is being ticketed: the ticket is released, nothing is uploaded', () async {
    final gated = _TicketGatedRelay();
    final carol = await MessengerParty.join(gated, handle: 'carol', userId: 'user-carol', deviceId: 'dev-carol');
    final dave = await MessengerParty.join(gated, handle: 'dave', userId: 'user-dave', deviceId: 'dev-dave');
    addTearDown(() async {
      await carol.dispose();
      await dave.dispose();
    });
    gated.addDirect(conv, 'carol', 'dave');
    await carol.signIn();
    await dave.signIn();
    await deliver(carol, dave, 'ticket next');

    final gate = gated.ticketGate = Completer<void>();
    await carol.controller.sendAttachment(conversationId: conv, attachment: await file(carol, 'i.pdf', pdfBytes('i')));
    final id = queuedOf(carol)!.clientMessageId!;
    await waitFor(() => gated.ticketsAsked == 1, reason: 'no ticket was asked for');

    final cancel = carol.controller.cancelPendingAttachment(id);
    gate.complete();
    await cancel;
    await settle();
    expect(gated.attachments[gated.uploadTickets.single]!.uploadStatus, 'failed', reason: 'the relay was not told');
    expect(gated.uploadedBlobs, isEmpty);
    expect(carol.controller.messagesFor(conv).where((message) => message.clientMessageId == id), isEmpty);
    expect(await carol.cache.readPendingMessages(), isEmpty);
  });

  group('the sealed blob', () {
    test('survives a disappearing message expiring in the same chat during the upload, and uploads', () async {
      await alice.controller.sendText(conversationId: conv, body: 'gone soon', disappearAfter: const Duration(seconds: 10));
      await sent(alice);
      final gate = holdUploads();
      await alice.controller.sendAttachment(conversationId: conv, attachment: await file(alice, 'd.pdf', pdfBytes('d')));
      final id = queuedOf(alice)!.clientMessageId!;
      await uploading(alice, id);

      relay.clockSkew += const Duration(seconds: 90);
      relay.deviceClockSkew['alice'] = const Duration(seconds: 90);
      await alice.controller.handleAppResumed();
      await settle();
      expect(await alice.bodies(conv), isNot(contains('gone soon')));
      expect(blobsIn(await mediaOf(alice)), hasLength(1));
      expect(alice.controller.media.pendingAttachmentIds(), isNotEmpty);

      gate.complete();
      await sent(alice);
      expect(relay.uploadedBlobs, hasLength(1));
    });

    test('is uploaded again under the same sealed id after a transient failure', () async {
      await deliver(alice, bob, 'retry next');
      relay.failUploads = 1;
      await alice.controller.sendAttachment(conversationId: conv, attachment: await file(alice, 'e.pdf', pdfBytes('e')));
      final id = queuedOf(alice)!.clientMessageId!;
      await waitFor(() => alice.controller.attachmentTransferForMessage(id)?.phase == AttachmentTransferPhase.failed);
      await alice.controller.retryPendingMessages(conv);
      await sent(alice);
      expect(relay.uploadTickets, hasLength(2));
      expect(relay.uploadTickets.toSet(), hasLength(1));
      await waitFor(() => bob.controller.messagesFor(conv).length == 2);
      expect((await latestAt(bob)).attachment!.attachmentId, relay.uploadTickets.first);
    });

    test('is found again by its id and digest after a restart mid-upload; no path is stored', () async {
      await deliver(alice, bob, 'restart next');
      holdUploads();
      await alice.controller.sendAttachment(conversationId: conv, attachment: await file(alice, 'f.pdf', pdfBytes('f')));
      await uploading(alice, queuedOf(alice)!.clientMessageId!);

      await alice.restart(whileClosed: () async {
        relay.uploadGate = null;
        final draft = (await alice.cache.readPendingMessages()).single.attachmentUploadDraft!;
        expect(draft.tempFilePath, isNull);
        expect(draft.sealedReference, isNotNull);
      });
      await sent(alice);
      await waitFor(() => bob.controller.messagesFor(conv).length == 2);
      expect((await latestAt(bob)).messageKind, MessageKind.file);
    });

    test('still uploads when a stored absolute path no longer exists', () async {
      await deliver(alice, bob, 'stale path next');
      holdUploads();
      await alice.controller.sendAttachment(conversationId: conv, attachment: await file(alice, 'g.pdf', pdfBytes('g')));
      await uploading(alice, queuedOf(alice)!.clientMessageId!);

      await alice.restart(whileClosed: () async {
        relay.uploadGate = null;
        final record = (await alice.cache.readPendingMessages()).single;
        await alice.cache.upsertPendingMessage(record.copyWith(
          attachmentUploadDraft: record.attachmentUploadDraft!.copyWith(tempFilePath: '/var/mobile/Containers/old/f.blob'),
        ));
      });
      await sent(alice);
      await waitFor(() => bob.controller.messagesFor(conv).length == 2);
    });

    test('that is missing fails the send for good and nothing is uploaded in its place', () async {
      await deliver(alice, bob, 'missing next');
      holdUploads();
      await alice.controller.sendAttachment(conversationId: conv, attachment: await file(alice, 'h.pdf', pdfBytes('h')));
      await uploading(alice, queuedOf(alice)!.clientMessageId!);
      final ticketsBefore = relay.uploadTickets.length;

      await alice.restart(whileClosed: () async {
        relay.uploadGate = null;
        for (final entity in (await mediaOf(alice)).listSync()) {
          entity.deleteSync();
        }
      });
      await waitFor(() async => (await alice.cache.readPendingMessages()).single.state == MessageDeliveryState.failed);
      final record = (await alice.cache.readPendingMessages()).single;
      expect(record.nextRetryAt, isNull);
      expect(record.errorMessage, UserFacingErrorCode.attachmentRejected.sentence);
      expect(relay.uploadTickets, hasLength(ticketsBefore));
      expect(relay.uploadedBlobs, isEmpty);
    });

    test('of a draft an older build queued is never sent: it fails at restore and its staging file goes', () async {
      await deliver(alice, bob, 'old draft next');
      final staged = await stage(alice, pdfBytes('old'));
      await alice.restart(whileClosed: () async {
        await alice.cache.upsertPendingMessage(PendingMessageRecord(
          clientMessageId: 'client-old-draft',
          conversationId: conv,
          senderDeviceId: 'dev-alice',
          recipientUserId: 'user-bob',
          envelope: const CryptoEnvelope(
            version: '2',
            conversationId: conv,
            senderDeviceId: 'dev-alice',
            recipientUserId: 'user-bob',
            ciphertext: 'an-encrypted-placeholder',
            nonce: 'nonce',
            messageKind: MessageKind.file,
          ),
          createdAt: DateTime.now().toUtc(),
          state: MessageDeliveryState.uploading,
          attachmentUploadDraft: AttachmentUploadDraft(
            filename: 'old.pdf',
            contentType: 'application/pdf',
            sizeBytes: 64,
            sha256: 'old-hash',
            tempFilePath: staged.path,
          ),
        ));
      });
      await settle();

      final record = (await alice.cache.readPendingMessages()).single;
      expect(record.state, MessageDeliveryState.failed);
      expect(record.errorMessage, UserFacingErrorCode.attachmentRejected.sentence);
      // Failed as it was restored: no attempt was made to send it.
      expect(record.retryCount, 0);
      expect(staged.existsSync(), isFalse);
      expect((await stagingOf(alice)).listSync(), isEmpty);
      expect(relay.uploadTickets, isEmpty);
      expect(alice.controller.attachmentTransferForMessage('client-old-draft')!.canCancel, isTrue);
    });

    test('sealed while the app stopped before its record was written: the next start drops its blob and content',
        () async {
      await deliver(alice, bob, 'crash next');
      holdUploads();
      await alice.controller.sendAttachment(conversationId: conv, attachment: await file(alice, 'k.pdf', pdfBytes('k')));
      final orphan = queuedOf(alice)!.clientMessageId!;
      await uploading(alice, orphan);
      // A photo queued behind it, whose record did reach the cache, stays.
      await alice.controller.sendAttachment(conversationId: conv, attachment: await photo(alice, _preparedJpeg()));
      final queued = queuedOf(alice)!.clientMessageId!;
      expect(blobsIn(await mediaOf(alice)), hasLength(2));

      await alice.restart(whileClosed: () async {
        relay.uploadGate = null;
        // The stopped app's last writes land, in an earlier second than the
        // start that follows.
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        // What a stop between the blob's commit and the record's write
        // leaves: the sealed blob and its stored content (the key), no record.
        await alice.cache.removePendingMessage(orphan);
        expect((await alice.cache.readPendingMessages()).map((record) => record.clientMessageId), [queued]);
      });
      await sent(alice);

      expect(blobsIn(await mediaOf(alice)), hasLength(1), reason: 'the blob no record named was kept');
      expect(alice.controller.messagesFor(conv).where((message) => message.clientMessageId == orphan), isEmpty,
          reason: 'its bubble waits for a send that never comes');
      final echo = ChatMessage(
        id: 'local-$orphan',
        clientMessageId: orphan,
        senderDeviceId: 'dev-alice',
        sentAt: DateTime.now(),
        envelope: CryptoEnvelope(
            version: '',
            conversationId: conv,
            senderDeviceId: 'dev-alice',
            recipientUserId: 'user-bob',
            ciphertext: '',
            nonce: '',
            messageKind: MessageKind.file),
      );
      expect(await alice.cache.getMany([echo].map((message) => 'local:${message.clientMessageId}')), isEmpty,
          reason: 'its stored content, the key with it, was kept');
      expect(relay.uploadTickets, hasLength(2), reason: 'only the queued photo was uploaded after the restart');
      await waitFor(() => bob.controller.messagesFor(conv).length == 2);
      expect((await latestAt(bob)).messageKind, MessageKind.image);
    });

    test('of a held 1:1 is never sealed nor uploaded', () async {
      await deliver(alice, bob, 'hello bob');
      await deliver(bob, alice, 'hi alice');
      final ghost = await InjectedDevice.mint('dev-ghost', owner: bob);
      await ghost.handshake(relay, alice, 'ghost hello', conversationId: conv);
      await alice.controller.loadConversationMessages(conv);
      await settle();
      relay.bundleOverrides['bob'] = ghost.bundleJson;
      await alice.controller.sendText(conversationId: conv, body: 'to the ghost while bob is unverified');
      await sent(alice);
      await alice.pins.markVerified('user-bob', 'dev-bob', bob.device.identity.identityPublicKey);
      await alice.controller.sendText(conversationId: conv, body: 'after verifying bob');
      await settle();
      expect(alice.controller.pendingIdentityChangeFor(conv), isNotNull, reason: 'the chat is not held');

      final attachment = await photo(alice, _preparedJpeg());
      expect(await alice.controller.sendAttachment(conversationId: conv, attachment: attachment), isFalse);
      expect(File(attachment.path).existsSync(), isFalse, reason: 'the staged plaintext stayed');
      expect(blobsIn(await mediaOf(alice)), isEmpty);
      expect(relay.uploadTickets, isEmpty);
      expect(alice.controller.errorMessage, isNull, reason: 'the banner says why, not a toast');
    });

    test('sealed before its 1:1 was held is not uploaded once the hold is there, and waits with its blob', () async {
      await deliver(alice, bob, 'hello bob');
      await deliver(bob, alice, 'hi alice');
      final gate = holdUploads();
      await alice.controller
          .sendAttachment(conversationId: conv, attachment: await file(alice, 'one.pdf', pdfBytes('one')));
      await uploading(alice, queuedOf(alice)!.clientMessageId!);
      // Sealed and queued behind the first while the chat is not held yet.
      await alice.controller
          .sendAttachment(conversationId: conv, attachment: await file(alice, 'two.pdf', pdfBytes('two')));
      final second = queuedOf(alice)!.clientMessageId!;
      expect(relay.uploadTickets, hasLength(1));

      final ghost = await InjectedDevice.mint('dev-ghost', owner: bob);
      await ghost.handshake(relay, alice, 'ghost hello', conversationId: conv);
      await alice.controller.loadConversationMessages(conv);
      await settle();
      relay.bundleOverrides['bob'] = ghost.bundleJson;
      await alice.controller.sendText(conversationId: conv, body: 'to the ghost while bob is unverified');
      await alice.pins.markVerified('user-bob', 'dev-bob', bob.device.identity.identityPublicKey);
      await alice.controller.sendText(conversationId: conv, body: 'after verifying bob');
      await settle();
      expect(alice.controller.pendingIdentityChangeFor(conv), isNotNull, reason: 'the chat is not held');

      gate.complete();
      await settle(const Duration(seconds: 1));
      expect(relay.uploadTickets, hasLength(1), reason: 'the second was ticketed in a held chat');
      expect(relay.uploadedBlobs, hasLength(1), reason: 'the second was uploaded in a held chat');
      expect((await alice.cache.readPendingMessages()).map((record) => record.clientMessageId), contains(second));
      expect(blobsIn(await mediaOf(alice)), hasLength(2));
    });

    // No sweep can tell this blob from one whose message was sent (both have
    // a row and a file, no expiry, a listed chat): the send undoes itself.
    test('whose queued record the cache refuses leaves nothing: no blob, no content, no bubble, nothing sent', () async {
      await deliver(alice, bob, 'refused next');
      final relayedBefore = relay.conversations[conv]!.messages.length;
      alice.cache.failPendingWrites = 1;
      final attachment = await photo(alice, _preparedJpeg());

      expect(await alice.controller.sendAttachment(conversationId: conv, attachment: attachment), isFalse);
      final id = alice.cache.refusedPending.single.clientMessageId;
      expect(alice.cache.refusedPending.single.attachmentUploadDraft, isNotNull);
      expect(File(attachment.path).existsSync(), isFalse, reason: 'the staged plaintext stayed');
      void expectNothing() {
        expect(alice.controller.messagesFor(conv).where((message) => message.clientMessageId == id), isEmpty);
        expect(alice.controller.pendingCountFor(conv), 0);
        expect(alice.controller.attachmentTransferForMessage(id), isNull);
      }

      expectNothing();
      expect(await alice.cache.get(localMessageContentKey(id)), isNull, reason: 'its content stayed');
      expect(blobsIn(await mediaOf(alice)), isEmpty, reason: 'its sealed blob stayed');
      expect(await alice.controller.media.blobs.entries(), isEmpty);

      // The retry sweep and a manual retry find nothing of it to send.
      await alice.controller.retryPendingMessages(conv);
      await settle(const Duration(seconds: 4));
      expect(relay.uploadTickets, isEmpty);
      expect(relay.conversations[conv]!.messages, hasLength(relayedBefore));

      await alice.restart();
      await settle();
      expectNothing();
      expect(blobsIn(await mediaOf(alice)), isEmpty);
    });
  });
}

/// A relay whose upload tickets wait for [ticketGate] while it is set.
class _TicketGatedRelay extends FakeRelay {
  Completer<void>? ticketGate;
  int ticketsAsked = 0;
  final Map<String, FakeRelayClient> _clients = {};

  @override
  FakeRelayClient clientFor(String handle) =>
      _clients.putIfAbsent(handle, () => _TicketGatedClient(this, partiesByHandle[handle]!));
}

class _TicketGatedClient extends FakeRelayClient {
  _TicketGatedClient(_TicketGatedRelay super.relay, super.me);

  @override
  Future<Map<String, dynamic>> createUploadTicket(String accessToken, Map<String, dynamic> body) async {
    final gated = relay as _TicketGatedRelay;
    gated.ticketsAsked += 1;
    await gated.ticketGate?.future;
    return super.createUploadTicket(accessToken, body);
  }
}

// What EngineImagePreparer leaves of a photo: pixels as a JPEG, no metadata.
Uint8List _preparedJpeg() {
  final image = img.Image(width: 64, height: 48);
  img.fillRect(image, x1: 0, y1: 0, x2: 32, y2: 48, color: img.ColorRgb8(200, 120, 40));
  img.fillRect(image, x1: 32, y1: 0, x2: 64, y2: 48, color: img.ColorRgb8(40, 90, 160));
  return img.encodeJpg(image, quality: 80);
}

bool _contains(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || needle.length > haystack.length) return false;
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
