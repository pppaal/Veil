import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/network/veil_api_exception.dart';
import 'attachment_storage_paths.dart';

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
  /// The staged file at [existingPath], with its size and digest. A file
  /// that is not there fails with attachment_upload_invalid: nothing is
  /// ever made up in its place.
  Future<AttachmentTempBlob> createOpaqueBlob({
    required String filename,
    required int sizeBytes,
    String? existingPath,
  });

  Future<void> deleteTempFile(String? path);

  /// Deletes every staging entry not in [keepPaths], whatever its age and
  /// however few there are: nothing in staging is wanted after a restart
  /// (D39). [maxAge] and [maxFileCount] no longer change that.
  Future<void> cleanupOrphanedFiles({
    Iterable<String> keepPaths,
    Duration maxAge,
    int maxFileCount,
  });

  Future<void> purgeAll();
}

/// Staging in the staging folder of [AttachmentStoragePaths]; a purge
/// empties every attachment folder the paths know.
class DefaultAttachmentTempFileStore implements AttachmentTempFileStore {
  DefaultAttachmentTempFileStore({required AttachmentStoragePaths paths}) : _paths = paths;

  final AttachmentStoragePaths _paths;

  static const defaultMaxAge = Duration(hours: 24);
  static const defaultMaxFileCount = 32;

  @override
  Future<AttachmentTempBlob> createOpaqueBlob({
    required String filename,
    required int sizeBytes,
    String? existingPath,
  }) async {
    final file = existingPath == null || existingPath.isEmpty ? null : File(existingPath);
    if (file == null || !await file.exists()) {
      throw VeilApiException('The staged file is gone.', code: 'attachment_upload_invalid');
    }
    return AttachmentTempBlob(
      path: file.path,
      filename: filename,
      sizeBytes: await file.length(),
      sha256: (await sha256.bind(file.openRead()).first).toString(),
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
    final keep = {for (final path in keepPaths) if (path.isNotEmpty) p.normalize(path)};
    if (keep.isEmpty) return _paths.purgeStaging();
    final directory = await _paths.stagingDir();
    await for (final entity in directory.list(followLinks: false)) {
      if (keep.contains(p.normalize(entity.path))) continue;
      try {
        await entity.delete(recursive: true);
      } on PathNotFoundException {
        // Gone already.
      }
    }
  }

  @override
  Future<void> purgeAll() => _paths.purgeAll();
}
