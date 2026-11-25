import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/app/system_sheet_grace.dart';
import 'package:veil_mobile/src/features/attachments/data/attach_flow.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_picker.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_storage_paths.dart';
import 'package:veil_mobile/src/features/attachments/data/image_preparer.dart';
import 'package:veil_mobile/src/features/attachments/domain/attachment_rules.dart';

import '../support/async_wait.dart';
import '../support/fake_attachment_picker.dart';
import '../support/media_fixtures.dart';

// Picking a photo or a file for a chat: where the plaintext goes, what is
// left behind (nothing), the limits, and what a lock does to a pick.

void main() {
  late Directory root;
  late Directory systemTemp;
  late AttachmentStoragePaths paths;
  late FakeAttachmentPicker picker;
  late _RecordingGrace grace;
  late _ScriptedPreparer preparer;

  setUp(() {
    root = Directory.systemTemp.createTempSync('veil-attach-flow-');
    systemTemp = Directory(p.join(root.path, 'system-tmp'))..createSync();
    paths = AttachmentStoragePaths(
      temporaryRoot: () async => Directory(p.join(root.path, 'tmp'))..createSync(recursive: true),
      supportRoot: () async => Directory(p.join(root.path, 'support'))..createSync(recursive: true),
      systemTempRoot: () => systemTemp,
      sweepSystemTemp: true,
    );
    picker = FakeAttachmentPicker(Directory(p.join(root.path, 'plugin-cache'))..createSync());
    grace = _RecordingGrace();
    preparer = _ScriptedPreparer();
  });

  tearDown(() => root.deleteSync(recursive: true));

  AttachFlow flow({Duration holdFor = AttachFlow.defaultHoldFor, PickerCopyRoots? copyRoots}) => AttachFlow(
        picker: picker,
        preparer: preparer,
        grace: grace,
        paths: paths,
        copyRoots: copyRoots ?? PickerCopyRoots.at([picker.pluginCache]),
        holdFor: holdFor,
      );

  Future<List<String>> staged() async => [
        for (final entity in (await paths.stagingDir()).listSync()) p.basename(entity.path),
      ];

  // What the iOS pickers leave in NSTemporaryDirectory, swept after each pick.
  void leaveInSystemTemp() {
    File(p.join(systemTemp.path, 'image_picker_4F2A.jpg')).writeAsStringSync('plaintext');
    Directory(p.join(systemTemp.path, 'io.veil.mobile-Inbox')).createSync();
  }

  test('a photo is staged under an opaque name, the plugin copy goes, and the system temporary folder is swept', () async {
    picker.photo = jpegWithMetadata();
    leaveInSystemTemp();

    final outcome = await flow().pickPhoto();
    final pick = outcome.pick! as PhotoPick;

    expect(p.dirname(pick.stagedPath), (await paths.stagingDir()).path);
    expect(p.basename(pick.stagedPath), matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(File(picker.written.single).existsSync(), isFalse, reason: 'the plugin copy stayed');
    expect(picker.pluginCache.listSync(), isEmpty, reason: 'the plugin folder stayed');
    expect(systemTemp.listSync(), isEmpty);

    // The prepared photo takes the picked one's place: the original, with
    // its metadata, is gone from staging as soon as the photo is ready.
    final prepared = (await pick.prepared)!;
    expect(File(pick.stagedPath).readAsBytesSync(), prepared.bytes);
    expect(await staged(), [p.basename(pick.stagedPath)]);
  });

  test('a file is staged with its sanitized name, size and whether it keeps metadata', () async {
    picker
      ..file = pdfBytes('lease')
      ..fileName = 'lease.pdf';
    leaveInSystemTemp();

    final pick = (await flow().pickFile()).pick! as FilePick;

    expect(pick.name, 'lease.pdf');
    expect(pick.sizeBytes, pdfBytes('lease').length);
    expect(pick.keepsMetadata, isFalse);
    expect(File(pick.stagedPath).readAsBytesSync(), pdfBytes('lease'));
    expect(picker.pluginCache.listSync(), isEmpty);
    expect(systemTemp.listSync(), isEmpty);
  });

  test('a video or a HEIC photo picked as a file says it keeps any location; a PDF does not', () async {
    for (final (bytes, name, keeps) in [
      (mp4Head(), 'clip.mp4', true),
      (heicHead(), 'IMG_2001.heic', true),
      (jpegWithMetadata(), 'scan', true),
      (pdfBytes('x'), 'notes.pdf', false),
    ]) {
      picker
        ..file = bytes
        ..fileName = name;
      final pick = (await flow().pickFile()).pick! as FilePick;
      expect(pick.keepsMetadata, keeps, reason: name);
    }
  });

  // The roots as each platform has them: Android's cache folder and iOS's
  // system temporary folder, both standing at the picker's cache here, and
  // none on Windows, macOS or Linux.
  Map<String, PickerCopyRoots> everyPlatform() => {
        'Android': PickerCopyRoots.platform(android: true, ios: false, cacheDir: () async => picker.pluginCache),
        'iOS': PickerCopyRoots.platform(android: false, ios: true, systemTemp: () => picker.pluginCache),
        'desktop': PickerCopyRoots.platform(android: false, ios: false),
      };

  test(
      'a photo or a file the picker hands over from the user\'s own folder (as desktop pickers do) outlives the pick, on every platform',
      () async {
    final pictures = Directory(p.join(root.path, 'Pictures'))..createSync();
    final photo = File(p.join(pictures.path, 'holiday.jpg'))..writeAsBytesSync(jpegWithMetadata());
    final document = File(p.join(pictures.path, 'lease.pdf'))..writeAsBytesSync(pdfBytes('lease'));
    // Inside a root only by its spelling: it climbs back out.
    final climbing = File(p.join(picker.pluginCache.path, '..', 'Pictures', 'holiday.jpg'));
    for (final MapEntry(key: platform, value: roots) in everyPlatform().entries) {
      for (final (own, isPhoto) in [(photo, true), (document, false), (climbing, true)]) {
        picker.ownFile = own;
        final attach = flow(copyRoots: roots);
        final pick = (isPhoto ? await attach.pickPhoto() : await attach.pickFile()).pick;
        expect(pick, isNotNull, reason: '$platform ${own.path}');
        if (pick case PhotoPick(:final prepared)) await prepared;
        expect(own.existsSync(), isTrue, reason: '$platform deleted the user\'s own ${own.path}');
        expect(File(pick!.stagedPath).existsSync(), isTrue, reason: '$platform ${own.path}');
        await attach.discard(pick);
      }
    }
    expect(photo.readAsBytesSync(), jpegWithMetadata());
    expect(document.readAsBytesSync(), pdfBytes('lease'));
  });

  test('on Windows, macOS and Linux nothing picked is deleted, even from a temporary folder', () async {
    picker.photo = jpegWithMetadata();
    final attach = flow(copyRoots: everyPlatform()['desktop']);
    final pick = (await attach.pickPhoto()).pick! as PhotoPick;
    await pick.prepared;
    expect(File(picker.written.single).existsSync(), isTrue, reason: 'a desktop pick is the user\'s own file');
    await attach.discard(pick);
  });

  test(
      'on Android and iOS the plugin\'s copy goes, also when the root is reached through a link (iOS /var is /private/var)',
      () async {
    final linked = Link(p.join(root.path, 'linked-cache'))..createSync(picker.pluginCache.path);
    for (final roots in [
      everyPlatform()['Android']!,
      everyPlatform()['iOS']!,
      PickerCopyRoots.platform(android: false, ios: true, systemTemp: () => Directory(linked.path)),
    ]) {
      picker.photo = jpegWithMetadata();
      await flow(copyRoots: roots).pickPhoto();
      expect(File(picker.written.last).existsSync(), isFalse, reason: 'the plugin copy stayed');
      expect(picker.pluginCache.listSync(), isEmpty, reason: 'the plugin folder stayed');
    }
  });

  test('a file over 25 MB is refused: nothing is staged and the plugin copy goes', () async {
    picker
      ..file = pdfBytes('big')
      ..reportedSize = kMaxFileBytes + 1;
    leaveInSystemTemp();

    final outcome = await flow().pickFile();

    expect(outcome.refusal, AttachRefusal.tooBig);
    expect(outcome.pick, isNull);
    expect(await staged(), isEmpty);
    expect(picker.pluginCache.listSync(), isEmpty);
    expect(systemTemp.listSync(), isEmpty);
  });

  test('a photo that cannot be prepared comes to nothing and its staged copy goes', () async {
    picker.photo = notAnImage();
    preparer.fail = true;

    final pick = (await flow().pickPhoto()).pick! as PhotoPick;

    expect(await pick.prepared, isNull);
    expect(await staged(), isEmpty);
  });

  test('closing a picker stages nothing', () async {
    final outcome = await flow().pickPhoto();
    expect(outcome.pick, isNull);
    expect(outcome.refusal, isNull);
    expect(await staged(), isEmpty);
  });

  test('every picker runs inside the system-sheet grace, as the sheet it is', () async {
    picker
      ..photo = jpegWithMetadata()
      ..file = pdfBytes('a');
    final attach = flow();
    await attach.pickPhoto();
    await attach.pickFile();
    expect(grace.sheets, [SystemSheet.photoPicker, SystemSheet.filePicker]);
    expect(picker.calls, ['photo', 'file']);
  });

  test('a lock closes the picker like a cancel; with no late result nothing is staged', () async {
    picker.gate = Completer<void>();
    final picking = flow().pickPhoto();
    await waitFor(() => grace.sheetRunning);

    grace.closeAllForLock();
    final outcome = await picking;

    expect(outcome.pick, isNull);
    expect(outcome.refusal, isNull);
    picker.gate!.complete();
    await settle();
    expect(await staged(), isEmpty);
  });

  test('a result the picker still delivers after the lock is staged and held, its plugin copy gone', () async {
    picker
      ..photo = jpegWithMetadata()
      ..gate = Completer<void>();
    final attach = flow();
    final picking = attach.pickPhoto();
    await waitFor(() => grace.sheetRunning);
    grace.closeAllForLock();
    expect((await picking).pick, isNull);

    picker.gate!.complete();
    await waitFor(() => attach.held.value != null, reason: 'the late pick was not held');

    final held = attach.held.value! as PhotoPick;
    expect(p.dirname(held.stagedPath), (await paths.stagingDir()).path);
    expect(picker.pluginCache.listSync(), isEmpty);
    expect(await held.prepared, isNotNull);
    expect(attach.takeHeld(), same(held));
    expect(attach.held.value, isNull);
  });

  test('a result the picker delivers after the session left is not held, and nothing stays staged', () async {
    picker
      ..photo = jpegWithMetadata()
      ..gate = Completer<void>();
    final attach = flow();
    final picking = attach.pickPhoto();
    await waitFor(() => grace.sheetRunning);
    grace.closeAllForLock();
    expect((await picking).pick, isNull);

    // Signed out (attachFlowProvider sets this as the session leaves).
    attach.holdsPicks = false;
    picker.gate!.complete();
    await waitFor(() => picker.pluginCache.listSync().isEmpty, reason: 'the late pick was never staged');
    await waitFor(() async => (await staged()).isEmpty, reason: 'the late pick stayed staged');
    expect(attach.held.value, isNull);
  });

  test('a held pick is dropped after a while, and when the chat is left', () async {
    expect(AttachFlow.defaultHoldFor, const Duration(minutes: 10));
    picker.file = pdfBytes('held');

    final attach = flow(holdFor: const Duration(milliseconds: 50));
    final pick = (await attach.pickFile()).pick!;
    attach.hold(pick);
    await waitFor(() => attach.held.value == null, reason: 'the held pick was kept');
    await waitFor(() => !File(pick.stagedPath).existsSync(), reason: 'its staged copy stayed');

    final left = flow();
    final again = (await left.pickFile()).pick!;
    left.hold(again);
    left.chatLeft();
    await waitFor(() => !File(again.stagedPath).existsSync(), reason: 'leaving the chat kept it');
    expect(left.held.value, isNull);
  });

  test('lost picks and the system temporary folder are cleaned once per process, when a chat first attaches', () async {
    final lost = picker.writeLostPick(jpegWithMetadata());
    leaveInSystemTemp();
    // A lost pick is only ever the plugin's: one named outside its cache
    // is left alone.
    final elsewhere = File(p.join(root.path, 'elsewhere.jpg'))..writeAsBytesSync(jpegWithMetadata());
    picker.lostPicks.add(elsewhere.path);
    final container = ProviderContainer(overrides: [
      attachmentPickerProvider.overrideWithValue(picker),
      pickerCopyRootsProvider.overrideWithValue(PickerCopyRoots.at([picker.pluginCache])),
      imagePreparerProvider.overrideWithValue(preparer),
      systemSheetGraceProvider.overrideWithValue(grace),
      attachmentStoragePathsProvider.overrideWithValue(paths),
    ]);
    addTearDown(container.dispose);

    // No session here: the flow holds nothing.
    expect(container.read(attachFlowProvider('conv-1')).holdsPicks, isFalse);
    await container.read(attachStartupCleanupProvider.future);
    expect(File(lost).existsSync(), isFalse);
    expect(picker.pluginCache.listSync(), isEmpty);
    expect(elsewhere.existsSync(), isTrue);
    expect(systemTemp.listSync(), isEmpty);

    container.read(attachFlowProvider('conv-2'));
    await settle(const Duration(milliseconds: 20));
    expect(picker.lostPickRequests, 1);
  });
}

/// The grace, recording which sheet each run is.
class _RecordingGrace extends SystemSheetGrace {
  _RecordingGrace() : super(isIOS: false);

  final List<SystemSheet> sheets = [];

  @override
  Future<T> run<T>(SystemSheet sheet, Future<T> Function() openSheet, {void Function(T late)? onLateResult}) {
    sheets.add(sheet);
    return super.run(sheet, openSheet, onLateResult: onLateResult);
  }
}

/// Answers at once with a small JPEG standing for the prepared photo, or
/// fails as an undecodable source would.
class _ScriptedPreparer implements ImagePreparer {
  bool fail = false;

  @override
  Future<PreparedImage> prepare(String sourcePath) async {
    if (fail) throw const ImagePrepareException('not a photo');
    return PreparedImage(bytes: Uint8List.fromList(preparedPhotoFixture), contentType: 'image/jpeg', width: 4, height: 3);
  }
}

final List<int> preparedPhotoFixture = [0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 0xff, 0xd9];
