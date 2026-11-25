import 'package:drift/drift.dart';

import 'app_database.dart';

/// One sealed blob in the media folder and the message it belongs to. Ids
/// are lower-cased; [digest] is the attachment pointer's `d`
/// (AttachmentReference.sha256). [sizeBytes] is the blob's size on disk.
class MediaIndexEntry {
  const MediaIndexEntry({
    required this.fileName,
    required this.conversationId,
    required this.attachmentId,
    required this.digest,
    required this.sizeBytes,
    required this.lastUsedAt,
    this.expiresAt,
  });

  static const Object _unset = Object();

  final String fileName;
  final String conversationId;
  final String attachmentId;
  final String digest;
  final int sizeBytes;

  /// When the blob goes with its message; null while it has no expiry (a
  /// message without a timer, or an upload not sealed into its frame yet).
  final DateTime? expiresAt;

  /// When the blob was last read on this phone, at most a minute stale.
  final DateTime lastUsedAt;

  MediaIndexEntry copyWith({Object? expiresAt = _unset, DateTime? lastUsedAt}) => MediaIndexEntry(
        fileName: fileName,
        conversationId: conversationId,
        attachmentId: attachmentId,
        digest: digest,
        sizeBytes: sizeBytes,
        expiresAt: identical(expiresAt, _unset) ? this.expiresAt : expiresAt as DateTime?,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is MediaIndexEntry &&
      other.fileName == fileName &&
      other.conversationId == conversationId &&
      other.attachmentId == attachmentId &&
      other.digest == digest &&
      other.sizeBytes == sizeBytes &&
      other.expiresAt == expiresAt &&
      other.lastUsedAt == lastUsedAt;

  @override
  int get hashCode => Object.hash(fileName, conversationId, attachmentId, digest, sizeBytes, expiresAt, lastUsedAt);

  @override
  String toString() => 'MediaIndexEntry($fileName, $conversationId, $attachmentId, $sizeBytes B, '
      'expires $expiresAt, used $lastUsedAt)';
}

/// Which blob in the media folder belongs to which message. The files carry
/// random names, so this is the only place that ties one to a conversation;
/// on the phone it lives inside the encrypted database ([DriftMediaIndex]).
/// Ids passed in are lower-cased here as well.
abstract interface class MediaIndex {
  Future<MediaIndexEntry?> find(String conversationId, String attachmentId, String digest);

  Future<List<MediaIndexEntry>> all();

  /// Adds [entry], replacing the one under its file name and the one for
  /// its conversation, attachment and digest.
  Future<void> put(MediaIndexEntry entry);

  /// Sets the expiry of every entry of [attachmentId] in [conversationId].
  Future<void> setExpiry(String conversationId, String attachmentId, DateTime? expiresAt);

  Future<void> touch(String fileName, DateTime at);

  Future<void> remove(String fileName);

  Future<void> clear();
}

/// The media index as rows of the encrypted database's media_blobs table.
class DriftMediaIndex implements MediaIndex {
  DriftMediaIndex(this._db);

  final AppDatabase _db;

  @override
  Future<MediaIndexEntry?> find(String conversationId, String attachmentId, String digest) async {
    final row = await (_db.select(_db.mediaBlobs)
          ..where((table) =>
              table.conversationId.equals(conversationId.toLowerCase()) &
              table.attachmentId.equals(attachmentId.toLowerCase()) &
              table.digest.equals(digest)))
        .getSingleOrNull();
    return row == null ? null : _entry(row);
  }

  @override
  Future<List<MediaIndexEntry>> all() async => [for (final row in await _db.select(_db.mediaBlobs).get()) _entry(row)];

  @override
  Future<void> put(MediaIndexEntry entry) async {
    final conversationId = entry.conversationId.toLowerCase();
    final attachmentId = entry.attachmentId.toLowerCase();
    await _db.transaction(() async {
      await (_db.delete(_db.mediaBlobs)
            ..where((table) =>
                table.conversationId.equals(conversationId) &
                table.attachmentId.equals(attachmentId) &
                table.digest.equals(entry.digest)))
          .go();
      await _db.into(_db.mediaBlobs).insertOnConflictUpdate(MediaBlobsCompanion.insert(
            fileName: entry.fileName,
            conversationId: conversationId,
            attachmentId: attachmentId,
            digest: entry.digest,
            sizeBytes: entry.sizeBytes,
            expiresAt: Value(entry.expiresAt?.millisecondsSinceEpoch),
            lastUsedAt: entry.lastUsedAt.millisecondsSinceEpoch,
          ));
    });
  }

  @override
  Future<void> setExpiry(String conversationId, String attachmentId, DateTime? expiresAt) async {
    await (_db.update(_db.mediaBlobs)
          ..where((table) =>
              table.conversationId.equals(conversationId.toLowerCase()) &
              table.attachmentId.equals(attachmentId.toLowerCase())))
        .write(MediaBlobsCompanion(expiresAt: Value(expiresAt?.millisecondsSinceEpoch)));
  }

  @override
  Future<void> touch(String fileName, DateTime at) async {
    await (_db.update(_db.mediaBlobs)..where((table) => table.fileName.equals(fileName)))
        .write(MediaBlobsCompanion(lastUsedAt: Value(at.millisecondsSinceEpoch)));
  }

  @override
  Future<void> remove(String fileName) async {
    await (_db.delete(_db.mediaBlobs)..where((table) => table.fileName.equals(fileName))).go();
  }

  @override
  Future<void> clear() async {
    await _db.delete(_db.mediaBlobs).go();
  }

  MediaIndexEntry _entry(MediaBlobRow row) => MediaIndexEntry(
        fileName: row.fileName,
        conversationId: row.conversationId,
        attachmentId: row.attachmentId,
        digest: row.digest,
        sizeBytes: row.sizeBytes,
        expiresAt: row.expiresAt == null ? null : DateTime.fromMillisecondsSinceEpoch(row.expiresAt!),
        lastUsedAt: DateTime.fromMillisecondsSinceEpoch(row.lastUsedAt),
      );
}

/// The media index in memory, for tests and for a process whose database
/// cannot be opened (its blobs are then orphans at the next start).
class MemoryMediaIndex implements MediaIndex {
  final Map<String, MediaIndexEntry> _byFileName = {};

  @override
  Future<MediaIndexEntry?> find(String conversationId, String attachmentId, String digest) async {
    final conversation = conversationId.toLowerCase();
    final attachment = attachmentId.toLowerCase();
    for (final entry in _byFileName.values) {
      if (entry.conversationId == conversation && entry.attachmentId == attachment && entry.digest == digest) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<List<MediaIndexEntry>> all() async => List.of(_byFileName.values);

  @override
  Future<void> put(MediaIndexEntry entry) async {
    final stored = MediaIndexEntry(
      fileName: entry.fileName,
      conversationId: entry.conversationId.toLowerCase(),
      attachmentId: entry.attachmentId.toLowerCase(),
      digest: entry.digest,
      sizeBytes: entry.sizeBytes,
      expiresAt: entry.expiresAt,
      lastUsedAt: entry.lastUsedAt,
    );
    _byFileName.removeWhere((_, other) =>
        other.conversationId == stored.conversationId &&
        other.attachmentId == stored.attachmentId &&
        other.digest == stored.digest);
    _byFileName[stored.fileName] = stored;
  }

  @override
  Future<void> setExpiry(String conversationId, String attachmentId, DateTime? expiresAt) async {
    final conversation = conversationId.toLowerCase();
    final attachment = attachmentId.toLowerCase();
    _byFileName.updateAll((_, entry) => entry.conversationId == conversation && entry.attachmentId == attachment
        ? entry.copyWith(expiresAt: expiresAt)
        : entry);
  }

  @override
  Future<void> touch(String fileName, DateTime at) async {
    final entry = _byFileName[fileName];
    if (entry != null) _byFileName[fileName] = entry.copyWith(lastUsedAt: at);
  }

  @override
  Future<void> remove(String fileName) async => _byFileName.remove(fileName);

  @override
  Future<void> clear() async => _byFileName.clear();
}

/// The media index on the database the conversation cache opens, which
/// opens asynchronously and may not open at all (iOS before first unlock).
/// Each call uses a [DriftMediaIndex] on the database [database] resolves
/// to; while it cannot be opened, a [MemoryMediaIndex] stands in for the
/// process, as the cache's content store does (CacheHandle).
class DeferredMediaIndex implements MediaIndex {
  DeferredMediaIndex(this._database);

  final Future<AppDatabase> Function() _database;
  final MemoryMediaIndex _processOnly = MemoryMediaIndex();
  AppDatabase? _openedOn;
  DriftMediaIndex? _drift;

  Future<MediaIndex> _index() async {
    try {
      final database = await _database();
      if (!identical(database, _openedOn)) {
        _openedOn = database;
        _drift = DriftMediaIndex(database);
      }
      return _drift!;
    } catch (_) {
      return _processOnly;
    }
  }

  @override
  Future<MediaIndexEntry?> find(String conversationId, String attachmentId, String digest) async =>
      (await _index()).find(conversationId, attachmentId, digest);

  @override
  Future<List<MediaIndexEntry>> all() async => (await _index()).all();

  @override
  Future<void> put(MediaIndexEntry entry) async => (await _index()).put(entry);

  @override
  Future<void> setExpiry(String conversationId, String attachmentId, DateTime? expiresAt) async =>
      (await _index()).setExpiry(conversationId, attachmentId, expiresAt);

  @override
  Future<void> touch(String fileName, DateTime at) async => (await _index()).touch(fileName, at);

  @override
  Future<void> remove(String fileName) async => (await _index()).remove(fileName);

  @override
  Future<void> clear() async {
    await _processOnly.clear();
    await (await _index()).clear();
  }
}
