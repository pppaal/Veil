import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/security/app_lock_service.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/app_lock/presentation/app_lock_screen.dart';
import 'package:veil_mobile/src/features/settings/presentation/settings_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_shell.dart';

import '../phone/phone_app.dart';
import '../support/memory_secure_store.dart';

// The App lock row of Settings is the one place that says whether the lock
// is on: whether this phone has a PIN. A new account has none until the
// first lock, where the lock screen has one chosen; back on Settings the
// row says On. These go through the app's real router, its lock guard and
// the real lock screen; only the keystore's PIN is a flag here (deriving a
// real verifier takes seconds).

const _signedIn = AppSessionState(
  accessToken: 'access-1',
  refreshToken: 'refresh-1',
  userId: 'user-1',
  deviceId: 'device-1',
  handle: 'alex',
  displayName: 'Alex Kim',
  onboardingAccepted: true,
  privacyConsentAccepted: true,
  locked: false,
  initializing: false,
);

class _NoBiometrics implements LocalUnlockAuthenticator {
  const _NoBiometrics();

  @override
  Future<bool> authenticateBiometric() async => false;

  @override
  Future<bool> canUseBiometrics() async => false;
}

/// A phone with biometrics that recognise the user.
class _Biometrics implements LocalUnlockAuthenticator {
  const _Biometrics();

  @override
  Future<bool> authenticateBiometric() async => true;

  @override
  Future<bool> canUseBiometrics() async => true;
}

/// The app lock with the PIN as a flag, counting how often it is asked.
class _Lock extends AppLockService {
  _Lock(SecureStorageService storage, {LocalUnlockAuthenticator biometrics = const _NoBiometrics()})
      : super(biometrics, storage);

  bool pinSet = false;
  int asked = 0;

  /// While set, the keystore has not answered yet.
  Completer<void>? answer;

  @override
  Future<bool> hasPin() async {
    asked++;
    await answer?.future;
    return pinSet;
  }

  @override
  Future<void> setPin(String pin) async {
    if (!isValidPinFormat(pin)) throw StateError('PIN must be 6 to 12 digits.');
    pinSet = true;
  }
}

class _App {
  _App(this.container, this.lock);

  final ProviderContainer container;
  final _Lock lock;

  GoRouter get router => container.read(appRouterProvider);
  String get path => router.state.uri.path;
  AppSessionController get session => container.read(appSessionProvider.notifier);
}

/// Screens the rows do not reach stand in as their paths; Settings and the
/// lock screen are the real ones.
List<RouteBase> _routes() => [
      for (final path in const ['/splash', '/privacy-consent', '/onboarding', '/choose-handle', '/conversations'])
        GoRoute(path: path, builder: (_, __) => Scaffold(body: Text(path))),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/lock', builder: (_, __) => const AppLockScreen()),
    ];

ProviderContainer _container(_Lock lock, SecureStorageService storage) {
  final session = AppSessionController(
    storage,
    VeilApiClient(baseUrl: 'http://localhost:3000/v1'),
    createDefaultCryptoAdapter(),
  )..state = _signedIn;
  return ProviderContainer(overrides: [
    secureStorageProvider.overrideWithValue(storage),
    appSessionProvider.overrideWith((ref) => session),
    appRoutesProvider.overrideWithValue(_routes()),
    appLockServiceProvider.overrideWithValue(lock),
  ]);
}

Future<_App> _openSettings(
  WidgetTester tester, {
  Completer<void>? answer,
  LocalUnlockAuthenticator biometrics = const _NoBiometrics(),
}) async {
  usePhoneView(tester, phoneLarge);
  final storage = SecureStorageService(MemorySecureStore());
  final lock = _Lock(storage, biometrics: biometrics)..answer = answer;
  final container = _container(lock, storage);
  addTearDown(container.dispose);
  final app = _App(container, lock);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: VeilTheme.dark(fontFamily: layoutFontFamily),
      locale: const Locale('en'),
      routerConfig: app.router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  ));
  await pumpFrames(tester, frames: 2);
  app.router.go('/settings');
  return app;
}

final _en = lookupAppLocalizations(const Locale('en'));
final _row = find.byKey(const ValueKey('settings-app-lock'));

Finder _inRow(Finder matching) => find.descendant(of: _row, matching: matching);

void _expectRowSays(String word) {
  expect(_inRow(find.text(word)), findsOneWidget);
  final other = word == _en.commonOn ? _en.commonOff : _en.commonOn;
  expect(_inRow(find.text(other)), findsNothing);
}

/// Chooses [pin] on the lock screen the way a person does: both fields,
/// then the button.
Future<void> _choosePin(WidgetTester tester, String pin) async {
  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(2), reason: 'a PIN and its confirmation');
  await tester.enterText(fields.at(0), pin);
  await tester.enterText(fields.at(1), pin);
  await tester.pump();
  final submit = find.byWidgetPredicate((widget) => widget is FilledButton);
  await tester.ensureVisible(submit);
  await tester.pump();
  await tester.tap(submit);
  await pumpFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadBundledFonts);

  testWidgets('Lock now on a phone without a PIN: the PIN chosen on the lock screen turns the row On',
      (tester) async {
    final answer = Completer<void>();
    final app = await _openSettings(tester, answer: answer);
    await pumpFrames(tester);
    // Before the keystore answers the row says neither, rather than a guess.
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(_inRow(find.text(_en.commonOn)), findsNothing);
    expect(_inRow(find.text(_en.commonOff)), findsNothing);

    answer.complete();
    app.lock.answer = null;
    await pumpFrames(tester);
    _expectRowSays(_en.commonOff);

    final askedBefore = app.lock.asked;
    await tester.tap(find.byKey(const ValueKey('settings-lock-now')));
    await pumpFrames(tester);
    expect(app.path, '/lock');
    expect(find.byType(AppLockScreen), findsOneWidget);

    await _choosePin(tester, '482916');
    expect(app.lock.pinSet, isTrue);
    expect(app.container.read(appSessionProvider).locked, isFalse);
    expect(app.path, '/settings', reason: 'unlocking puts Settings back');
    expect(app.lock.asked, greaterThan(askedBefore), reason: 'the keystore is asked again');
    _expectRowSays(_en.commonOn);
  });

  testWidgets('while Off the row turns the lock on; once On it only says so', (tester) async {
    final app = await _openSettings(tester);
    await pumpFrames(tester);
    _expectRowSays(_en.commonOff);
    expect(_inRow(find.byIcon(Icons.chevron_right)), findsOneWidget, reason: 'Off leads somewhere');

    await tester.tap(_row);
    await pumpFrames(tester);
    expect(app.path, '/lock');
    expect(find.byType(AppLockScreen), findsOneWidget);

    await _choosePin(tester, '482916');
    expect(app.path, '/settings');
    _expectRowSays(_en.commonOn);
    expect(_inRow(find.byIcon(Icons.chevron_right)), findsNothing, reason: 'nothing to set once it is on');

    await tester.tap(_row);
    await pumpFrames(tester);
    expect(app.path, '/settings', reason: 'the row no longer opens anything');
    expect(app.container.read(appSessionProvider).locked, isFalse);
  });

  // The first-PIN setup that Settings opens on a phone with no PIN guards
  // nothing yet, so it can be cancelled: back to Settings, unlocked, with
  // the lock still off. Once a PIN exists, or when the app locked by itself,
  // there is no way past the lock screen but the PIN.
  final cancel = find.byKey(AppLockScreen.cancelKey);

  testWidgets('Lock now without a PIN: back cancels the setup and puts Settings back, unlocked',
      (tester) async {
    final app = await _openSettings(tester);
    await pumpFrames(tester);
    _expectRowSays(_en.commonOff);

    await tester.tap(find.byKey(const ValueKey('settings-lock-now')));
    await pumpFrames(tester);
    expect(app.path, '/lock');
    expect(find.text(_en.appLockTurnOn), findsOneWidget, reason: 'the PIN is chosen here');
    expect(cancel, findsOneWidget);

    await tester.tap(cancel);
    await pumpFrames(tester);
    expect(app.container.read(appSessionProvider).locked, isFalse);
    expect(app.path, '/settings', reason: 'cancelling goes back to where the user was');
    expect(app.lock.pinSet, isFalse);
    _expectRowSays(_en.commonOff);

    // The cancel was for that one request: the lock the app engages by
    // itself still asks for a PIN.
    app.session.lock();
    await pumpFrames(tester);
    expect(app.path, '/lock');
    expect(find.text(_en.appLockTurnOn), findsOneWidget);
    expect(cancel, findsNothing);
  });

  testWidgets('the App lock row while Off: the system back button cancels the setup too', (tester) async {
    final app = await _openSettings(tester);
    await pumpFrames(tester);

    await tester.tap(_row);
    await pumpFrames(tester);
    expect(app.path, '/lock');
    expect(cancel, findsOneWidget);

    await tester.binding.handlePopRoute();
    await pumpFrames(tester);
    expect(app.container.read(appSessionProvider).locked, isFalse);
    expect(app.path, '/settings');
    expect(app.lock.pinSet, isFalse);
    _expectRowSays(_en.commonOff);
  });

  // On a phone with biometrics, the setup Settings opens does not offer
  // them: they would only unlock, as Cancel does, and turn nothing on. The
  // lock the app engages by itself still does.
  testWidgets('with biometrics, the setup Settings opens offers the PIN and a way back, not biometrics',
      (tester) async {
    final app = await _openSettings(tester, biometrics: const _Biometrics());
    await pumpFrames(tester);

    await tester.tap(find.byKey(const ValueKey('settings-lock-now')));
    await pumpFrames(tester);
    expect(app.path, '/lock');
    expect(find.text(_en.appLockTurnOn), findsOneWidget);
    expect(cancel, findsOneWidget);
    expect(find.text(_en.appLockUseBiometrics, skipOffstage: false), findsNothing);

    await tester.tap(cancel);
    await pumpFrames(tester);
    expect(app.path, '/settings');

    app.session.lock();
    await pumpFrames(tester);
    expect(app.path, '/lock');
    expect(cancel, findsNothing);
    expect(find.text(_en.appLockUseBiometrics, skipOffstage: false), findsOneWidget);
  });

  testWidgets('the lock the app engages by itself keeps its first-PIN setup without a way back', (tester) async {
    final app = await _openSettings(tester);
    await pumpFrames(tester);

    // What going to the background does.
    app.session.lock();
    await pumpFrames(tester);
    expect(app.path, '/lock');
    expect(find.text(_en.appLockTurnOn), findsOneWidget);
    expect(cancel, findsNothing);
    expect(find.byType(VeilBackButton), findsNothing);

    await tester.binding.handlePopRoute();
    await pumpFrames(tester);
    expect(app.container.read(appSessionProvider).locked, isTrue);
    expect(app.path, '/lock');
  });

  testWidgets('once a PIN exists, Lock now opens the lock screen with no way back', (tester) async {
    final app = await _openSettings(tester);
    app.lock.pinSet = true;
    await pumpFrames(tester);
    _expectRowSays(_en.commonOn);

    await tester.tap(find.byKey(const ValueKey('settings-lock-now')));
    await pumpFrames(tester);
    expect(app.path, '/lock');
    expect(find.text(_en.appLockLockedTitle), findsOneWidget);
    expect(cancel, findsNothing);
    expect(find.byType(VeilBackButton), findsNothing);

    await tester.binding.handlePopRoute();
    await pumpFrames(tester);
    expect(app.container.read(appSessionProvider).locked, isTrue);
    expect(app.path, '/lock');
  });

  testWidgets('a lock from elsewhere (the app went to the background) is followed on Settings as well',
      (tester) async {
    usePhoneView(tester, phoneLarge);
    final storage = SecureStorageService(MemorySecureStore());
    final lock = _Lock(storage);
    final container = _container(lock, storage);
    addTearDown(container.dispose);
    // Settings without the router, so it stays on screen through the lock:
    // the row must not rely on being built again.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: VeilTheme.light(fontFamily: layoutFontFamily),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    ));
    await pumpFrames(tester);
    _expectRowSays(_en.commonOff);

    final session = container.read(appSessionProvider.notifier);
    session.lock();
    await pumpFrames(tester, frames: 2);
    // The lock screen has a PIN chosen, then unlocks.
    await lock.setPin('482916');
    session.unlock();
    await pumpFrames(tester);
    _expectRowSays(_en.commonOn);
  });
}
