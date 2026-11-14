import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/realtime/realtime_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_composer_bar.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_dialogs.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_status_banners.dart';
import 'package:veil_mobile/src/features/chat/presentation/disappearing_timer_sheet.dart';
import 'package:veil_mobile/src/features/chat/presentation/gradient_send_button.dart';
import 'package:veil_mobile/src/features/chat/presentation/presence_selector.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/conversation_peer_bindings.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_change.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/presence_typing_service.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';
import 'package:veil_mobile/src/features/reactions/presentation/reaction_picker_widget.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations_en.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

// The controls around a chat's messages, one at a time.

final AppLocalizations l10n = AppLocalizationsEn();

class _Offline extends RealtimeService {
  @override
  void connect({
    required String baseUrl,
    required String accessToken,
    required void Function(String event, dynamic payload) onEvent,
    void Function(bool connected)? onConnectionChanged,
  }) {}

  @override
  void disconnect() {}

  @override
  void emit(String event, Map<String, dynamic> payload) {}
}

/// A messenger whose state the test sets, recording what the chat asks of it.
class _ScriptedMessenger extends VeilMessengerController {
  _ScriptedMessenger._(CryptoAdapter adapter)
      : super(
          apiClient: VeilApiClient(baseUrl: 'http://relay.invalid/v1'),
          cryptoEngine: adapter.messaging,
          keyBundleCodec: adapter.keyBundles,
          envelopeCodec: adapter.envelopeCodec,
          sessionBootstrapper: adapter.sessions,
          realtimeService: _Offline(),
          cacheService: null,
        );

  factory _ScriptedMessenger() => _ScriptedMessenger._(createDefaultCryptoAdapter());

  final typing = <String>[];
  final sent = <(String, String, Duration?)>[];
  PeerAccountHold? hold;
  PeerAccountHold? holdOnSend;
  PendingIdentityChange? identityChange;
  int pending = 0;
  bool connected = true;
  String? error;

  @override
  void notifyTyping(String conversationId) => typing.add(conversationId);

  @override
  Future<void> sendText({required String conversationId, required String body, Duration? disappearAfter}) async {
    sent.add((conversationId, body, disappearAfter));
    hold = holdOnSend ?? hold;
  }

  @override
  PeerAccountHold? peerAccountHoldFor(String conversationId) => hold;

  @override
  PendingIdentityChange? pendingIdentityChangeFor(String conversationId) => identityChange;

  @override
  int pendingCountFor(String conversationId) => pending;

  @override
  DateTime? nextRetryAtForConversation(String conversationId) => null;

  @override
  bool get realtimeConnected => connected;

  @override
  String? get errorMessage => error;
}

const _envelope = CryptoEnvelope(
  version: 'veil-envelope-v2',
  conversationId: 'conv-1',
  senderDeviceId: 'device-peer',
  recipientUserId: 'user-local',
  ciphertext: 'opaque',
  nonce: 'nonce',
  messageKind: MessageKind.text,
);

ChatMessage _message(String id, MessageDeliveryState state) => ChatMessage(
      id: id,
      senderDeviceId: 'device-local',
      sentAt: DateTime.utc(2026, 4, 1, 9),
      envelope: _envelope,
      deliveryState: state,
      isMine: true,
    );

ConversationPreview _conversation(ConversationType type) => ConversationPreview(
      id: 'conv-1',
      peerHandle: 'selene',
      peerDisplayName: 'Selene',
      recipientBundle: const KeyBundle(
        userId: 'user-peer',
        deviceId: 'device-peer',
        handle: 'selene',
        identityPublicKey: 'pub-peer',
        signedPrekeyBundle: 'bundle-peer',
      ),
      lastEnvelope: null,
      updatedAt: DateTime.utc(2026, 4, 1),
      type: type,
    );

Widget _app(Widget child, {VeilMessengerController? messenger}) {
  final app = MaterialApp(
    theme: VeilTheme.dark(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
  return ProviderScope(
    overrides: [if (messenger != null) messengerControllerProvider.overrideWith((ref) => messenger)],
    child: app,
  );
}

void main() {
  group('ChatStatusBanners', () {
    late _ScriptedMessenger messenger;
    var reviewed = 0;
    var retried = 0;
    final acknowledged = <(PeerAccountHold, String)>[];

    setUp(() {
      messenger = _ScriptedMessenger();
      reviewed = 0;
      retried = 0;
      acknowledged.clear();
    });
    tearDown(() => messenger.dispose());

    Widget banners({
      ConversationType type = ConversationType.direct,
      List<ChatMessage> messages = const [],
      bool hasMoreHistory = true,
      bool peerVerified = false,
      bool hasSearchQuery = false,
      bool searching = false,
      int searchHitCount = 0,
    }) =>
        _app(ChatStatusBanners(
          controller: messenger,
          conversationId: 'conv-1',
          conversation: _conversation(type),
          messages: messages,
          hasMoreHistory: hasMoreHistory,
          isLoadingHistory: false,
          peerVerified: peerVerified,
          hasSearchQuery: hasSearchQuery,
          searching: searching,
          searchHitCount: searchHitCount,
          onReviewIdentity: () => reviewed++,
          onAcknowledgeHold: (hold, handle) => acknowledged.add((hold, handle)),
          onRetryFailed: () => retried++,
        ));

    testWidgets('a failed send stalls delivery and offers to retry the failed sends', (tester) async {
      messenger.pending = 2;
      await tester.pumpWidget(banners(messages: [
        _message('m1', MessageDeliveryState.failed),
        _message('m2', MessageDeliveryState.pending),
      ]));

      expect(find.text(l10n.chatBannerDeliveryStalled), findsOneWidget);
      expect(find.text(l10n.chatBannerFailedSends(1)), findsOneWidget);
      await tester.tap(find.text(l10n.chatRetryFailedSendsAction));
      expect(retried, 1);
    });

    testWidgets('queued sends wait locally, and say so differently while the relay reconnects', (tester) async {
      messenger.pending = 1;
      final messages = [_message('m1', MessageDeliveryState.pending)];
      await tester.pumpWidget(banners(messages: messages));
      expect(find.text(l10n.chatBannerQueuedLocally), findsOneWidget);
      expect(find.text(l10n.chatBannerQueuedMessages(1)), findsOneWidget);
      expect(find.text(l10n.chatRetryFailedSendsAction), findsNothing);
      expect(find.text(l10n.chatMetricRelayLinked), findsOneWidget);

      messenger.connected = false;
      await tester.pumpWidget(banners(messages: [...messages]));
      expect(find.text(l10n.chatBannerRelayReconnecting), findsOneWidget);
      expect(find.text(l10n.chatNetworkRecoveryQueued(1, l10n.chatRetryResumes)), findsOneWidget);
      expect(find.text(l10n.chatMetricRelayRecovering), findsOneWidget);

      messenger.pending = 0;
      await tester.pumpWidget(banners(messages: [...messages]));
      expect(find.text(l10n.chatBannerRelayReconnecting), findsNothing);
    });

    testWidgets('a 1:1 shows its verified mark, an identity change and a held account, each with its action',
        (tester) async {
      messenger
        ..error = 'keystore unavailable'
        ..hold = const PeerAccountHold(
          PeerAccountHoldReason.otherAccount,
          known: ConversationPeer(userId: 'user-earlier', handle: 'selene'),
        )
        ..identityChange = const PendingIdentityChange(
          conversationId: 'conv-1',
          userId: 'user-peer',
          deviceId: 'device-peer',
          presentedKey: 'key-new',
          previousKey: 'key-old',
          requiresReverification: true,
        );
      await tester.pumpWidget(banners(peerVerified: true));

      expect(find.text(l10n.chatPeerVerified), findsOneWidget);
      expect(find.text(l10n.chatBannerConversationIssue), findsOneWidget);
      expect(find.text('keystore unavailable'), findsOneWidget);
      expect(find.text(l10n.chatIdentityChangedTitle), findsOneWidget);
      expect(find.text(l10n.chatAccountHoldOtherTitle), findsOneWidget);
      expect(find.text(l10n.chatAccountHoldOtherBody('selene')), findsOneWidget);

      await tester.tap(find.text(l10n.chatIdentityChangedReview));
      expect(reviewed, 1);
      await tester.tap(find.text(l10n.chatAccountHoldAcknowledge));
      expect(acknowledged.single.$1, same(messenger.hold));
      expect(acknowledged.single.$2, 'selene');
    });

    testWidgets('a group never pauses for a peer: no verified mark, identity change or account hold',
        (tester) async {
      messenger
        ..hold = const PeerAccountHold(PeerAccountHoldReason.unissuedHandle)
        ..identityChange = const PendingIdentityChange(
          conversationId: 'conv-1',
          userId: 'user-peer',
          deviceId: 'device-peer',
          presentedKey: 'key-new',
          previousKey: 'key-old',
          requiresReverification: true,
        );
      await tester.pumpWidget(banners(type: ConversationType.group, peerVerified: true));

      expect(find.text(l10n.chatPeerVerified), findsNothing);
      expect(find.text(l10n.chatIdentityChangedTitle), findsNothing);
      expect(find.text(l10n.chatAccountHoldUnissuedTitle), findsNothing);
      expect(find.byType(VeilMetricStrip), findsOneWidget);
    });

    testWidgets('a search reports its hits in place of the history window', (tester) async {
      final loaded = [_message('m1', MessageDeliveryState.read)];
      await tester.pumpWidget(banners(messages: loaded, hasMoreHistory: false));
      expect(find.text(l10n.chatBannerHistoryCompleteTitle), findsOneWidget);
      expect(find.text(l10n.chatMetricSearchIdle), findsOneWidget);
      expect(find.text(l10n.chatMetricHistoryComplete), findsOneWidget);

      await tester.pumpWidget(banners(messages: loaded, hasMoreHistory: false, hasSearchQuery: true, searching: true));
      expect(find.text(l10n.chatBannerHistoryCompleteTitle), findsNothing);
      expect(find.text(l10n.chatSearchBannerSearchingTitle), findsOneWidget);

      await tester.pumpWidget(banners(messages: loaded, hasSearchQuery: true));
      expect(find.text(l10n.chatSearchBannerEmptyBody), findsOneWidget);

      await tester.pumpWidget(banners(messages: loaded, hasSearchQuery: true, searchHitCount: 3));
      expect(find.text(l10n.chatSearchBannerResultBody(3)), findsOneWidget);
      expect(find.text(l10n.chatMetricSearchHits(3)), findsOneWidget);
    });
  });

  group('ChatComposerBar', () {
    late _ScriptedMessenger messenger;
    late FocusNode focusNode;

    setUp(() {
      messenger = _ScriptedMessenger();
      focusNode = FocusNode();
    });
    tearDown(() => focusNode.dispose());

    Widget composer({Duration? messageTtl, bool busy = false}) => _app(
          ChatComposerBar(conversationId: 'conv-1', focusNode: focusNode, messageTtl: messageTtl, busy: busy),
          messenger: messenger,
        );

    String draft(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).controller!.text;
    String? helper(WidgetTester tester) => tester.widget<VeilComposer>(find.byType(VeilComposer)).helper;

    testWidgets('typing tells the peer; a send carries the timer and clears the draft', (tester) async {
      await tester.pumpWidget(composer(messageTtl: const Duration(minutes: 5)));
      expect(helper(tester), l10n.chatComposerExpiryOn(l10n.chatDurationMinutes(5)));

      await tester.enterText(find.byType(TextField), 'hello');
      expect(messenger.typing, isNotEmpty);
      expect(messenger.typing.toSet(), {'conv-1'});

      await tester.tap(find.byType(GradientSendButton));
      await tester.pump();
      expect(messenger.sent, [('conv-1', 'hello', const Duration(minutes: 5))]);
      expect(draft(tester), isEmpty);
      await tester.pump(VeilMotion.fast);
    });

    testWidgets('a send the messenger holds back for review keeps the draft', (tester) async {
      messenger.holdOnSend = const PeerAccountHold(PeerAccountHoldReason.ownHandle);
      await tester.pumpWidget(composer());

      await tester.enterText(find.byType(TextField), 'wait for me');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(messenger.sent.single.$2, 'wait for me');
      expect(messenger.sent.single.$3, isNull);
      expect(draft(tester), 'wait for me');
      await tester.pump(VeilMotion.fast);
    });

    testWidgets('a blank draft sends nothing, and a busy messenger disables the composer', (tester) async {
      await tester.pumpWidget(composer());
      expect(helper(tester), l10n.chatComposerExpiryOff);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.byType(GradientSendButton));
      await tester.pump();
      expect(messenger.sent, isEmpty);
      expect(messenger.typing, isEmpty);

      await tester.pumpWidget(composer(busy: true));
      expect(tester.widget<GradientSendButton>(find.byType(GradientSendButton)).onPressed, isNull);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    });
  });

  group('disappearing timer', () {
    test('the label names the preset in force, or says it is off or custom', () {
      expect(disappearingTimerLabel(l10n, null), l10n.chatTtlDisabledLabel);
      expect(disappearingTimerLabel(l10n, const Duration(minutes: 5)), l10n.chatTtl5m);
      expect(disappearingTimerLabel(l10n, const Duration(minutes: 7)), l10n.chatTtlCustom);
    });

    testWidgets('the sheet marks the current timer and tells a dismissal from choosing Off', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final results = <({Duration? ttl})?>[];
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              results.add(await showDisappearingTimerSheet(context, current: () => const Duration(minutes: 1))),
          child: const Text('open'),
        ),
      )));

      Future<void> open() async {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }

      await open();
      expect(find.text(l10n.chatTtlSheetTitle), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(
        find.descendant(
            of: find.widgetWithText(ListTile, l10n.chatTtl1m), matching: find.byIcon(Icons.check_circle_rounded)),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(results, [null]);

      await open();
      await tester.tap(find.text(l10n.chatTtlOff));
      await tester.pumpAndSettle();
      expect(results.last, isNotNull);
      expect(results.last!.ttl, isNull);

      await open();
      await tester.tap(find.text(l10n.chatTtl1h));
      await tester.pumpAndSettle();
      expect(results.last!.ttl, const Duration(hours: 1));
    });
  });

  group('dialogs', () {
    Widget opener(Future<void> Function(BuildContext context) open) =>
        _app(Builder(builder: (context) => TextButton(onPressed: () => open(context), child: const Text('open'))));

    testWidgets('a download ticket is shown only as a summary, never as the URL', (tester) async {
      const url = 'https://blobs.example/attachments/0123456789abcdef?X-Amz-Signature=deadbeefsecret';
      await tester.pumpWidget(opener((context) => showAttachmentTicketDialog(context, url)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.chatAttachmentTicketTitle), findsOneWidget);
      expect(find.text(l10n.chatAttachmentTicketBody('blobs.example / ...456789abcdef')), findsOneWidget);
      expect(find.textContaining('deadbeefsecret'), findsNothing);
      expect(find.textContaining(url), findsNothing);

      await tester.tap(find.text(l10n.commonClose));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('the reaction sheet closes on a pick and hands the emoji on', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(opener((context) => showReactionPickerSheet(context, onSelected: picked.add)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(ReactionPickerWidget), findsOneWidget);

      await tester.tap(find.text('\u{1F525}'));
      await tester.pumpAndSettle();
      expect(picked, ['\u{1F525}']);
      expect(find.byType(ReactionPickerWidget), findsNothing);
    });

    testWidgets('another account under the user\'s own handle is confirmed only by the confirm button',
        (tester) async {
      final answers = <bool>[];
      await tester.pumpWidget(opener((context) async => answers.add(await confirmOwnHandleHold(context, 'atlas'))));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.chatAccountHoldOwnConfirmTitle('atlas')), findsOneWidget);
      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.chatAccountHoldAcknowledge));
      await tester.pumpAndSettle();

      expect(answers, [false, false, true]);
    });
  });

  testWidgets('PresenceSelector rebuilds only when the value it selects changes', (tester) async {
    final presence = PresenceTypingService(
      realtime: _Offline(),
      isConnected: () => true,
      typingIndicatorsEnabled: () => true,
    );
    addTearDown(presence.dispose);
    var builds = 0;
    await tester.pumpWidget(_app(PresenceSelector<String?>(
      presence: presence,
      select: (presence) => presence.typingHandleFor('conv-a'),
      builder: (context, handle) {
        builds++;
        return Text(handle ?? 'nobody');
      },
    )));
    expect(builds, 1);

    presence.typingStarted('conv-b', 'lyra');
    presence.presenceChanged('user-lyra', online: true);
    await tester.pump();
    expect(builds, 1, reason: 'typing elsewhere and presence select nothing here');

    presence.typingStarted('conv-a', 'selene');
    await tester.pump();
    expect(builds, 2);
    expect(find.text('selene'), findsOneWidget);

    presence.typingStopped('conv-a');
    await tester.pump();
    expect(builds, 3);
    expect(find.text('nobody'), findsOneWidget);

    // Lets the remaining typing timeout run out.
    await tester.pump(const Duration(seconds: 6));
  });
}
