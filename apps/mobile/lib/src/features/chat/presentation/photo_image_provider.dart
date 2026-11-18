import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../attachments/domain/attachment_rules.dart';
import '../../conversations/data/messenger/attachment_media_service.dart' show MediaKey;

/// The size a photo bubble takes (D23) for a photo [width] by [height]
/// pixels: its aspect fitted into 150 to 240 dp wide, never wider than
/// [maxWidth], and 100 to 320 dp tall. What falls outside is cropped from
/// the middle; the viewer shows the whole photo.
Size photoBubbleSize(int width, int height, {double maxWidth = 240}) {
  final widest = math.min(240.0, maxWidth);
  final narrowest = math.min(150.0, widest);
  final aspect = width / height;
  var w = widest;
  var h = w / aspect;
  if (h > 320) {
    h = 320;
    w = math.max(narrowest, h * aspect);
  }
  if (h < 100) h = 100;
  return Size(w, h);
}

/// The tile an incoming photo shows before it has opened (D24): the
/// pointer carries no size, so it is square, as Signal's is.
const double photoTileExtent = 210;

/// What a photo is decoded for: a bubble no wider than [bubbleWidth] dp on
/// a screen of [pixelRatio], or the viewer, whose long edge is at most
/// [longEdge] pixels.
@immutable
class PhotoDecodeTarget {
  const PhotoDecodeTarget.bubble(int this.bubbleWidth, {this.pixelRatio = 1}) : longEdge = null;

  const PhotoDecodeTarget.viewer(int this.longEdge)
      : bubbleWidth = null,
        pixelRatio = 1;

  final int? bubbleWidth;
  final double pixelRatio;
  final int? longEdge;

  /// The size in pixels to decode a [width] x [height] photo at: enough to
  /// cover its bubble on this screen, or to fit the viewer's long edge;
  /// never larger than it is.
  (int, int) decodeSize(int width, int height) {
    final double scale;
    if (bubbleWidth case final bubble?) {
      final box = photoBubbleSize(width, height, maxWidth: bubble.toDouble()) * pixelRatio;
      scale = math.max(box.width / width, box.height / height);
    } else {
      scale = longEdge! / math.max(width, height);
    }
    final fit = math.min(1.0, scale);
    return (math.max(1, (width * fit).round()), math.max(1, (height * fit).round()));
  }

  @override
  bool operator ==(Object other) =>
      other is PhotoDecodeTarget &&
      other.bubbleWidth == bubbleWidth &&
      other.pixelRatio == pixelRatio &&
      other.longEdge == longEdge;

  @override
  int get hashCode => Object.hash(bubbleWidth, pixelRatio, longEdge);
}

/// What the image cache keeps a decoded photo under: whose it is (the
/// conversation, attachment, digest and key) and what it was decoded for.
@immutable
class PhotoImageKey {
  const PhotoImageKey(this.media, this.target);

  final MediaKey media;
  final PhotoDecodeTarget target;

  @override
  bool operator ==(Object other) => other is PhotoImageKey && other.media == media && other.target == target;

  @override
  int get hashCode => Object.hash(media, target);
}

/// Thrown instead of decoding a photo the render limits refuse (D34).
class PhotoNotShown implements Exception {
  const PhotoNotShown();
}

/// A decrypted photo for an [Image]: its header is read first and nothing
/// is decoded unless its bytes sniff as a JPEG, PNG or WebP within the
/// render limits (D34); then only its first frame, at the size its
/// [target] needs. At most two photos decode at once.
class PhotoImageProvider extends ImageProvider<PhotoImageKey> {
  const PhotoImageProvider({required this.media, required this.bytes, required this.target});

  final MediaKey media;
  final Uint8List bytes;
  final PhotoDecodeTarget target;

  PhotoImageKey get key => PhotoImageKey(media, target);

  /// How many decodes were started in this process.
  @visibleForTesting
  static int debugDecodes = 0;

  static const int _maxDecodes = 2;
  static int _decoding = 0;
  static final Queue<Completer<void>> _waiting = Queue();

  @override
  Future<PhotoImageKey> obtainKey(ImageConfiguration configuration) => SynchronousFuture(key);

  @override
  ImageStreamCompleter loadImage(PhotoImageKey key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_load());

  Future<ImageInfo> _load() async {
    if (_decoding >= _maxDecodes) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    } else {
      _decoding += 1;
    }
    try {
      return await _decodeFirstFrame();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _decoding -= 1;
      }
    }
  }

  Future<ImageInfo> _decodeFirstFrame() async {
    final type = sniffImageType(bytes);
    if (type == null) throw const PhotoNotShown();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (!withinRenderLimits(type, descriptor.width, descriptor.height)) throw const PhotoNotShown();
      final (width, height) = target.decodeSize(descriptor.width, descriptor.height);
      debugDecodes += 1;
      final codec = await descriptor.instantiateCodec(targetWidth: width, targetHeight: height);
      try {
        // An animated WebP or PNG shows its first frame only.
        final frame = await codec.getNextFrame();
        return ImageInfo(image: frame.image);
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
