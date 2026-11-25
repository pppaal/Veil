import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/attachments/data/image_preparer.dart';
import 'package:veil_mobile/src/features/attachments/domain/attachment_rules.dart';
import 'package:veil_mobile/src/features/attachments/domain/outgoing_attachment.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/attachment_media_service.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/media_fixtures.dart';
import '../support/messenger_party.dart';

// A photo and a file from one phone to the other and back, end to end:
// the composer's path on the sender (sendAttachment seals the staged
// plaintext at once, uploads the sealed blob, then sends the one real
// frame) and the media service on the receiver (prefetch for the photo, a
// tap for the file, the digest, the decrypt). Two real LibCryptoAdapter
// devices, encrypted Drift caches and every attachment folder on disk, so
// what the test reads in the folders is what a phone would keep. Along the
// way: the unread count the two arrivals add and the open that clears it,
// the sender's own photo drawn from her own blob without a download, and
// what the relay ever holds.

const conv = 'conv-ab';

final _opaque = RegExp(r'^[0-9a-f]{64}$');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    // Both apps are in front and unlocked, as VeilApp reports it.
    alice.controller.media.setInUse(true);
    bob.controller.media.setInUse(true);
  });

  tearDown(() async {
    await alice.dispose();
    await bob.dispose();
  });

  Future<void> deliver(MessengerParty from, MessengerParty to, String body) async {
    await from.controller.sendText(conversationId: conv, body: body);
    await waitFor(() => from.controller.pendingCountFor(conv) == 0, reason: '"$body" was not acked');
    await waitFor(() async => (await to.bodies(conv)).contains(body), reason: '"$body" did not arrive');
  }

  // [bytes] as the attach flow leaves them: a plaintext under an opaque
  // name in the sender's staging folder.
  Future<String> stage(MessengerParty party, List<int> bytes) async {
    final staging = await party.attachmentPaths.stagingDir();
    final name = List.generate(32, (i) => ((DateTime.now().microsecondsSinceEpoch + i) % 16).toRadixString(16)).join();
    return (File(p.join(staging.path, name))..writeAsBytesSync(bytes)).path;
  }

  // Every file in [party]'s attachment folders (temporary, support and the
  // system temporary folder) that is not a sealed blob of the media folder:
  // a plaintext, wherever it sits.
  Future<List<String>> plaintextFiles(MessengerParty party) async {
    final media = (await party.attachmentPaths.mediaDir()).path;
    return [
      for (final entity in party.attachmentDirectory.listSync(recursive: true))
        if (entity is File && !p.equals(p.dirname(entity.path), media))
          p.relative(entity.path, from: party.attachmentDirectory.path),
    ];
  }

  Future<List<File>> sealedBlobs(MessengerParty party) async =>
      (await party.attachmentPaths.mediaDir()).listSync().whereType<File>().toList();

  // Sends a photo and a file from [from] to [to] through sendAttachment and
  // returns what [to] received, in order, with what was meant to arrive.
  Future<({AttachmentReference photo, AttachmentReference file, ChatMessage photoMessage})> sendBoth(
    MessengerParty from,
    MessengerParty to, {
    required Uint8List prepared,
    required List<int> pdf,
    required String name,
  }) async {
    final before = to.controller.messagesFor(conv).length;
    final photoPath = await stage(from, prepared);
    final pdfPath = await stage(from, pdf);
    expect(
      await from.controller.sendAttachment(
          conversationId: conv, attachment: OutgoingAttachment.photo(path: photoPath, contentType: 'image/jpeg')),
      isTrue,
    );
    expect(
      await from.controller.sendAttachment(
        conversationId: conv,
        attachment: OutgoingAttachment.file(
            path: pdfPath, name: sanitizeFileName(name), contentType: contentTypeForName(sanitizeFileName(name))),
      ),
      isTrue,
    );
    // Sealed at once: the staged plaintexts are gone before anything is uploaded.
    expect(File(photoPath).existsSync(), isFalse);
    expect(File(pdfPath).existsSync(), isFalse);
    expect((await from.attachmentPaths.stagingDir()).listSync(), isEmpty);
    await waitFor(() => from.controller.pendingCountFor(conv) == 0,
        timeout: const Duration(seconds: 10), reason: 'the photo and the file were not sent');
    await waitFor(() => to.controller.messagesFor(conv).length == before + 2,
        timeout: const Duration(seconds: 10), reason: 'the photo and the file did not arrive');

    final arrived = to.controller.messagesFor(conv).skip(before).toList();
    final photo = await to.controller.decryptMessage(arrived[0]);
    final file = await to.controller.decryptMessage(arrived[1]);
    expect(photo.isOk && file.isOk, isTrue, reason: 'the receiver could not open the messages');
    expect(photo.messageKind, MessageKind.image);
    expect(photo.body, '');
    expect(file.messageKind, MessageKind.file);
    expect(file.body, name);
    expect(photo.attachment!.algorithmHint, kAttachmentAlgorithmV2);
    expect(file.attachment!.contentType, 'application/pdf');
    return (photo: photo.attachment!, file: file.attachment!, photoMessage: arrived[0]);
  }

  // The sender's own photo comes from the blob it sealed, with no ticket
  // and no download of its own.
  Future<void> ownPhotoFromOwnBlob(MessengerParty sender, Uint8List prepared) async {
    final own = sender.controller.messagesFor(conv).where((message) => message.isMine).toList();
    final photoMessage = own[own.length - 2];
    final opened = await sender.controller.decryptMessage(photoMessage);
    expect(opened.messageKind, MessageKind.image);
    final reference = opened.attachment!;
    expect(await sender.controller.media.blobs.pathOf(conv, reference.attachmentId, reference.sha256), isNotNull);
    expect(await sender.controller.media.photoBytes(conv, reference, sentAt: photoMessage.sentAt), prepared);
    expect(sender.controller.media.statusOf(conv, reference).state, MediaState.ready);
    expect(relay.downloadTicketRequestsBy[sender.device.handle] ?? const [], isNot(contains(reference.attachmentId)));
    expect(relay.blobDownloadsBy[sender.device.handle] ?? const [], isNot(contains(reference.attachmentId)));
  }

  // The receiver's media service: the photo comes by itself and shows the
  // prepared bytes; the file waits for a tap and opens to the original
  // bytes, through a copy under veil_open that is the only plaintext on
  // the phone while the open (or a save) runs, and is gone after.
  Future<void> opensBoth(
    MessengerParty receiver, {
    required AttachmentReference photo,
    required AttachmentReference file,
    required Uint8List prepared,
    required List<int> pdf,
    required String name,
    required MediaCopyPurpose purpose,
  }) async {
    final media = receiver.controller.media;
    await waitFor(() => media.statusOf(conv, photo).state == MediaState.ready,
        timeout: const Duration(seconds: 10), reason: 'the photo did not come by itself');
    expect(media.statusOf(conv, file).state, MediaState.idle, reason: 'a file waits for a tap');
    expect(await media.photoBytes(conv, photo), prepared);
    expect(await plaintextFiles(receiver), isEmpty, reason: 'showing a photo writes nothing decrypted');

    final copy = await media.plaintextFileFor(conv, file, name: name, purpose: purpose);
    expect(copy, isNotNull);
    expect(File(copy!).readAsBytesSync(), pdf);
    final relative = p.relative(copy, from: receiver.attachmentDirectory.path);
    expect(await plaintextFiles(receiver), [relative], reason: 'more plaintext than the copy being opened');
    expect(p.split(relative), ['tmp', 'veil_open', isNotEmpty, name]);
    await media.releaseCopy(copy);
    expect(await plaintextFiles(receiver), isEmpty, reason: 'plaintext outlived the ${purpose.name}');
  }

  test('a photo and a file reach the other phone and the relay holds only ciphertext', () async {
    // A session first, by text.
    await deliver(alice, bob, 'hello');
    final unreadBefore = bob.controller.reads.unreadCount(conv);

    // A camera photo, prepared as the composer prepares it: upright, at
    // most 1600 px, re-encoded with nothing of its metadata.
    final camera = jpegWithMetadata(width: 2000, height: 1500, orientation: 6);
    final cameraPath = await stage(alice, camera);
    final prepared = (await EngineImagePreparer().prepare(cameraPath)).bytes;
    File(cameraPath).deleteSync();
    expect(img.decodeJpg(prepared)!.height, 1600);
    // The camera's location, make, model and other metadata were in the
    // picked photo and are not in what is sent (and what bob opens).
    for (final marker in [
      'Exif\u0000\u0000',
      'GPS fixture fix',
      fixtureMake,
      fixtureModel,
      fixtureMakerNote,
      fixtureXmpNamespace,
      fixtureXmpMarker,
    ]) {
      expect(_contains(camera, latin1.encode(marker)), isTrue, reason: 'the camera photo lacks $marker');
      expect(_contains(prepared, latin1.encode(marker)), isFalse, reason: 'the photo sent says $marker');
    }
    final pdf = pdfBytes('lease for the flat on Elm Street');
    const pdfName = 'Lease agreement Elm Street.pdf';

    // Alice to bob.
    final toBob = await sendBoth(alice, bob, prepared: prepared, pdf: pdf, name: pdfName);
    expect(bob.controller.reads.unreadCount(conv), unreadBefore + 2, reason: 'the two arrivals did not count');
    await ownPhotoFromOwnBlob(alice, prepared);
    await opensBoth(bob,
        photo: toBob.photo,
        file: toBob.file,
        prepared: prepared,
        pdf: pdf,
        name: pdfName,
        purpose: MediaCopyPurpose.open);

    // Bob opens the chat: read, and the count is back to nothing.
    bob.controller.setActiveConversation(conv);
    await waitFor(() => bob.controller.reads.unreadCount(conv) == 0, reason: 'opening the chat did not read them');
    bob.controller.setActiveConversation(null);

    // And back: bob to alice, the file saved this time.
    final reply = _preparedJpeg();
    final replyPdf = pdfBytes('the signed copy');
    const replyName = 'Signed lease.pdf';
    final unreadAlice = alice.controller.reads.unreadCount(conv);
    final toAlice = await sendBoth(bob, alice, prepared: reply, pdf: replyPdf, name: replyName);
    expect(alice.controller.reads.unreadCount(conv), unreadAlice + 2);
    await ownPhotoFromOwnBlob(bob, reply);
    await opensBoth(alice,
        photo: toAlice.photo,
        file: toAlice.file,
        prepared: reply,
        pdf: replyPdf,
        name: replyName,
        purpose: MediaCopyPurpose.save);

    // The relay holds four sealed blobs and the messages that point at
    // them, and none of it says what they hold: no plaintext, no prepared
    // photo, no metadata, no name, no type, no key.
    final plaintexts = <List<int>>[camera, prepared, pdf, reply, replyPdf];
    final references = [toBob.photo, toBob.file, toAlice.photo, toAlice.file];
    expect(relay.uploadedBlobs.keys.toSet(), {for (final reference in references) reference.attachmentId});
    for (final blob in relay.uploadedBlobs.values) {
      for (final plaintext in plaintexts) {
        expect(_contains(blob, plaintext.sublist(0, 64)), isFalse, reason: 'a blob holds plaintext');
      }
      // Long enough that ciphertext never holds one by chance.
      for (final marker in ['%PDF-1.4', 'Exif\u0000\u0000', fixtureMake, fixtureModel, 'Lease agreement', 'Signed lease']) {
        expect(_contains(blob, latin1.encode(marker)), isFalse, reason: 'a blob says $marker');
      }
    }
    final onRelay = jsonEncode(relay.conversations[conv]!.messages, toEncodable: (value) => '$value');
    for (final secret in [
      pdfName,
      replyName,
      'Lease',
      'application/pdf',
      'image/jpeg',
      for (final reference in references) ...[reference.encryptedKey, reference.nonce, reference.sha256],
    ]) {
      expect(onRelay, isNot(contains(secret)), reason: 'the relay\'s messages say $secret');
    }
    expect(relay.uploadTicketContentTypes, everyElement('application/octet-stream'));

    // On each phone: no plaintext anywhere in its temporary, support or
    // system temporary folders, and a media folder of opaque names whose
    // blobs are the very ciphertext the relay holds.
    for (final party in [alice, bob]) {
      expect(await plaintextFiles(party), isEmpty, reason: '${party.device.handle} kept plaintext');
      final blobs = await sealedBlobs(party);
      expect(blobs, hasLength(4), reason: '${party.device.handle}: two sent, two received');
      for (final blob in blobs) {
        expect(p.basename(blob.path), matches(_opaque));
        final bytes = blob.readAsBytesSync();
        expect(relay.uploadedBlobs.values.any((stored) => _same(stored, bytes)), isTrue,
            reason: '${party.device.handle} keeps a blob the relay never had');
        for (final plaintext in plaintexts) {
          expect(_contains(bytes, plaintext.sublist(0, 64)), isFalse);
        }
      }
      for (final name in [pdfName, replyName, 'Lease', 'Signed']) {
        expect(party.attachmentDirectory.listSync(recursive: true).any((entity) => p.basename(entity.path).contains(name)),
            isFalse,
            reason: '${party.device.handle} names a file $name');
      }
    }
  });
}

Uint8List _preparedJpeg() {
  final image = img.Image(width: 64, height: 48);
  img.fillRect(image, x1: 0, y1: 0, x2: 32, y2: 48, color: img.ColorRgb8(200, 120, 40));
  img.fillRect(image, x1: 32, y1: 0, x2: 64, y2: 48, color: img.ColorRgb8(40, 90, 160));
  return img.encodeJpg(image, quality: 80);
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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
