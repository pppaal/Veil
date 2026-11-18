import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/features/attachments/data/attachment_storage_paths.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_temp_file_store.dart';

// Every root is a temporary folder of the test's own, so each purge runs for
// real and the phone's real system temporary folder is never touched.

void main() {
  late Directory root;
  late Directory temporary;
  late Directory support;
  late Directory systemTemp;
  late List<String> prepared;

  AttachmentStoragePaths paths({required bool sweepSystemTemp, bool sweepPickerCopies = false}) =>
      AttachmentStoragePaths(
        temporaryRoot: () async => temporary,
        supportRoot: () async => support,
        systemTempRoot: () => systemTemp,
        sweepSystemTemp: sweepSystemTemp,
        sweepPickerCopies: sweepPickerCopies,
        onDirectoryPrepared: (path) async => prepared.add(path),
      );

  File write(Directory directory, String relative, [String contents = 'plaintext']) =>
      File(p.join(directory.path, relative))
        ..createSync(recursive: true)
        ..writeAsStringSync(contents);

  List<String> entriesOf(Directory directory) =>
      directory.existsSync() ? [for (final entity in directory.listSync()) p.basename(entity.path)] : const [];

  setUp(() {
    root = Directory.systemTemp.createTempSync('veil-paths-test-');
    temporary = Directory(p.join(root.path, 'tmp'))..createSync();
    support = Directory(p.join(root.path, 'support'))..createSync();
    systemTemp = Directory(p.join(root.path, 'system-tmp'))..createSync();
    prepared = [];
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('the three folders sit where the decisions put them, each excluded from backup once', () async {
    final storage = paths(sweepSystemTemp: false);
    expect((await storage.stagingDir()).path, p.join(temporary.path, 'veil_attachment_cache'));
    expect((await storage.mediaDir()).path, p.join(support.path, 'veil_media'));
    expect((await storage.openDir()).path, p.join(temporary.path, 'veil_open'));
    await storage.mediaDir();
    expect(prepared, [
      p.join(temporary.path, 'veil_attachment_cache'),
      p.join(support.path, 'veil_media'),
      p.join(temporary.path, 'veil_open'),
    ]);
    // A folder made again after a purge is excluded again.
    await storage.purgeAll();
    await storage.mediaDir();
    expect(prepared.last, p.join(support.path, 'veil_media'));
    expect(prepared, hasLength(4));
  });

  test('purgeAll removes the three folders, stray temporary entries and the whole system temp folder', () async {
    final storage = paths(sweepSystemTemp: true);
    write(await storage.stagingDir(), 'picked.jpg');
    write(await storage.mediaDir(), 'a' * 64);
    write(await storage.openDir(), 'abc/report.pdf');
    write(temporary, 'image_picker_123/IMG_0001.jpg');
    write(temporary, 'file_dialog-77/Lease.pdf');
    // What the iOS pickers and save sheet leave in NSTemporaryDirectory():
    // a file under its original name, the document picker's inbox folder.
    write(systemTemp, 'Lease agreement final.pdf');
    write(systemTemp, 'image_picker_4F2A.jpg');
    write(systemTemp, 'io.veil.mobile-Inbox/scan.pdf');
    // The app's support folder keeps everything that is not media.
    final database = write(support, '.veil/cache/veil_cache_v3.sqlite', 'db');

    await storage.purgeAll();

    expect(entriesOf(temporary), isEmpty);
    expect(Directory(p.join(support.path, 'veil_media')).existsSync(), isFalse);
    expect(entriesOf(systemTemp), isEmpty);
    expect(systemTemp.existsSync(), isTrue, reason: 'the folder itself belongs to the system');
    expect(database.existsSync(), isTrue);
  });

  test('without the iOS sweep the system temp folder is left alone', () async {
    final storage = paths(sweepSystemTemp: false);
    write(systemTemp, 'someone-elses.tmp');
    write(systemTemp, 'x-Inbox/kept.pdf');
    await storage.purgeSystemTemp();
    await storage.purgeAll();
    expect(entriesOf(systemTemp)..sort(), ['someone-elses.tmp', 'x-Inbox']);
  });

  test('purgeSystemTemp empties the system temp folder, files and folders alike', () async {
    final storage = paths(sweepSystemTemp: true);
    write(systemTemp, 'Report Q3.pdf');
    write(systemTemp, 'x-Inbox/report.pdf');
    final staged = write(await storage.stagingDir(), 'kept.jpg');
    await storage.purgeSystemTemp();
    expect(entriesOf(systemTemp), isEmpty);
    expect(staged.existsSync(), isTrue);
  });

  test('the sweep runs on iOS only unless told otherwise', () {
    expect(AttachmentStoragePaths().sweepSystemTemp, Platform.isIOS);
  });

  test('purgeStaging empties staging and nothing else', () async {
    final storage = paths(sweepSystemTemp: true);
    write(await storage.stagingDir(), 'one.jpg');
    write(await storage.stagingDir(), 'nested/two.pdf');
    final media = write(await storage.mediaDir(), 'b' * 64);
    final open = write(await storage.openDir(), 'xyz/open.pdf');
    final system = write(systemTemp, 'left.tmp');
    final stray = write(temporary, 'other.tmp');

    await storage.purgeStaging();

    expect(entriesOf(await storage.stagingDir()), isEmpty);
    for (final file in [media, open, system, stray]) {
      expect(file.existsSync(), isTrue, reason: file.path);
    }
  });

  test('purgeLeftPlaintext, run as the app starts, empties veil_open and staging and keeps the media', () async {
    final storage = paths(sweepSystemTemp: false);
    write(await storage.stagingDir(), 'one.jpg');
    write(await storage.openDir(), 'xyz/open.pdf');
    final media = write(await storage.mediaDir(), 'b' * 64);
    final system = write(systemTemp, 'left.tmp');

    await storage.purgeLeftPlaintext();

    expect(entriesOf(await storage.stagingDir()), isEmpty);
    expect(entriesOf(await storage.openDir()), isEmpty);
    expect(media.existsSync(), isTrue, reason: 'a sealed blob went');
    expect(system.existsSync(), isTrue, reason: 'the system temp folder is swept on iOS only');
  });

  // D39: a crash between a plugin's copy and its move into staging leaves
  // the pick under its real name. The next start deletes it before the lock
  // screen is passed, as it does staging.
  test('purgeLeftPlaintext on iOS also empties tmp/, where the pickers and the save screen copy under real names',
      () async {
    final storage = paths(sweepSystemTemp: true);
    write(systemTemp, 'lease-signed.pdf');
    write(systemTemp, 'image_picker_ABCD.jpg');
    write(systemTemp, 'app.veil-Inbox/scan.pdf');
    final media = write(await storage.mediaDir(), 'b' * 64);

    await storage.purgeLeftPlaintext();

    expect(entriesOf(systemTemp), isEmpty, reason: 'a pick or save copy outlived a crash under its real name');
    expect(media.existsSync(), isTrue);
  });

  test('purgeLeftPlaintext on Android also deletes the pickers\' own copy folders, and only those', () async {
    final storage = paths(sweepSystemTemp: false, sweepPickerCopies: true);
    write(temporary, 'file_dialog-0f8fad5b-d9cb-469f-a165-70867728950e/tax-return.pdf');
    write(temporary, '7c9e6679-7425-40de-944b-e07fc1f90ae7/IMG_2041.jpg');
    final other = write(temporary, 'some_cache/keep.bin');
    final lookalike = write(temporary, 'file_dialog-notes/keep.txt');
    final flat = write(temporary, '0f8fad5b-d9cb-469f-a165-70867728950e');

    await storage.purgeLeftPlaintext();

    expect(entriesOf(temporary), unorderedEquals(['some_cache', 'file_dialog-notes', p.basename(flat.path)]));
    for (final file in [other, lookalike, flat]) {
      expect(file.existsSync(), isTrue, reason: file.path);
    }
  });

  test('purgeLeftPlaintext elsewhere leaves the temporary folder\'s other folders alone', () async {
    final storage = paths(sweepSystemTemp: false);
    final copy = write(temporary, 'file_dialog-0f8fad5b-d9cb-469f-a165-70867728950e/tax-return.pdf');
    await storage.purgeLeftPlaintext();
    expect(copy.existsSync(), isTrue, reason: 'a desktop temporary folder is shared with other apps');
  });

  test('the pickers\' copy folders are swept on Android only unless told otherwise', () {
    expect(AttachmentStoragePaths().sweepPickerCopies, Platform.isAndroid);
  });

  test('purgeLeftPlaintext with no folders yet does nothing and creates none', () async {
    final storage = paths(sweepSystemTemp: true);
    await storage.purgeLeftPlaintext();
    expect(entriesOf(temporary), isEmpty);
  });

  test('a purge keeps going past a root that cannot be read, then says so', () async {
    final storage = AttachmentStoragePaths(
      temporaryRoot: () async => temporary,
      supportRoot: () async => throw const FileSystemException('no support folder'),
      systemTempRoot: () => systemTemp,
      sweepSystemTemp: true,
    );
    write(temporary, 'picked.jpg');
    write(systemTemp, 'picked.jpg');
    await expectLater(storage.purgeAll(), throwsA(isA<FileSystemException>()));
    expect(entriesOf(temporary), isEmpty);
    expect(entriesOf(systemTemp), isEmpty);
  });

  test('the staging store stages in the staging folder and its purge empties every folder', () async {
    final storage = paths(sweepSystemTemp: true);
    final store = DefaultAttachmentTempFileStore(paths: storage);
    // A pick is staged as a file of its own; the store only reads it back.
    final staged = write(await storage.stagingDir(), 'staged-brief');
    final blob = await store.createOpaqueBlob(filename: 'brief.pdf', sizeBytes: 64, existingPath: staged.path);
    expect(p.dirname(blob.path), (await storage.stagingDir()).path);
    expect(blob.sizeBytes, staged.lengthSync());
    write(await storage.mediaDir(), 'c' * 64);
    write(systemTemp, 'brief.pdf');

    await store.purgeAll();

    expect(File(blob.path).existsSync(), isFalse);
    expect(entriesOf(temporary), isEmpty);
    expect(Directory(p.join(support.path, 'veil_media')).existsSync(), isFalse);
    expect(entriesOf(systemTemp), isEmpty);
  });
}
