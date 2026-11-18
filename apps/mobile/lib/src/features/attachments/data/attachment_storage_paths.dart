import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where photos and files live on the phone, and how each place is emptied.
///
/// - Staging (`<tmp>/veil_attachment_cache`): a picked plaintext until it is
///   sealed or dropped (up to 10 minutes while a lock holds it for its
///   chat). Nothing there is wanted after a restart.
/// - Media (`<app support>/veil_media`): sealed blobs under random names,
///   flat; which one belongs to which message is only in the encrypted
///   database (MediaIndex). Excluded from backup.
/// - Open (`<tmp>/veil_open`): the only decrypted files, a copy while
///   another app opens it or the save screen keeps it.
/// - The system temporary folder (`NSTemporaryDirectory()` on iOS, which is
///   not `<tmp>`: that is Library/Caches there): where the iOS pickers and
///   save sheet leave copies under their real names. Swept on iOS only.
///
/// Every root can be injected, so tests run every purge for real against
/// folders of their own.
class AttachmentStoragePaths {
  AttachmentStoragePaths({
    Future<Directory> Function()? temporaryRoot,
    Future<Directory> Function()? supportRoot,
    Directory Function()? systemTempRoot,
    bool? sweepSystemTemp,
    Future<void> Function(String path)? onDirectoryPrepared,
  })  : _temporaryRoot = temporaryRoot ?? getTemporaryDirectory,
        _supportRoot = supportRoot ?? getApplicationSupportDirectory,
        _systemTempRoot = systemTempRoot ?? (() => Directory.systemTemp),
        sweepSystemTemp = sweepSystemTemp ?? Platform.isIOS,
        _onDirectoryPrepared = onDirectoryPrepared;

  static const stagingFolder = 'veil_attachment_cache';
  static const mediaFolder = 'veil_media';
  static const openFolder = 'veil_open';

  final Future<Directory> Function() _temporaryRoot;
  final Future<Directory> Function() _supportRoot;
  final Directory Function() _systemTempRoot;
  final Future<void> Function(String path)? _onDirectoryPrepared;

  /// Whether [purgeSystemTemp] empties the system temporary folder: on iOS,
  /// where the pickers write there; elsewhere it holds nothing of ours.
  final bool sweepSystemTemp;

  // Folders handed out since they were last created, so each is excluded
  // from backup once per creation rather than on every call.
  final Set<String> _prepared = {};

  /// The staging folder, created if missing.
  Future<Directory> stagingDir() => _folder(_temporaryRoot, stagingFolder);

  /// The sealed media folder, created if missing.
  Future<Directory> mediaDir() => _folder(_supportRoot, mediaFolder);

  /// The folder of decrypted Open and Save copies, created if missing.
  Future<Directory> openDir() => _folder(_temporaryRoot, openFolder);

  /// Deletes every entry in the staging folder.
  Future<void> purgeStaging() async {
    final staging = Directory(p.join((await _temporaryRoot()).path, stagingFolder));
    await _deleteEntriesOf(staging);
  }

  /// Deletes every entry of the system temporary folder when
  /// [sweepSystemTemp]; does nothing otherwise.
  Future<void> purgeSystemTemp() async {
    if (!sweepSystemTemp) return;
    await _deleteEntriesOf(_systemTempRoot());
  }

  /// Deletes the staging, media and open folders, everything else under
  /// the temporary folder, and runs [purgeSystemTemp]: what a wipe or a
  /// sign-out leaves of attachments is nothing. Every step runs even when
  /// one fails; the first failure is rethrown at the end.
  Future<void> purgeAll() async {
    Object? failure;
    StackTrace? failureTrace;
    Future<void> step(Future<void> Function() run) async {
      try {
        await run();
      } catch (error, trace) {
        failure ??= error;
        failureTrace ??= trace;
      }
    }

    await step(() async => _delete(Directory(p.join((await _supportRoot()).path, mediaFolder))));
    await step(() async => _deleteEntriesOf(await _temporaryRoot()));
    await step(purgeSystemTemp);
    _prepared.clear();
    if (failure case final error?) Error.throwWithStackTrace(error, failureTrace!);
  }

  Future<Directory> _folder(Future<Directory> Function() root, String name) async {
    final directory = Directory(p.join((await root()).path, name));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      _prepared.remove(directory.path);
    }
    if (_prepared.add(directory.path)) {
      try {
        await _onDirectoryPrepared?.call(directory.path);
      } catch (_) {
        // Retried the next time the folder is handed out.
        _prepared.remove(directory.path);
        rethrow;
      }
    }
    return directory;
  }

  Future<void> _deleteEntriesOf(Directory directory) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      await _delete(entity);
    }
    _prepared.removeWhere((path) => p.isWithin(directory.path, path));
  }

  Future<void> _delete(FileSystemEntity entity) async {
    try {
      await entity.delete(recursive: true);
    } on PathNotFoundException {
      // Gone already.
    }
    _prepared.remove(entity.path);
  }
}
