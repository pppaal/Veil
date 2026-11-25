import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// How opening a file in another app ended. [lockedFirst]: the app locked
/// before the file was handed over, so nothing was.
enum FileOpenResult { opened, closed, noApp, failed, lockedFirst }

/// Opens one decrypted file with what the phone has for it.
abstract interface class FileOpenChannel {
  /// Android: starts the viewer in its own task and answers [FileOpenResult.opened]
  /// at once. iOS: shows Quick Look over the app and answers
  /// [FileOpenResult.closed] when it closes, whether the user or the lock
  /// closed it. [FileOpenResult.noApp] when nothing can show the file.
  /// [mayHandOver] is asked right before the platform is, after every
  /// check that awaits: false (the app locked meanwhile) hands nothing
  /// over and answers [FileOpenResult.lockedFirst].
  Future<FileOpenResult> open(String path, {required String mimeType, bool Function()? mayHandOver});
}

/// The app's own `veil/file_open` channel (MainActivity's FileOpenChannel,
/// AppDelegate's FileOpenPlugin). Only a file inside
/// `<temporary directory>/veil_open/` is ever handed over; any other path
/// answers [FileOpenResult.failed] without reaching the platform. The iOS
/// side refuses too ("locked") once the app's lock has engaged.
class MethodChannelFileOpen implements FileOpenChannel {
  MethodChannelFileOpen({
    MethodChannel channel = const MethodChannel(channelName),
    Future<Directory> Function()? temporaryRoot,
  })  : _channel = channel,
        _temporaryRoot = temporaryRoot ?? getTemporaryDirectory;

  static const channelName = 'veil/file_open';

  /// The folder under the temporary directory decrypted copies are opened
  /// from (AttachmentStoragePaths.openFolder).
  static const openFolder = 'veil_open';

  final MethodChannel _channel;
  final Future<Directory> Function() _temporaryRoot;

  @override
  Future<FileOpenResult> open(String path, {required String mimeType, bool Function()? mayHandOver}) async {
    final String resolved;
    try {
      final root = await Directory(p.join((await _temporaryRoot()).path, openFolder)).resolveSymbolicLinks();
      resolved = await File(path).resolveSymbolicLinks();
      if (!p.isWithin(root, resolved) || !await File(resolved).exists()) return FileOpenResult.failed;
    } on FileSystemException {
      return FileOpenResult.failed;
    }
    // Nothing is awaited between this and the call: a lock in the checks
    // above hands nothing to another app or to Quick Look.
    if (mayHandOver != null && !mayHandOver()) return FileOpenResult.lockedFirst;
    try {
      final reply = await _channel.invokeMethod<String>('open', {'path': resolved, 'mimeType': mimeType});
      return switch (reply) {
        'opened' => FileOpenResult.opened,
        'closed' => FileOpenResult.closed,
        'locked' => FileOpenResult.lockedFirst,
        'noApp' => FileOpenResult.noApp,
        _ => FileOpenResult.failed,
      };
    } on MissingPluginException {
      return FileOpenResult.failed;
    } on PlatformException {
      return FileOpenResult.failed;
    }
  }
}

final fileOpenChannelProvider = Provider<FileOpenChannel>((ref) => MethodChannelFileOpen());
