import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:veil_mobile/src/app/system_sheet_grace.dart';
import 'package:veil_mobile/src/core/platform/file_open_channel.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_opener.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_storage_paths.dart';

// The production opener and the app lock (D39, D40): the save screen always
// runs inside the system-sheet grace, Quick Look does on iOS, and opening a
// file on Android never does (Veil locks as soon as it is hidden). A sheet
// the lock closes counts as closed or cancelled, and every save empties the
// system temporary folder, where the iOS save sheet keeps its copy under
// the file's name.

class _Channel implements FileOpenChannel {
  _Channel(this._grace);

  final SystemSheetGrace _grace;
  final List<(String, String)> calls = [];
  final List<bool> sheetRunningDuringCall = [];
  final List<bool Function()> mayHandOver = [];
  Completer<FileOpenResult> answer = Completer();

  @override
  Future<FileOpenResult> open(String path, {required String mimeType, bool Function()? mayHandOver}) {
    calls.add((path, mimeType));
    if (mayHandOver != null) this.mayHandOver.add(mayHandOver);
    sheetRunningDuringCall.add(_grace.sheetRunning);
    return answer.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AttachmentStoragePaths paths;
  late Directory systemTemp;

  setUp(() {
    root = Directory.systemTemp.createTempSync('veil-opener-');
    systemTemp = Directory(p.join(root.path, 'system-tmp'))..createSync();
    paths = AttachmentStoragePaths(
      temporaryRoot: () async => Directory(p.join(root.path, 'tmp'))..createSync(recursive: true),
      supportRoot: () async => Directory(p.join(root.path, 'support'))..createSync(recursive: true),
      systemTempRoot: () => systemTemp,
      sweepSystemTemp: true,
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  // What the save sheet leaves behind on iOS: a copy under the file's name.
  void sheetCopyLeftBehind() => File(p.join(systemTemp.path, 'lease.pdf')).writeAsStringSync('plaintext');

  for (final isIOS in [true, false]) {
    final platform = isIOS ? 'iOS' : 'Android';

    group('save on $platform', () {
      test('runs inside the sheet grace, and the system temp folder is empty after', () async {
        final grace = SystemSheetGrace(isIOS: isIOS);
        final saved = Completer<String?>();
        final asked = <(String, String)>[];
        var sheetRunning = false;
        final opener = PluginAttachmentOpener(
          channel: _Channel(grace),
          grace: grace,
          paths: paths,
          saveFile: (path, fileName) {
            asked.add((path, fileName));
            sheetRunning = grace.sheetRunning;
            return saved.future;
          },
        );
        sheetCopyLeftBehind();
        final saving = opener.save('/open/abc/lease.pdf', fileName: 'lease.pdf');
        await Future<void>.delayed(Duration.zero);
        expect(sheetRunning, isTrue, reason: 'the save screen ran outside the grace: the app would lock under it');
        expect(asked, [('/open/abc/lease.pdf', 'lease.pdf')]);
        saved.complete('/storage/Documents/lease.pdf');
        expect(await saving, SaveOutcome.saved);
        expect(grace.sheetRunning, isFalse);
        expect(systemTemp.listSync(), isEmpty, reason: 'D39: the save sheet\'s copy outlived the save');
      });

      test('the lock closes it: cancelled, and the system temp folder is emptied all the same', () async {
        final grace = SystemSheetGrace(isIOS: isIOS);
        final saved = Completer<String?>();
        final opener = PluginAttachmentOpener(
          channel: _Channel(grace),
          grace: grace,
          paths: paths,
          saveFile: (_, __) => saved.future,
        );
        sheetCopyLeftBehind();
        final saving = opener.save('/open/abc/lease.pdf', fileName: 'lease.pdf');
        await Future<void>.delayed(Duration.zero);
        grace.closeAllForLock();
        expect(await saving, SaveOutcome.canceled);
        expect(systemTemp.listSync(), isEmpty);
        // The plugin still answers later: nothing is done with it.
        saved.complete('/storage/Documents/lease.pdf');
        await Future<void>.delayed(Duration.zero);
      });

      test('backing out is a cancel; a plugin error is a failure', () async {
        final grace = SystemSheetGrace(isIOS: isIOS);
        Future<String?> Function(String, String) answer = (_, __) async => null;
        final opener = PluginAttachmentOpener(
          channel: _Channel(grace),
          grace: grace,
          paths: paths,
          saveFile: (path, fileName) => answer(path, fileName),
        );
        expect(await opener.save('/open/abc/lease.pdf', fileName: 'lease.pdf'), SaveOutcome.canceled);
        answer = (_, __) async => throw PlatformException(code: 'io');
        expect(await opener.save('/open/abc/lease.pdf', fileName: 'lease.pdf'), SaveOutcome.failed);
        expect(grace.sheetRunning, isFalse);
      });
    });
  }

  group('open', () {
    test('on iOS Quick Look runs inside the grace, and the lock closes it', () async {
      final grace = SystemSheetGrace(isIOS: true);
      final channel = _Channel(grace);
      final opener = PluginAttachmentOpener(channel: channel, grace: grace, paths: paths);
      final opening = opener.open('/open/abc/lease.pdf', mimeType: 'application/pdf');
      await Future<void>.delayed(Duration.zero);
      expect(channel.calls, [('/open/abc/lease.pdf', 'application/pdf')]);
      expect(channel.sheetRunningDuringCall, [isTrue], reason: 'Quick Look ran outside the grace');
      expect(grace.sheetRunning, isTrue);
      grace.closeAllForLock();
      expect(await opening, OpenOutcome.closed);
      channel.answer.complete(FileOpenResult.closed);
    });

    test('on Android another app opens it with no grace: Veil locks as soon as it is hidden', () async {
      final grace = SystemSheetGrace(isIOS: false);
      final channel = _Channel(grace);
      final opener = PluginAttachmentOpener(channel: channel, grace: grace, paths: paths);
      final opening = opener.open('/open/abc/lease.pdf', mimeType: 'application/pdf');
      await Future<void>.delayed(Duration.zero);
      expect(channel.sheetRunningDuringCall, [isFalse], reason: 'opening a file on Android got a grace');
      expect(grace.shouldLockOn(AppLifecycleState.paused), isTrue);
      channel.answer.complete(FileOpenResult.opened);
      expect(await opening, OpenOutcome.opened);
    });

    // open_file checks the lock right before it calls open; the real
    // channel then still awaits the temporary directory (a platform call),
    // resolves links and checks the file before the platform is asked. A
    // lock in there hands nothing over, on either platform.
    for (final isIOS in [false, true]) {
      test('${isIOS ? 'iOS' : 'Android'}: a lock while the channel checks the path hands nothing to the platform',
          () async {
        final tmp = Directory(p.join(root.path, 'tmp'))..createSync(recursive: true);
        final copy = File(p.join(tmp.path, 'veil_open', 'abcdefghijklmnopqrstuvwx', 'lease.pdf'))
          ..createSync(recursive: true)
          ..writeAsStringSync('plaintext');
        final gate = Completer<void>();
        const channel = MethodChannel(MethodChannelFileOpen.channelName);
        final invoked = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
          invoked.add('${call.method} ${(call.arguments as Map)['path']}');
          return isIOS ? 'closed' : 'opened';
        });
        addTearDown(
            () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
        final grace = SystemSheetGrace(isIOS: isIOS);
        final opener = PluginAttachmentOpener(
          channel: MethodChannelFileOpen(temporaryRoot: () async {
            await gate.future;
            return tmp;
          }),
          grace: grace,
          paths: paths,
        );

        final opening = opener.open(copy.path, mimeType: 'application/pdf');
        await pumpEventQueue();
        // The app locks now (VeilApp closes every sheet on every lock).
        grace.closeAllForLock();
        gate.complete();
        expect(await opening, OpenOutcome.closed, reason: 'the caller deletes the copy of anything not opened');
        await pumpEventQueue();
        expect(invoked, isEmpty, reason: 'the decrypted file reached the platform after the app locked');
      });
    }

    test('a lock before any check: the same', () async {
      final grace = SystemSheetGrace(isIOS: false);
      final channel = _Channel(grace);
      final opener = PluginAttachmentOpener(channel: channel, grace: grace, paths: paths);
      final opening = opener.open('/open/abc/lease.pdf', mimeType: 'application/pdf');
      grace.closeAllForLock();
      await Future<void>.delayed(Duration.zero);
      expect(channel.mayHandOver.single(), isFalse, reason: 'the channel was not told the app locked');
      channel.answer.complete(FileOpenResult.lockedFirst);
      expect(await opening, OpenOutcome.closed);
    });

    for (final (result, outcome) in [
      (FileOpenResult.opened, OpenOutcome.opened),
      (FileOpenResult.closed, OpenOutcome.closed),
      (FileOpenResult.lockedFirst, OpenOutcome.closed),
      (FileOpenResult.noApp, OpenOutcome.noApp),
      (FileOpenResult.failed, OpenOutcome.failed),
    ]) {
      test('the channel answering ${result.name} is ${outcome.name}', () async {
        final grace = SystemSheetGrace(isIOS: false);
        final channel = _Channel(grace)..answer.complete(result);
        final opener = PluginAttachmentOpener(channel: channel, grace: grace, paths: paths);
        expect(await opener.open('/open/abc/lease.pdf', mimeType: 'application/pdf'), outcome);
      });
    }
  });
}
