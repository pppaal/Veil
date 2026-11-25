import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/system_sheet_grace.dart';
import '../../../core/platform/file_open_channel.dart';
import 'attachment_providers.dart';
import 'attachment_storage_paths.dart';

/// How opening a decrypted file in another app (or Quick Look) ended.
/// [closed] also when the app locked before the file was handed over.
enum OpenOutcome { opened, closed, noApp, failed }

/// How handing a decrypted file to the system save screen ended.
enum SaveOutcome { saved, canceled, failed }

/// Hands a decrypted copy under veil_open to the phone: to the app the user
/// opens it with, or to the system save screen. The only way a decrypted
/// file leaves the app.
abstract interface class AttachmentOpener {
  /// Opens [path] with what the phone has for [mimeType].
  Future<OpenOutcome> open(String path, {required String mimeType});

  /// Shows the system save screen for [path], suggesting [fileName].
  Future<SaveOutcome> save(String path, {required String fileName});
}

/// The app's own `veil/file_open` channel and flutter_file_dialog's save
/// screen, each inside the system-sheet grace where the lock allows one
/// (D40): the save screen always; Quick Look on iOS, which is presented
/// over the app; never opening a file on Android, which is another app's
/// task, so Veil locks as soon as it is hidden. A sheet the lock closes
/// counts as closed or cancelled, and a lock before a file is handed to
/// the platform hands nothing over (closed). After every save the iOS temporary
/// folder, where the save sheet keeps its copy under the file's name, is
/// emptied (D39).
class PluginAttachmentOpener implements AttachmentOpener {
  PluginAttachmentOpener({
    required FileOpenChannel channel,
    required SystemSheetGrace grace,
    required AttachmentStoragePaths paths,
    Future<String?> Function(String path, String fileName)? saveFile,
  })  : _channel = channel,
        _grace = grace,
        _paths = paths,
        _saveFile = saveFile ?? _pluginSaveFile;

  final FileOpenChannel _channel;
  final SystemSheetGrace _grace;
  final AttachmentStoragePaths _paths;
  final Future<String?> Function(String path, String fileName) _saveFile;

  static Future<String?> _pluginSaveFile(String path, String fileName) =>
      FlutterFileDialog.saveFile(params: SaveFileDialogParams(sourceFilePath: path, fileName: fileName));

  @override
  Future<OpenOutcome> open(String path, {required String mimeType}) async {
    // Read now, right after the caller's own lock check: the channel asks
    // again right before the platform call, past its own awaits.
    final locks = _grace.locks;
    Future<OpenOutcome> show() async =>
        switch (await _channel.open(path, mimeType: mimeType, mayHandOver: () => _grace.locks == locks)) {
          FileOpenResult.opened => OpenOutcome.opened,
          FileOpenResult.closed || FileOpenResult.lockedFirst => OpenOutcome.closed,
          FileOpenResult.noApp => OpenOutcome.noApp,
          FileOpenResult.failed => OpenOutcome.failed,
        };
    if (!_grace.isIOS) return show();
    try {
      return await _grace.run(SystemSheet.quickLook, show);
    } on SheetClosedByLock {
      return OpenOutcome.closed;
    }
  }

  @override
  Future<SaveOutcome> save(String path, {required String fileName}) async {
    try {
      // A save the lock cut short may still answer later; it names where
      // the user saved, which is theirs, so nothing is done with it.
      final saved = await _grace.run(SystemSheet.saveScreen, () => _saveFile(path, fileName));
      return saved == null ? SaveOutcome.canceled : SaveOutcome.saved;
    } on SheetClosedByLock {
      return SaveOutcome.canceled;
    } on PlatformException {
      return SaveOutcome.failed;
    } on MissingPluginException {
      return SaveOutcome.failed;
    } finally {
      await _paths.purgeSystemTemp().catchError((Object _) {});
    }
  }
}

/// Whether this platform can hand a file over, the one place that decides
/// it: pick one with the system's file picker, open a decrypted one in
/// another app (or Quick Look), and save one through the system save
/// screen. flutter_file_dialog and the app's veil/file_open channel exist
/// only on Android and iOS; elsewhere (the desktop alpha) the attach sheet
/// offers no File row, nothing offers Save, and only a photo opens, in the
/// viewer.
final fileHandOverAvailableProvider = Provider<bool>(
    (ref) => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

final attachmentOpenerProvider = Provider<AttachmentOpener>((ref) => PluginAttachmentOpener(
      channel: ref.read(fileOpenChannelProvider),
      grace: ref.read(systemSheetGraceProvider),
      paths: ref.read(attachmentStoragePathsProvider),
    ));
