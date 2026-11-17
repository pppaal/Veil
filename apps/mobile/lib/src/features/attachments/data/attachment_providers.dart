import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import 'attachment_storage_paths.dart';
import 'attachment_temp_file_store.dart';

/// The app's attachment folders on the phone's own storage. Each folder is
/// excluded from backup when it is created.
final attachmentStoragePathsProvider = Provider<AttachmentStoragePaths>((ref) {
  return AttachmentStoragePaths(
    onDirectoryPrepared: (path) => ref.read(platformSecurityServiceProvider).excludePathFromBackup(path),
  );
});

final attachmentTempFileStoreProvider = Provider<AttachmentTempFileStore>((ref) {
  return DefaultAttachmentTempFileStore(paths: ref.read(attachmentStoragePathsProvider));
});
