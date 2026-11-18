import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/features/attachments/data/attachment_picker.dart';

/// The system pickers, scripted. Each pick writes its fixture into
/// [pluginCache] the way the Android plugins do (a folder of its own per
/// pick: `<uuid>/` for a photo, `file_dialog-<uuid>/` for a file), so a test
/// sees whether the app deletes the plugin's copy.
class FakeAttachmentPicker implements AttachmentPicker {
  FakeAttachmentPicker(this.pluginCache);

  /// Stands for the plugins' cache folder.
  final Directory pluginCache;

  /// The next photo's bytes and name; null bytes close the picker.
  List<int>? photo;
  String photoName = 'IMG_0001.jpg';

  /// The next file's bytes and name; null bytes close the picker.
  List<int>? file;
  String fileName = 'report.pdf';

  /// The size the picker reports instead of the file's own, as a huge pick
  /// would without writing one.
  int? reportedSize;

  /// While set, a pick waits for it before it answers, as a picker the user
  /// is still looking at; a lock meanwhile closes the sheet around it.
  Completer<void>? gate;

  /// What retrieveLostData answers.
  List<String> lostPicks = [];
  int lostPickRequests = 0;

  /// Every pick asked for, 'photo' or 'file', in order.
  final List<String> calls = [];

  /// Every copy a pick wrote, in order.
  final List<String> written = [];

  final Random _random = Random();

  @override
  Future<PickedFile?> pickPhoto() async {
    calls.add('photo');
    await gate?.future;
    final bytes = photo;
    if (bytes == null) return null;
    return _write(bytes, _uuid(), photoName);
  }

  @override
  Future<PickedFile?> pickFile() async {
    calls.add('file');
    await gate?.future;
    final bytes = file;
    if (bytes == null) return null;
    return _write(bytes, 'file_dialog-${_uuid()}', fileName);
  }

  @override
  Future<List<String>> recoverLostPicks() async {
    lostPickRequests += 1;
    return lostPicks;
  }

  /// A photo lost to an activity death: written where the plugin keeps it.
  String writeLostPick(List<int> bytes) {
    final folder = Directory(p.join(pluginCache.path, _uuid()))..createSync(recursive: true);
    final path = p.join(folder.path, 'lost.jpg');
    File(path).writeAsBytesSync(bytes);
    lostPicks.add(path);
    return path;
  }

  PickedFile _write(List<int> bytes, String folderName, String name) {
    final folder = Directory(p.join(pluginCache.path, folderName))..createSync(recursive: true);
    final path = p.join(folder.path, name);
    File(path).writeAsBytesSync(bytes);
    written.add(path);
    return PickedFile(path: path, sizeBytes: reportedSize ?? bytes.length, name: name);
  }

  String _uuid() {
    String hex(int length) => List.generate(length, (_) => _random.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
  }
}
