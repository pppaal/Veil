import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/identity/identity_key_value_backend.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_resolver.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_store.dart';
import 'package:veil_mobile/src/core/storage/media_index.dart';
import 'package:veil_mobile/src/core/util/base64url.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_storage_paths.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_temp_file_store.dart';
import 'package:veil_mobile/src/features/attachments/data/media_blob_store.dart';
import 'package:veil_mobile/src/features/attachments/domain/outgoing_attachment.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';
import 'package:veil_mobile/src/features/safety/application/silenced_notifications.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';
import '../support/mock_relay_parties.dart';
import '../support/strict_mock_crypto_adapter.dart';

// What the messenger offers the photo, file and unread work before any of
// it is built: the services behind the facade and the rule both use for a
// chat whose peer is in question or blocked.

void main() {
  late FakeRelay relay;
  late Directory root;
  late IdentityTrust trust;
  late Set<String> blockedConversations;
  late VeilMessengerController controller;
  late bool disposed;

  setUp(() async {
    disposed = false;
    relay = FakeRelay();
    seedMockParties(relay, 'conv-1', ['atlas', 'selene']);
    relay.addGroup('conv-team', ['atlas', 'selene'], useSenderKeys: false);
    root = Directory.systemTemp.createTempSync('veil-contracts-');
    final paths = AttachmentStoragePaths(
      temporaryRoot: () async => Directory('${root.path}/tmp')..createSync(recursive: true),
      supportRoot: () async => Directory('${root.path}/support')..createSync(recursive: true),
      systemTempRoot: () => Directory('${root.path}/system-tmp')..createSync(recursive: true),
    );
    trust = IdentityTrust(TrustedIdentityResolver(store: TrustedIdentityStore(InMemoryIdentityKeyValueBackend())));
    blockedConversations = {};
    final crypto = StrictMockCryptoAdapter(localDeviceId: 'dev-atlas');
    controller = VeilMessengerController(
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
      mediaIndex: MemoryMediaIndex(),
      isBlockedDirect: blockedConversations.contains,
    );
    await controller.applySession(mockPartySession('atlas'));
  });

  tearDown(() {
    if (!disposed) controller.dispose();
    root.deleteSync(recursive: true);
  });

  test('the facade hands out the read state and media services, which do nothing yet', () async {
    expect(controller.media.blobs, isA<MediaBlobStore>());
    controller.setActiveConversation('conv-1');
    expect(controller.activeConversationId, 'conv-1');
    controller.reads.setActive(null);
    expect(controller.activeConversationId, isNull);

    final viewer = Object();
    controller.reads
      ..beginViewing('conv-1', viewer: viewer)
      ..endViewing('conv-1', viewer: viewer);
    controller.media
      ..setInUse(true)
      ..evictDecrypted()
      ..setInUse(false);
    expect(controller.media.pendingAttachmentIds(), isEmpty);

    // Messages still flow past both observers as before.
    await controller.sendText(conversationId: 'conv-1', body: 'still here');
    await waitFor(() => controller.pendingCountFor('conv-1') == 0, reason: 'not acked');
    expect(controller.messagesFor('conv-1'), hasLength(1));
  });

  test('disposing the messenger disposes the media service, so its timers can stop with it', () {
    final media = controller.media;
    expect(() => media.addListener(() {}), returnsNormally);
    controller.dispose();
    disposed = true;
    expect(() => media.addListener(() {}), throwsFlutterError, reason: 'the media service outlived its messenger');
  });

  test('sending a photo or a file is not built yet', () async {
    await expectLater(
      controller.sendAttachment(
        conversationId: 'conv-1',
        attachment: const OutgoingAttachment.photo(path: '/staging/photo.jpg', contentType: 'image/jpeg'),
      ),
      throwsUnimplementedError,
    );
  });

  test('the attachment id of a sealed upload still pending is held back from cleanup, lower-cased', () async {
    relay.uploadGate = Completer<void>();
    await controller.sendAttachmentPlaceholder('conv-1', filename: 'brief.pdf');
    await waitFor(() => controller.media.pendingAttachmentIds().isNotEmpty, reason: 'never sealed');
    final pending = controller.media.pendingAttachmentIds().single;
    expect(pending, pending.toLowerCase());
    expect(relay.uploadedBlobs, isEmpty, reason: 'the upload is held');

    relay.uploadGate!.complete();
    await waitFor(() => controller.pendingCountFor('conv-1') == 0, reason: 'not sent');
    expect(controller.media.pendingAttachmentIds(), isEmpty);
    expect(relay.uploadedBlobs.keys, [pending]);
  });

  group('receipts and fetches are withheld', () {
    bool withheld(String conversationId) {
      final receipts = controller.reads.receiptsWithheld(conversationId);
      expect(controller.media.autoDownloadWithheld(conversationId), receipts, reason: 'one rule for both');
      return receipts;
    }

    test('from nothing in an ordinary chat', () {
      expect(withheld('conv-1'), isFalse);
      expect(withheld('conv-team'), isFalse);
      expect(withheld('conv-unknown'), isFalse);
    });

    test('from a 1:1 with someone blocked', () {
      blockedConversations.add('conv-1');
      expect(withheld('conv-1'), isTrue);
      expect(withheld('conv-team'), isFalse);
    });

    test('from a chat with an identity change pending, and a 1:1 whose peer has one pending elsewhere', () async {
      final selene = relay.partiesByHandle['selene']!;
      await trust.resolver.evaluate(selene.userId, selene.deviceId, selene.identity.identityPublicKey);
      final changedKey = base64UrlNoPadEncode(utf8.encode('ik-selene-new'));
      expect(await trust.admit('conv-team', selene.userId, selene.deviceId, changedKey), isFalse);
      expect(controller.pendingIdentityChangeFor('conv-team'), isNotNull);
      expect(controller.pendingIdentityChangeFor('conv-1'), isNull);

      expect(withheld('conv-team'), isTrue);
      expect(withheld('conv-1'), isTrue, reason: 'who selene is waits in the group');
    });

    test('from a 1:1 held for its account', () async {
      // The relay lists selene's 1:1 under atlas's own handle.
      relay.listedHandles['atlas'] = {'selene': 'atlas'};
      await controller.refreshConversations();
      expect(controller.peerAccountHoldFor('conv-1'), isNotNull);
      expect(withheld('conv-1'), isTrue);
    });
  });

  test('a read chat\'s notification is taken back, muted or not', () async {
    final recorder = RecordingNotifications();
    final silenced = SilencedNotifications(recorder, isSilenced: (conversationId) => conversationId == 'conv-muted');
    await silenced.showMessageNotification(conversationId: 'conv-muted', title: 'Veil', body: 'New message');
    await silenced.cancelConversation('conv-muted');
    await silenced.cancelConversation('conv-1');
    expect(recorder.shownForConversations, isEmpty);
    expect(recorder.cancelledForConversations, ['conv-muted', 'conv-1']);
  });
}
