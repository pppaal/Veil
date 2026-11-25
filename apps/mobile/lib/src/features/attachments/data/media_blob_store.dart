import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../../../core/storage/media_index.dart';
import '../../../core/util/uuid_v4.dart';
import 'attachment_storage_paths.dart';

/// The sealed blobs of photos and files on the phone, downloaded or sent:
/// the ciphertext exactly as uploaded, digest-verified, each under a random
/// name of 64 lower-case hex characters in one flat folder. Which blob
/// belongs to which message is only in the [MediaIndex] (inside the
/// encrypted database); a file's name, size on disk aside, says nothing.
/// A blob is written as `<name>.part` and renamed once whole. Recency is
/// the index's `lastUsedAt`, never a file time.
///
/// Policy (when to fetch, what to evict, expiry) is the media service's;
/// this store only keeps the folder and the index in step.
class MediaBlobStore {
  MediaBlobStore({
    required AttachmentStoragePaths paths,
    required MediaIndex index,
    DateTime Function() now = DateTime.now,
  })  : _paths = paths,
        _index = index,
        _now = now;

  /// How stale an entry's `lastUsedAt` may get before [flushRecency]
  /// writes it again.
  static const recencyInterval = Duration(minutes: 1);

  static final RegExp _conversationIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
  static final RegExp _blobName = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _partName = RegExp(r'^[0-9a-f]{64}\.part$');

  final AttachmentStoragePaths _paths;
  final MediaIndex _index;
  final DateTime Function() _now;
  final Random _random = Random.secure();

  // Part files reserved in this process and not committed yet, which
  // removeOrphans leaves alone: a seal may be writing one right now.
  final Set<String> _reserved = {};
  // When each entry was last used here, and the lastUsedAt last written.
  final Map<String, DateTime> _usedAt = {};
  final Map<String, DateTime> _writtenAt = {};

  /// Told of every index entry removed here, whoever removed it and why (a
  /// sweep, a cancelled send, a file found gone): whatever is held
  /// decrypted for it goes too (D36). Set by the media service's cleanup.
  void Function(MediaIndexEntry entry)? onEntryRemoved;

  /// Told of every expiry written here, a blob committed with one or one
  /// set later, so the media service's cleanup can arm its timer for it.
  void Function(DateTime expiresAt)? onExpiryWritten;

  /// A fresh `<media>/<random 64 hex>.part` path for a blob to be written
  /// to and then [commit]ted.
  Future<String> reservePartPath() async {
    final folder = await _paths.mediaDir();
    final name = '${_randomName()}.part';
    _reserved.add(name);
    return p.join(folder.path, name);
  }

  /// Renames the whole blob at [partPath] (from [reservePartPath]) to its
  /// opaque name and indexes it under [conversationId] and [attachmentId]
  /// (both checked and lower-cased) and [digest]; [sizeBytes] is the
  /// blob's size. A blob indexed for the same three before is replaced.
  /// Returns the blob's path.
  Future<String> commit({
    required String partPath,
    required String conversationId,
    required String attachmentId,
    required String digest,
    required int sizeBytes,
    DateTime? expiresAt,
  }) async {
    final (conversation, attachment) = _checkedIds(conversationId, attachmentId);
    final folder = await _paths.mediaDir();
    final partName = p.basename(partPath);
    if (!p.equals(p.dirname(partPath), folder.path) || !_partName.hasMatch(partName)) {
      throw ArgumentError.value(partPath, 'partPath', 'is not a part file of the media folder');
    }
    final fileName = partName.substring(0, 64);
    final path = p.join(folder.path, fileName);
    final MediaIndexEntry? previous;
    final now = _now();
    // The part stays reserved until the row is written: between the rename
    // and the row, removeOrphans keeps the blob by its reserved part.
    try {
      await File(partPath).rename(path);
      previous = await _index.find(conversation, attachment, digest);
      await _index.put(MediaIndexEntry(
        fileName: fileName,
        conversationId: conversation,
        attachmentId: attachment,
        digest: digest,
        sizeBytes: sizeBytes,
        expiresAt: expiresAt,
        lastUsedAt: now,
      ));
    } finally {
      _reserved.remove(partName);
    }
    _writtenAt[fileName] = now;
    if (expiresAt != null) onExpiryWritten?.call(expiresAt);
    // The entry this one replaced is removed like any other.
    if (previous != null && previous.fileName != fileName) {
      await _deleteFile(previous.fileName);
      _removed(previous);
    }
    return path;
  }

  /// Writes [sealedBytes] as a part file, flushes it, renames it and indexes
  /// it, as [commit] does. Ids are checked before any file is created.
  Future<String> write({
    required String conversationId,
    required String attachmentId,
    required String digest,
    required List<int> sealedBytes,
    DateTime? expiresAt,
  }) async {
    _checkedIds(conversationId, attachmentId);
    final partPath = await reservePartPath();
    final part = File(partPath);
    try {
      await part.writeAsBytes(sealedBytes, flush: true);
      return await commit(
        partPath: partPath,
        conversationId: conversationId,
        attachmentId: attachmentId,
        digest: digest,
        sizeBytes: sealedBytes.length,
        expiresAt: expiresAt,
      );
    } catch (_) {
      _reserved.remove(p.basename(partPath));
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  /// The path of the blob indexed for the three, or null when there is
  /// none (an entry whose file is gone is dropped). Notes the use, which
  /// [flushRecency] writes.
  Future<String?> pathOf(String conversationId, String attachmentId, String digest) async {
    final ids = _idsOrNull(conversationId, attachmentId);
    if (ids == null) return null;
    final entry = await _index.find(ids.$1, ids.$2, digest);
    if (entry == null) return null;
    // A row only this store writes; one naming anything but a blob is
    // dropped rather than joined onto the folder.
    final path = _blobName.hasMatch(entry.fileName) ? p.join((await _paths.mediaDir()).path, entry.fileName) : null;
    if (path == null || !await File(path).exists()) {
      await _index.remove(entry.fileName);
      _removed(entry);
      return null;
    }
    _usedAt[entry.fileName] = _now();
    return path;
  }

  /// Writes each noted use to the index, at most once a minute per entry.
  Future<void> flushRecency() async {
    final now = _now();
    for (final MapEntry(key: fileName, value: usedAt) in Map.of(_usedAt).entries) {
      final written = _writtenAt[fileName];
      if (written != null && now.difference(written) < recencyInterval) continue;
      await _index.touch(fileName, usedAt);
      _writtenAt[fileName] = usedAt;
      if (_usedAt[fileName] == usedAt) _usedAt.remove(fileName);
    }
  }

  /// Sets the expiry of every blob of [attachmentId] in [conversationId].
  Future<void> setExpiry(String conversationId, String attachmentId, DateTime? expiresAt) async {
    final (conversation, attachment) = _checkedIds(conversationId, attachmentId);
    await _index.setExpiry(conversation, attachment, expiresAt);
    if (expiresAt != null) onExpiryWritten?.call(expiresAt);
  }

  /// Deletes every blob of [attachmentId] in [conversationId], whatever
  /// its digest.
  Future<void> delete(String conversationId, String attachmentId) async {
    final ids = _idsOrNull(conversationId, attachmentId);
    if (ids == null) return;
    for (final entry in await _index.all()) {
      if (entry.conversationId == ids.$1 && entry.attachmentId == ids.$2) await deleteEntry(entry);
    }
  }

  Future<List<MediaIndexEntry>> entries() => _index.all();

  /// Deletes [entry]'s file and its row.
  Future<void> deleteEntry(MediaIndexEntry entry) async {
    await _deleteFile(entry.fileName);
    await _index.remove(entry.fileName);
    _removed(entry);
  }

  /// Deletes every file of the folder without a row (a part file reserved
  /// in this process and not committed yet aside), and every row without
  /// a file.
  ///
  /// Safe against a [commit] or [write] running meanwhile, whoever makes
  /// it: a blob is renamed into place before its row is written, and its
  /// part stays reserved until then. So the folder is listed before the
  /// rows are read (a blob listed without a row is one whose commit has not
  /// written it yet, kept by its reserved part), and a row counts as
  /// without a file only when its file is not there after the row was read.
  Future<void> removeOrphans() async {
    final folder = await _paths.mediaDir();
    final listed = await folder.list(followLinks: false).toList();
    final rows = {for (final entry in await _index.all()) entry.fileName: entry};
    for (final entity in listed) {
      final name = p.basename(entity.path);
      final committing = _reserved.contains('$name.part');
      final kept = entity is File &&
          ((_blobName.hasMatch(name) && (rows.containsKey(name) || committing)) || _reserved.contains(name));
      if (!kept) await _deleteEntity(entity);
    }
    for (final MapEntry(key: fileName, value: entry) in rows.entries) {
      if (!_blobName.hasMatch(fileName) || !await File(p.join(folder.path, fileName)).exists()) {
        await _index.remove(fileName);
        _removed(entry);
      }
    }
  }

  /// Empties the index and the folder.
  Future<void> clear() async {
    await _index.clear();
    final folder = await _paths.mediaDir();
    await for (final entity in folder.list(followLinks: false)) {
      await _deleteEntity(entity);
    }
    _reserved.clear();
    _usedAt.clear();
    _writtenAt.clear();
  }

  (String, String) _checkedIds(String conversationId, String attachmentId) =>
      _idsOrNull(conversationId, attachmentId) ??
      (throw ArgumentError('A blob is kept only under a relay conversation id and a UUID attachment id.'));

  (String, String)? _idsOrNull(String conversationId, String attachmentId) {
    if (!_conversationIdPattern.hasMatch(conversationId) || !isUuidString(attachmentId)) return null;
    return (conversationId.toLowerCase(), attachmentId.toLowerCase());
  }

  Future<void> _deleteFile(String fileName) async {
    _forget(fileName);
    if (!_blobName.hasMatch(fileName)) return;
    await _deleteEntity(File(p.join((await _paths.mediaDir()).path, fileName)));
  }

  Future<void> _deleteEntity(FileSystemEntity entity) async {
    try {
      await entity.delete(recursive: true);
    } on PathNotFoundException {
      // Gone already.
    }
  }

  void _forget(String fileName) {
    _usedAt.remove(fileName);
    _writtenAt.remove(fileName);
  }

  void _removed(MediaIndexEntry entry) {
    _forget(entry.fileName);
    onEntryRemoved?.call(entry);
  }

  String _randomName() {
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
