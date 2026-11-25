// What the phone sends as a photo or a file, opened by the web client's own
// modules (apps/web-demo/src, through apps/web-demo/interop/web-peer.mjs
// under Node): a photo prepared by EngineImagePreparer and sealed by the
// app's sealer goes as kind image with an empty body, and the web opens
// pixels without metadata; a file named with a bidi override and 130
// characters goes under the name the web would have given it.
@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/features/attachments/data/image_preparer.dart';
import 'package:veil_mobile/src/features/attachments/domain/attachment_rules.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/attachment_sealer.dart';

import '../support/media_fixtures.dart';

var _lastId = 0x100;

String _nextId() => '00000000-0000-4000-8000-${(++_lastId).toRadixString(16).padLeft(12, '0')}';

File? _webPeerScript() {
  final script = File(p.normalize(p.join(Directory.current.path, '..', 'web-demo', 'interop', 'web-peer.mjs')));
  return script.existsSync() ? script : null;
}

/// The web peer, one JSON line per request.
class _WebPeer {
  _WebPeer._(this._process) {
    _process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      final response = json.decode(line) as Map<String, dynamic>;
      final pending = _pending.remove(response['id']);
      if (pending == null) return;
      if (response['error'] != null) {
        pending.completeError(StateError('web peer: ${response['error']}'));
      } else {
        pending.complete((response['result'] as Map).cast<String, dynamic>());
      }
    });
    _process.stderr.transform(utf8.decoder).listen(_stderr.write);
    unawaited(_process.exitCode.then((code) {
      for (final pending in _pending.values) {
        pending.completeError(StateError('web peer exited with code $code\n$_stderr'));
      }
      _pending.clear();
    }));
  }

  final Process _process;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  final _stderr = StringBuffer();
  var _lastRequest = 0;

  static Future<_WebPeer> start(File script) async => _WebPeer._(await Process.start('node', [script.path]));

  Future<Map<String, dynamic>> call(String op, Map<String, dynamic> arguments) {
    final id = ++_lastRequest;
    final response = Completer<Map<String, dynamic>>();
    _pending[id] = response;
    _process.stdin.writeln(json.encode({'id': id, 'op': op, ...arguments}));
    return response.future;
  }

  Future<void> close() async {
    await _process.stdin.close();
    await _process.exitCode;
  }
}

/// What the relay stores of a posted envelope and serves back.
Map<String, dynamic> _relayed(Map<String, dynamic> posted) {
  final attachment = posted['attachment'] as Map<String, dynamic>?;
  return {
    for (final field in ['version', 'conversationId', 'senderDeviceId', 'ciphertext', 'nonce', 'messageType'])
      field: posted[field],
    'attachment': attachment == null ? null : {'attachmentId': attachment['attachmentId']},
    'expiresAt': posted['expiresAt'],
  };
}

void main() {
  final script = _webPeerScript();
  final skip = script == null && Platform.environment['CI'] != 'true'
      ? 'apps/web-demo is not next to apps/mobile in this checkout'
      : null;

  testWidgets('a photo and a hostile file name from the phone open on the web as the web would have sent them',
      (tester) async {
    if (script == null) throw StateError('apps/web-demo/interop/web-peer.mjs not found from ${Directory.current.path}');
    final folder = Directory.systemTemp.createTempSync('veil-send-interop-');
    addTearDown(() => folder.deleteSync(recursive: true));

    // The engine decodes only inside runAsync; so does everything else here
    // that waits on real I/O (the web peer, files, isolates).
    await tester.runAsync(() async {
      final peer = await _WebPeer.start(script);
      try {
        // The web device, and the phone with a session to it.
        final webUser = _nextId();
        final webDevice = _nextId();
        final webName = 'web-$webDevice';
        final published = await peer.call('create', {'name': webName, 'userId': webUser, 'deviceId': webDevice});
        final mobile = LibCryptoAdapter();
        final mobileDevice = _nextId();
        final mobileUser = _nextId();
        final identity = await mobile.identity.generateDeviceIdentity(mobileDevice);
        mobile.setLocalIdentityLoader(() async => identity.identityPrivateKeyRef);
        final conversationId = _nextId();
        await mobile.sessions.bootstrapSession(SessionBootstrapRequest(
          conversationId: conversationId,
          localDeviceId: mobileDevice,
          localUserId: mobileUser,
          remoteUserId: webUser,
          remoteDeviceId: webDevice,
          remoteIdentityPublicKey: published['identityPublicKey'] as String,
          remoteSignedPrekeyBundle: published['signedPrekeyBundle'] as String,
        ));
        final web = KeyBundle(
          userId: webUser,
          deviceId: webDevice,
          handle: '',
          identityPublicKey: published['identityPublicKey'] as String,
          signedPrekeyBundle: published['signedPrekeyBundle'] as String,
        );

        // Sealed as the app seals a staged plaintext; sent as the outbox
        // sends once the upload is done.
        Future<(AttachmentReference, List<int>)> seal(List<int> plaintext, String contentType) async {
          final staged = File(p.join(folder.path, 'staged-${_lastId++}'))..writeAsBytesSync(plaintext);
          final part = p.join(folder.path, '${'a' * 64}.part');
          final sealed = await sealStagedFileInIsolate(staged.path, part, contentType);
          return (sealed.reference, File(part).readAsBytesSync());
        }

        Future<Map<String, dynamic>> sendAndOpen(String body, MessageKind kind, AttachmentReference reference) async {
          final envelope = await mobile.messaging.encryptMessage(
            conversationId: conversationId,
            senderDeviceId: mobileDevice,
            recipientUserId: webUser,
            body: body,
            messageKind: kind,
            recipientBundle: web,
            attachment: reference,
          );
          final relayed = _relayed(mobile.envelopeCodec.encodeApiEnvelope(envelope));
          expect(relayed['attachment'], {'attachmentId': reference.attachmentId});
          final opened = await peer.call('decrypt', {'name': webName, 'envelope': relayed});
          expect(opened['status'], 'ok', reason: opened['reason'] as String?);
          return opened['content'] as Map<String, dynamic>;
        }

        // A camera photo, prepared on the phone.
        final picked = File(p.join(folder.path, 'picked.jpg'))
          ..writeAsBytesSync(jpegWithMetadata(width: 2000, height: 1500, orientation: 6));
        final prepared = await EngineImagePreparer().prepare(picked.path);
        final (photoPointer, photoBlob) = await seal(prepared.bytes, prepared.contentType);
        final photo = await sendAndOpen('', MessageKind.image, photoPointer);
        expect(photo['kind'], 'image');
        expect(photo['text'], '');
        final photoAttachment = photo['attachment'] as Map<String, dynamic>;
        expect(photoAttachment, containsPair('ct', 'image/jpeg'));
        expect(photoAttachment, containsPair('alg', kAttachmentAlgorithmV2));
        final photoBytes = b64uDecode(
          (await peer.call('decryptAttachment', {'pointer': photoAttachment, 'blob': b64uEncode(photoBlob)}))['data']
              as String,
        );
        expect(photoBytes.sublist(0, 3), [0xff, 0xd8, 0xff]);
        expect(latin1.decode(photoBytes, allowInvalid: true).contains('Exif'), isFalse);
        expect(photoBytes, prepared.bytes);

        // A file whose name hides its extension behind a right-to-left
        // override and runs past the 120 characters the web keeps.
        final hostile = '${'quarterly report ' * 7}invoice\u202Efdp.exe';
        expect(hostile.runes.length, greaterThanOrEqualTo(130));
        final name = sanitizeFileName(hostile);
        expect(name.contains('\u202E'), isFalse);
        final (filePointer, fileBlob) = await seal(pdfBytes('quarterly'), contentTypeForName(name));
        final file = await sendAndOpen(name, MessageKind.file, filePointer);
        expect(file['kind'], 'file');
        expect(file['text'], name);
        final fileBytes = b64uDecode(
          (await peer.call('decryptAttachment', {'pointer': file['attachment'], 'blob': b64uEncode(fileBlob)}))['data']
              as String,
        );
        expect(fileBytes, pdfBytes('quarterly'));
      } finally {
        await peer.close();
      }
    });
  }, skip: skip != null);
}
