import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/app/router/route_guard.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/security/app_lock_service.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/app_lock/presentation/app_lock_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

const _signedIn = AppSessionState(
  accessToken: 'access-1',
  refreshToken: 'refresh-1',
  userId: 'user-1',
  deviceId: 'device-1',
  handle: 'atlas',
  onboardingAccepted: true,
  privacyConsentAccepted: true,
  locked: false,
  initializing: false,
);

class _Harness {
  _Harness(this.container, this.session);

  final ProviderContainer container;
  final AppSessionController session;

  GoRouter get router => container.read(appRouterProvider);

  /// The top-most visible location, pushed pages included.
  Uri get location => router.state.uri;

  Future<void> unlockWithBiometrics(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Use biometrics'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Use biometrics'));
    await tester.pumpAndSettle();
  }
}

/// The real guard, refresh wiring and lock screen, with lightweight stand-ins
/// for screens that need the messenger stack.
List<RouteBase> _stubRoutes() {
  return [
    for (final path in const [
      '/splash',
      '/privacy-consent',
      '/onboarding',
      '/create-account',
      '/choose-handle',
      '/conversations',
      '/settings',
    ])
      GoRoute(path: path, builder: (_, __) => Scaffold(body: Text(path))),
    GoRoute(
      path: '/chat/:conversationId',
      builder: (_, state) =>
          Scaffold(body: Text('chat ${state.pathParameters['conversationId']}')),
    ),
    GoRoute(path: '/lock', builder: (_, __) => const AppLockScreen()),
  ];
}

Future<_Harness> _pumpApp(WidgetTester tester) async {
  final storage = SecureStorageService(_MemorySecureKeyValueStore());
  final session = AppSessionController(
    storage,
    _RefreshingApiClient(),
    createDefaultCryptoAdapter(),
  )..state = _signedIn;
  final container = ProviderContainer(
    overrides: [
      appSessionProvider.overrideWith((ref) => session),
      appRoutesProvider.overrideWithValue(_stubRoutes()),
      appLockServiceProvider.overrideWithValue(
        AppLockService(_BiometricAuthenticator(), storage),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: VeilTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: ref.watch(appRouterProvider),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(container, session);
}

void main() {
  group('app router', () {
    testWidgets('router instance identical across token refresh', (tester) async {
      final app = await _pumpApp(tester);
      app.router.go('/chat/conv-1');
      await tester.pumpAndSettle();
      final before = app.router;
      final routerInTree = GoRouter.of(tester.element(find.text('chat conv-1')));

      expect(await app.session.refreshSession(), 'access-2');
      await tester.pumpAndSettle();

      expect(app.container.read(appSessionProvider).accessToken, 'access-2');
      expect(app.router, same(before));
      expect(routerInTree, same(before));
      expect(GoRouter.of(tester.element(find.text('chat conv-1'))), same(before));
    });

    testWidgets('/chat/conv-1 survives token refresh', (tester) async {
      final app = await _pumpApp(tester);
      expect(app.location.path, '/conversations');
      // Pushed the way the conversation list opens a chat.
      app.router.push('/chat/conv-1');
      await tester.pumpAndSettle();

      await app.session.refreshSession();
      await tester.pumpAndSettle();

      expect(app.location.toString(), '/chat/conv-1');
      expect(find.text('chat conv-1'), findsOneWidget);
      expect(app.router.canPop(), isTrue, reason: 'the stack under the chat is intact');
    });

    testWidgets('unlock returns to previous location', (tester) async {
      final app = await _pumpApp(tester);
      app.router.go('/chat/conv-1');
      await tester.pumpAndSettle();

      app.session.lock();
      await tester.pumpAndSettle();

      expect(app.location.path, '/lock');
      expect(app.location.queryParameters['from'], '/chat/conv-1');
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.text('chat conv-1'), findsNothing);

      await app.unlockWithBiometrics(tester);

      expect(app.container.read(appSessionProvider).locked, isFalse);
      expect(app.location.toString(), '/chat/conv-1');
      expect(find.text('chat conv-1'), findsOneWidget);
    });

    testWidgets('unlock restores a pushed chat with the list beneath it', (tester) async {
      final app = await _pumpApp(tester);
      app.router.push('/chat/conv-1');
      await tester.pumpAndSettle();

      app.session.lock();
      await tester.pumpAndSettle();
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.text('chat conv-1'), findsNothing);

      await app.unlockWithBiometrics(tester);

      expect(app.location.toString(), '/chat/conv-1');
      expect(find.text('chat conv-1'), findsOneWidget);
      app.router.pop();
      await tester.pumpAndSettle();
      expect(app.location.toString(), '/conversations');
    });

    testWidgets('a destination requested while locked wins after unlock', (tester) async {
      final app = await _pumpApp(tester);
      app.router.go('/chat/conv-1');
      await tester.pumpAndSettle();
      app.session.lock();
      await tester.pumpAndSettle();

      // e.g. a notification tap while the barrier is up.
      app.router.go('/settings');
      await tester.pumpAndSettle();
      expect(app.location.queryParameters['from'], '/settings');

      await app.unlockWithBiometrics(tester);

      expect(app.location.toString(), '/settings');
    });

    testWidgets('signing out from a deep screen lands on account creation', (tester) async {
      final app = await _pumpApp(tester);
      app.router.go('/settings');
      await tester.pumpAndSettle();

      app.session.state = app.session.state.copyWith(accessToken: null);
      await tester.pumpAndSettle();

      expect(app.location.path, '/create-account');
    });

    testWidgets('a wipe while locked never resurfaces the old stack', (tester) async {
      final app = await _pumpApp(tester);
      app.router.push('/chat/conv-1');
      await tester.pumpAndSettle();
      app.session.lock();
      await tester.pumpAndSettle();

      app.session.state = app.session.state.copyWith(accessToken: null, locked: false);
      await tester.pumpAndSettle();

      expect(app.location.toString(), '/create-account');
      expect(find.text('chat conv-1'), findsNothing);
    });
  });

  group('RouteGuardState', () {
    test('token and error changes are not routing changes', () {
      final base = RouteGuardState.fromSession(_signedIn);

      expect(
        RouteGuardState.fromSession(
          _signedIn.copyWith(accessToken: 'access-2', refreshToken: 'refresh-2'),
        ),
        base,
      );
      expect(
        RouteGuardState.fromSession(_signedIn.copyWith(errorMessage: 'handle taken')),
        base,
      );
      expect(RouteGuardState.fromSession(_signedIn.copyWith(locked: true)), isNot(base));
    });
  });

  group('redirectFor', () {
    final signedIn = RouteGuardState.fromSession(_signedIn);
    final locked = RouteGuardState.fromSession(_signedIn.copyWith(locked: true));
    final signedOut = RouteGuardState.fromSession(
      const AppSessionState(
        onboardingAccepted: true,
        privacyConsentAccepted: true,
        locked: false,
        initializing: false,
      ),
    );

    String? redirect(RouteGuardState state, String location) =>
        redirectFor(state, Uri.parse(location));

    test('locking remembers the interrupted location', () {
      expect(redirect(locked, '/settings'), '/lock?from=%2Fsettings');
      expect(
        Uri.parse(redirect(locked, '/safety-numbers/c1?member=u2')!).queryParameters['from'],
        '/safety-numbers/c1?member=u2',
      );
      expect(redirect(locked, '/splash'), '/lock');
      expect(redirect(locked, '/lock?from=%2Fsettings'), isNull);
    });

    test('unlock follows only safe in-app return locations', () {
      expect(redirect(signedIn, '/lock?from=%2Fchat%2Fc1'), '/chat/c1');
      for (final unsafe in [
        '//evil.example/x',
        'https://evil.example/x',
        'chat/c1',
        '/lock',
        '/lock?from=%2Fchat',
        '/onboarding',
      ]) {
        expect(
          redirect(signedIn, Uri(path: '/lock', queryParameters: {'from': unsafe}).toString()),
          '/conversations',
          reason: unsafe,
        );
      }
      expect(redirect(signedIn, '/lock'), '/conversations');
    });

    test('unlock resumes the interrupted location only if none was requested', () {
      final interrupted = Uri.parse('/conversations');

      expect(resumesInterruptedLocation(Uri.parse('/lock'), interrupted), isTrue);
      expect(
        resumesInterruptedLocation(Uri.parse('/lock?from=%2Fconversations'), interrupted),
        isTrue,
      );
      expect(
        resumesInterruptedLocation(Uri.parse('/lock?from=%2Fsettings'), interrupted),
        isFalse,
      );
      expect(resumesInterruptedLocation(Uri.parse('/settings'), interrupted), isFalse);
    });

    test('a lock over a gate screen does not resume the gate', () {
      expect(resumesInterruptedLocation(Uri.parse('/lock'), Uri.parse('/splash')), isFalse);
      expect(
        resumesInterruptedLocation(Uri.parse('/lock'), Uri.parse('/privacy-consent')),
        isFalse,
      );
    });

    test('gates apply in order', () {
      final initializing = RouteGuardState.fromSession(const AppSessionState());
      final noConsent = RouteGuardState.fromSession(
        const AppSessionState(initializing: false, locked: false),
      );

      expect(redirect(initializing, '/chat/c1'), '/splash');
      expect(redirect(initializing, '/splash'), isNull);
      expect(redirect(noConsent, '/conversations'), '/privacy-consent');
      expect(redirect(signedOut, '/chat/c1'), '/create-account');
      expect(redirect(signedOut, '/device-transfer'), isNull);
      expect(redirect(signedIn, '/choose-handle'), '/conversations');
      expect(redirect(signedIn, '/chat/c1'), isNull);
    });
  });
}

class _RefreshingApiClient extends VeilApiClient {
  _RefreshingApiClient() : super(baseUrl: 'http://localhost:3000/v1');

  @override
  Future<Map<String, dynamic>> refreshAuth(String refreshToken) async {
    return {'accessToken': 'access-2', 'refreshToken': 'refresh-2'};
  }
}

class _BiometricAuthenticator implements LocalUnlockAuthenticator {
  @override
  Future<bool> authenticateBiometric() async => true;

  @override
  Future<bool> canUseBiometrics() async => true;
}

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete({required String key}) async => _values.remove(key);

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}
