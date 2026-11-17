import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/app/system_sheet_grace.dart';
import 'package:veil_mobile/src/app/veil_app.dart';
import 'package:veil_mobile/src/core/notifications/local_notification_service.dart';
import 'package:veil_mobile/src/core/security/platform_security_service.dart';

import '../layout/support/layout_world.dart';
import '../support/fake_platform_security.dart';

// The app lock through VeilApp's own lifecycle handling, on an Android and
// an iOS flavour of the system-sheet grace, with the platform channel
// recorded: what locks, what does not while a sheet is up, and what the
// platform is told on every lock and unlock.

class _QuietNotifications implements LocalNotificationService {
  @override
  void Function(String? conversationId)? onNotificationTapped;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showMessageNotification({required String conversationId, required String title, required String body}) async {}

  @override
  Future<void> cancelConversation(String conversationId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;

  setUpAll(() async => identities = await LayoutIdentities.generate());

  // The app, signed in and unlocked, with the grace of [isIOS]'s platform.
  Future<({LayoutWorld world, RecordingPlatformSecurity platform, SystemSheetGrace grace})> openApp(
    WidgetTester tester, {
    required bool isIOS,
  }) async {
    final platform = RecordingPlatformSecurity();
    final grace = SystemSheetGrace(isIOS: isIOS);
    final world = await LayoutWorld.create(
      identities: identities,
      account: LayoutAccount.signedIn,
      locale: 'en',
      overrides: [
        platformSecurityServiceProvider.overrideWithValue(platform),
        systemSheetGraceProvider.overrideWithValue(grace),
        localNotificationServiceProvider.overrideWithValue(_QuietNotifications()),
      ],
    );
    addTearDown(platform.close);
    await tester.pumpWidget(UncontrolledProviderScope(container: world.container, child: const VeilApp()));
    await tester.pump();
    await tester.pump();
    return (world: world, platform: platform, grace: grace);
  }

  Future<void> closeApp(WidgetTester tester, LayoutWorld world) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    world.dispose();
  }

  AppSessionState session(LayoutWorld world) => world.container.read(appSessionProvider);

  // Lifecycle changes arrive one legal step at a time, as on a device.
  void away(WidgetTester tester, {AppLifecycleState until = AppLifecycleState.paused}) {
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      if (state == until) return;
    }
  }

  void back(WidgetTester tester) {
    final current = tester.binding.lifecycleState;
    final steps = switch (current) {
      AppLifecycleState.paused => [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed],
      AppLifecycleState.hidden => [AppLifecycleState.inactive, AppLifecycleState.resumed],
      AppLifecycleState.inactive => [AppLifecycleState.resumed],
      _ => <AppLifecycleState>[],
    };
    for (final state in steps) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  for (final isIOS in [false, true]) {
    final flavour = isIOS ? 'iOS' : 'Android';

    testWidgets('$flavour: with no sheet up, going inactive locks; the platform hears it once, then the drawn lock screen',
        (tester) async {
      final app = await openApp(tester, isIOS: isIOS);
      expect(session(app.world).locked, isFalse);
      expect(app.platform.calls, isEmpty);

      away(tester, until: AppLifecycleState.inactive);
      expect(session(app.world).locked, isTrue);
      expect(app.platform.calls, ['lockEngaged'], reason: 'the lock screen is not drawn yet');
      await tester.pump();
      expect(app.platform.calls, ['lockEngaged', 'lockScreenShown']);

      // Further steps away lock nothing new and tell the platform nothing.
      away(tester);
      await tester.pump();
      expect(app.platform.count('lockEngaged'), 1);

      back(tester);
      // The lock screen has faded in by the time anyone could unlock.
      await tester.pump(const Duration(seconds: 1));
      expect(session(app.world).locked, isTrue);
      app.world.container.read(appSessionProvider.notifier).unlock();
      await tester.pump();
      expect(app.platform.calls, ['lockEngaged', 'lockScreenShown', 'sessionUnlocked']);
      await tester.pump(const Duration(seconds: 1));
      await closeApp(tester, app.world);
    });

    testWidgets('$flavour: a lock from the integrity check also tells the platform', (tester) async {
      final app = await openApp(tester, isIOS: isIOS);
      app.platform.integrityCompromised = true;
      // Away and back, unlocked again: only the integrity check is left to lock.
      away(tester, until: AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 1));
      app.world.container.read(appSessionProvider.notifier).unlock();
      await tester.pump(const Duration(seconds: 1));
      app.platform.calls.clear();

      back(tester);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(session(app.world).locked, isTrue);
      expect(app.platform.calls, ['lockEngaged', 'lockScreenShown']);
      await closeApp(tester, app.world);
    });
  }

  testWidgets('Android: while a picker is up, hidden and paused do not lock', (tester) async {
    final app = await openApp(tester, isIOS: false);
    final picker = Completer<String?>();
    final picked = app.grace.run(SystemSheet.photoPicker, () => picker.future);

    away(tester);
    await tester.pump();
    expect(session(app.world).locked, isFalse);
    expect(app.platform.calls, isEmpty);

    back(tester);
    picker.complete('/cache/picked.jpg');
    expect(await picked, '/cache/picked.jpg');
    await tester.pump(const Duration(milliseconds: 200));
    expect(session(app.world).locked, isFalse);

    // The picker is gone: the next hide locks again.
    away(tester, until: AppLifecycleState.inactive);
    expect(session(app.world).locked, isTrue);
    back(tester);
    await tester.pump(const Duration(milliseconds: 200));
    await closeApp(tester, app.world);
  });

  testWidgets('Android: back from a picker that was up more than 3 minutes is locked', (tester) async {
    var now = DateTime.utc(2026, 4, 7, 9);
    final platform = RecordingPlatformSecurity();
    final grace = SystemSheetGrace(isIOS: false, clock: () => now);
    final world = await LayoutWorld.create(
      identities: identities,
      account: LayoutAccount.signedIn,
      locale: 'en',
      overrides: [
        platformSecurityServiceProvider.overrideWithValue(platform),
        systemSheetGraceProvider.overrideWithValue(grace),
        localNotificationServiceProvider.overrideWithValue(_QuietNotifications()),
      ],
    );
    addTearDown(platform.close);
    await tester.pumpWidget(UncontrolledProviderScope(container: world.container, child: const VeilApp()));
    await tester.pump();

    final picker = Completer<String?>();
    final picked = grace.run(SystemSheet.filePicker, () => picker.future);
    away(tester);
    expect(world.container.read(appSessionProvider).locked, isFalse);
    now = now.add(const Duration(minutes: 4));
    back(tester);
    expect(world.container.read(appSessionProvider).locked, isTrue);
    expect(platform.count('lockEngaged'), 1);
    await expectLater(picked, throwsA(isA<SheetClosedByLock>()));
    await tester.pump(const Duration(milliseconds: 200));
    await closeApp(tester, world);
  });

  testWidgets('iOS: while a sheet is up, hidden does not lock, and the scene entering the background does',
      (tester) async {
    final app = await openApp(tester, isIOS: true);
    final quickLook = Completer<void>();
    final shown = app.grace.run(SystemSheet.quickLook, () => quickLook.future);
    final outcome = expectLater(shown, throwsA(isA<SheetClosedByLock>()));

    away(tester, until: AppLifecycleState.hidden);
    await tester.pump();
    expect(session(app.world).locked, isFalse);
    expect(app.platform.calls, isEmpty);

    app.platform.emit(PlatformSecurityEvent.sceneEnteredBackground);
    await tester.pump();
    expect(session(app.world).locked, isTrue);
    expect(app.platform.count('lockEngaged'), 1);
    // The lock closed the running sheet.
    await outcome;
    expect(app.grace.sheetRunning, isFalse);

    back(tester);
    await tester.pump(const Duration(milliseconds: 200));
    await closeApp(tester, app.world);
  });

  testWidgets('every lock closes the running sheets, whatever caused it', (tester) async {
    final app = await openApp(tester, isIOS: false);
    final save = Completer<bool>();
    final saving = app.grace.run(SystemSheet.saveScreen, () => save.future);
    final outcome = expectLater(saving, throwsA(isA<SheetClosedByLock>()));
    app.world.container.read(appSessionProvider.notifier).lock();
    await tester.pump();
    await outcome;
    expect(app.platform.calls, ['lockEngaged', 'lockScreenShown']);
    await tester.pump(const Duration(seconds: 1));
    await closeApp(tester, app.world);
  });
}
