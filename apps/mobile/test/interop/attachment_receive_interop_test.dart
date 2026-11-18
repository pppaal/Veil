// A photo the web demo seals (apps/web-demo/src/crypto/attachment-v2.js,
// run under Node by apps/web-demo/interop/web-peer.mjs) reaches the phone
// as a kind image message pointing at it, and the phone's media service
// fetches it, checks its digest and opens it through its decrypt and sniff
// path: a PNG, byte for byte. The message itself travels over the fake
// relay sealed by the mock engine; web_mobile_interop_test.dart covers the
// ratchet between the two clients.
@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/identity/identity_key_value_backend.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_resolver.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_store.dart';
import 'package:veil_mobile/src/core/storage/media_index.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_storage_paths.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_temp_file_store.dart';
import 'package:veil_mobile/src/features/attachments/domain/attachment_rules.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/attachment_media_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/media_fixtures.dart';
import '../support/mock_relay_parties.dart';

const _chat = 'conv-1';
const _attachmentId = '00000000-0000-4000-8000-0000000000c1';

File? _webPeerScript() {
  final script = File(p.normalize(p.join(Directory.current.path, '..', 'web-demo', 'interop', 'web-peer.mjs')));
  return script.existsSync() ? script : null;
}

/// One request to a fresh web peer process, one JSON line each way.
Future<Map<String, dynamic>> _webPeer(File script, String op, Map<String, dynamic> arguments) async {
  final process = await Process.start('node', [script.path]);
  final errors = StringBuffer();
  process.stderr.transform(utf8.decoder).listen(errors.write);
  process.stdin.writeln(json.encode({'id': 1, 'op': op, ...arguments}));
  final line = await process.stdout.transform(utf8.decoder).transform(const LineSplitter()).first;
  await process.stdin.close();
  await process.exitCode;
  final response = json.decode(line) as Map<String, dynamic>;
  if (response['error'] != null) throw StateError('web peer: ${response['error']}\n$errors');
  return (response['result'] as Map).cast<String, dynamic>();
}

void main() {
  final script = _webPeerScript();

  test('a PNG the web seals opens on the phone through the media service', () async {
    final png = solidPng(width: 48, height: 32);
    final sealed = await _webPeer(script!, 'encryptAttachment', {
      'attachmentId': _attachmentId,
      'contentType': 'image/png',
      'data': b64uEncode(png),
    });
    final pointer = (sealed['pointer'] as Map).cast<String, dynamic>();
    final blob = b64uDecode(sealed['blob'] as String);
    final reference = AttachmentReference(
      attachmentId: pointer['id'] as String,
      storageKey: '',
      contentType: pointer['ct'] as String,
      sizeBytes: pointer['sz'] as int,
      sha256: pointer['d'] as String,
      encryptedKey: pointer['ck'] as String,
      nonce: pointer['n'] as String,
      algorithmHint: pointer['alg'] as String,
    );
    expect(AttachmentMediaService.opens(reference), isTrue, reason: 'the web\'s pointer is not one the phone opens');

    final relay = FakeRelay();
    seedMockParties(relay, _chat, ['atlas', 'selene']);
    relay.putUploadedBlob(_attachmentId, blob, uploaderDeviceId: 'dev-selene');
    final root = Directory.systemTemp.createTempSync('veil-interop-media-');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = AttachmentStoragePaths(
      temporaryRoot: () async => Directory('${root.path}/tmp')..createSync(recursive: true),
      supportRoot: () async => Directory('${root.path}/support')..createSync(recursive: true),
      systemTempRoot: () => Directory('${root.path}/system-tmp')..createSync(recursive: true),
    );
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
      identityTrust:
          IdentityTrust(TrustedIdentityResolver(store: TrustedIdentityStore(InMemoryIdentityKeyValueBackend()))),
      attachmentPaths: paths,
      mediaIndex: MemoryMediaIndex(),
    );
    addTearDown(controller.dispose);
    await controller.applySession(mockPartySession('atlas'));
    controller.media.setInUse(true);

    final sender = MockCryptoAdapter();
    final envelope = await sender.messaging.encryptMessage(
      conversationId: _chat,
      senderDeviceId: 'dev-selene',
      recipientUserId: 'user-atlas',
      body: '',
      messageKind: MessageKind.image,
      recipientBundle: const KeyBundle(
        userId: 'user-atlas',
        deviceId: 'dev-atlas',
        handle: 'atlas',
        identityPublicKey: 'ik',
        signedPrekeyBundle: 'spk',
      ),
      attachment: reference,
    );
    final stored =
        relay.inject(senderHandle: 'selene', conversationId: _chat, envelope: sender.envelopeCodec.encodeApiEnvelope(envelope));
    relay.realtimeFor('atlas').deliver('message.new', Map<String, dynamic>.of(stored));

    final media = controller.media;
    await waitFor(() => media.statusOf(_chat, reference).state == MediaState.ready,
        reason: 'never fetched: ${media.statusOf(_chat, reference).state.name}');
    final bytes = await media.photoBytes(_chat, reference);
    expect(bytes, png);
    expect(sniffImageType(bytes!), 'image/png');
    expect(relay.blobDownloads, [_attachmentId]);
  }, skip: script == null ? 'no web demo next to the mobile app' : false);
}
