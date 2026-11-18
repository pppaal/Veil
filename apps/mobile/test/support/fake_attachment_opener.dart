import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/features/attachments/data/attachment_opener.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_storage_paths.dart';

/// What the fake opener was handed: the copy's path, what it was opened
/// as (or the name it was saved under), and its bytes at that moment.
class HandedFile {
  HandedFile(this.path, this.as, this.bytes);

  final String path;

  /// The MIME type for an open, the suggested file name for a save.
  final String as;
  final Uint8List bytes;
}

/// The phone's file opener and save screen, for tests: records every file
/// handed over (refusing any that is not a copy in its own folder under
/// veil_open, as the real channel does) and answers with the outcomes set.
/// While [saveGate] is set, a save waits for it, as the save screen waits
/// for the user.
class FakeAttachmentOpener implements AttachmentOpener {
  FakeAttachmentOpener({this.openOutcome = OpenOutcome.opened, this.saveOutcome = SaveOutcome.saved});

  OpenOutcome openOutcome;
  SaveOutcome saveOutcome;
  Completer<void>? saveGate;

  final List<HandedFile> opened = [];
  final List<HandedFile> saved = [];

  @override
  Future<OpenOutcome> open(String path, {required String mimeType}) async {
    opened.add(HandedFile(path, mimeType, _read(path)));
    return openOutcome;
  }

  @override
  Future<SaveOutcome> save(String path, {required String fileName}) async {
    saved.add(HandedFile(path, fileName, _read(path)));
    final gate = saveGate;
    if (gate != null) await gate.future;
    return saveOutcome;
  }

  static Uint8List _read(String path) {
    final folder = p.dirname(path);
    if (p.basename(p.dirname(folder)) != AttachmentStoragePaths.openFolder) {
      throw StateError('Only a copy in its own folder under veil_open is handed over: $path');
    }
    return File(path).readAsBytesSync();
  }
}
