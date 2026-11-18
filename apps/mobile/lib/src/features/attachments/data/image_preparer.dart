import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../domain/attachment_rules.dart';

/// A photo made ready to send: encoded pixels and nothing else.
class PreparedImage {
  const PreparedImage({required this.bytes, required this.contentType, required this.width, required this.height});

  final Uint8List bytes;

  /// image/jpeg, or image/png for a photo with transparency (D9).
  final String contentType;
  final int width;
  final int height;
}

/// A photo that cannot be prepared: too large to decode safely, a format
/// the platform cannot decode, or not a photo at all (D10).
class ImagePrepareException implements Exception {
  const ImagePrepareException(this.reason);

  final String reason;

  @override
  String toString() => 'ImagePrepareException: $reason';
}

/// Makes a picked photo ready to send (D8).
abstract interface class ImagePreparer {
  /// Throws [ImagePrepareException].
  Future<PreparedImage> prepare(String sourcePath);
}

/// Re-encodes a photo on the phone, so what is sent is pixels only: EXIF,
/// GPS, XMP, IPTC, the maker's notes, the embedded thumbnail and the colour
/// profile are gone by construction, with no list of what to strip.
///
/// The source's size is read from its header before anything is decoded,
/// and anything past the limits is refused (a JPEG up to 200 MP, which the
/// engine scales while it decodes; any other format up to 40 MP, which it
/// decodes whole first). The engine decodes the first frame straight to a
/// long edge of at most 1600 px, applying the EXIF orientation, never
/// upscaling; its straight (not premultiplied) RGBA is encoded in an isolate
/// as a JPEG at quality 80, or as a PNG when any pixel is transparent. A PNG
/// over 10 MiB is flattened on white and sent as a JPEG instead.
class EngineImagePreparer implements ImagePreparer {
  @override
  Future<PreparedImage> prepare(String sourcePath) async {
    final Uint8List source;
    try {
      source = await File(sourcePath).readAsBytes();
    } on FileSystemException {
      throw const ImagePrepareException('unreadable');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(source);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? frame;
    try {
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
      } catch (_) {
        throw const ImagePrepareException('not a photo');
      }
      final width = descriptor.width;
      final height = descriptor.height;
      final isJpeg = sniffImageType(source) == 'image/jpeg';
      if (!withinSourceLimits(isJpeg: isJpeg, width: width, height: height)) {
        throw const ImagePrepareException('too large');
      }
      final longEdge = width > height ? width : height;
      final scale = longEdge > kPhotoMaxEdge ? kPhotoMaxEdge / longEdge : 1.0;
      try {
        codec = await descriptor.instantiateCodec(
          targetWidth: scale < 1 ? (width * scale).round().clamp(1, kPhotoMaxEdge) : null,
          targetHeight: scale < 1 ? (height * scale).round().clamp(1, kPhotoMaxEdge) : null,
        );
        frame = (await codec.getNextFrame()).image;
      } catch (_) {
        throw const ImagePrepareException('undecodable');
      }
      final rgba = await frame.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (rgba == null) throw const ImagePrepareException('undecodable');
      final pixels = TransferableTypedData.fromList([rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes)]);
      final frameWidth = frame.width;
      final frameHeight = frame.height;
      final (encoded, contentType) = await Isolate.run(() => _encode(pixels, frameWidth, frameHeight));
      return PreparedImage(
        bytes: encoded.materialize().asUint8List(),
        contentType: contentType,
        width: frameWidth,
        height: frameHeight,
      );
    } finally {
      frame?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}

/// Above this a PNG is flattened and sent as a JPEG.
const int _maxPngBytes = 10 * 1024 * 1024;

// Runs in its own isolate: straight RGBA in, the encoded photo out.
(TransferableTypedData, String) _encode(TransferableTypedData pixels, int width, int height) {
  final rgba = pixels.materialize().asUint8List();
  var transparent = false;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] < 255) {
      transparent = true;
      break;
    }
  }
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  if (transparent) {
    final png = img.encodePng(image);
    if (png.length <= _maxPngBytes) return (TransferableTypedData.fromList([png]), 'image/png');
  }
  final jpeg = img.encodeJpg(transparent ? _onWhite(rgba, width, height) : image, quality: kPhotoJpegQuality);
  return (TransferableTypedData.fromList([jpeg]), 'image/jpeg');
}

// Straight alpha over white: c' = c * a + 255 * (1 - a).
img.Image _onWhite(Uint8List rgba, int width, int height) {
  final flat = img.Image(width: width, height: height);
  for (var y = 0, i = 0; y < height; y++) {
    for (var x = 0; x < width; x++, i += 4) {
      final alpha = rgba[i + 3];
      int over(int channel) => (channel * alpha + 255 * (255 - alpha) + 127) ~/ 255;
      flat.setPixelRgb(x, y, over(rgba[i]), over(rgba[i + 1]), over(rgba[i + 2]));
    }
  }
  return flat;
}

final imagePreparerProvider = Provider<ImagePreparer>((ref) => EngineImagePreparer());
