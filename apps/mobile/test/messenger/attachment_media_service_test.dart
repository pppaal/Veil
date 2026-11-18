import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/app/app_session_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/identity/identity_key_value_backend.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_resolver.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_store.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/core/storage/media_index.dart';
import 'package:veil_mobile/src/core/util/base64url.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_decrypt.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_storage_paths.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_temp_file_store.dart';
import 'package:veil_mobile/src/features/attachments/data/media_blob_store.dart';
import 'package:veil_mobile/src/features/attachments/data/media_cleanup.dart';
import 'package:veil_mobile/src/features/attachments/data/media_prefetch.dart';
import 'package:veil_mobile/src/features/attachments/domain/attachment_rules.dart';
import 'package:veil_mobile/src/features/chat/presentation/photo_image_provider.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/attachment_media_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/media_fixtures.dart';
import '../support/mock_relay_parties.dart';

// Receiving photos and files: what is fetched by itself and what is not,
// what a hostile pointer or relay can make the phone do, what is decrypted
// and when, and what the cleanup takes. A real messenger over the fake
// relay, with the media folders in a temporary folder of each test's and
// the media index in memory.

const _chat = 'conv-1';
const _group = 'conv-team';

int _ids = 0;
String _uuid() => '00000000-0000-4000-8000-${(++_ids).toString().padLeft(12, '0')}';

class _Phone {
  _Phone._(this.relay, this.root, this.paths, this.index, this.trust, this.blocked, this.controller);

  final FakeRelay relay;
  final Directory root;
  final AttachmentStoragePaths paths;
  final MediaIndex index;
  final IdentityTrust trust;
  final Set<String> blocked;
  final VeilMessengerController controller;
  final MockCryptoAdapter _sealer = MockCryptoAdapter();

  AttachmentMediaService get media => controller.media;

  static Future<_Phone> start({bool inUse = true, void Function(Directory root)? beforeStart}) async {
    final relay = FakeRelay();
    seedMockParties(relay, _chat, ['atlas', 'selene']);
    relay.addGroup(_group, ['atlas', 'selene'], useSenderKeys: false);
    final root = Directory.systemTemp.createTempSync('veil-media-');
    beforeStart?.call(root);
    final paths = AttachmentStoragePaths(
      temporaryRoot: () async => Directory('${root.path}/tmp')..createSync(recursive: true),
      supportRoot: () async => Directory('${root.path}/support')..createSync(recursive: true),
      systemTempRoot: () => Directory('${root.path}/system-tmp')..createSync(recursive: true),
      sweepSystemTemp: true,
    );
    final index = MemoryMediaIndex();
    final trust =
        IdentityTrust(TrustedIdentityResolver(store: TrustedIdentityStore(InMemoryIdentityKeyValueBackend())));
    final blocked = <String>{};
    final crypto = MockCryptoAdapter();
    final controller = VeilMessengerController(
      apiClient: relay.clientFor('atlas'),
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
      realtimeService: relay.realtimeFor('atlas'),
      cacheService: null,
      attachmentTempFileStore: DefaultAttachmentTempFileStore(paths: paths),
      identityTrust: trust,
      attachmentPaths: paths,
      mediaIndex: index,
      isBlockedDirect: blocked.contains,
    );
    await controller.applySession(mockPartySession('atlas'));
    if (inUse) controller.media.setInUse(true);
    return _Phone._(relay, root, paths, index, trust, blocked, controller);
  }

  /// [plaintext] sealed as selene's phone seals it and put in storage
  /// unless [uploaded] is false.
  Future<AttachmentReference> seal(List<int> plaintext,
      {String contentType = 'image/jpeg', String? id, int seed = 1, bool uploaded = true}) async {
    final sealed = await sealV2(plaintext, attachmentId: id ?? _uuid(), contentType: contentType, seed: seed);
    if (uploaded) relay.putUploadedBlob(sealed.reference.attachmentId, sealed.blob, uploaderDeviceId: 'dev-selene');
    return sealed.reference;
  }

  /// A message from selene as it arrives over the socket; the message once
  /// this phone has it.
  Future<ChatMessage> receive({
    String conversationId = _chat,
    MessageKind kind = MessageKind.image,
    String body = '',
    AttachmentReference? attachment,
    DateTime? expiresAt,
  }) async {
    final envelope = await _sealer.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: 'dev-selene',
      recipientUserId: 'user-atlas',
      body: body,
      messageKind: kind,
      recipientBundle: const KeyBundle(
        userId: 'user-atlas',
        deviceId: 'dev-atlas',
        handle: 'atlas',
        identityPublicKey: 'ik',
        signedPrekeyBundle: 'spk',
      ),
      expiresAt: expiresAt,
      attachment: attachment,
    );
    final stored = relay.inject(
      senderHandle: 'selene',
      conversationId: conversationId,
      envelope: _sealer.envelopeCodec.encodeApiEnvelope(envelope),
    );
    relay.realtimeFor('atlas').deliver('message.new', Map<String, dynamic>.of(stored));
    final id = stored['id'] as String;
    await waitFor(() => controller.messagesFor(conversationId).any((message) => message.id == id),
        reason: 'the message never arrived');
    final message = controller.messagesFor(conversationId).firstWhere((message) => message.id == id);
    expect((await controller.decryptMessage(message)).isOk, isTrue, reason: 'the message did not open');
    return message;
  }

  MediaState stateOf(AttachmentReference reference, [String conversationId = _chat]) =>
      media.statusOf(conversationId, reference).state;

  Future<void> waitForState(AttachmentReference reference, MediaState state, [String conversationId = _chat]) =>
      waitFor(() => stateOf(reference, conversationId) == state,
          reason: 'never ${state.name}, still ${stateOf(reference, conversationId).name}');

  Future<List<String>> mediaFiles() async =>
      [for (final entity in (await paths.mediaDir()).listSync()) p.basename(entity.path)]..sort();

  Future<List<String>> openFiles() async => [
        for (final entity in (await paths.openDir()).listSync(recursive: true))
          if (entity is File) entity.path,
      ];

  void dispose() {
    controller.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

AttachmentReference _withPointer(AttachmentReference reference,
        {String? attachmentId, int? sizeBytes, String? encryptedKey, String? algorithmHint}) =>
    AttachmentReference(
      attachmentId: attachmentId ?? reference.attachmentId,
      storageKey: reference.storageKey,
      contentType: reference.contentType,
      sizeBytes: sizeBytes ?? reference.sizeBytes,
      sha256: reference.sha256,
      encryptedKey: encryptedKey ?? reference.encryptedKey,
      nonce: reference.nonce,
      algorithmHint: algorithmHint ?? reference.algorithmHint,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Phone phone;
  final photo = jpegWithMetadata(width: 64, height: 48);

  setUp(() async {
    debugAttachmentDecrypts = 0;
    PhotoImageProvider.debugDecodes = 0;
    phone = await _Phone.start();
  });

  tearDown(() => phone.dispose());

  group('prefetch (D25)', () {
    test('a photo that arrives is fetched and digest-checked at once, and nothing is decrypted until it is shown',
        () async {
      final reference = await phone.seal(photo);
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.ready);

      expect(phone.relay.downloadTicketRequests, [reference.attachmentId]);
      expect(phone.relay.blobDownloads, [reference.attachmentId]);
      expect(debugAttachmentDecrypts, 0, reason: 'a prefetch decrypted');
      expect(await phone.index.all(), hasLength(1));
      expect(phone.media.cachedPhotoBytes(_chat, reference), isNull);

      final bytes = await phone.media.photoBytes(_chat, reference);
      expect(bytes, photo);
      expect(debugAttachmentDecrypts, 1);
      expect(phone.relay.blobDownloads, hasLength(1), reason: 'shown from the blob already here');
    });

    test('a photo that arrives while the app is locked waits for the unlock', () async {
      phone.media.setInUse(false);
      final reference = await phone.seal(photo);
      await phone.receive(attachment: reference);
      await settle();
      expect(phone.relay.downloadTicketRequests, isEmpty);

      phone.media.setInUse(true);
      await phone.waitForState(reference, MediaState.ready);
      expect(phone.relay.blobDownloads, [reference.attachmentId]);
      expect(debugAttachmentDecrypts, 0);
    });

    test('a file never comes by itself; a tap fetches it', () async {
      final reference = await phone.seal(pdfBytes('lease'), contentType: 'application/pdf');
      await phone.receive(kind: MessageKind.file, body: 'lease.pdf', attachment: reference);
      await settle();
      expect(phone.relay.downloadTicketRequests, isEmpty);
      expect(phone.stateOf(reference), MediaState.idle);

      await phone.media.download(_chat, reference);
      expect(phone.stateOf(reference), MediaState.ready);
      expect(phone.relay.blobDownloads, [reference.attachmentId]);
      expect(debugAttachmentDecrypts, 0, reason: 'fetching a file decrypts nothing');
    });

    test('a 30 MiB photo is not fetched by itself, and a tap fetches it', () async {
      final reference = _withPointer(await phone.seal(photo), sizeBytes: 30 * 1024 * 1024);
      await phone.receive(attachment: reference);
      await settle();
      expect(phone.relay.downloadTicketRequests, isEmpty);
      expect(await phone.media.photoBytes(_chat, reference), isNull, reason: 'a bubble built for it fetches nothing');
      await settle();
      expect(phone.relay.downloadTicketRequests, isEmpty);

      expect(await phone.media.photoBytes(_chat, reference, userAsked: true), photo);
      expect(phone.relay.blobDownloads, [reference.attachmentId]);
    });

    test('a photo from a 1:1 with someone blocked is not fetched by itself; a tap fetches it', () async {
      phone.blocked.add(_chat);
      final reference = await phone.seal(photo);
      await phone.receive(attachment: reference);
      await settle();
      expect(await phone.media.photoBytes(_chat, reference), isNull);
      await settle();
      expect(phone.relay.downloadTicketRequests, isEmpty);
      expect(phone.stateOf(reference), MediaState.idle);

      expect(await phone.media.photoBytes(_chat, reference, userAsked: true), photo);
    });

    test('nothing is fetched from a chat whose peer changed safety number until that is settled', () async {
      final selene = phone.relay.partiesByHandle['selene']!;
      await phone.trust.resolver.evaluate(selene.userId, selene.deviceId, selene.identity.identityPublicKey);
      final changedKey = base64UrlNoPadEncode(utf8.encode('ik-selene-new'));
      await phone.trust.admit(_group, selene.userId, selene.deviceId, changedKey);
      expect(phone.media.autoDownloadWithheld(_chat), isTrue, reason: 'who selene is waits in the group');

      final reference = await phone.seal(photo);
      final message = await phone.receive(attachment: reference);
      await settle();
      expect(await phone.media.photoBytes(_chat, reference, sentAt: message.sentAt), isNull);
      await settle();
      expect(phone.relay.downloadTicketRequests, isEmpty);

      await phone.controller.approveIdentityChange(_group, reviewed: phone.controller.pendingIdentityChangeFor(_group));
      expect(phone.media.autoDownloadWithheld(_chat), isFalse);
      // Settled: the photo's bubble fetches it by the same rules.
      expect(await phone.media.photoBytes(_chat, reference, sentAt: message.sentAt), isNull);
      await phone.waitForState(reference, MediaState.ready);
      expect(await phone.media.photoBytes(_chat, reference), photo);
    });

    test('nothing is fetched from a 1:1 held for its account', () async {
      phone.relay.listedHandles['atlas'] = {'selene': 'atlas'};
      await phone.controller.refreshConversations();
      expect(phone.controller.peerAccountHoldFor(_chat), isNotNull);
      final reference = await phone.seal(photo);
      phone.relay.inject(senderHandle: 'selene', conversationId: _chat, envelope: {
        'version': 'v2',
        'conversationId': _chat,
        'senderDeviceId': 'dev-selene',
        'ciphertext': 'held',
        'nonce': 'n',
        'messageType': 'image',
        'attachment': {'attachmentId': reference.attachmentId},
      });
      await phone.controller.loadConversationMessages(_chat);
      for (final message in phone.controller.messagesFor(_chat)) {
        expect(await phone.media.photoBytes(_chat, reference, sentAt: message.sentAt), isNull);
      }
      await settle();
      expect(phone.relay.downloadTicketRequests, isEmpty);
      expect(phone.relay.blobDownloads, isEmpty);
    });

    test('at most two transfers run at once', () async {
      phone.relay.downloadGate = Completer<void>();
      final references = [for (var seed = 1; seed <= 4; seed++) await phone.seal(photo, seed: seed)];
      for (final reference in references) {
        await phone.receive(attachment: reference);
      }
      await waitFor(() => phone.relay.blobDownloads.length == 2);
      await settle();
      expect(phone.relay.blobDownloads, hasLength(2), reason: 'a third transfer started');

      phone.relay.downloadGate!.complete();
      for (final reference in references) {
        await phone.waitForState(reference, MediaState.ready);
      }
      expect(phone.relay.blobDownloads, hasLength(4));
    });

    // Two photos hold both transfer slots, then a file is tapped (what
    // openFileAttachment does): its card shows the ring and the cross.
    Future<(AttachmentReference, Future<String?>)> tapFileBehindTwoPhotos() async {
      phone.relay.downloadGate = Completer<void>();
      for (var seed = 1; seed <= 2; seed++) {
        await phone.receive(attachment: await phone.seal(photo, seed: seed));
      }
      await waitFor(() => phone.relay.blobDownloads.length == 2);
      final fileRef = await phone.seal(pdfBytes('queued'), contentType: 'application/pdf');
      await phone.receive(kind: MessageKind.file, body: 'queued.pdf', attachment: fileRef);
      final opening = phone.media.plaintextFileFor(_chat, fileRef, name: 'queued.pdf', purpose: MediaCopyPurpose.open);
      await settle();
      expect(phone.stateOf(fileRef), MediaState.downloading, reason: 'the card shows the ring and the cross');
      return (fileRef, opening);
    }

    test('the cross on a file whose tap waits for a transfer slot stops it: nothing is fetched or opened', () async {
      final (fileRef, opening) = await tapFileBehindTwoPhotos();
      phone.media.cancel(_chat, fileRef);
      expect(phone.stateOf(fileRef), MediaState.idle, reason: 'the card stayed on downloading after the cross');

      phone.relay.downloadGate!.complete();
      expect(await opening, isNull, reason: 'a cancelled tap still opened the file in another app');
      await settle();
      expect(phone.relay.blobDownloads, isNot(contains(fileRef.attachmentId)), reason: 'cancelled, yet fetched');
      expect(await phone.openFiles(), isEmpty, reason: 'a decrypted copy was made for a cancelled tap');
      expect(phone.stateOf(fileRef), MediaState.idle);

      // A tap afterwards fetches it as usual.
      await phone.media.download(_chat, fileRef);
      expect(phone.stateOf(fileRef), MediaState.ready);
    });

    test('a tap again right after the cross, while the slots are still busy, fetches it once one frees', () async {
      final (fileRef, opening) = await tapFileBehindTwoPhotos();
      phone.media.cancel(_chat, fileRef);
      final again = phone.media.download(_chat, fileRef);
      expect(phone.stateOf(fileRef), MediaState.downloading);

      phone.relay.downloadGate!.complete();
      await again;
      expect(await opening, isNull, reason: 'the cancelled tap opened the file');
      expect(phone.stateOf(fileRef), MediaState.ready, reason: 'the second tap did not fetch it');
      expect(phone.relay.blobDownloads.where((id) => id == fileRef.attachmentId), hasLength(1));
    });

    test('newest first, and at most 50 waiting per chat', () async {
      final slots = TransferSlots(capacity: 1);
      final fetched = <DateTime>[];
      final hold = Completer<void>();
      final prefetch = MediaPrefetch(
        slots: slots,
        withheld: (_) => false,
        fetch: (item) async {
          fetched.add(item.sentAt);
          await hold.future;
        },
      );
      PrefetchItem item(int minute, {String chat = _chat}) => PrefetchItem(
            key: MediaKey(
                chat,
                AttachmentReference(
                  attachmentId: _uuid(),
                  storageKey: '',
                  contentType: 'image/jpeg',
                  sizeBytes: 1,
                  sha256: 'd$minute',
                  encryptedKey: 'k',
                  nonce: 'n',
                )),
            conversationId: chat,
            reference: const AttachmentReference(
                attachmentId: '',
                storageKey: '',
                contentType: '',
                sizeBytes: 0,
                sha256: '',
                encryptedKey: '',
                nonce: ''),
            sentAt: DateTime.utc(2026, 4, 7, 9, minute),
          );
      for (var minute = 0; minute < 60; minute++) {
        prefetch.enqueue(item(minute));
      }
      expect(prefetch.queuedCount, 50, reason: 'only the 50 newest wait');
      prefetch.setRunning(true);
      await settle(const Duration(milliseconds: 20));
      expect(fetched, [DateTime.utc(2026, 4, 7, 9, 59)], reason: 'the newest goes first');
      hold.complete();
      await waitFor(() => fetched.length == 50);
      expect(fetched.last, DateTime.utc(2026, 4, 7, 9, 10), reason: 'the 10 oldest wait for their bubbles');
    });

    // The encrypted cache keeps whole seconds: content stored in the second
    // the service started is an arrival, content from an earlier second is
    // what the cache held, and content not stored yet was opened just now.
    test('only arrivals are fetched by themselves, never what the cache held', () async {
      final prefetch = MediaPrefetch(slots: TransferSlots(), withheld: (_) => false, fetch: (_) async {});
      final since = DateTime.utc(2026, 4, 7, 9, 0, 30, 400);
      final references = <String, AttachmentReference>{};
      ChatMessage message(String id) {
        references[id] = AttachmentReference(
          attachmentId: _uuid(),
          storageKey: '',
          contentType: 'image/jpeg',
          sizeBytes: 1000,
          sha256: 'd-$id',
          encryptedKey: 'k',
          nonce: 'n',
          algorithmHint: 'aes256gcm-v2',
        );
        return ChatMessage(
          id: id,
          senderDeviceId: 'dev-selene',
          sentAt: since,
          envelope: const CryptoEnvelope(
            version: 'v2',
            conversationId: _chat,
            senderDeviceId: 'dev-selene',
            recipientUserId: 'user-atlas',
            ciphertext: 'c',
            nonce: 'n',
            messageKind: MessageKind.image,
          ),
        );
      }

      MessageContentRecord stored(String id, DateTime at) => MessageContentRecord(
            messageKey: id,
            conversationId: _chat,
            body: '',
            kind: MessageKind.image,
            status: MessageContentStatus.ok,
            createdAt: at,
            updatedAt: at,
          );
      final messages = [message('cached'), message('same-second'), message('unstored')];
      await prefetch.queueArrivals(
        _chat,
        messages,
        read: (message) async => DecryptedMessage(
            body: '', messageKind: MessageKind.image, attachment: references[message.id]),
        stored: (_) async => {
          'cached': stored('cached', DateTime.utc(2026, 4, 7, 9, 0, 29)),
          'same-second': stored('same-second', DateTime.utc(2026, 4, 7, 9, 0, 30)),
        },
        opens: AttachmentMediaService.opens,
        since: since,
        now: () => since,
        stillWanted: () => true,
      );
      expect(prefetch.isQueued(MediaKey(_chat, references['cached']!)), isFalse);
      expect(prefetch.isQueued(MediaKey(_chat, references['same-second']!)), isTrue);
      expect(prefetch.isQueued(MediaKey(_chat, references['unstored']!)), isTrue);
    });
  });

  group('what a pointer or a relay cannot make the phone do (D33, D34)', () {
    test('a pointer naming 1 TiB is not opened, and nothing is requested for it', () async {
      final reference = _withPointer(await phone.seal(photo), sizeBytes: 1 << 40);
      await phone.receive(attachment: reference);
      expect(phone.stateOf(reference), MediaState.unsupported);
      expect(await phone.media.photoBytes(_chat, reference, userAsked: true), isNull);
      await phone.media.download(_chat, reference);
      expect(await phone.media.plaintextFileFor(_chat, reference, name: 'x', purpose: MediaCopyPurpose.save), isNull);
      await settle();
      expect(phone.relay.downloadTicketRequests, isEmpty);
      expect(phone.relay.blobDownloads, isEmpty);
    });

    test('an attachment id that is not a UUID makes no request at all', () async {
      final reference = _withPointer(await phone.seal(photo), attachmentId: '../keys/x');
      await phone.receive(attachment: reference);
      expect(phone.stateOf(reference), MediaState.unsupported);
      expect(await phone.media.photoBytes(_chat, reference, userAsked: true), isNull);
      await phone.media.download(_chat, reference);
      await settle();
      expect(phone.relay.downloadTicketRequests, isEmpty);
      expect(phone.relay.blobDownloads, isEmpty);
    });

    test('a pointer of another scheme is not opened', () async {
      final reference = _withPointer(await phone.seal(photo), algorithmHint: 'x25519-aes256gcm');
      await phone.receive(attachment: reference);
      expect(phone.stateOf(reference), MediaState.unsupported);
      await settle();
      expect(phone.relay.downloadTicketRequests, isEmpty);
    });

    test('a relay serving more bytes than the pointer allows is cut off, and nothing is kept', () async {
      final reference = await phone.seal(photo);
      phone.relay.oversizedBlobs[reference.attachmentId] = maxCiphertextBytes(reference.sizeBytes);
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.failed);
      expect(await phone.mediaFiles(), isEmpty);
      expect(await phone.index.all(), isEmpty);
    });

    test('a download URL on a host outside the allowlist is refused before any GET', () async {
      phone.relay.downloadHost = 'storage.example.com';
      final reference = await phone.seal(photo);
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.failed);
      expect(phone.relay.downloadTicketRequests, [reference.attachmentId]);
      expect(phone.relay.blobDownloads, isEmpty);
    });

    test('kind image whose bytes are HTML is not a photo, and nothing is decoded', () async {
      final reference = await phone.seal(notAnImage(), contentType: 'image/jpeg');
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.ready);
      expect(await phone.media.photoBytes(_chat, reference), isNull);
      expect(phone.stateOf(reference), MediaState.unsupported);
      expect(PhotoImageProvider.debugDecodes, 0);
    });

    test('kind image whose bytes are HTML is never saved as a photo', () async {
      final reference = await phone.seal(notAnImage(), contentType: 'image/jpeg');
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.ready);
      final copy = await phone.media
          .plaintextFileFor(_chat, reference, name: 'photo-20260407-095201', photo: true, purpose: MediaCopyPurpose.save);
      expect(copy, isNull, reason: 'bytes that are not a photo went to Save under a photo\'s name');
      expect(await phone.openFiles(), isEmpty);
    });

    test('decode budget: a 7000 x 7000 PNG in a few kilobytes is never decoded', () async {
      final png = solidPng(width: 7000, height: 7000);
      expect(png.length, lessThan(100 * 1024));
      final reference = await phone.seal(png, contentType: 'image/png');
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.ready);
      expect(await phone.media.photoBytes(_chat, reference), isNull);
      expect(phone.stateOf(reference), MediaState.unsupported);
      expect(PhotoImageProvider.debugDecodes, 0, reason: 'a decode was attempted');
    });

    test('a 6000 x 8000 JPEG opens, and is decoded scaled to its bubble', () async {
      final big = img.encodeJpg(img.Image(width: 6000, height: 8000), quality: 50);
      final reference = await phone.seal(big);
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.ready, _chat);
      final bytes = await phone.media.photoBytes(_chat, reference);
      expect(bytes, isNotNull);
      final provider = PhotoImageProvider(
        media: MediaKey(_chat, reference),
        bytes: bytes!,
        target: const PhotoDecodeTarget.bubble(240, pixelRatio: 3),
      );
      final info = await _resolve(provider);
      // Its 240 x 320 dp bubble on a 3x screen, sharp and no larger.
      expect(info.image.width, 720);
      expect(info.image.height, 960);
      expect(PhotoImageProvider.debugDecodes, 1);
      info.dispose();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('gone and failed (D31)', () {
    test('a download ticket refused as not found leaves it gone', () async {
      final reference = await phone.seal(photo, uploaded: false);
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.gone);
      expect(phone.relay.downloadTicketRequests, [reference.attachmentId]);
      expect(phone.relay.blobDownloads, isEmpty);
    });

    test('a download ticket refused as forbidden leaves it gone', () async {
      final reference = await phone.seal(photo);
      final message = await _receiveHeld(phone, reference);
      phone.relay.deletedMessageIds.add(message.id);
      phone.media.setInUse(true);
      await phone.waitForState(reference, MediaState.gone);
      expect(phone.relay.downloadTicketRequests, [reference.attachmentId]);
      expect(phone.relay.blobDownloads, isEmpty);
    });

    test('a GET refused once gets one fresh ticket, which works', () async {
      final reference = await phone.seal(photo);
      phone.relay.downloadStatus[reference.attachmentId] = 403;
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.ready);
      expect(phone.relay.downloadTicketRequests, hasLength(2));
      expect(phone.relay.blobDownloads, hasLength(2));
    });

    test('a GET refused again after a fresh ticket leaves it gone', () async {
      final reference = await phone.seal(photo);
      phone.relay
        ..downloadStatus[reference.attachmentId] = 403
        ..downloadStatusSticky = true;
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.gone);
      expect(phone.relay.downloadTicketRequests, hasLength(2));
      expect(phone.relay.blobDownloads, hasLength(2));
    });

    test('a network failure fails it, and a retry works', () async {
      phone.relay.failDownloads = 1;
      final reference = await phone.seal(photo);
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.failed);
      expect(await phone.media.photoBytes(_chat, reference, userAsked: true), photo);
      expect(phone.stateOf(reference), MediaState.ready);
    });

    test('a tampered download fails, and is gone the second time; nothing of it is kept or opened', () async {
      final reference = await phone.seal(pdfBytes('tampered'), contentType: 'application/pdf');
      phone.relay.tamperedBlobs.add(reference.attachmentId);
      await phone.receive(kind: MessageKind.file, body: 'lease.pdf', attachment: reference);

      await phone.media.download(_chat, reference);
      expect(phone.stateOf(reference), MediaState.failed);
      await phone.media.download(_chat, reference);
      expect(phone.stateOf(reference), MediaState.gone);
      expect(
        await phone.media.plaintextFileFor(_chat, reference, name: 'lease.pdf', purpose: MediaCopyPurpose.open),
        isNull,
      );
      expect(await phone.mediaFiles(), isEmpty);
      expect(await phone.openFiles(), isEmpty);
      expect(debugAttachmentDecrypts, 0);
    });

    test('a blob damaged on the phone is deleted and fetched again, and the photo shows', () async {
      final reference = await phone.seal(photo);
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.ready);
      final [name] = await phone.mediaFiles();
      final file = File(p.join((await phone.paths.mediaDir()).path, name));
      final bytes = file.readAsBytesSync();
      bytes[bytes.length ~/ 2] ^= 0x01;
      file.writeAsBytesSync(bytes);

      expect(await phone.media.photoBytes(_chat, reference, userAsked: true), photo);
      expect(phone.stateOf(reference), MediaState.ready);
      expect(phone.relay.blobDownloads, hasLength(2));
      expect(await phone.mediaFiles(), hasLength(1));
      expect(await phone.mediaFiles(), isNot(contains(name)), reason: 'the damaged blob was kept');
    });
  });

  group('decrypted bytes (D36)', () {
    test('two pointers with one id and other keys never share decrypted bytes', () async {
      final id = _uuid();
      final first = await phone.seal(photo, id: id, seed: 1);
      final second = (await sealV2(pngWithAlpha(), attachmentId: id, contentType: 'image/png', seed: 2)).reference;
      await phone.receive(attachment: first);
      await phone.waitForState(first, MediaState.ready);
      expect(await phone.media.photoBytes(_chat, first), photo);

      // Another digest and key under the same id: its own entry.
      expect(MediaKey(_chat, second), isNot(MediaKey(_chat, first)));
      expect(PhotoImageKey(MediaKey(_chat, second), const PhotoDecodeTarget.bubble(240, pixelRatio: 3)),
          isNot(PhotoImageKey(MediaKey(_chat, first), const PhotoDecodeTarget.bubble(240, pixelRatio: 3))));
      expect(phone.media.cachedPhotoBytes(_chat, second), isNull);
      expect(await phone.media.photoBytes(_chat, second, userAsked: true), isNull);

      // The first one's digest with another key: not the first one's bytes.
      final rekeyed = _withPointer(first, encryptedKey: second.encryptedKey);
      expect(phone.media.cachedPhotoBytes(_chat, rekeyed), isNull);
      expect(await phone.media.photoBytes(_chat, rekeyed, userAsked: true), isNull);
      expect(phone.stateOf(rekeyed), MediaState.failed);
      expect(phone.stateOf(first), MediaState.ready, reason: 'the good blob was taken for the bad pointer');
      expect(await phone.mediaFiles(), hasLength(1));

      // A second AES-GCM failure of a blob whose digest matches is gone
      // (D31); the blob stays for the pointer it opens with.
      final downloads = phone.relay.blobDownloads.length;
      expect(await phone.media.photoBytes(_chat, rekeyed, userAsked: true), isNull);
      expect(phone.stateOf(rekeyed), MediaState.gone);
      expect(phone.stateOf(first), MediaState.ready);
      expect(await phone.mediaFiles(), hasLength(1));
      expect(phone.relay.blobDownloads, hasLength(downloads), reason: 'a key that does not open it fetched it again');
    });

    test('a photo shown again comes from the sealed blob, with no request', () async {
      final reference = await phone.seal(photo);
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.ready);
      await phone.media.photoBytes(_chat, reference);
      phone.media.evictDecrypted();
      expect(phone.media.cachedPhotoBytes(_chat, reference), isNull);
      expect(await phone.media.photoBytes(_chat, reference), photo);
      expect(phone.relay.blobDownloads, hasLength(1));
      expect(debugAttachmentDecrypts, 2);
    });

    test('the lock empties memory, the image cache and Save copies, and keeps an open copy', () async {
      final photoRef = await phone.seal(photo);
      final fileRef = await phone.seal(pdfBytes('keep'), contentType: 'application/pdf');
      await phone.receive(attachment: photoRef);
      await phone.receive(kind: MessageKind.file, body: 'keep.pdf', attachment: fileRef);
      await phone.waitForState(photoRef, MediaState.ready);
      await phone.media.photoBytes(_chat, photoRef);
      final save = await phone.media.plaintextFileFor(_chat, fileRef, name: 'keep.pdf', purpose: MediaCopyPurpose.save);
      final open = await phone.media.plaintextFileFor(_chat, fileRef, name: 'keep.pdf', purpose: MediaCopyPurpose.open);
      final cache = PaintingBinding.instance.imageCache;
      final cached = Completer<ImageInfo>();
      cache.putIfAbsent(const Object(), () => OneFrameImageStreamCompleter(cached.future));
      expect(cache.currentSize + cache.pendingImageCount, greaterThan(0));

      phone.media.evictDecrypted();
      await settle(const Duration(milliseconds: 50));
      expect(phone.media.cachedPhotoBytes(_chat, photoRef), isNull);
      expect(cache.currentSize + cache.pendingImageCount, 0);
      expect(File(save!).existsSync(), isFalse, reason: 'a Save copy outlived the lock');
      expect(File(open!).existsSync(), isTrue, reason: 'the app it was handed to may still read it');
    });

    test('a photo decrypt that finishes after the lock keeps nothing in memory', () async {
      final reference = await phone.seal(photo);
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.ready);
      final opening = phone.media.photoBytes(_chat, reference);
      // The lock lands while the isolate decrypts.
      phone.media
        ..evictDecrypted()
        ..setInUse(false);
      expect(await opening, isNull, reason: 'bytes decrypted across the lock were handed out');
      expect(phone.media.cachedPhotoBytes(_chat, reference), isNull,
          reason: 'decrypted bytes entered memory after the lock emptied it');

      // Unlocked again, the photo opens as before.
      phone.media.setInUse(true);
      expect(await phone.media.photoBytes(_chat, reference), photo);
    });

    for (final purpose in MediaCopyPurpose.values) {
      test('a ${purpose.name} copy still being made when the app locks is deleted, and none is handed out',
          () async {
        final reference = await phone.seal(pdfBytes('late'), contentType: 'application/pdf');
        await phone.receive(kind: MessageKind.file, body: 'late.pdf', attachment: reference);
        final copying = phone.media.plaintextFileFor(_chat, reference, name: 'late.pdf', purpose: purpose);
        phone.media.evictDecrypted();
        expect(await copying, isNull);
        await settle(const Duration(milliseconds: 50));
        expect(await phone.openFiles(), isEmpty, reason: 'a copy made across the lock was left behind');
      });
    }

    test('a blob removed outside the sweeps (a cancelled send, a sealer that failed) takes its bytes and copies along',
        () async {
      final reference = await phone.seal(photo);
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.ready);
      expect(await phone.media.photoBytes(_chat, reference), photo);
      final copy = await phone.media
          .plaintextFileFor(_chat, reference, name: 'p.jpg', purpose: MediaCopyPurpose.open, photo: true);
      expect(File(copy!).existsSync(), isTrue);

      await phone.media.blobs.delete(_chat, reference.attachmentId);
      await settle();
      expect(phone.media.cachedPhotoBytes(_chat, reference), isNull,
          reason: 'the decrypted photo stayed in memory after its blob went');
      expect(phone.stateOf(reference), isNot(MediaState.ready));
      expect(File(copy).existsSync(), isFalse, reason: 'its decrypted copy outlived the blob');
    });

    test('a blob whose file is found gone takes its decrypted bytes along', () async {
      final reference = await phone.seal(photo);
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.ready);
      expect(await phone.media.photoBytes(_chat, reference), photo);

      for (final entity in (await phone.paths.mediaDir()).listSync()) {
        entity.deleteSync();
      }
      expect(await phone.media.blobs.pathOf(_chat, reference.attachmentId, reference.sha256), isNull);
      expect(phone.media.cachedPhotoBytes(_chat, reference), isNull);
      expect(phone.stateOf(reference), isNot(MediaState.ready));
    });

    test('signing out forgets every blob, status and decrypted byte', () async {
      final reference = await phone.seal(photo);
      await phone.receive(attachment: reference);
      await phone.waitForState(reference, MediaState.ready);
      await phone.media.photoBytes(_chat, reference);

      await phone.controller.applySession(const AppSessionState(locked: false, initializing: false));
      await settle();
      expect(phone.media.cachedPhotoBytes(_chat, reference), isNull);
      expect(phone.stateOf(reference), MediaState.idle);
      expect(await phone.index.all(), isEmpty);
      expect(await phone.mediaFiles(), isEmpty);
    });
  });

  group('decrypted copies (D38)', () {
    for (final (label, name) in [
      ('with dots up the tree', '../../evil.sh'),
      ('with path separators', r'a/b\c.pdf'),
      ('with a right-to-left override', 'invoice\u202Efdp.exe'),
      ('of 120 emoji', '${'\u{1F600}' * 120}.pdf'),
    ]) {
      test('a file named $label is copied only into its own folder of veil_open', () async {
        final reference = await phone.seal(pdfBytes('named'), contentType: 'application/pdf');
        await phone.receive(kind: MessageKind.file, body: name, attachment: reference);
        final path = await phone.media.plaintextFileFor(_chat, reference, name: name, purpose: MediaCopyPurpose.open);
        final root = (await phone.paths.openDir()).path;
        expect(path, isNotNull);
        expect(p.isWithin(root, path!), isTrue);
        expect(p.dirname(p.dirname(path)), root, reason: 'not in a folder of its own');
        expect(p.basename(p.dirname(path)), matches(RegExp(r'^[a-z0-9]{24}$')));
        expect(utf8.encode(p.basename(path)).length, lessThanOrEqualTo(200));
        expect(p.basename(path), isNot(contains('/')));
        expect(p.basename(path), isNot(startsWith('.')));
        expect(p.basename(path), isNot(contains('\u202E')));
        expect(File(path).readAsBytesSync(), pdfBytes('named'));
        await phone.media.releaseCopy(path);
        expect(Directory(p.dirname(path)).existsSync(), isFalse);
      });
    }

    test('a copy older than 10 minutes goes on the next return to the app', () async {
      final reference = await phone.seal(pdfBytes('old'), contentType: 'application/pdf');
      await phone.receive(kind: MessageKind.file, body: 'old.pdf', attachment: reference);
      final path =
          await phone.media.plaintextFileFor(_chat, reference, name: 'old.pdf', purpose: MediaCopyPurpose.open);
      phone.media
        ..setInUse(false)
        ..setInUse(true);
      await settle(const Duration(milliseconds: 50));
      expect(File(path!).existsSync(), isTrue, reason: 'a fresh copy went');

      phone.relay.deviceClockSkew['atlas'] = const Duration(minutes: 11);
      phone.media
        ..setInUse(false)
        ..setInUse(true);
      await waitFor(() => !File(path).existsSync(), reason: 'the old copy stayed');
    });

    test('a copy older than 10 minutes goes on the minute tick', () async {
      var now = DateTime.utc(2026, 4, 7, 9);
      final paths = _ownPaths();
      final cleanup = MediaCleanup(
        blobs: MediaBlobStore(paths: paths, index: MemoryMediaIndex()),
        paths: paths,
        now: () => now,
        pendingAttachmentIds: () => const {},
        onEntryDeleted: (_) {},
        copySweepInterval: const Duration(milliseconds: 40),
      );
      addTearDown(cleanup.dispose);
      final path = await cleanup.newCopyPath('tick.pdf');
      File(path).writeAsStringSync('x');
      cleanup.registerCopy(MediaCopy(
          path: path,
          conversationId: _chat,
          attachmentId: _uuid(),
          digest: 'd',
          purpose: MediaCopyPurpose.open,
          createdAt: now));
      // Nothing says the app is in use: the tick runs while it is locked
      // or in the background too.
      await settle(const Duration(milliseconds: 120));
      expect(File(path).existsSync(), isTrue);
      now = now.add(const Duration(minutes: 10));
      await waitFor(() => !File(path).existsSync(), reason: 'the tick left it');
    });

    test('an open copy older than 10 minutes goes on a return to the lock screen', () async {
      final reference = await phone.seal(pdfBytes('old'), contentType: 'application/pdf');
      await phone.receive(kind: MessageKind.file, body: 'old.pdf', attachment: reference);
      final path =
          await phone.media.plaintextFileFor(_chat, reference, name: 'old.pdf', purpose: MediaCopyPurpose.open);
      // Handed to another app on Android: Veil is hidden and locks at once,
      // which leaves an open copy in place.
      phone.media
        ..evictDecrypted()
        ..setInUse(false);
      await settle(const Duration(milliseconds: 50));
      expect(File(path!).existsSync(), isTrue);

      phone.relay.deviceClockSkew['atlas'] = const Duration(minutes: 30);
      // Back in front, on the lock screen: still not in use.
      phone.media.setInUse(false);
      await waitFor(() => !File(path).existsSync(), reason: 'a 30-minute-old plaintext copy outlived a resume');
    });

    test('a file opened in a chat with a 1-minute timer has no copy once its message is gone', () async {
      final reference = await phone.seal(pdfBytes('brief'), contentType: 'application/pdf');
      final expiresAt = phone.relay.now().add(const Duration(minutes: 1));
      final message =
          await phone.receive(kind: MessageKind.file, body: 'brief.pdf', attachment: reference, expiresAt: expiresAt);
      await phone.media.download(_chat, reference, expiresAt: message.expiresAt);
      final path =
          await phone.media.plaintextFileFor(_chat, reference, name: 'brief.pdf', purpose: MediaCopyPurpose.open);
      expect(File(path!).existsSync(), isTrue);
      expect((await phone.index.all()).single.expiresAt, isNotNull);

      phone.relay.deviceClockSkew['atlas'] = const Duration(minutes: 1, seconds: 1);
      await phone.media.cleanup.sweepExpired();
      expect(File(path).existsSync(), isFalse, reason: 'the open copy outlived its message');
      expect(await phone.index.all(), isEmpty);
      expect(await phone.mediaFiles(), isEmpty);
    });
  });

  group('cleanup by the index (D37)', () {
    test('a disappearing photo goes with its message: blob, decrypted bytes and copies', () async {
      final reference = await phone.seal(photo);
      final message = await phone.receive(
        attachment: reference,
        expiresAt: phone.relay.now().add(const Duration(minutes: 1)),
      );
      await phone.waitForState(reference, MediaState.ready);
      expect((await phone.index.all()).single.expiresAt, message.expiresAt);
      await phone.media.photoBytes(_chat, reference);
      final copy = await phone.media
          .plaintextFileFor(_chat, reference, name: 'photo', photo: true, purpose: MediaCopyPurpose.open);
      expect(p.extension(copy!), '.jpg');

      phone.relay.deviceClockSkew['atlas'] = const Duration(minutes: 2);
      // Any change to the messages sweeps.
      await phone.receive(kind: MessageKind.text, body: 'later');
      await waitFor(() async => (await phone.index.all()).isEmpty, reason: 'the expired blob stayed');
      expect(await phone.mediaFiles(), isEmpty);
      expect(phone.media.cachedPhotoBytes(_chat, reference), isNull);
      expect(File(copy).existsSync(), isFalse);
    });

    test('a disappearing photo whose relay dropped the timer still goes with its message', () async {
      // The sender sealed a minute in; the relay strips its own copy of it.
      phone.relay.stripOuterExpiresAt = true;
      final reference = await phone.seal(photo);
      final message = await phone.receive(
        attachment: reference,
        expiresAt: phone.relay.now().add(const Duration(minutes: 1)),
      );
      await phone.waitForState(reference, MediaState.ready);
      final stored = phone.controller.messagesFor(_chat).firstWhere((m) => m.id == message.id);
      expect(stored.expiresAt, isNotNull, reason: 'the store keeps the sealed expiry');
      expect((await phone.index.all()).single.expiresAt, stored.expiresAt,
          reason: 'the prefetched blob was indexed without its message\'s expiry');
      await phone.media.photoBytes(_chat, reference);

      phone.relay.deviceClockSkew['atlas'] = const Duration(minutes: 2);
      await phone.receive(kind: MessageKind.text, body: 'later');
      await waitFor(() => phone.controller.messagesFor(_chat).every((m) => m.id != message.id),
          reason: 'the message itself stayed');
      await waitFor(() async => (await phone.index.all()).isEmpty, reason: 'the blob outlived its message');
      expect(await phone.mediaFiles(), isEmpty);
      expect(phone.media.cachedPhotoBytes(_chat, reference), isNull, reason: 'decrypted bytes outlived the message');
    });

    test('a photo whose message expired is neither fetched again nor decrypted into a copy', () async {
      final reference = await phone.seal(photo);
      final message = await phone.receive(
        attachment: reference,
        expiresAt: phone.relay.now().add(const Duration(minutes: 1)),
      );
      await phone.waitForState(reference, MediaState.ready);
      phone.relay.deviceClockSkew['atlas'] = const Duration(minutes: 2);
      await phone.media.cleanup.sweepExpired();
      expect(await phone.mediaFiles(), isEmpty);
      final downloads = phone.relay.blobDownloads.length;
      final tickets = phone.relay.downloadTicketRequests.length;

      for (final purpose in MediaCopyPurpose.values) {
        expect(
            await phone.media.plaintextFileFor(_chat, reference,
                name: 'photo', photo: true, purpose: purpose, expiresAt: message.expiresAt),
            isNull);
      }
      expect(await phone.media.photoBytes(_chat, reference, userAsked: true, expiresAt: message.expiresAt), isNull);
      await phone.media.download(_chat, reference, expiresAt: message.expiresAt);
      expect(phone.relay.downloadTicketRequests, hasLength(tickets), reason: 'an expired photo was asked for again');
      expect(phone.relay.blobDownloads, hasLength(downloads));
      expect(await phone.openFiles(), isEmpty);
    });

    for (final purpose in MediaCopyPurpose.values) {
      test('a file whose message expires while its download runs is not kept, and no ${purpose.name} copy is made',
          () async {
        final reference = await phone.seal(pdfBytes('brief'), contentType: 'application/pdf');
        final message = await phone.receive(
            kind: MessageKind.file,
            body: 'brief.pdf',
            attachment: reference,
            expiresAt: phone.relay.now().add(const Duration(minutes: 1)));
        phone.relay.downloadGate = Completer<void>();
        final copying = phone.media
            .plaintextFileFor(_chat, reference, name: 'brief.pdf', purpose: purpose, expiresAt: message.expiresAt);
        await waitFor(() => phone.relay.blobDownloads.contains(reference.attachmentId), reason: 'no GET started');

        // The message's minute passes while the GET runs, and the sweeps
        // that run then find nothing to take.
        phone.relay.deviceClockSkew['atlas'] = const Duration(minutes: 2);
        await phone.media.cleanup.sweepExpired();
        phone.relay.downloadGate!.complete();
        expect(await copying, isNull, reason: 'a file whose message had gone was decrypted into a copy');
        await settle();
        expect(await phone.openFiles(), isEmpty, reason: 'a plaintext copy outlived its message');
        expect(await phone.index.all(), isEmpty, reason: 'the blob of an expired message was kept');
        expect(await phone.mediaFiles(), isEmpty);
      });
    }

    test('a photo tapped as its message expires keeps no decrypted bytes and no blob', () async {
      final reference = await phone.seal(photo);
      // A blocked 1:1: nothing comes by itself, the tap fetches it.
      phone.blocked.add(_chat);
      final message =
          await phone.receive(attachment: reference, expiresAt: phone.relay.now().add(const Duration(minutes: 1)));
      await settle();
      expect(phone.relay.blobDownloads, isEmpty);
      phone.relay.downloadGate = Completer<void>();
      final opening = phone.media.photoBytes(_chat, reference, userAsked: true, expiresAt: message.expiresAt);
      await waitFor(() => phone.relay.blobDownloads.contains(reference.attachmentId), reason: 'no GET started');

      phone.relay.deviceClockSkew['atlas'] = const Duration(minutes: 2);
      await phone.media.cleanup.sweepExpired();
      phone.relay.downloadGate!.complete();
      expect(await opening, isNull, reason: 'a photo whose message had gone was decrypted');
      await settle();
      expect(phone.media.cachedPhotoBytes(_chat, reference), isNull,
          reason: 'decrypted bytes of a photo whose message had gone stay in memory');
      expect(await phone.index.all(), isEmpty, reason: 'the blob of an expired message was kept');
      expect(await phone.mediaFiles(), isEmpty);
    });

    test('a blob written with an expiry after the last sweep goes when it expires, with nothing else happening',
        () async {
      final paths = _ownPaths();
      final blobs = MediaBlobStore(paths: paths, index: MemoryMediaIndex());
      final forgotten = <String>[];
      final cleanup = MediaCleanup(
        blobs: blobs,
        paths: paths,
        now: DateTime.now,
        pendingAttachmentIds: () => const {},
        onEntryDeleted: (entry) => forgotten.add(entry.attachmentId),
      );
      addTearDown(cleanup.dispose);
      // The start's sweep finds nothing, so no timer is armed by it.
      await cleanup.start();
      final fetched = _uuid();
      final sent = _uuid();
      // A photo fetched with its message's expiry, and an own photo stamped
      // after its upload (D18).
      await blobs.write(
          conversationId: _chat,
          attachmentId: fetched,
          digest: 'd1',
          sealedBytes: [1, 2, 3],
          expiresAt: DateTime.now().add(const Duration(milliseconds: 300)));
      await blobs.write(conversationId: _chat, attachmentId: sent, digest: 'd2', sealedBytes: [4, 5, 6]);
      await blobs.setExpiry(_chat, sent, DateTime.now().add(const Duration(milliseconds: 600)));
      expect(await blobs.entries(), hasLength(2));
      await waitFor(() async => (await blobs.entries()).isEmpty,
          reason: 'a blob written after the last sweep waited for an unrelated one');
      expect(forgotten, unorderedEquals([fetched, sent]), reason: 'its decrypted bytes were not dropped with it');
    });

    test('a disappearing photo only in the cache, not loaded, goes too', () async {
      final reference = await phone.seal(photo);
      // After the start's sweeps (they run one after another), so none of
      // them races the write below.
      await phone.media.cleanup.sweepExpired();
      await phone.media.blobs.write(
        conversationId: 'conv-cached-only',
        attachmentId: reference.attachmentId,
        digest: reference.sha256,
        sealedBytes: phone.relay.uploadedBlobs[reference.attachmentId]!,
        expiresAt: phone.relay.now().add(const Duration(minutes: 1)),
      );
      expect(await phone.mediaFiles(), hasLength(1));
      phone.relay.deviceClockSkew['atlas'] = const Duration(minutes: 2);
      await phone.media.cleanup.sweepExpired();
      expect(await phone.mediaFiles(), isEmpty);
      expect(await phone.index.all(), isEmpty);
    });

    test('a chat that leaves the list takes its blobs along', () async {
      final reference = await phone.seal(photo);
      await phone.receive(conversationId: _group, attachment: reference);
      await phone.waitForState(reference, MediaState.ready, _group);
      expect(await phone.mediaFiles(), hasLength(1));

      phone.relay.conversations.remove(_group);
      await phone.controller.refreshConversations();
      await waitFor(() async => (await phone.index.all()).isEmpty, reason: 'the chat that left kept its blob');
      expect(await phone.mediaFiles(), isEmpty);
    });

    test('a photo still downloading when its chat leaves the list is not kept, then or at the next start', () async {
      phone.relay.downloadGate = Completer<void>();
      final reference = await phone.seal(photo);
      await phone.receive(conversationId: _group, attachment: reference);
      await waitFor(() => phone.relay.blobDownloads.contains(reference.attachmentId));

      phone.relay.conversations.remove(_group);
      await phone.controller.refreshConversations();
      await settle();
      phone.relay.downloadGate!.complete();
      await phone.waitForState(reference, MediaState.idle, _group);
      expect(await phone.index.all(), isEmpty, reason: 'the blob of a chat that left was kept');
      expect(await phone.mediaFiles(), isEmpty);

      // A start's sweeps, as the next launch runs them, find nothing either.
      await phone.media.cleanup.start();
      expect(await phone.index.all(), isEmpty);
      expect(await phone.mediaFiles(), isEmpty);
    });

    test('a chat listed again after it left keeps what it fetches', () async {
      final paths = _ownPaths();
      final cleanup = MediaCleanup(
        blobs: MediaBlobStore(paths: paths, index: MemoryMediaIndex()),
        paths: paths,
        now: () => _clock,
        pendingAttachmentIds: () => {},
        onEntryDeleted: (_) {},
      );
      addTearDown(cleanup.dispose);
      await cleanup.conversationsListed(['conv-a', 'Conv-B']);
      expect(cleanup.hasLeft('conv-b'), isFalse);
      await cleanup.conversationsListed(['conv-a']);
      expect(cleanup.hasLeft('CONV-B'), isTrue);
      expect(cleanup.hasLeft('conv-new'), isFalse, reason: 'a chat never listed is not one that left');
      await cleanup.conversationsListed(['conv-a', 'conv-b']);
      expect(cleanup.hasLeft('conv-b'), isFalse);
    });

    test('the first list after a start is compared with what the cache held', () async {
      final paths = _ownPaths();
      final blobs = MediaBlobStore(paths: paths, index: MemoryMediaIndex());
      final cleanup = MediaCleanup(
        blobs: blobs,
        paths: paths,
        now: () => _clock,
        pendingAttachmentIds: () => {},
        onEntryDeleted: (_) {},
      );
      addTearDown(cleanup.dispose);
      for (final conversation in ['conv-a', 'conv-b']) {
        await blobs.write(
            conversationId: conversation,
            attachmentId: '00000000-0000-4000-8000-00000000000${conversation == 'conv-a' ? 1 : 2}',
            digest: 'd-$conversation',
            sealedBytes: [1, 2, 3]);
      }
      // conv-b was in the cache and the relay lists it no more; conv-new
      // was never listed.
      await cleanup.conversationsListed(['conv-a', 'conv-new'], cached: ['conv-a', 'Conv-B']);
      expect(cleanup.hasLeft('conv-b'), isTrue);
      expect(cleanup.hasLeft('conv-new'), isFalse);
      expect([for (final entry in await blobs.entries()) entry.conversationId], ['conv-a']);
      // Only the first list: later ones are compared with the one before.
      await cleanup.conversationsListed(['conv-a', 'conv-new'], cached: ['conv-gone']);
      expect(cleanup.hasLeft('conv-gone'), isFalse);
    });

    test('a start deletes files without a row, and every decrypted copy left behind', () async {
      phone.dispose();
      phone = await _Phone.start(beforeStart: (root) {
        File('${root.path}/support/veil_media/${'ab' * 32}').createSync(recursive: true);
        File('${root.path}/tmp/veil_open/leftover/old.pdf').createSync(recursive: true);
      });
      await waitFor(() async => (await phone.mediaFiles()).isEmpty, reason: 'the orphan stayed');
      await waitFor(() async => (await phone.paths.openDir()).listSync().isEmpty, reason: 'the copy stayed');
    });

    test('the cap takes the least recently used, never the blob of an upload still pending', () async {
      final paths = _ownPaths();
      final blobs = MediaBlobStore(paths: paths, index: MemoryMediaIndex(), now: () => _clock);
      final pending = _uuid();
      final ids = [pending, _uuid(), _uuid()];
      for (final (age, id) in ids.indexed) {
        _clock = DateTime.utc(2026, 4, 7, 9, age);
        await blobs.write(conversationId: _chat, attachmentId: id, digest: 'd', sealedBytes: List.filled(400, age));
      }
      final cleanup = MediaCleanup(
        blobs: blobs,
        paths: paths,
        now: () => _clock,
        pendingAttachmentIds: () => {pending.toUpperCase()},
        onEntryDeleted: (_) {},
        maxBytes: 900,
      );
      addTearDown(cleanup.dispose);
      await cleanup.enforceCap();
      final kept = [for (final entry in await blobs.entries()) entry.attachmentId]..sort();
      expect(kept, ([pending, ids[2]]..sort()), reason: 'the pending blob or the newest went');
    });

    test('the media folder holds only opaque names', () async {
      final photoRef = await phone.seal(photo);
      final fileRef = await phone.seal(pdfBytes('names'), contentType: 'application/pdf');
      await phone.receive(attachment: photoRef);
      await phone.receive(kind: MessageKind.file, body: 'names.pdf', attachment: fileRef);
      await phone.waitForState(photoRef, MediaState.ready);
      await phone.media.download(_chat, fileRef);
      final names = await phone.mediaFiles();
      expect(names, hasLength(2));
      for (final name in names) {
        expect(name, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(name, isNot(contains(photoRef.attachmentId.replaceAll('-', ''))));
      }
    });
  });
}

DateTime _clock = DateTime.utc(2026, 4, 7, 9);

// Folders of a unit test's own, apart from the messenger's, whose start
// sweeps its folders.
AttachmentStoragePaths _ownPaths() {
  final root = Directory.systemTemp.createTempSync('veil-media-unit-');
  addTearDown(() => root.deleteSync(recursive: true));
  return AttachmentStoragePaths(
    temporaryRoot: () async => Directory('${root.path}/tmp')..createSync(recursive: true),
    supportRoot: () async => Directory('${root.path}/support')..createSync(recursive: true),
    systemTempRoot: () => Directory('${root.path}/system-tmp')..createSync(recursive: true),
  );
}

// A photo whose message lands while the app is not in use, so nothing is
// fetched until it is.
Future<ChatMessage> _receiveHeld(_Phone phone, AttachmentReference reference) async {
  phone.media.setInUse(false);
  return phone.receive(attachment: reference);
}

Future<ImageInfo> _resolve(ImageProvider provider) {
  final done = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener((info, _) {
    stream.removeListener(listener);
    done.complete(info);
  }, onError: (error, stack) {
    stream.removeListener(listener);
    done.completeError(error, stack);
  });
  stream.addListener(listener);
  return done.future;
}
