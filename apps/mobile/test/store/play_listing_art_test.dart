import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// The Google Play listing art in store/play, which
// tool/play_store_art_test.dart draws from the app's screens. Play takes 2
// to 8 phone screenshots and one 1024 x 500 feature graphic, as PNGs without
// an alpha channel (24-bit). The screenshots are 1080 x 1920 and numbered
// in the order they are uploaded. A file put there by hand, or a run of the
// tool that changed a size, fails here before Play refuses it.

const _playDir = '../../store/play';

void main() {
  test('the Play screenshots are 2 to 8 numbered RGB PNGs of 1080 x 1920', () {
    final shots = Directory('$_playDir/screenshots')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.png'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(shots.length, inInclusiveRange(2, 8), reason: 'run tool/play_store_art_test.dart from apps/mobile');

    for (final (index, shot) in shots.indexed) {
      final name = shot.uri.pathSegments.last;
      expect(name, matches(RegExp(r'^\d\d-[a-z0-9-]+\.png$')), reason: 'NN-<screen>.png');
      expect(int.parse(name.substring(0, 2)), index + 1, reason: '$name: the numbers run from 01 without a gap');
      expect(_pngHeader(shot), (width: 1080, height: 1920, bitDepth: 8, colourType: _rgb), reason: name);
    }
  });

  test('the feature graphic is an RGB PNG of 1024 x 500', () {
    expect(_pngHeader(File('$_playDir/feature-graphic.png')), (width: 1024, height: 500, bitDepth: 8, colourType: _rgb));
  });
}

/// PNG colour type 2: red, green and blue, no alpha (6 would add alpha).
const _rgb = 2;

/// The image header of a PNG: the IHDR chunk, which the format puts first,
/// right after the 8-byte signature.
({int width, int height, int bitDepth, int colourType}) _pngHeader(File file) {
  final bytes = file.readAsBytesSync();
  expect(bytes.length, greaterThan(33), reason: '${file.path} is too short for a PNG');
  expect(bytes.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], reason: '${file.path} is not a PNG');
  expect(String.fromCharCodes(bytes.sublist(12, 16)), 'IHDR', reason: file.path);
  final header = ByteData.sublistView(bytes, 16, 26);
  return (
    width: header.getUint32(0),
    height: header.getUint32(4),
    bitDepth: header.getUint8(8),
    colourType: header.getUint8(9),
  );
}
