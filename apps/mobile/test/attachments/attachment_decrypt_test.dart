import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_decrypt.dart';

import '../support/media_fixtures.dart';

// Opening a sealed attachment (pointer v2) off the UI isolate: digest first,
// then AES-GCM with the id bound in, then, for a photo, the bytes decide
// whether it is one.

// Sealed by the web demo (apps/web-demo/src/crypto/attachment-v2.js,
// encryptAttachment), run under Node as the interop harness runs it: a 3 x 2
// PNG and its pointer, exactly as the web peer printed them.
const _webPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAHElEQVR4nGNgiDqhEXUiIOoEA0NUj0ZUT0BUDwBE/AcJDdC3ogAAAABJRU5ErkJggg==';
const _webBlob = 'g2/0MbJMZjKKLCijmNT9BM50/BriBgZEiAXvZ6NWux2CLYjYwyE0eZa/BufibiHH9TZRtZmwnrwaT8xzIMCiSFbMFpiBophsUVL'
    'tixJ3XbL/6ka//dWmGI/2+AryqPUFL1XlvfiC5ZA=';
const _webPointer = AttachmentReference(
  attachmentId: '6f1c2b0e-4d3a-4e8b-9a71-2c5d8e0f4b13',
  storageKey: '',
  contentType: 'image/png',
  sizeBytes: 85,
  sha256: 'MW3AM9sM9JQIcihyJ_g9klneFUcWR7Wmhuy78KimegY',
  encryptedKey: 'w9BLJ4nlS7WQbrpu8dT1w602eGPis-pDt6Ef0EEFtyk',
  nonce: 'ZreP_3sDs71epYn2',
  algorithmHint: 'aes256gcm-v2',
);

const _id = '00000000-0000-4000-8000-0000000000a1';

void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('veil-decrypt-'));
  tearDown(() => folder.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final file = File(p.join(folder.path, name))..writeAsBytesSync(bytes);
    return file.path;
  }

  test('a photo sealed here opens to its bytes', () async {
    final photo = jpegWithMetadata();
    final sealed = await sealV2(photo, attachmentId: _id, contentType: 'image/jpeg');
    expect(await openPhoto(sealed.reference, write('blob', sealed.blob)), photo);
  });

  test('a photo sealed by the web demo opens to its bytes', () async {
    final bytes = await openPhoto(_webPointer, write('blob', base64.decode(_webBlob)));
    expect(bytes, base64.decode(_webPng));
    expect(await readImageHeader(bytes), (width: 3, height: 2));
  });

  test('a blob that is not the one its pointer names is refused before any decrypt', () async {
    final sealed = await sealV2(jpegWithMetadata(), attachmentId: _id, contentType: 'image/jpeg');
    final tampered = Uint8List.fromList(sealed.blob)..[sealed.blob.length ~/ 2] ^= 0x01;
    await expectLater(
      openPhoto(sealed.reference, write('blob', tampered)),
      throwsA(isA<AttachmentOpenException>()
          .having((error) => error.failure, 'failure', AttachmentOpenFailure.integrity)),
    );
  });

  test('a blob under another id does not open: the id is bound in', () async {
    final sealed = await sealV2(jpegWithMetadata(), attachmentId: _id, contentType: 'image/jpeg');
    final moved = sealed.reference.copyWith(attachmentId: '00000000-0000-4000-8000-0000000000a2');
    await expectLater(
      openPhoto(moved, write('blob', sealed.blob)),
      throwsA(isA<AttachmentOpenException>()
          .having((error) => error.failure, 'failure', AttachmentOpenFailure.integrity)),
    );
  });

  test('a blob opened with another key does not open', () async {
    final sealed = await sealV2(jpegWithMetadata(), attachmentId: _id, contentType: 'image/jpeg');
    final other = await sealV2(jpegWithMetadata(), attachmentId: _id, contentType: 'image/jpeg', seed: 9);
    await expectLater(
      openPhoto(sealed.reference.copyWith(encryptedKey: other.reference.encryptedKey), write('blob', sealed.blob)),
      throwsA(isA<AttachmentOpenException>()),
    );
  });

  test('bytes that are not a JPEG, PNG or WebP are not a photo, whatever the pointer says', () async {
    final sealed = await sealV2(notAnImage(), attachmentId: _id, contentType: 'image/jpeg');
    await expectLater(
      openPhoto(sealed.reference, write('blob', sealed.blob)),
      throwsA(isA<AttachmentOpenException>()
          .having((error) => error.failure, 'failure', AttachmentOpenFailure.unsupported)),
    );
  });

  test('a file is written to its target and nowhere else', () async {
    final pdf = pdfBytes('lease');
    final sealed = await sealV2(pdf, attachmentId: _id, contentType: 'application/pdf');
    final blob = write('blob', sealed.blob);
    final target = p.join(folder.path, 'copy', 'lease.pdf');
    Directory(p.dirname(target)).createSync();

    expect(await openFileTo(sealed.reference, blob, target), pdf.length);
    expect(File(target).readAsBytesSync(), pdf);
    final files = [for (final entity in folder.listSync(recursive: true)) if (entity is File) entity.path]..sort();
    expect(files, [blob, target]..sort());
    expect(File(blob).readAsBytesSync(), sealed.blob, reason: 'the sealed blob changed');
  });

  test('a file that does not open writes nothing', () async {
    final sealed = await sealV2(pdfBytes('x'), attachmentId: _id, contentType: 'application/pdf');
    final target = p.join(folder.path, 'x.pdf');
    await expectLater(
      openFileTo(sealed.reference.copyWith(sha256: _webPointer.sha256), write('blob', sealed.blob), target),
      throwsA(isA<AttachmentOpenException>()),
    );
    expect(File(target).existsSync(), isFalse);
  });

  test('digestMatches says whether a blob is the one its pointer names', () async {
    final sealed = await sealV2(pdfBytes('d'), attachmentId: _id, contentType: 'application/pdf');
    final blob = write('blob', sealed.blob);
    expect(await digestMatches(blob, sealed.reference.sha256), isTrue);
    expect(await digestMatches(blob, _webPointer.sha256), isFalse);
    expect(await digestMatches(blob, 'not base64url!'), isFalse);
  });

  test('every open counts as a decrypt; a digest check does not', () async {
    debugAttachmentDecrypts = 0;
    final sealed = await sealV2(jpegWithMetadata(), attachmentId: _id, contentType: 'image/jpeg');
    final blob = write('blob', sealed.blob);
    await digestMatches(blob, sealed.reference.sha256);
    expect(debugAttachmentDecrypts, 0);
    await openPhoto(sealed.reference, blob);
    expect(debugAttachmentDecrypts, 1);
  });
}
