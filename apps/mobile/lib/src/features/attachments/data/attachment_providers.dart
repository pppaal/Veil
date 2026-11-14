import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import 'attachment_temp_file_store.dart';

final attachmentTempFileStoreProvider =
    Provider<AttachmentTempFileStore>((ref) {
  return DefaultAttachmentTempFileStore(
    onDirectoryPrepared: (path) =>
        ref.read(platformSecurityServiceProvider).excludePathFromBackup(path),
  );
});
