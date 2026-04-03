import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AttachmentTempBlob {
  const AttachmentTempBlob({
    required this.path,
    required this.filename,
    required this.sizeBytes,
    required this.sha256,
    required this.createdAt,
  });

  final String path;
  final String filename;
  final int sizeBytes;
  final String sha256;
  final DateTime createdAt;
}

abstract class AttachmentTempFileStore {
  Future<AttachmentTempBlob> createOpaqueBlob({
    required String filename,
    required int sizeBytes,
    String? existingPath,
  });

  Future<void> deleteTempFile(String? path);

  Future<void> cleanupOrphanedFiles({
    Iterable<String> keepPaths,
    Duration maxAge,
    int maxFileCount,
  });

  Future<void> purgeAll();
}

class DefaultAttachmentTempFileStore implements AttachmentTempFileStore {
  DefaultAttachmentTempFileStore({
    Directory Function()? rootDirectoryFactory,
    Future<void> Function(String path)? onDirectoryPrepared,
  })  : _rootDirectoryFactory = rootDirectoryFactory,
        _onDirectoryPrepared = onDirectoryPrepared;

  final Directory Function()? _rootDirectoryFactory;
  final Future<void> Function(String path)? _onDirectoryPrepared;
  final Random _random = Random.secure();

  static const defaultMaxAge = Duration(hours: 24);
  static const defaultMaxFileCount = 32;

  @override
  Future<AttachmentTempBlob> createOpaqueBlob({
    required String filename,
    required int sizeBytes,
    String? existingPath,
  }) async {
    if (existingPath != null && existingPath.isNotEmpty) {
      final existingFile = File(existingPath);
      if (await existingFile.exists()) {
        return AttachmentTempBlob(
          path: existingFile.path,
          filename: filename,
          sizeBytes: await existingFile.length(),
          sha256: await _digestFile(existingFile),
          createdAt: await existingFile.lastModified(),
        );
      }
    }

    final directory = await _resolveDirectory();
    final opaqueId = _randomToken(24);
    final file = File(
      p.join(
        directory.path,
        '${DateTime.now().microsecondsSinceEpoch}_$opaqueId.blob',
      ),
    );

    final sink = file.openWrite();
    var remaining = sizeBytes;
    while (remaining > 0) {
      final chunkSize = remaining > 8192 ? 8192 : remaining;
      final chunk = List<int>.generate(chunkSize, (_) => _random.nextInt(256));
      sink.add(chunk);
      remaining -= chunkSize;
    }
    await sink.close();

    return AttachmentTempBlob(
      path: file.path,
      filename: filename,
      sizeBytes: sizeBytes,
      sha256: await _digestFile(file),
      createdAt: await file.lastModified(),
    );
  }

  @override
  Future<void> deleteTempFile(String? path) async {
    if (path == null || path.isEmpty) {
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> cleanupOrphanedFiles({
    Iterable<String> keepPaths = const <String>[],
    Duration maxAge = defaultMaxAge,
    int maxFileCount = defaultMaxFileCount,
  }) async {
    final directory = await _resolveDirectory();
    if (!await directory.exists()) {
      return;
    }

    final keep = keepPaths.where((value) => value.isNotEmpty).toSet();
    final entities = await directory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    final now = DateTime.now();
    final candidates = <File>[];
    for (final file in entities) {
      if (keep.contains(file.path)) {
        continue;
      }
      final modifiedAt = await file.lastModified();
      if (now.difference(modifiedAt) > maxAge) {
        await file.delete();
        continue;
      }
      candidates.add(file);
    }

    if (candidates.length <= maxFileCount) {
      return;
    }

    candidates.sort((left, right) {
      final leftStamp = left.statSync().modified;
      final rightStamp = right.statSync().modified;
      return leftStamp.compareTo(rightStamp);
    });
    final overflow = candidates.length - maxFileCount;
    for (final file in candidates.take(overflow)) {
      await file.delete();
    }
  }

  @override
  Future<void> purgeAll() async {
    final directory = await _resolveDirectory();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<Directory> _resolveDirectory() async {
    final provided = _rootDirectoryFactory?.call();
    if (provided != null) {
      await provided.create(recursive: true);
      await _onDirectoryPrepared?.call(provided.path);
      return provided;
    }

    final base = await getTemporaryDirectory();
    final directory = Directory(p.join(base.path, 'veil_attachment_cache'));
    await directory.create(recursive: true);
    await _onDirectoryPrepared?.call(directory.path);
    return directory;
  }

  Future<String> _digestFile(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  String _randomToken(int length) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List<String>.generate(
      length,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }
}
