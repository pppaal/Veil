import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:veil_mobile/src/core/crypto/attachment/attachment_cipher_v2.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/random_source.dart';

// Photos, files and sealed blobs for attachment tests and layout seeds, made
// in memory so no binary fixture sits in the repository. Each carries what a
// test looks for: the metadata a photo must lose, the alpha a PNG must keep,
// a size its header claims, or a marker in a file's bytes.

/// Strings a [jpegWithMetadata] photo carries, which a prepared photo must
/// not.
const fixtureMake = 'VeilFixtureCam';
const fixtureModel = 'VF-Model-9';
const fixtureMakerNote = 'VeilFixtureMakerNote';
const fixtureXmpNamespace = 'http://ns.adobe.com/xap/1.0/';
const fixtureXmpMarker = 'veil-fixture-xmp-marker-7d3f';
const fixturePngText = 'veil-fixture-png-text-chunk';

/// A JPEG of [width] x [height] (left half red, right half blue) as a
/// camera writes one: an EXIF APP1 with Make, Model, the given EXIF
/// [orientation], a MakerNote and, with [gps], a GPS IFD (latitude,
/// longitude and a processing method that reads "GPS"), then an XMP APP1
/// with the Adobe namespace and [fixtureXmpMarker].
Uint8List jpegWithMetadata({int width = 64, int height = 48, int orientation = 1, bool gps = true}) {
  final image = img.Image(width: width, height: height);
  img.fillRect(image, x1: 0, y1: 0, x2: width ~/ 2, y2: height, color: img.ColorRgb8(200, 30, 30));
  img.fillRect(image, x1: width ~/ 2, y1: 0, x2: width, y2: height, color: img.ColorRgb8(30, 60, 200));
  final encoded = img.encodeJpg(image, quality: 90);
  // What follows the start-of-image marker, without the encoder's JFIF
  // segment: a camera's file opens with its EXIF segment.
  var rest = encoded.sublist(2);
  if (rest[0] == 0xff && rest[1] == 0xe0) rest = rest.sublist(2 + ((rest[2] << 8) | rest[3]));
  final exif = _segment(0xe1, [...ascii.encode('Exif'), 0, 0, ..._exifTiff(orientation: orientation, gps: gps)]);
  final xmpPacket = '<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>'
      '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
      '<rdf:Description xmlns:xmp="$fixtureXmpNamespace" xmp:Label="$fixtureXmpMarker"/>'
      '</rdf:RDF></x:xmpmeta><?xpacket end="w"?>';
  final xmp = _segment(0xe1, [...ascii.encode(fixtureXmpNamespace), 0, ...utf8.encode(xmpPacket)]);
  return Uint8List.fromList([0xff, 0xd8, ...exif, ...xmp, ...rest]);
}

/// A PNG of [width] x [height] whose pixels are partly transparent, with a
/// tEXt chunk holding [fixturePngText].
Uint8List pngWithAlpha({int width = 32, int height = 32}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, 20 + (x * 7) % 200, 120, 200 - (y * 5) % 180, x < width ~/ 2 ? 255 : 96);
    }
  }
  image.textData = {'Comment': fixturePngText};
  return img.encodePng(image);
}

/// One pixel of pure red (255, 0, 0) at alpha 128: premultiplied bytes
/// would make it (128, 0, 0).
Uint8List halfAlphaRedPng() {
  final image = img.Image(width: 1, height: 1, numChannels: 4)..setPixelRgba(0, 0, 255, 0, 0, 128);
  return img.encodePng(image);
}

/// A PNG of [width] x [height] that compresses to almost nothing (one bit
/// per pixel, every pixel black): 7000 x 7000 is a few kilobytes, while
/// decoding it would take about 200 MB.
Uint8List solidPng({required int width, required int height}) {
  final rowBytes = 1 + (width + 7) ~/ 8; // a filter byte, then the bits
  final raw = Uint8List(rowBytes * height); // all zero: filter none, black
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 1) // bit depth
    ..setUint8(9, 0) // greyscale
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  return Uint8List.fromList([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
    ..._pngChunk('IHDR', header.buffer.asUint8List()),
    ..._pngChunk('IDAT', ZLibCodec(level: 9).encode(raw)),
    ..._pngChunk('IEND', const []),
  ]);
}

/// The head of an MP4 file: just enough of its ftyp box to sniff.
Uint8List mp4Head() => _ftyp('isom', ['isom', 'iso2', 'avc1', 'mp41']);

/// The head of a HEIC photo: just enough of its ftyp box to sniff.
Uint8List heicHead() => _ftyp('heic', ['mif1', 'heic']);

/// A small PDF whose bytes hold [marker].
Uint8List pdfBytes(String marker) => Uint8List.fromList(utf8.encode(
      '%PDF-1.4\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'
      '2 0 obj << /Type /Pages /Kids [] /Count 0 >> endobj\n'
      '% $marker\ntrailer << /Root 1 0 R >>\n%%EOF\n',
    ));

/// What a hostile sender might label image/png: an SVG with a script.
Uint8List notAnImage() => Uint8List.fromList(utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
      '<script>alert(document.cookie)</script><html><body>not an image</body></html></svg>',
    ));

/// [plaintext] sealed as the app and the web seal an attachment (pointer
/// v2), with keys drawn from a source seeded by [seed], so a seed gives the
/// same blob on every run.
Future<({AttachmentReference reference, Uint8List blob})> sealV2(
  List<int> plaintext, {
  required String attachmentId,
  required String contentType,
  int seed = 1,
}) async {
  final sealed = await encryptAttachmentV2(
    attachmentId: attachmentId,
    storageKey: '',
    contentType: contentType,
    plaintext: plaintext,
    random: _SeededRandom(seed),
  );
  return (reference: sealed.reference, blob: Uint8List.fromList(sealed.ciphertext));
}

class _SeededRandom implements RandomSource {
  _SeededRandom(int seed) : _random = Random(seed);

  final Random _random;

  @override
  Uint8List nextBytes(int length) => Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));
}

// A JPEG marker segment: FF, the marker, a big-endian length that counts
// itself, then [payload].
List<int> _segment(int marker, List<int> payload) {
  final length = payload.length + 2;
  return [0xff, marker, length >> 8, length & 0xff, ...payload];
}

Uint8List _ftyp(String major, List<String> compatible) {
  final size = 16 + 4 * compatible.length;
  return Uint8List.fromList([
    ...[size >> 24, (size >> 16) & 0xff, (size >> 8) & 0xff, size & 0xff],
    ...ascii.encode('ftyp'),
    ...ascii.encode(major),
    0, 0, 0, 0, // minor version
    for (final brand in compatible) ...ascii.encode(brand),
  ]);
}

List<int> _pngChunk(String type, List<int> data) {
  final typed = [...ascii.encode(type), ...data];
  final length = data.length;
  final crc = _crc32(typed);
  return [
    length >> 24, (length >> 16) & 0xff, (length >> 8) & 0xff, length & 0xff, //
    ...typed,
    crc >> 24, (crc >> 16) & 0xff, (crc >> 8) & 0xff, crc & 0xff,
  ];
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >> 8);
  }
  return crc ^ 0xffffffff;
}

// One TIFF directory entry: tag, type, count and the value's bytes (little
// endian), inline when they fit in four bytes.
class _Entry {
  const _Entry(this.tag, this.type, this.count, this.value);

  final int tag;
  final int type;
  final int count;
  final List<int> value;
}

List<int> _u16(int value) => [value & 0xff, (value >> 8) & 0xff];
List<int> _u32(int value) => [value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff, (value >> 24) & 0xff];

_Entry _ascii(int tag, String text) {
  final bytes = [...ascii.encode(text), 0];
  return _Entry(tag, 2, bytes.length, bytes);
}

_Entry _short(int tag, int value) => _Entry(tag, 3, 1, _u16(value));
_Entry _long(int tag, int value) => _Entry(tag, 4, 1, _u32(value));
_Entry _undefined(int tag, List<int> bytes) => _Entry(tag, 7, bytes.length, bytes);
_Entry _bytes(int tag, List<int> bytes) => _Entry(tag, 1, bytes.length, bytes);
_Entry _rationals(int tag, List<(int, int)> values) =>
    _Entry(tag, 5, values.length, [
      for (final (numerator, denominator) in values) ...[..._u32(numerator), ..._u32(denominator)],
    ]);

// A little-endian TIFF structure as EXIF holds it: IFD0 (Make, Model,
// Orientation, and pointers to the EXIF and GPS directories), the EXIF
// directory (a MakerNote), the GPS directory, then every value too long to
// sit in its entry.
List<int> _exifTiff({required int orientation, required bool gps}) {
  final ifd0 = <_Entry>[
    _ascii(0x010f, fixtureMake),
    _ascii(0x0110, fixtureModel),
    _short(0x0112, orientation),
    _long(0x8769, 0), // EXIF directory, patched below
    if (gps) _long(0x8825, 0), // GPS directory, patched below
  ];
  final exif = [_undefined(0x927c, ascii.encode('$fixtureMakerNote:serial-0042:lens-28mm'))];
  final gpsIfd = [
    _bytes(0x0000, const [2, 3, 0, 0]),
    _ascii(0x0001, 'N'),
    _rationals(0x0002, const [(37, 1), (33, 1), (3012, 100)]),
    _ascii(0x0003, 'E'),
    _rationals(0x0004, const [(126, 1), (58, 1), (4200, 100)]),
    _undefined(0x001b, [...ascii.encode('ASCII'), 0, 0, 0, ...ascii.encode('GPS fixture fix')]),
  ];
  final ifds = [ifd0, exif, if (gps) gpsIfd];
  final offsets = <int>[];
  var offset = 8;
  for (final ifd in ifds) {
    offsets.add(offset);
    offset += 2 + 12 * ifd.length + 4;
  }
  ifd0[3] = _long(0x8769, offsets[1]);
  if (gps) ifd0[4] = _long(0x8825, offsets[2]);

  final dataStart = offset;
  final out = <int>[0x49, 0x49, 0x2a, 0x00, ..._u32(8)];
  final data = <int>[];
  for (final ifd in ifds) {
    out.addAll(_u16(ifd.length));
    for (final entry in ifd) {
      out
        ..addAll(_u16(entry.tag))
        ..addAll(_u16(entry.type))
        ..addAll(_u32(entry.count));
      if (entry.value.length <= 4) {
        out.addAll([...entry.value, ...List<int>.filled(4 - entry.value.length, 0)]);
      } else {
        out.addAll(_u32(dataStart + data.length));
        data.addAll(entry.value);
        if (data.length.isOdd) data.add(0);
      }
    }
    out.addAll(_u32(0));
  }
  return [...out, ...data];
}
