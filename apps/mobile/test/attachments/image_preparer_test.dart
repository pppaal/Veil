import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:veil_mobile/src/features/attachments/data/image_preparer.dart';

import '../support/media_fixtures.dart';

// EngineImagePreparer with the real engine decode (inside runAsync, where
// the engine's codecs answer): what a sent photo keeps and loses.

void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('veil-preparer-'));
  tearDown(() => folder.deleteSync(recursive: true));

  Future<PreparedImage> prepare(WidgetTester tester, List<int> source) async {
    final file = File('${folder.path}/picked-${DateTime.now().microsecondsSinceEpoch}')..writeAsBytesSync(source);
    return (await tester.runAsync(() => EngineImagePreparer().prepare(file.path)))!;
  }

  Future<Object?> refusal(WidgetTester tester, List<int> source) async {
    final file = File('${folder.path}/picked-${DateTime.now().microsecondsSinceEpoch}')..writeAsBytesSync(source);
    return tester.runAsync<Object?>(() async {
      try {
        await EngineImagePreparer().prepare(file.path);
        return null;
      } catch (error) {
        return error;
      }
    });
  }

  bool holds(Uint8List bytes, String text) {
    final needle = latin1.encode(text);
    outer:
    for (var i = 0; i + needle.length <= bytes.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (bytes[i + j] != needle[j]) continue outer;
      }
      return true;
    }
    return false;
  }

  testWidgets('a camera photo is turned upright, scaled to 1600 px and keeps no metadata', (tester) async {
    final prepared = await prepare(tester, jpegWithMetadata(width: 4032, height: 3024, orientation: 6));

    expect(prepared.contentType, 'image/jpeg');
    expect((prepared.width, prepared.height), (1200, 1600));
    final decoded = img.decodeJpg(prepared.bytes)!;
    expect((decoded.width, decoded.height), (1200, 1600));
    for (final marker in ['Exif', 'GPS', fixtureXmpNamespace, fixtureXmpMarker, fixtureMake, fixtureModel, fixtureMakerNote]) {
      expect(holds(prepared.bytes, marker), isFalse, reason: marker);
    }
  });

  testWidgets('a PNG with transparency stays a PNG, without its text chunks', (tester) async {
    final prepared = await prepare(tester, pngWithAlpha(width: 40, height: 30));

    expect(prepared.contentType, 'image/png');
    expect((prepared.width, prepared.height), (40, 30));
    for (final chunk in ['tEXt', 'iTXt', 'eXIf', fixturePngText]) {
      expect(holds(prepared.bytes, chunk), isFalse, reason: chunk);
    }
  });

  testWidgets('a half transparent red pixel keeps its colour: straight alpha, not premultiplied', (tester) async {
    final prepared = await prepare(tester, halfAlphaRedPng());

    expect(prepared.contentType, 'image/png');
    final pixel = img.decodePng(prepared.bytes)!.getPixel(0, 0);
    expect([pixel.r, pixel.g, pixel.b, pixel.a], [255, 0, 0, 128]);
  });

  testWidgets('a small photo is never upscaled', (tester) async {
    final prepared = await prepare(tester, jpegWithMetadata(width: 800, height: 600));

    expect((prepared.width, prepared.height), (800, 600));
    expect(prepared.contentType, 'image/jpeg');
  });

  testWidgets('what is not a photo is refused', (tester) async {
    final error = await refusal(tester, notAnImage());
    expect(error, isA<ImagePrepareException>());
    expect((error! as ImagePrepareException).reason, 'not a photo');
  });

  testWidgets('a PNG over 40 MP by its header is refused before it is decoded', (tester) async {
    final watch = Stopwatch()..start();
    final error = await refusal(tester, solidPng(width: 7000, height: 7000));

    expect(error, isA<ImagePrepareException>());
    expect((error! as ImagePrepareException).reason, 'too large');
    // Decoding 49 MP would take seconds and about 200 MB; the header alone
    // takes nothing.
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  testWidgets('a JPEG whose header names 150 MP passes the size check', (tester) async {
    // A tiny JPEG whose frame header claims 15000 x 10000: the size check
    // lets it by (the engine scales a JPEG while it decodes), so whatever
    // happens next it is not refused as too large, nor as not a photo.
    final error = await refusal(tester, _jpegNaming(width: 15000, height: 10000));
    expect(error, anyOf(isNull, isA<ImagePrepareException>().having((e) => e.reason, 'reason', 'undecodable')));
  });
}

// A small baseline JPEG whose frame header names [width] x [height].
Uint8List _jpegNaming({required int width, required int height}) {
  final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 16, height: 16), quality: 90));
  var i = 2;
  while (i < jpeg.length - 1) {
    final marker = jpeg[i + 1];
    final length = (jpeg[i + 2] << 8) | jpeg[i + 3];
    if (marker == 0xc0) {
      jpeg[i + 5] = height >> 8;
      jpeg[i + 6] = height & 0xff;
      jpeg[i + 7] = width >> 8;
      jpeg[i + 8] = width & 0xff;
      break;
    }
    i += 2 + length;
  }
  return jpeg;
}
