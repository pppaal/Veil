import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/core/storage/media_index.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_storage_paths.dart';
import 'package:veil_mobile/src/features/attachments/data/media_blob_store.dart';

// The sealed media folder: random names that hold no id, the index as the
// only map from a blob to its message, atomic writes, recency kept in the
// index and never in a file time.

const _photoId = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
const _fileId = '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d';

void main() {
  late Directory root;
  late AttachmentStoragePaths paths;
  late MemoryMediaIndex index;
  late DateTime now;
  late MediaBlobStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('veil-blob-store-test-');
    paths = AttachmentStoragePaths(
      temporaryRoot: () async => Directory(p.join(root.path, 'tmp'))..createSync(recursive: true),
      supportRoot: () async => Directory(p.join(root.path, 'support'))..createSync(recursive: true),
      systemTempRoot: () => Directory(p.join(root.path, 'system-tmp'))..createSync(recursive: true),
      sweepSystemTemp: false,
    );
    index = MemoryMediaIndex();
    now = DateTime.utc(2026, 4, 7, 9);
    store = MediaBlobStore(paths: paths, index: index, now: () => now);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<Directory> media() => paths.mediaDir();

  Future<List<String>> folderListing() async => [for (final entity in (await media()).listSync()) p.basename(entity.path)];

  test('names are 64 lower-case hex, hold no id, and the folder holds nothing else', () async {
    final first = await store.write(
        conversationId: 'conv-sam', attachmentId: _photoId, digest: 'digest-a', sealedBytes: List.filled(40, 1));
    final second = await store.write(
        conversationId: 'conv-omar', attachmentId: _fileId, digest: 'digest-b', sealedBytes: List.filled(80, 2));
    final listing = await folderListing();
    expect(listing, unorderedEquals([p.basename(first), p.basename(second)]));
    for (final name in listing) {
      expect(name, matches(RegExp(r'^[0-9a-f]{64}$')));
      for (final id in [_photoId, _fileId, 'conv-sam', 'conv-omar', _photoId.replaceAll('-', '')]) {
        expect(name, isNot(contains(id)));
      }
    }
    expect(File(first).readAsBytesSync(), List.filled(40, 1));
    final entries = await store.entries();
    expect(entries.map((entry) => entry.sizeBytes), unorderedEquals([40, 80]));
    expect(entries.map((entry) => entry.lastUsedAt).toSet(), {now});
  });

  test('ids are lower-cased: an upper-case id finds the same entry', () async {
    final path = await store.write(
        conversationId: 'Conv-Sam', attachmentId: _photoId.toUpperCase(), digest: 'd', sealedBytes: const [1, 2, 3]);
    final entry = (await store.entries()).single;
    expect(entry.conversationId, 'conv-sam');
    expect(entry.attachmentId, _photoId);
    expect(await store.pathOf('conv-sam', _photoId, 'd'), path);
    expect(await store.pathOf('CONV-SAM', _photoId.toUpperCase(), 'd'), path);
    // The digest is the pointer's, compared as it is.
    expect(await store.pathOf('conv-sam', _photoId, 'D'), isNull);
  });

  test('invalid ids throw before any file is created', () async {
    for (final (conversationId, attachmentId) in [
      ('conv-sam', '../keys/x'),
      ('conv-sam', 'not-a-uuid'),
      ('../../etc', _photoId),
      ('conv sam', _photoId),
      ('', _photoId),
      ('c' * 129, _photoId),
    ]) {
      await expectLater(
        store.write(conversationId: conversationId, attachmentId: attachmentId, digest: 'd', sealedBytes: const [1]),
        throwsArgumentError,
        reason: '$conversationId $attachmentId',
      );
      expect(Directory(p.join(root.path, 'support', 'veil_media')).existsSync(), isFalse);
    }
    expect(await store.pathOf('conv-sam', '../keys/x', 'd'), isNull);
    await expectLater(store.setExpiry('conv-sam', 'nope', null), throwsArgumentError);
  });

  test('a commit takes only a part file this store reserved', () async {
    final outside = File(p.join(root.path, 'elsewhere.part'))..writeAsBytesSync(const [1]);
    await expectLater(
      store.commit(partPath: outside.path, conversationId: 'conv-sam', attachmentId: _photoId, digest: 'd', sizeBytes: 1),
      throwsArgumentError,
    );
    final part = await store.reservePartPath();
    expect(p.basename(part), matches(RegExp(r'^[0-9a-f]{64}\.part$')));
    File(part).writeAsBytesSync(const [9, 9]);
    final path = await store.commit(partPath: part, conversationId: 'conv-sam', attachmentId: _photoId, digest: 'd', sizeBytes: 2);
    expect(p.basename(path), p.basenameWithoutExtension(part));
    expect(File(part).existsSync(), isFalse);
    expect(await store.pathOf('conv-sam', _photoId, 'd'), path);
  });

  test('a write is atomic: a part left behind is removed by removeOrphans', () async {
    final kept = await store.write(conversationId: 'conv-sam', attachmentId: _photoId, digest: 'd', sealedBytes: const [1]);
    // What a crash in the middle of a write leaves: a part file, never a
    // half-written blob under an indexed name.
    final leftBehind = File(p.join((await media()).path, '${'e' * 64}.part'))..writeAsBytesSync(const [1, 2]);
    // A part this process reserved and is still writing stays.
    final inFlight = File(await store.reservePartPath())..writeAsBytesSync(const [3]);

    await store.removeOrphans();

    expect(leftBehind.existsSync(), isFalse);
    expect(inFlight.existsSync(), isTrue);
    expect(File(kept).existsSync(), isTrue);
  });

  test('removeOrphans removes files without rows and rows without files', () async {
    final kept = await store.write(conversationId: 'conv-sam', attachmentId: _photoId, digest: 'd', sealedBytes: const [1]);
    final lost = await store.write(conversationId: 'conv-sam', attachmentId: _fileId, digest: 'd', sealedBytes: const [2]);
    File(lost).deleteSync();
    final unindexed = File(p.join((await media()).path, 'f' * 64))..writeAsBytesSync(const [3]);
    final stranger = File(p.join((await media()).path, 'notes.txt'))..writeAsStringSync('x');

    await store.removeOrphans();

    expect(await folderListing(), [p.basename(kept)]);
    expect(unindexed.existsSync(), isFalse);
    expect(stranger.existsSync(), isFalse);
    expect((await store.entries()).map((entry) => entry.attachmentId), [_photoId]);
  });

  test('recency lives in the index; file times are never read', () async {
    final older = await store.write(conversationId: 'conv-sam', attachmentId: _photoId, digest: 'd', sealedBytes: const [1]);
    now = now.add(const Duration(minutes: 5));
    final newer = await store.write(conversationId: 'conv-sam', attachmentId: _fileId, digest: 'd', sealedBytes: const [2]);
    // The file times say the opposite of what happened.
    File(older).setLastModifiedSync(DateTime.utc(2001));
    File(newer).setLastModifiedSync(DateTime.utc(2000));
    File(newer).setLastAccessedSync(DateTime.utc(2000));

    // The older one is viewed now; recency is written at most once a minute.
    now = now.add(const Duration(minutes: 10));
    expect(await store.pathOf('conv-sam', _photoId, 'd'), older);
    await store.flushRecency();
    List<String> byRecency(List<MediaIndexEntry> entries) =>
        [for (final entry in entries..sort((a, b) => a.lastUsedAt.compareTo(b.lastUsedAt))) entry.attachmentId];
    expect(byRecency(await store.entries()), [_fileId, _photoId]);

    // Viewed again within the minute: nothing is written.
    final written = (await index.find('conv-sam', _photoId, 'd'))!.lastUsedAt;
    now = now.add(const Duration(seconds: 20));
    await store.pathOf('conv-sam', _photoId, 'd');
    await store.flushRecency();
    expect((await index.find('conv-sam', _photoId, 'd'))!.lastUsedAt, written);
    // A minute after the last write, the use that waited is written.
    now = now.add(const Duration(minutes: 1));
    await store.flushRecency();
    expect((await index.find('conv-sam', _photoId, 'd'))!.lastUsedAt, written.add(const Duration(seconds: 20)));
  });

  test('a blob whose file is gone reads as missing and its row goes', () async {
    final path = await store.write(conversationId: 'conv-sam', attachmentId: _photoId, digest: 'd', sealedBytes: const [1]);
    File(path).deleteSync();
    expect(await store.pathOf('conv-sam', _photoId, 'd'), isNull);
    expect(await store.entries(), isEmpty);
  });

  test('a second blob for the same id and digest replaces the first', () async {
    final first = await store.write(conversationId: 'conv-sam', attachmentId: _photoId, digest: 'd', sealedBytes: const [1]);
    final second = await store.write(conversationId: 'conv-sam', attachmentId: _photoId, digest: 'd', sealedBytes: const [2]);
    expect(File(first).existsSync(), isFalse);
    expect(await folderListing(), [p.basename(second)]);
    expect(await store.entries(), hasLength(1));
  });

  test('the entry a commit replaces is told as removed, like every other removal', () async {
    final removed = <String>[];
    store.onEntryRemoved = (entry) => removed.add(entry.fileName);
    final first = await store.write(conversationId: 'conv-sam', attachmentId: _photoId, digest: 'd', sealedBytes: const [1]);
    expect(removed, isEmpty);
    await store.write(conversationId: 'conv-sam', attachmentId: _photoId, digest: 'd', sealedBytes: const [2]);
    expect(removed, [p.basename(first)], reason: 'the replaced entry went without a word');
  });

  test('every expiry written is told: a commit with one, and one set later', () async {
    final written = <DateTime>[];
    store.onExpiryWritten = written.add;
    final commitExpiry = DateTime.utc(2026, 4, 7, 10);
    final stampExpiry = DateTime.utc(2026, 4, 7, 11);
    await store.write(conversationId: 'conv-sam', attachmentId: _photoId, digest: 'd', sealedBytes: const [1]);
    await store.write(
        conversationId: 'conv-sam', attachmentId: _fileId, digest: 'd', sealedBytes: const [2], expiresAt: commitExpiry);
    await store.setExpiry('conv-sam', _photoId, stampExpiry);
    await store.setExpiry('conv-sam', _photoId, null);
    expect(written, [commitExpiry, stampExpiry]);
  });

  test('expiry is set per id, delete takes every digest of an id, deleteEntry one entry', () async {
    await store.write(conversationId: 'conv-sam', attachmentId: _photoId, digest: 'one', sealedBytes: const [1]);
    await store.write(conversationId: 'conv-sam', attachmentId: _photoId, digest: 'two', sealedBytes: const [2]);
    final other = await store.write(conversationId: 'conv-sam', attachmentId: _fileId, digest: 'one', sealedBytes: const [3]);
    final expiry = DateTime.utc(2026, 4, 8);
    await store.setExpiry('conv-sam', _photoId.toUpperCase(), expiry);
    expect({for (final entry in await store.entries()) entry.digest + entry.attachmentId: entry.expiresAt}, {
      'one$_photoId': expiry,
      'two$_photoId': expiry,
      'one$_fileId': null,
    });

    await store.delete('conv-sam', _photoId);
    expect(await folderListing(), [p.basename(other)]);
    expect((await store.entries()).single.attachmentId, _fileId);

    await store.deleteEntry((await store.entries()).single);
    expect(await folderListing(), isEmpty);
    expect(await store.entries(), isEmpty);
  });

  test('a row whose file name is not a blob name never reaches outside the folder', () async {
    final outside = File(p.join(root.path, 'outside.txt'))..writeAsStringSync('keep');
    final folder = await media();
    // The media folder is <root>/support/<...>; walk back up to the root.
    final escape = p.relative(outside.path, from: folder.path);
    expect(escape, startsWith('..'));
    final hostile = MediaIndexEntry(
      fileName: escape,
      conversationId: 'conv-sam',
      attachmentId: _photoId,
      digest: 'd',
      sizeBytes: 4,
      lastUsedAt: now,
    );
    await index.put(hostile);
    expect(await store.pathOf('conv-sam', _photoId, 'd'), isNull);
    expect(await index.all(), isEmpty, reason: 'the row goes');
    expect(outside.readAsStringSync(), 'keep');

    await index.put(hostile);
    await store.deleteEntry(hostile);
    expect(outside.existsSync(), isTrue, reason: 'deleteEntry took a file outside the folder');
    expect(await index.all(), isEmpty);
  });

  test('every entry removed is told, however it went (D36): delete, deleteEntry, a file found gone, an orphan row',
      () async {
    const thirdId = '6ba7b810-9dad-41d1-80b4-00c04fd430c8';
    const fourthId = '6ba7b811-9dad-41d1-80b4-00c04fd430c8';
    final removed = <String>[];
    store.onEntryRemoved = (entry) => removed.add(entry.attachmentId);
    Future<String> put(String id) =>
        store.write(conversationId: 'conv-sam', attachmentId: id, digest: 'd', sealedBytes: const [1, 2]);
    await put(_photoId);
    await put(_fileId);
    final third = await put(thirdId);
    final fourth = await put(fourthId);

    await store.delete('conv-sam', _photoId);
    await store.deleteEntry((await store.entries()).firstWhere((entry) => entry.attachmentId == _fileId));
    File(third).deleteSync();
    expect(await store.pathOf('conv-sam', thirdId, 'd'), isNull);
    File(fourth).deleteSync();
    await store.removeOrphans();
    expect(removed, [_photoId, _fileId, thirdId, fourthId]);
    expect(await index.all(), isEmpty);
  });

  test('clear empties the index and the folder', () async {
    await store.write(conversationId: 'conv-sam', attachmentId: _photoId, digest: 'd', sealedBytes: const [1]);
    File(p.join((await media()).path, '${'a' * 64}.part')).writeAsBytesSync(const [1]);
    await store.clear();
    expect(await folderListing(), isEmpty);
    expect(await index.all(), isEmpty);
  });

  // A start sweep runs while a photo or file is sealed (the sealer commits
  // outside the media service's serial lock): neither order of the two may
  // lose the blob or its row.
  group('removeOrphans while a blob is committed', () {
    late _GatedMediaIndex gated;

    setUp(() {
      gated = _GatedMediaIndex(index);
      store = MediaBlobStore(paths: paths, index: gated, now: () => now);
    });

    Future<String> commitOne() async {
      final part = await store.reservePartPath();
      File(part).writeAsBytesSync(const [7, 7, 7]);
      return store.commit(partPath: part, conversationId: 'conv-sam', attachmentId: _photoId, digest: 'd', sizeBytes: 3);
    }

    test('the sweep lists the folder after the rename and before the row is written', () async {
      final putGate = gated.holdNextPut();
      final committing = commitOne();
      await gated.putReached;
      // The blob is in place under its name, its row not written yet.
      expect(await folderListing(), hasLength(1));
      expect(await index.all(), isEmpty);

      await store.removeOrphans();
      putGate.complete();
      final path = await committing;

      expect(File(path).existsSync(), isTrue, reason: 'the sweep took a blob being committed');
      expect(await store.pathOf('conv-sam', _photoId, 'd'), path);
      expect(await folderListing(), [p.basename(path)]);
    });

    test('the sweep reads the rows while a whole commit runs', () async {
      final allGate = gated.holdNextAll();
      final sweeping = store.removeOrphans();
      await gated.allReached;
      final path = await commitOne();
      allGate.complete();
      await sweeping;

      expect(File(path).existsSync(), isTrue, reason: 'the sweep took a blob committed while it read the rows');
      expect(await store.pathOf('conv-sam', _photoId, 'd'), path);
    });

    test('a part left by a commit that failed is not kept for ever', () async {
      gated.failNextPut = true;
      await expectLater(commitOne(), throwsStateError);
      // Its blob was renamed but never indexed: an orphan the next sweep takes.
      await store.removeOrphans();
      expect(await folderListing(), isEmpty);
      expect(await index.all(), isEmpty);
    });
  });
}

/// A media index whose next `put` or `all` waits until the test lets it go,
/// or whose next `put` fails.
class _GatedMediaIndex implements MediaIndex {
  _GatedMediaIndex(this._inner);

  final MediaIndex _inner;
  Completer<void>? _putGate;
  Completer<void>? _allGate;
  final Completer<void> _putReached = Completer<void>();
  final Completer<void> _allReached = Completer<void>();
  bool failNextPut = false;

  Future<void> get putReached => _putReached.future;
  Future<void> get allReached => _allReached.future;

  Completer<void> holdNextPut() => _putGate = Completer<void>();
  Completer<void> holdNextAll() => _allGate = Completer<void>();

  @override
  Future<void> put(MediaIndexEntry entry) async {
    if (failNextPut) {
      failNextPut = false;
      throw StateError('the database refused the row');
    }
    final gate = _putGate;
    _putGate = null;
    if (gate != null) {
      _putReached.complete();
      await gate.future;
    }
    await _inner.put(entry);
  }

  @override
  Future<List<MediaIndexEntry>> all() async {
    final gate = _allGate;
    _allGate = null;
    final rows = await _inner.all();
    if (gate != null) {
      _allReached.complete();
      await gate.future;
    }
    return rows;
  }

  @override
  Future<MediaIndexEntry?> find(String conversationId, String attachmentId, String digest) =>
      _inner.find(conversationId, attachmentId, digest);

  @override
  Future<void> setExpiry(String conversationId, String attachmentId, DateTime? expiresAt) =>
      _inner.setExpiry(conversationId, attachmentId, expiresAt);

  @override
  Future<void> touch(String fileName, DateTime at) => _inner.touch(fileName, at);

  @override
  Future<void> remove(String fileName) => _inner.remove(fileName);

  @override
  Future<void> clear() => _inner.clear();
}
