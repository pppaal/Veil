import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A system screen the user asked for while Veil is open.
enum SystemSheet {
  photoPicker,
  filePicker,
  saveScreen,

  /// iOS only: opening a file shows Quick Look inside the app. On Android a
  /// file opens in another app's task, which gets no grace at all.
  quickLook,
}

/// What a sheet's [SystemSheetGrace.run] throws when the app locked while
/// the sheet was up. Callers treat it as a cancel.
class SheetClosedByLock implements Exception {
  const SheetClosedByLock();
}

/// The app lock while a system sheet the user asked for is up (D40).
///
/// Without a sheet, the app locks as soon as it leaves the foreground, as
/// it always has. A sheet changes what leaving means:
/// - iOS: pickers, the save screen and Quick Look are presented inside the
///   app, so a lifecycle change while one runs is the presentation, not the
///   user leaving. Only the scene really entering the background locks
///   ([sceneEnteredBackground], a native event), as Home does without a
///   sheet; a sheet up longer than [limit] stops being one.
/// - Android: a picker or the save screen is another app's activity, so
///   Veil is hidden while it runs and is not locked for it. The next resume
///   locks if the sheet opened more than [limit] before it: going Home from
///   a picker leaves Veil unlocked for up to [limit].
///
/// Every lock ends every running sheet's [run] with [SheetClosedByLock]
/// ([closeAllForLock]); a result the plugin still delivers afterwards goes
/// to the caller's `onLateResult`.
class SystemSheetGrace {
  SystemSheetGrace({
    required this.isIOS,
    DateTime Function() clock = DateTime.now,
    this.limit = const Duration(minutes: 3),
  }) : _clock = clock;

  final bool isIOS;
  final Duration limit;
  final DateTime Function() _clock;
  final Set<_RunningSheet> _running = {};

  // When the oldest sheet that was up while the app was away opened; null
  // while the app has not been away with a sheet up.
  DateTime? _awaySheetOpenedAt;

  /// Runs [openSheet], the call that shows [sheet] and completes when it
  /// closes. Completes with its result, or throws [SheetClosedByLock] when
  /// the session locked while it ran; a result that still arrives later is
  /// handed to [onLateResult] (the attach flow holds it; every other caller
  /// deletes the file it names). The sheet ends when [run] ends, with a
  /// result or an error.
  Future<T> run<T>(SystemSheet sheet, Future<T> Function() openSheet, {void Function(T late)? onLateResult}) {
    if (sheet == SystemSheet.quickLook && !isIOS) {
      throw ArgumentError('Quick Look is iOS only; opening a file on Android gets no grace.');
    }
    final result = Completer<T>();
    final running = _RunningSheet(sheet, _clock(), () {
      if (!result.isCompleted) result.completeError(const SheetClosedByLock());
    });
    _running.add(running);
    final Future<T> opened;
    try {
      opened = openSheet();
    } catch (error, trace) {
      _running.remove(running);
      return Future<T>.error(error, trace);
    }
    opened.then(
      (value) {
        _running.remove(running);
        if (!result.isCompleted) {
          result.complete(value);
        } else {
          onLateResult?.call(value);
        }
      },
      onError: (Object error, StackTrace trace) {
        _running.remove(running);
        if (!result.isCompleted) result.completeError(error, trace);
      },
    );
    return result.future;
  }

  /// Whether a sheet is up now.
  bool get sheetRunning => _running.isNotEmpty;

  /// Whether this lifecycle change locks the app now (D40 a).
  bool shouldLockOn(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        return false;
      case AppLifecycleState.detached:
        return true;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        final openedAt = _oldestRunningOpenedAt();
        if (openedAt == null) return true;
        if (isIOS && _clock().difference(openedAt) >= limit) return true;
        final away = _awaySheetOpenedAt;
        _awaySheetOpenedAt = away == null || openedAt.isBefore(away) ? openedAt : away;
        return false;
    }
  }

  /// iOS: the scene really went to the background. It always locks; the
  /// caller locks the app.
  void sceneEnteredBackground() => _awaySheetOpenedAt = null;

  /// On resume: true when a sheet that was up while the app was away opened
  /// more than [limit] ago, whether or not it is still up. Ends the away
  /// period.
  bool noteResumedShouldLock() {
    final openedAt = _awaySheetOpenedAt;
    _awaySheetOpenedAt = null;
    return openedAt != null && _clock().difference(openedAt) > limit;
  }

  /// The session locked: every running [run] throws [SheetClosedByLock].
  void closeAllForLock() {
    final closing = List.of(_running);
    _running.clear();
    _awaySheetOpenedAt = null;
    for (final sheet in closing) {
      sheet.close();
    }
  }

  DateTime? _oldestRunningOpenedAt() {
    DateTime? oldest;
    for (final sheet in _running) {
      if (oldest == null || sheet.openedAt.isBefore(oldest)) oldest = sheet.openedAt;
    }
    return oldest;
  }
}

class _RunningSheet {
  _RunningSheet(this.sheet, this.openedAt, this.close);

  final SystemSheet sheet;
  final DateTime openedAt;
  final void Function() close;
}

/// The grace for this platform: iOS presents sheets in-process; every other
/// platform is treated as Android.
final systemSheetGraceProvider =
    Provider<SystemSheetGrace>((ref) => SystemSheetGrace(isIOS: defaultTargetPlatform == TargetPlatform.iOS));
