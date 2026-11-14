import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/realtime/realtime_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

/// Two 1:1 conversations, neither with any history.
class _TwoChatsApi extends VeilApiClient {
  _TwoChatsApi() : super(baseUrl: 'http://relay.invalid/v1');

  Map<String, dynamic> _direct(String id, String peer) => {
        'id': id,
        'type': 'direct',
        'createdAt': DateTime.utc(2026, 4, 1).toIso8601String(),
        'members': [
          {'userId': 'user-atlas', 'handle': 'atlas', 'displayName': null},
          {'userId': 'user-$peer', 'handle': peer, 'displayName': null},
        ],
        'lastMessage': null,
        'disappearingTimerSeconds': null,
      };

  @override
  Future<Map<String, dynamic>> getConversations(String accessToken) async => {
        'items': [_direct('conv-selene', 'selene'), _direct('conv-lyra', 'lyra')],
      };

  @override
  Future<Map<String, dynamic>> getMessages(String accessToken, String conversationId,
          {String? cursor, int limit = 50}) async =>
      {'items': <Object?>[], 'nextCursor': null};
}

/// A connected socket whose events the test delivers.
class _RealtimeRelay extends RealtimeService {
  void Function(String event, dynamic payload)? _onEvent;

  @override
  void connect({
    required String baseUrl,
    required String accessToken,
    required void Function(String event, dynamic payload) onEvent,
    void Function(bool connected)? onConnectionChanged,
  }) {
    _onEvent = onEvent;
    onConnectionChanged?.call(true);
  }

  @override
  void disconnect() {}

  void typing(String conversationId, String handle) =>
      _onEvent!('typing.start', {'conversationId': conversationId, 'userId': 'user-$handle', 'handle': handle});
}

void main() {
  testWidgets('typing in another conversation causes zero ChatRoomScreen rebuilds', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final adapter = createDefaultCryptoAdapter();
    final realtime = _RealtimeRelay();
    final controller = VeilMessengerController(
      apiClient: _TwoChatsApi(),
      cryptoEngine: adapter.messaging,
      keyBundleCodec: adapter.keyBundles,
      envelopeCodec: adapter.envelopeCodec,
      sessionBootstrapper: adapter.sessions,
      realtimeService: realtime,
      cacheService: null,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await controller.applySession(const AppSessionState(
      accessToken: 'token-atlas',
      userId: 'user-atlas',
      deviceId: 'dev-atlas',
      handle: 'atlas',
      onboardingAccepted: true,
      locked: false,
      initializing: false,
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [messengerControllerProvider.overrideWith((ref) => controller)],
      child: MaterialApp(
        theme: VeilTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ChatRoomScreen(conversationId: 'conv-selene', embedded: true),
      ),
    ));
    await tester.pumpAndSettle();

    // Every build of the screen creates a new metric strip, so the same
    // instance after an event means the screen did not build again.
    VeilMetricStrip strip() => tester.widget<VeilMetricStrip>(find.byType(VeilMetricStrip));
    final before = strip();

    realtime.typing('conv-lyra', 'lyra');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.typingHandleFor('conv-lyra'), 'lyra', reason: 'the event was handled');
    expect(identical(strip(), before), isTrue, reason: 'typing elsewhere rebuilt the open chat');

    // Typing here shows, in the indicator alone.
    realtime.typing('conv-selene', 'selene');
    await tester.pump();
    expect(find.text('@selene is typing'), findsOneWidget);
    expect(identical(strip(), before), isTrue);

    // The probe does see a rebuild when the messenger itself changes.
    unawaited(controller.retryPendingMessages());
    await tester.pump();
    expect(identical(strip(), before), isFalse);

    // Both indicators clear by themselves.
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('@selene is typing'), findsNothing);
    expect(controller.typingHandleFor('conv-lyra'), isNull);
  });
}
