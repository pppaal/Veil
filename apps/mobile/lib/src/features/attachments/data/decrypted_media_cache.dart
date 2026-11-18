import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../core/crypto/crypto_engine.dart';

/// Which attachment of which conversation something belongs to: the
/// conversation and attachment id (lower-cased, as the media index keeps
/// them) and the pointer's digest. The pointer's key, nonce and exact id
/// count too, so a pointer that reuses another message's id and digest with
/// another key is another attachment, and never gets that message's bytes.
@immutable
class MediaKey {
  MediaKey(String conversationId, AttachmentReference reference)
      : conversationId = conversationId.toLowerCase(),
        attachmentId = reference.attachmentId.toLowerCase(),
        digest = reference.sha256,
        _sealedWith = '${reference.attachmentId}|${reference.encryptedKey}|${reference.nonce}';

  final String conversationId;
  final String attachmentId;
  final String digest;
  final String _sealedWith;

  /// Whether this key names the blob [conversationId] / [attachmentId] /
  /// [digest] of the media index, whatever key opens it.
  bool names(String conversationId, String attachmentId, String digest) =>
      this.conversationId == conversationId.toLowerCase() &&
      this.attachmentId == attachmentId.toLowerCase() &&
      this.digest == digest;

  @override
  bool operator ==(Object other) =>
      other is MediaKey &&
      other.conversationId == conversationId &&
      other.attachmentId == attachmentId &&
      other.digest == digest &&
      other._sealedWith == _sealedWith;

  @override
  int get hashCode => Object.hash(conversationId, attachmentId, digest, _sealedWith);

  // Never the key.
  @override
  String toString() => 'MediaKey($conversationId, $attachmentId)';
}

/// Decrypted photos in memory, least recently used out first, at most
/// [maxBytes] in all (48 MB). Nothing decrypted is ever written to disk for
/// a photo; this and the image cache are where it lives, both emptied when
/// the app locks.
class DecryptedMediaCache {
  DecryptedMediaCache({this.maxBytes = 48 * 1024 * 1024});

  final int maxBytes;
  final LinkedHashMap<MediaKey, Uint8List> _entries = LinkedHashMap();
  final Map<MediaKey, Set<Object>> _imageKeys = {};
  int _bytes = 0;

  /// Notes that the image cache holds [imageKey] for [key], so the decoded
  /// image goes when [removeWhere] takes [key].
  void noteImageKey(MediaKey key, Object imageKey) => _imageKeys.putIfAbsent(key, () => {}).add(imageKey);

  int get sizeBytes => _bytes;

  int get length => _entries.length;

  Uint8List? get(MediaKey key) {
    final bytes = _entries.remove(key);
    if (bytes != null) _entries[key] = bytes;
    return bytes;
  }

  /// Keeps [bytes] under [key]; a photo larger than the whole cache is not
  /// kept at all.
  void put(MediaKey key, Uint8List bytes) {
    remove(key);
    if (bytes.length > maxBytes) return;
    _entries[key] = bytes;
    _bytes += bytes.length;
    while (_bytes > maxBytes && _entries.isNotEmpty) {
      remove(_entries.keys.first);
    }
  }

  void remove(MediaKey key) {
    final bytes = _entries.remove(key);
    if (bytes != null) _bytes -= bytes.length;
  }

  /// Drops the bytes and the decoded images of every key [test] accepts.
  void removeWhere(bool Function(MediaKey key) test) {
    for (final key in _entries.keys.where(test).toList()) {
      remove(key);
    }
    for (final key in _imageKeys.keys.where(test).toList()) {
      for (final imageKey in _imageKeys.remove(key)!) {
        decodedImageCache?.evict(imageKey, includeLive: true);
      }
    }
  }

  /// Drops every decrypted byte and every decoded image.
  void clear() {
    _entries.clear();
    _imageKeys.clear();
    _bytes = 0;
    clearDecodedImages();
  }
}

/// Flutter's image cache, where decoded photos live; null without a binding
/// (a test without one, where nothing was decoded).
ImageCache? get decodedImageCache {
  try {
    return PaintingBinding.instance.imageCache;
  } on FlutterError {
    return null;
  }
}

/// Drops every decoded image, live ones included: the session locked.
void clearDecodedImages() => decodedImageCache
  ?..clear()
  ..clearLiveImages();
