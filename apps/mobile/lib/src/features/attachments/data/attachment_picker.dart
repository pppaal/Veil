import 'dart:io';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// What a system picker handed over: the copy the plugin wrote (into its
/// cache on Android, into the system temporary folder on iOS; on Windows,
/// macOS and Linux the user's own file, never a copy), its size, and the
/// name the picker gave it.
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

/// Where the system pickers write the copies they hand over (D39), and so
/// the only places a picked file is ever deleted from: Android's cache
/// folder (image_picker's `<uuid>/`, flutter_file_dialog's
/// `file_dialog-<uuid>/`) and iOS's `NSTemporaryDirectory()`
/// (image_picker's `image_picker_*`, flutter_file_dialog's picked
/// `<original name>`). Windows, macOS and Linux have none: their pickers
/// hand over the user's own file, which must outlive the pick.
class PickerCopyRoots {
  PickerCopyRoots(Future<List<Directory>> Function() roots) : _roots = roots;

  /// Fixed folders, as the test pickers' caches are.
  PickerCopyRoots.at(List<Directory> roots) : _roots = (() async => roots);

  /// The roots of the platform this runs on; [android] and [ios] stand in
  /// for it in tests, [cacheDir] for Android's cache folder and
  /// [systemTemp] for iOS's `NSTemporaryDirectory()`.
  factory PickerCopyRoots.platform({
    bool? android,
    bool? ios,
    Future<Directory> Function() cacheDir = getTemporaryDirectory,
    Directory Function()? systemTemp,
  }) {
    if (android ?? Platform.isAndroid) return PickerCopyRoots(() async => [await cacheDir()]);
    if (ios ?? Platform.isIOS) return PickerCopyRoots(() async => [(systemTemp ?? () => Directory.systemTemp)()]);
    return PickerCopyRoots(() async => const []);
  }

  final Future<List<Directory>> Function() _roots;

  /// [path] with its links resolved when it lies strictly inside one of
  /// the roots (compared with the roots' links resolved too, as iOS's
  /// `/var` is `/private/var`); null when it lies anywhere else, is a root
  /// itself, or is not there.
  Future<String?> copyAt(String path) async {
    final roots = await _roots();
    if (roots.isEmpty) return null;
    final String resolved;
    try {
      resolved = await File(path).resolveSymbolicLinks();
    } on FileSystemException {
      return null;
    }
    for (final root in roots) {
      try {
        if (p.isWithin(await root.resolveSymbolicLinks(), resolved)) return resolved;
      } on FileSystemException {
        // A root that is not there holds nothing.
      }
    }
    return null;
  }
}

/// The pickers' copy folders on this platform; tests point it at theirs.
final pickerCopyRootsProvider = Provider<PickerCopyRoots>((ref) => PickerCopyRoots.platform());
