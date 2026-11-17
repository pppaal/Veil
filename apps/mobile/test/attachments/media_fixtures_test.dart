import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:veil_mobile/src/core/crypto/attachment/attachment_cipher_v2.dart';
import 'package:veil_mobile/src/features/attachments/domain/attachment_rules.dart';

import '../support/media_fixtures.dart';

// The fixtures carry what the attachment tests look for; if one stopped
// doing so, a test that checks it is gone would pass for the wrong reason.

bool _contains(List<int> haystack, String needle) => latin1.decode(haystack).contains(needle);

void main() {
  test('the camera JPEG carries EXIF with GPS, the orientation, a MakerNote and XMP', () {
    final jpeg = jpegWithMetadata(width: 40, height: 30, orientation: 6);
    expect(sniffImageType(jpeg), 'image/jpeg');
    final exif = img.decodeJpgExif(jpeg)!;
    expect(exif.imageIfd['Make']?.toString(), fixtureMake);
    expect(exif.imageIfd['Model']?.toString(), fixtureModel);
    expect(exif.imageIfd.orientation, 6);
    expect(exif.gpsIfd.isEmpty, isFalse);
    expect(exif.gpsIfd.hasGPSLatitude, isTrue);
    expect(exif.gpsIfd.hasGPSLongitude, isTrue);
    for (final marker in ['Exif', 'GPS', fixtureMake, fixtureModel, fixtureMakerNote, fixtureXmpNamespace, fixtureXmpMarker]) {
      expect(_contains(jpeg, marker), isTrue, reason: marker);
    }
    // A decoder that honours the orientation turns it upright: 90 degrees.
    final decoded = img.decodeJpg(jpeg)!;
    expect((decoded.width, decoded.height), (30, 40));
    final upright = img.decodeJpg(jpegWithMetadata(width: 40, height: 30))!;
    expect((upright.width, upright.height), (40, 30));
    expect(img.decodeJpgExif(jpegWithMetadata(gps: false))!.gpsIfd.isEmpty, isTrue);
  });

  test('the PNGs carry a text chunk, partial alpha and a straight half-alpha red', () {
    final png = pngWithAlpha(width: 8, height: 8);
    expect(sniffImageType(png), 'image/png');
    expect(_contains(png, 'tEXt'), isTrue);
    expect(_contains(png, fixturePngText), isTrue);
    final decoded = img.decodePng(png)!;
    expect(decoded.getPixel(7, 0).a, lessThan(255));

    final pixel = img.decodePng(halfAlphaRedPng())!.getPixel(0, 0);
    expect([pixel.r, pixel.g, pixel.b, pixel.a], [255, 0, 0, 128]);
  });

  test('the solid PNG names 49 MP in a few kilobytes', () {
    final png = solidPng(width: 7000, height: 7000);
    expect(png.length, lessThan(100 * 1024));
    expect(sniffImageType(png), 'image/png');
    final info = img.PngDecoder().startDecode(png)!;
    expect((info.width, info.height), (7000, 7000));
    expect(withinRenderLimits('image/png', info.width, info.height), isFalse);
  });

  test('heads, documents and a fake image sniff as what they are', () {
    expect(looksLikePhotoOrVideo(mp4Head(), 'x'), isTrue);
    expect(looksLikePhotoOrVideo(heicHead(), 'x'), isTrue);
    expect(_contains(pdfBytes('marker-1'), 'marker-1'), isTrue);
    expect(utf8.decode(pdfBytes('m')).startsWith('%PDF-'), isTrue);
    expect(sniffImageType(notAnImage()), isNull);
  });

  test('a sealed blob is the same for a seed, opens, and differs for another seed', () async {
    const id = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
    final plaintext = utf8.encode('photo bytes');
    final first = await sealV2(plaintext, attachmentId: id, contentType: 'image/png');
    final again = await sealV2(plaintext, attachmentId: id, contentType: 'image/png');
    final other = await sealV2(plaintext, attachmentId: id, contentType: 'image/png', seed: 2);
    expect(again.blob, first.blob);
    expect(again.reference.sha256, first.reference.sha256);
    expect(other.blob, isNot(first.blob));
    expect(first.reference.algorithmHint, kAttachmentAlgorithmV2);
    expect(first.reference.attachmentId, id);
    expect(first.reference.sizeBytes, plaintext.length);
    expect(await decryptAttachmentV2(reference: first.reference, ciphertext: first.blob), plaintext);
  });
}
