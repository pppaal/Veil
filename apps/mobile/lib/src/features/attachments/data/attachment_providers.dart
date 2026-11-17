import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'attachment_storage_paths.dart';
import 'attachment_temp_file_store.dart';

final attachmentTempFileStoreProvider = Provider<AttachmentTempFileStore>((ref) {
  return DefaultAttachmentTempFileStore(paths: ref.read(attachmentStoragePathsProvider));
});
