import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/system_sheet_grace.dart';

// The lock while a system sheet the user opened is up (D40), on both
// platforms, with a wall clock and a monotonic clock the test moves.

const _away = [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused];

// The way back from paused, as the framework delivers it.
const _back = [AppLifecycleState.hidden, AppLifecycleState.inactive];

void main() {
  late DateTime now;
  late Duration uptime;

  SystemSheetGrace grace({required bool isIOS}) =>
      SystemSheetGrace(isIOS: isIOS, clock: () => now, uptime: () => uptime);

  setUp(() {
    now = DateTime.utc(2026, 4, 7, 9);
    uptime = const Duration(hours: 5);
  });

  for (final isIOS in [false, true]) {
    final platform = isIOS ? 'iOS' : 'Android';

    test('$platform: with no sheet up, leaving the foreground locks as it always did', () {
      final subject = grace(isIOS: isIOS);
      expect(subject.sheetRunning, isFalse);
      for (final state in _away) {
        expect(subject.shouldLockOn(state), isTrue, reason: '$state');
      }
      expect(subject.shouldLockOn(AppLifecycleState.detached), isTrue);
      expect(subject.shouldLockOn(AppLifecycleState.resumed), isFalse);
      expect(subject.noteResumedShouldLock(), isFalse);
    });

    test('$platform: a sheet that throws ends, and the next hide locks', () async {
      final subject = grace(isIOS: isIOS);
      await expectLater(
        subject.run(SystemSheet.filePicker, () async => throw StateError('plugin failed')),
        throwsStateError,
      );
      expect(subject.sheetRunning, isFalse);
      expect(subject.shouldLockOn(AppLifecycleState.hidden), isTrue);
      // One that throws before it returns a future ends as well.
      expect(() => subject.run<int>(SystemSheet.photoPicker, () => throw StateError('sync')), throwsStateError);
      expect(subject.sheetRunning, isFalse);
    });

    test('$platform: a lock makes a running sheet throw SheetClosedByLock, and a late result goes to onLateResult',
        () async {
      final subject = grace(isIOS: isIOS);
      final picker = Completer<String?>();
      final late = <String?>[];
      final running = subject.run(SystemSheet.photoPicker, () => picker.future, onLateResult: late.add);
      expect(subject.sheetRunning, isTrue);

      subject.closeAllForLock();
      await expectLater(running, throwsA(isA<SheetClosedByLock>()));
      expect(subject.sheetRunning, isFalse);
      expect(subject.shouldLockOn(AppLifecycleState.hidden), isTrue, reason: 'nothing is up any more');

      picker.complete('/cache/image_picker_1/IMG_1.jpg');
      await pumpEventQueue();
      expect(late, ['/cache/image_picker_1/IMG_1.jpg']);
    });

    test('$platform: a sheet that answered while the app was away: the way back does not lock, the resume decides',
        () async {
      final subject = grace(isIOS: isIOS);
      final picker = Completer<String?>();
      final result = subject.run(SystemSheet.filePicker, () => picker.future);
      for (final state in _away) {
        expect(subject.shouldLockOn(state), isFalse, reason: '$state');
      }
      now = now.add(const Duration(minutes: 1));
      // A cancel lands before the app is back (Android answers it inside
      // onActivityResult, before onResume).
      picker.complete(null);
      expect(await result, isNull);
      expect(subject.sheetRunning, isFalse);
      for (final state in _back) {
        expect(subject.shouldLockOn(state), isFalse, reason: 'on the way back: $state');
      }
      expect(subject.noteResumedShouldLock(), isFalse);
      // Back in front: the next hide locks.
      expect(subject.shouldLockOn(AppLifecycleState.inactive), isTrue);
    });

    test('$platform: a sheet that answered while away, more than 3 minutes after it opened: the resume locks',
        () async {
      final subject = grace(isIOS: isIOS);
      final picker = Completer<String?>();
      final result = subject.run(SystemSheet.photoPicker, () => picker.future);
      // iOS counts the limit while the sheet is up; leave before it passes.
      for (final state in _away) {
        expect(subject.shouldLockOn(state), isFalse, reason: '$state');
      }
      now = now.add(const Duration(minutes: 4));
      uptime += const Duration(minutes: 4);
      picker.complete(null);
      await result;
      for (final state in _back) {
        expect(subject.shouldLockOn(state), isFalse, reason: 'on the way back: $state');
      }
      expect(subject.noteResumedShouldLock(), isTrue);
    });

    test('$platform: leaving again after the sheet answered, before the resume, locks', () async {
      final subject = grace(isIOS: isIOS);
      final picker = Completer<String?>();
      final result = subject.run(SystemSheet.saveScreen, () => picker.future);
      for (final state in _away) {
        expect(subject.shouldLockOn(state), isFalse, reason: '$state');
      }
      picker.complete(null);
      await result;
      expect(subject.shouldLockOn(AppLifecycleState.hidden), isFalse, reason: 'on the way back');
      expect(subject.shouldLockOn(AppLifecycleState.paused), isTrue, reason: 'away again with no sheet up');
      expect(subject.shouldLockOn(AppLifecycleState.detached), isTrue);
    });

    test('$platform: a wall clock set back while away locks the resume', () async {
      final subject = grace(isIOS: isIOS);
      final picker = Completer<void>();
      unawaited(subject.run(SystemSheet.photoPicker, () => picker.future));
      for (final state in _away) {
        expect(subject.shouldLockOn(state), isFalse, reason: '$state');
      }
      // 30 real minutes asleep (the monotonic clock stops), then the date
      // set back a day in Settings.
      now = now.add(const Duration(minutes: 30)).subtract(const Duration(days: 1));
      uptime += const Duration(seconds: 20);
      expect(subject.noteResumedShouldLock(), isTrue);
      picker.complete();
    });

    test('$platform: the monotonic clock counts when the wall clock was set back only a little', () async {
      final subject = grace(isIOS: isIOS);
      final picker = Completer<void>();
      unawaited(subject.run(SystemSheet.filePicker, () => picker.future));
      for (final state in _away) {
        expect(subject.shouldLockOn(state), isFalse, reason: '$state');
      }
      // 10 minutes awake, the clock set back so it reads 1 minute later.
      uptime += const Duration(minutes: 10);
      now = now.add(const Duration(minutes: 1));
      expect(subject.noteResumedShouldLock(), isTrue);
      picker.complete();
    });

    test('$platform: a result before any lock is the result, and no late call follows', () async {
      final subject = grace(isIOS: isIOS);
      final late = <int>[];
      expect(await subject.run(SystemSheet.saveScreen, () async => 7, onLateResult: late.add), 7);
      subject.closeAllForLock();
      await pumpEventQueue();
      expect(late, isEmpty);
    });
  }

  group('Android', () {
    test('while a picker or the save screen is up, hidden and paused do not lock', () async {
      for (final sheet in [SystemSheet.photoPicker, SystemSheet.filePicker, SystemSheet.saveScreen]) {
        final subject = grace(isIOS: false);
        final open = Completer<void>();
        unawaited(subject.run(sheet, () => open.future));
        for (final state in _away) {
          expect(subject.shouldLockOn(state), isFalse, reason: '$sheet $state');
        }
        open.complete();
      }
    });

    test('a resume within 3 minutes does not lock; after 3 minutes it does', () async {
      final subject = grace(isIOS: false);
      final picker = Completer<void>();
      unawaited(subject.run(SystemSheet.photoPicker, () => picker.future));
      expect(subject.shouldLockOn(AppLifecycleState.hidden), isFalse);
      expect(subject.shouldLockOn(AppLifecycleState.paused), isFalse);
      now = now.add(const Duration(minutes: 2, seconds: 59));
      expect(subject.noteResumedShouldLock(), isFalse);

      // Away again, still the same sheet; it has been up past the limit.
      expect(subject.shouldLockOn(AppLifecycleState.paused), isFalse);
      now = now.add(const Duration(seconds: 2));
      expect(subject.noteResumedShouldLock(), isTrue);
      // The away period ended with that resume.
      expect(subject.noteResumedShouldLock(), isFalse);
      picker.complete();
    });

    test('the limit counts even when the picker answered just before the resume', () async {
      final subject = grace(isIOS: false);
      final picker = Completer<String>();
      final result = subject.run(SystemSheet.filePicker, () => picker.future);
      expect(subject.shouldLockOn(AppLifecycleState.paused), isFalse);
      now = now.add(const Duration(minutes: 4));
      // The activity result lands before onResume, as Android delivers it.
      picker.complete('/cache/file_dialog-1/lease.pdf');
      expect(await result, '/cache/file_dialog-1/lease.pdf');
      expect(subject.noteResumedShouldLock(), isTrue);
    });

    test('a second hide after the sheet ended locks', () async {
      final subject = grace(isIOS: false);
      await subject.run(SystemSheet.photoPicker, () async {
        expect(subject.shouldLockOn(AppLifecycleState.hidden), isFalse);
        return null;
      });
      expect(subject.noteResumedShouldLock(), isFalse);
      expect(subject.shouldLockOn(AppLifecycleState.hidden), isTrue);
    });

    test('Quick Look is iOS only: on Android opening a file gets no grace', () {
      final subject = grace(isIOS: false);
      expect(() => subject.run(SystemSheet.quickLook, () async {}), throwsArgumentError);
      expect(subject.sheetRunning, isFalse);
    });
  });

  group('iOS', () {
    test('while a sheet is up, inactive, hidden and paused do not lock', () async {
      for (final sheet in SystemSheet.values) {
        final subject = grace(isIOS: true);
        final open = Completer<void>();
        unawaited(subject.run(sheet, () => open.future));
        for (final state in _away) {
          expect(subject.shouldLockOn(state), isFalse, reason: '$sheet $state');
        }
        expect(subject.noteResumedShouldLock(), isFalse);
        open.complete();
      }
    });

    test('the scene entering the background always locks, and ends the away period', () async {
      final subject = grace(isIOS: true);
      final open = Completer<void>();
      unawaited(subject.run(SystemSheet.quickLook, () => open.future));
      expect(subject.shouldLockOn(AppLifecycleState.inactive), isFalse);
      // The caller locks on it; the grace only forgets the away period.
      subject.sceneEnteredBackground();
      now = now.add(const Duration(minutes: 10));
      expect(subject.noteResumedShouldLock(), isFalse);
      open.complete();
    });

    test('a sheet up for 3 minutes or more no longer holds the lock back', () async {
      final subject = grace(isIOS: true);
      final open = Completer<void>();
      unawaited(subject.run(SystemSheet.photoPicker, () => open.future));
      now = now.add(const Duration(minutes: 3));
      expect(subject.shouldLockOn(AppLifecycleState.inactive), isTrue);
      open.complete();
    });

    test('a wall clock set back while a sheet is up no longer holds the lock back', () async {
      final subject = grace(isIOS: true);
      final open = Completer<void>();
      unawaited(subject.run(SystemSheet.quickLook, () => open.future));
      now = now.subtract(const Duration(hours: 1));
      expect(subject.shouldLockOn(AppLifecycleState.inactive), isTrue);
      open.complete();
    });
  });
}
