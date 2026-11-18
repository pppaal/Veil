import 'dart:io';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;

/// What a system picker handed over: the copy the plugin wrote (into its
/// cache on Android, into the system temporary folder on iOS), its size,
/// and the name the picker gave it.
class PickedFile {
  const PickedFile({required this.path, required this.sizeBytes, this.name});

  final String path;
  final int sizeBytes;
  final String? name;
}

/// The system photo and file pickers (D1, D2). Neither needs a permission:
/// each shows only what the user picks.
abstract interface class AttachmentPicker {
  /// The system photo picker: Android's Photo Picker, iOS's PHPicker. Null
  /// when the user closed it.
  Future<PickedFile?> pickPhoto();

  /// The system document picker, any type. Null when the user closed it.
  Future<PickedFile?> pickFile();

  /// Android: photos picked while the activity was killed, which nobody
  /// will ask for now (retrieveLostData). Nothing elsewhere.
  Future<List<String>> recoverLostPicks();
}

/// The pickers through image_picker and flutter_file_dialog: the only file
/// that talks to them.
class PluginAttachmentPicker implements AttachmentPicker {
  PluginAttachmentPicker() {
    final platform = ImagePickerPlatform.instance;
    if (platform is ImagePickerAndroid) platform.useAndroidPhotoPicker = true;
  }

  final ImagePicker _images = ImagePicker();

  @override
  Future<PickedFile?> pickPhoto() async {
    // No resize options: the plugin's own resize keeps GPS EXIF. Without the
    // full metadata the plugin never asks the photo library for access.
    final picked = await _images.pickImage(source: ImageSource.gallery, requestFullMetadata: false);
    if (picked == null) return null;
    return PickedFile(path: picked.path, sizeBytes: await picked.length(), name: picked.name);
  }

  @override
  Future<PickedFile?> pickFile() async {
    // The plugin copies the pick on a background thread, so a large file
    // never freezes the app; the copy keeps the name the picker showed.
    final path = await FlutterFileDialog.pickFile(params: const OpenFileDialogParams(copyFileToCacheDir: true));
    if (path == null) return null;
    return PickedFile(path: path, sizeBytes: await File(path).length(), name: p.basename(path));
  }

  @override
  Future<List<String>> recoverLostPicks() async {
    if (!Platform.isAndroid) return const [];
    final lost = await _images.retrieveLostData();
    if (lost.isEmpty) return const [];
    return [
      for (final file in lost.files ?? [if (lost.file case final single?) single]) file.path,
    ];
  }
}

final attachmentPickerProvider = Provider<AttachmentPicker>((ref) => PluginAttachmentPicker());
