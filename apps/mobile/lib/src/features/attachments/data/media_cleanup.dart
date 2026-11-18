import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../../../core/crypto/crypto_engine.dart';
import '../../../core/storage/media_index.dart';
import '../domain/attachment_rules.dart';
import 'attachment_decrypt.dart';
import 'attachment_storage_paths.dart';
import 'media_blob_store.dart';

/// What a decrypted copy under veil_open is for.
enum MediaCopyPurpose {
  /// Handed to another app to open it (or, on iOS, to Quick Look).
  open,

  /// Handed to the system save screen.
  save,
}

/// One decrypted copy: its own random folder under veil_open, the blob it
/// came from, and when it was made.
class MediaCopy {
  MediaCopy({
    required this.path,
    required this.conversationId,
    required this.attachmentId,
    required this.digest,
    required this.purpose,
    required this.createdAt,
  });

  final String path;
  final String conversationId;
  final String attachmentId;
  final String digest;
  final MediaCopyPurpose purpose;
  final DateTime createdAt;

  String get folder => p.dirname(path);
}

/// Keeps the media folder and the decrypted copies within their rules
/// (D37, D38), all by the media index, never by a file's times:
/// - an entry whose `expiresAt` is at or before [now] goes (its file, its
///   row, its decrypted bytes through [onEntryDeleted], its copies), swept
///   at start, after messages change (at most once per
///   [expiryCheckInterval]) and by a timer armed for the next expiry;
/// - the entries of a conversation that leaves the list go;
/// - at start, files without a row and rows without a file go;
/// - the folder is held to [maxBytes] by `lastUsedAt`, least recent first,
///   never taking the blob of an upload still pending;
/// - a decrypted copy lives at most [copyLifetime] (swept every
///   [copySweepInterval] while the app is in use, and on every return to
///   it), a Save copy only until the save screen returns or the app locks,
///   and every copy goes at start.
class MediaCleanup {
  MediaCleanup({
    required MediaBlobStore blobs,
    required AttachmentStoragePaths paths,
    required DateTime Function() now,
    required Set<String> Function() pendingAttachmentIds,
    required void Function(MediaIndexEntry entry) onEntryDeleted,
    this.maxBytes = 1024 * 1024 * 1024,
    this.copyLifetime = const Duration(minutes: 10),
    this.copySweepInterval = const Duration(seconds: 60),
    this.expiryCheckInterval = const Duration(seconds: 2),
  })  : _blobs = blobs,
        _paths = paths,
        _now = now,
        _pendingAttachmentIds = pendingAttachmentIds,
        _onEntryDeleted = onEntryDeleted;

  final int maxBytes;
  final Duration copyLifetime;
  final Duration copySweepInterval;
  final Duration expiryCheckInterval;
  final MediaBlobStore _blobs;
  final AttachmentStoragePaths _paths;
  final DateTime Function() _now;
  final Set<String> Function() _pendingAttachmentIds;
  final void Function(MediaIndexEntry entry) _onEntryDeleted;
  final Random _random = Random.secure();

  final Map<String, MediaCopy> _copies = {};
  Set<String>? _listed;
  Timer? _expiryTimer;
  Timer? _copyTimer;
  Timer? _trailingSweep;
  DateTime? _lastExpirySweep;
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  Iterable<MediaCopy> get copies => _copies.values;

  /// Everything a start does: no copy survives one, orphans go, then the
  /// expiry sweep and the cap.
  Future<void> start() => _serial(() async {
        await _deleteEntriesOf(await _paths.openDir());
        _copies.clear();
        await _blobs.removeOrphans();
        await _sweepExpired();
        await _enforceCap();
      });

  /// Deletes only the decrypted copies left from before (the folder's
  /// entries), as soon as the service exists.
  Future<void> purgeCopies() => _serial(() async {
        await _deleteEntriesOf(await _paths.openDir());
        _copies.clear();
      });

  /// Messages changed: the expiry sweep runs now, or once
  /// [expiryCheckInterval] after the last one.
  void noteMessagesChanged() {
    if (_disposed) return;
    final last = _lastExpirySweep;
    final since = last == null ? null : _now().difference(last);
    if (since == null || since >= expiryCheckInterval || since.isNegative) {
      unawaited(sweepExpired());
      return;
    }
    _trailingSweep ??= Timer(expiryCheckInterval - since, () {
      _trailingSweep = null;
      unawaited(sweepExpired());
    });
  }

  Future<void> sweepExpired() => _serial(_sweepExpired);

  /// The conversations the store lists now. Those listed before and gone
  /// now (the store drops one only after a successful list) lose their
  /// blobs, decrypted bytes and copies.
  Future<void> conversationsListed(Iterable<String> conversationIds) {
    final now = {for (final id in conversationIds) id.toLowerCase()};
    final before = _listed;
    _listed = now;
    if (before == null) return Future<void>.value();
    final left = before.difference(now);
    if (left.isEmpty) return Future<void>.value();
    return _serial(() async {
      for (final entry in await _blobs.entries()) {
        if (left.contains(entry.conversationId)) await _deleteEntry(entry);
      }
    });
  }

  Future<void> enforceCap() => _serial(_enforceCap);

  /// Deletes the entry [conversationId] / [attachmentId] / [digest], its
  /// decrypted bytes and its copies: a blob on disk that did not match its
  /// digest.
  Future<void> deleteEntryFor(String conversationId, String attachmentId, String digest) => _serial(() async {
        for (final entry in await _blobs.entries()) {
          if (entry.conversationId == conversationId.toLowerCase() &&
              entry.attachmentId == attachmentId.toLowerCase() &&
              entry.digest == digest) {
            await _deleteEntry(entry);
          }
        }
      });

  /// A fresh path for a decrypted copy named [safeName] (already made safe
  /// by safeLocalFileName): `veil_open/<24 random characters>/<safeName>`,
  /// its folder created, checked to resolve inside veil_open.
  Future<String> newCopyPath(String safeName) async {
    final root = await _paths.openDir();
    final folder = Directory(p.join(root.path, _randomFolderName()));
    await folder.create(recursive: true);
    final path = p.join(folder.path, safeName);
    if (!p.isWithin(root.path, path) || !p.equals(p.dirname(path), folder.path)) {
      await _delete(folder);
      throw ArgumentError('A copy is kept only inside its own folder of veil_open.');
    }
    return path;
  }

  /// Decrypts [blob] into a fresh copy named [safeName] and tracks it for
  /// [purpose]; a [photo] gets the extension its bytes call for. Nothing is
  /// left behind when it fails.
  Future<String> decryptCopy({
    required String conversationId,
    required AttachmentReference reference,
    required String blob,
    required String safeName,
    required MediaCopyPurpose purpose,
    bool photo = false,
  }) async {
    var path = await newCopyPath(safeName);
    try {
      await openFileTo(reference, blob, path);
      if (photo) path = await _withPhotoExtension(path);
    } catch (_) {
      await deleteCopy(path);
      rethrow;
    }
    registerCopy(MediaCopy(
      path: path,
      conversationId: conversationId,
      attachmentId: reference.attachmentId,
      digest: reference.sha256,
      purpose: purpose,
      createdAt: _now(),
    ));
    return path;
  }

  static Future<String> _withPhotoExtension(String path) async {
    final file = File(path);
    final head = await file.openRead(0, 16).fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
    final extension = switch (sniffImageType(head)) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => null,
    };
    if (extension == null || path.toLowerCase().endsWith('.$extension')) return path;
    return (await file.rename('$path.$extension')).path;
  }

  void registerCopy(MediaCopy copy) => _copies[copy.folder] = copy;

  /// Deletes the copy at [path] and its folder.
  Future<void> deleteCopy(String path) async {
    final folder = p.dirname(path);
    _copies.remove(folder);
    final root = await _paths.openDir();
    if (p.isWithin(root.path, folder)) await _delete(Directory(folder));
  }

  /// The app locked: every Save copy goes (an Android Open copy stays, the
  /// app it was handed to may still be reading it).
  Future<void> deleteSaveCopies() async {
    for (final copy in _copies.values.where((copy) => copy.purpose == MediaCopyPurpose.save).toList()) {
      await deleteCopy(copy.path);
    }
  }

  /// Deletes every copy older than [copyLifetime].
  Future<void> sweepCopies() async {
    final now = _now();
    try {
      for (final copy in _copies.values.toList()) {
        if (now.difference(copy.createdAt) >= copyLifetime) await deleteCopy(copy.path);
      }
    } on FileSystemException {
      // Tried again on the next tick.
    }
  }

  /// In use (in front and unlocked): copies are swept on every return and
  /// every [copySweepInterval] while it lasts.
  void setInUse(bool inUse) {
    if (_disposed) return;
    if (inUse) {
      if (_copyTimer != null) return;
      unawaited(sweepCopies());
      _copyTimer = Timer.periodic(copySweepInterval, (_) => unawaited(sweepCopies()));
    } else {
      _copyTimer?.cancel();
      _copyTimer = null;
    }
  }

  /// Forgets what it tracked for the identity that left; its folders are
  /// the session's purge to delete.
  void reset() {
    _listed = null;
    _copies.clear();
    _lastExpirySweep = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _trailingSweep?.cancel();
    _trailingSweep = null;
  }

  void dispose() {
    _disposed = true;
    _expiryTimer?.cancel();
    _copyTimer?.cancel();
    _trailingSweep?.cancel();
  }

  Future<void> _sweepExpired() async {
    final now = _now();
    _lastExpirySweep = now;
    DateTime? next;
    for (final entry in await _blobs.entries()) {
      final expiresAt = entry.expiresAt;
      if (expiresAt == null) continue;
      if (!expiresAt.isAfter(now)) {
        await _deleteEntry(entry);
      } else if (next == null || expiresAt.isBefore(next)) {
        next = expiresAt;
      }
    }
    _armExpiryTimer(next, now);
  }

  void _armExpiryTimer(DateTime? next, DateTime now) {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (next == null || _disposed) return;
    // The timer runs on the monotonic clock; the sweep checks the expiry
    // clock itself when it fires, and arms the next one.
    _expiryTimer = Timer(next.difference(now) + const Duration(milliseconds: 1), () => unawaited(sweepExpired()));
  }

  Future<void> _enforceCap() async {
    await _blobs.flushRecency();
    final entries = await _blobs.entries();
    var total = entries.fold<int>(0, (sum, entry) => sum + entry.sizeBytes);
    if (total <= maxBytes) return;
    final pending = {for (final id in _pendingAttachmentIds()) id.toLowerCase()};
    final byRecency = entries.where((entry) => !pending.contains(entry.attachmentId)).toList()
      ..sort((a, b) => a.lastUsedAt.compareTo(b.lastUsedAt));
    for (final entry in byRecency) {
      if (total <= maxBytes) break;
      await _deleteEntry(entry);
      total -= entry.sizeBytes;
    }
  }

  Future<void> _deleteEntry(MediaIndexEntry entry) async {
    await _blobs.deleteEntry(entry);
    _onEntryDeleted(entry);
    for (final copy in _copies.values.toList()) {
      if (copy.conversationId.toLowerCase() == entry.conversationId &&
          copy.attachmentId.toLowerCase() == entry.attachmentId &&
          copy.digest == entry.digest) {
        await deleteCopy(copy.path);
      }
    }
  }

  // Sweeps run one after another, so a sweep never races another over the
  // same rows. A failing one (an unreachable folder) is dropped: the next
  // sweep tries again, and nothing waits on a sweep's outcome.
  Future<void> _serial(Future<void> Function() step) {
    return _tail = _tail.then<void>((_) async {
      if (!_disposed) await step();
    }).catchError((Object _) {});
  }

  String _randomFolderName() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(List.generate(24, (_) => alphabet.codeUnitAt(_random.nextInt(alphabet.length))));
  }

  static Future<void> _deleteEntriesOf(Directory directory) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      await _delete(entity);
    }
  }

  static Future<void> _delete(FileSystemEntity entity) async {
    try {
      await entity.delete(recursive: true);
    } on PathNotFoundException {
      // Gone already.
    }
  }
}
