import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/attachment_media_service.dart';

import '../../support/media_fixtures.dart';
import 'layout_seed.dart';
import 'layout_world.dart';

// Photos and files sent to alex, sealed for real (pointer v2, as a phone
// or the web seals them), their blobs on the fake relay, the messages that
// point at them delivered over the socket after the first list. What this
// device fetches and opens, it does through its own media service, on
// isolates and files, which only real time moves: before the app is up
// there is no tester, so the binding drives it.

/// The photo of the beach, 3:2, Sam sends first.
final Uint8List landscapePhoto = _scene(1200, 800, seed: 3);

/// The photo of the stairwell, 2:3.
final Uint8List portraitPhoto = _scene(800, 1200, seed: 7);

/// The photo alex sent.
final Uint8List ownPhoto = _scene(1000, 750, seed: 11);

/// The PDF Sam sends (a scan's size), and its name as he wrote it.
final Uint8List leasePdf = Uint8List.fromList([...pdfBytes('lease, signed by both'), ...List<int>.filled(240 * 1024, 0x20)]);
const leaseFileName = 'Lease agreement Elm Street signed final.pdf';

/// A voice message recorded on the web: a file this version does not play.
final Uint8List webVoiceNote = Uint8List.fromList(List<int>.generate(57344, (i) => (i * 31) % 251));

/// Runs real time until [done] holds, pumping the test's clock between
/// turns so the work the media service queued on it goes on too.
Future<void> untilReal(bool Function() done, {int rounds = 400}) async {
  final binding = TestWidgetsFlutterBinding.instance;
  for (var i = 0; i < rounds && !done(); i++) {
    await binding.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await binding.pump();
  }
}

int _ids = 0;
String _attachmentId() => '7a1c3e5f-2b4d-4c6e-8f0a-${(++_ids).toRadixString(16).padLeft(12, '0')}';

/// One attachment message: what it points at, and the message once this
/// device has it.
class SeededAttachment {
  SeededAttachment(this.reference, this.message);

  final AttachmentReference reference;
  final ChatMessage message;
}

/// Puts a message of [kind] pointing at [plaintext] in [conversationId],
/// from [from] (alex's own when [from] is alex) at [hour]:[minute] this
/// morning, and waits until this device lists it. [uploaded] false leaves
/// the blob off the relay, as one it deleted.
Future<SeededAttachment> deliverAttachment(
  LayoutWorld world, {
  required List<int> plaintext,
  required String contentType,
  required MessageKind kind,
  required int hour,
  required int minute,
  String conversationId = chatConversationId,
  String from = peerHandle,
  String body = '',
  bool uploaded = true,
  DateTime? expiresAt,
}) async {
  final relay = world.relay;
  final mine = from == selfHandle;
  final peer = conversationId == chatConversationId ? peerHandle : from;
  final id = _attachmentId();
  final sealed = (await TestWidgetsFlutterBinding.instance
      .runAsync(() => sealV2(plaintext, attachmentId: id, contentType: contentType, seed: _ids)))!;
  final reference = sealed.reference;
  if (uploaded) relay.putUploadedBlob(reference.attachmentId, sealed.blob, uploaderDeviceId: 'dev-$from');
  final sealer = createDefaultCryptoAdapter();
  final recipient = mine ? peer : selfHandle;
  final envelope = await sealer.messaging.encryptMessage(
    conversationId: conversationId,
    senderDeviceId: 'dev-$from',
    recipientUserId: 'user-$recipient',
    body: body,
    messageKind: kind,
    recipientBundle: KeyBundle(
      userId: 'user-$recipient',
      deviceId: 'dev-$recipient',
      handle: recipient,
      identityPublicKey: 'ik',
      signedPrekeyBundle: 'spk',
    ),
    attachment: reference,
    expiresAt: expiresAt,
  );
  final stored = relay.inject(
    senderHandle: from,
    conversationId: conversationId,
    envelope: sealer.envelopeCodec.encodeApiEnvelope(envelope),
  );
  final sentAt = DateTime.utc(2026, 4, 7, hour, minute);
  stored['serverReceivedAt'] = sentAt.toIso8601String();
  if (mine) {
    stored['deliveredAt'] = sentAt.add(const Duration(seconds: 2)).toIso8601String();
    stored['readAt'] = sentAt.add(const Duration(minutes: 1)).toIso8601String();
    // No device opens its own frames: what alex sent is what he stored,
    // and the photo's sealed blob stays on the phone it was sent from.
    await world.cache.put(MessageContentRecord(
      messageKey: stored['id'] as String,
      conversationId: conversationId,
      serverMessageId: stored['id'] as String,
      senderDeviceId: 'dev-$selfHandle',
      body: body,
      kind: kind,
      attachment: reference,
      status: MessageContentStatus.ok,
      createdAt: sentAt,
      updatedAt: sentAt,
    ));
    var written = false;
    unawaited(world.messenger.media.blobs
        .write(
          conversationId: conversationId,
          attachmentId: reference.attachmentId,
          digest: reference.sha256,
          sealedBytes: sealed.blob,
        )
        .whenComplete(() => written = true));
    await untilReal(() => written);
  }
  relay.realtimeFor(selfHandle).deliver('message.new', Map<String, dynamic>.of(stored));
  final messageId = stored['id'] as String;
  await untilReal(() => world.messenger.messagesFor(conversationId).any((message) => message.id == messageId));
  final message = world.messenger.messagesFor(conversationId).firstWhere((message) => message.id == messageId);
  return SeededAttachment(reference, message);
}

/// Fetches [attachment] as a tap does and, for a photo, opens it into
/// memory, as its bubble would once on screen.
Future<void> fetchAndOpen(LayoutWorld world, SeededAttachment attachment, {bool photo = true}) async {
  final media = world.messenger.media;
  final conversationId = attachment.message.envelope.conversationId;
  final reference = attachment.reference;
  if (media.statusOf(conversationId, reference).state != MediaState.ready) {
    unawaited(media.download(conversationId, reference));
    await untilReal(() {
      final state = media.statusOf(conversationId, reference).state;
      return state != MediaState.downloading && state != MediaState.idle;
    });
  }
  if (!photo) return;
  var opened = false;
  unawaited(media.photoBytes(conversationId, reference, userAsked: true).whenComplete(() => opened = true));
  await untilReal(() => opened);
}

/// Starts fetching [attachment] and leaves it on its way: the relay holds
/// every download until the world goes.
Future<void> startHeldDownload(LayoutWorld world, SeededAttachment attachment) async {
  final media = world.messenger.media;
  world.relay.downloadGate ??= Completer<void>();
  unawaited(media.download(attachment.message.envelope.conversationId, attachment.reference));
  await untilReal(() =>
      media.statusOf(attachment.message.envelope.conversationId, attachment.reference).state == MediaState.downloading);
}

/// Sam's chat with two photos from him, one of alex's, his signed lease and
/// a voice message from the web, all fetched and opened.
Future<void> seedChatPhotos(LayoutWorld world) async {
  final landscape = await deliverAttachment(world,
      plaintext: landscapePhoto, contentType: 'image/jpeg', kind: MessageKind.image, hour: 10, minute: 14);
  final portrait = await deliverAttachment(world,
      plaintext: portraitPhoto, contentType: 'image/jpeg', kind: MessageKind.image, hour: 10, minute: 15);
  final own = await deliverAttachment(world,
      plaintext: ownPhoto, contentType: 'image/jpeg', kind: MessageKind.image, hour: 10, minute: 16, from: selfHandle);
  final lease = await deliverAttachment(world,
      plaintext: leasePdf,
      contentType: 'application/pdf',
      kind: MessageKind.file,
      body: leaseFileName,
      hour: 10,
      minute: 17);
  await deliverAttachment(world,
      plaintext: webVoiceNote, contentType: 'audio/webm', kind: MessageKind.voice, hour: 10, minute: 18);
  for (final photo in [landscape, portrait, own]) {
    await fetchAndOpen(world, photo);
  }
  await fetchAndOpen(world, lease, photo: false);
}

/// Sam's chat with one photo of each state a photo or a file stands in
/// before it opens: on its way, failed, gone from the server, a file not
/// fetched yet and a file on its way.
Future<void> seedPhotoStates(LayoutWorld world) async {
  final failed = await deliverAttachment(world,
      plaintext: landscapePhoto, contentType: 'image/jpeg', kind: MessageKind.image, hour: 10, minute: 12);
  final gone = await deliverAttachment(world,
      plaintext: portraitPhoto,
      contentType: 'image/jpeg',
      kind: MessageKind.image,
      hour: 10,
      minute: 13,
      uploaded: false);
  await deliverAttachment(world,
      plaintext: leasePdf,
      contentType: 'application/pdf',
      kind: MessageKind.file,
      body: leaseFileName,
      hour: 10,
      minute: 14);
  final fileOnItsWay = await deliverAttachment(world,
      plaintext: pdfBytes('inventory'),
      contentType: 'application/pdf',
      kind: MessageKind.file,
      body: 'Inventory.pdf',
      hour: 10,
      minute: 15);
  final photoOnItsWay = await deliverAttachment(world,
      plaintext: ownPhoto, contentType: 'image/jpeg', kind: MessageKind.image, hour: 10, minute: 16);
  world.relay.failDownloads = 1;
  await fetchAndOpen(world, failed, photo: false);
  await fetchAndOpen(world, gone, photo: false);
  await startHeldDownload(world, fileOnItsWay);
  await startHeldDownload(world, photoOnItsWay);
}

/// Sam's chat ending on one opened photo: [portrait] or the landscape one.
Future<void> seedOnePhoto(LayoutWorld world, {bool portrait = false}) async {
  final photo = await deliverAttachment(world,
      plaintext: portrait ? portraitPhoto : landscapePhoto,
      contentType: 'image/jpeg',
      kind: MessageKind.image,
      hour: 10,
      minute: 16);
  await fetchAndOpen(world, photo);
}

/// Sam's chat ending on his signed lease, fetched.
Future<void> seedLease(LayoutWorld world) async {
  final lease = await deliverAttachment(world,
      plaintext: leasePdf,
      contentType: 'application/pdf',
      kind: MessageKind.file,
      body: leaseFileName,
      hour: 10,
      minute: 16);
  await fetchAndOpen(world, lease, photo: false);
}

/// The group ending on a photo from Priya, after Omar's line, opened.
Future<void> seedGroupPhoto(LayoutWorld world) async {
  final photo = await deliverAttachment(world,
      plaintext: landscapePhoto,
      contentType: 'image/jpeg',
      kind: MessageKind.image,
      hour: 10,
      minute: 16,
      conversationId: groupConversationId,
      from: noticeChatPeerHandle);
  await fetchAndOpen(world, photo);
}

// A photo-like scene: a sky that lightens toward the horizon, a sea, a
// strip of sand, and a little noise, so a render reads as a photo and its
// JPEG has a photo's size.
Uint8List _scene(int width, int height, {required int seed}) {
  final random = math.Random(seed);
  final image = img.Image(width: width, height: height);
  final horizon = (height * 0.55).round();
  final shore = (height * 0.78).round();
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final noise = random.nextInt(9) - 4;
      int r, g, b;
      if (y < horizon) {
        final t = y / horizon;
        r = (92 + 120 * t).round();
        g = (146 + 80 * t).round();
        b = (214 + 30 * t).round();
      } else if (y < shore) {
        final t = (y - horizon) / (shore - horizon);
        r = (38 + 30 * t).round();
        g = (104 + 40 * t).round();
        b = (150 + 20 * t).round();
      } else {
        r = 222;
        g = 198;
        b = 152;
      }
      image.setPixelRgb(x, y, (r + noise).clamp(0, 255), (g + noise).clamp(0, 255), (b + noise).clamp(0, 255));
    }
  }
  return img.encodeJpg(image, quality: 80);
}
