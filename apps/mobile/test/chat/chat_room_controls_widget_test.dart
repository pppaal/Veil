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
import 'package:veil_mobile/src/features/chat/presentation/chat_search_bar.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_status_banners.dart';
import 'package:veil_mobile/src/features/chat/presentation/disappearing_timer_sheet.dart';
import 'package:veil_mobile/src/features/chat/presentation/presence_selector.dart';
import 'package:veil_mobile/src/features/chat/presentation/send_button.dart';
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

  // A change of the peer's key that waits in a group they share.
  bool changeElsewhere = false;

  @override
  PendingIdentityChange? pendingIdentityChangeAbout(String userId) => changeElsewhere
      ? PendingIdentityChange(
          conversationId: 'conv-group',
          userId: userId,
          deviceId: 'device-peer',
          presentedKey: 'key-new',
          previousKey: 'key-old',
          requiresReverification: false,
        )
      : null;

  @override
  int pendingCountFor(String conversationId) => pending;

  @override
  DateTime? nextRetryAtForConversation(String conversationId) => null;

  @override
  bool get realtimeConnected => connected;

  @override
  String? get errorMessage => error;
}

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
  // What sits between a chat's bar and its messages, on a phone and in the
  // wide layout's pane alike: the warnings, each with its action inside its
  // banner, and nothing else.
  group('ChatStatusBanners', () {
    late _ScriptedMessenger messenger;
    var reviewed = 0;
    final acknowledged = <(PeerAccountHold, String)>[];

    setUp(() {
      messenger = _ScriptedMessenger();
      reviewed = 0;
      acknowledged.clear();
    });
    tearDown(() => messenger.dispose());

    Widget banners({ConversationType type = ConversationType.direct}) => _app(ChatStatusBanners(
          controller: messenger,
          conversationId: 'conv-1',
          conversation: _conversation(type),
          onReviewIdentity: () => reviewed++,
          onAcknowledgeHold: (hold, handle) => acknowledged.add((hold, handle)),
        ));

    // Signal's way: a failed send says so on its bubble, a queued one shows
    // its clock there, and the connection is the bar's subtitle.
    testWidgets('failed and queued sends raise no banner', (tester) async {
      messenger.pending = 2;
      await tester.pumpWidget(banners());
      expect(find.byType(VeilNotice), findsNothing);

      messenger.connected = false;
      await tester.pumpWidget(banners());
      expect(find.byType(VeilNotice), findsNothing);
      expect(tester.getSize(find.byType(ChatStatusBanners)).height, 0);
    });

    testWidgets('a quiet chat shows nothing: no metrics, no history window, no verified pill', (tester) async {
      await tester.pumpWidget(banners());

      expect(find.byType(VeilNotice), findsNothing);
      expect(find.text(l10n.chatPeerVerified), findsNothing, reason: 'the bar carries the verified mark');
      expect(tester.getSize(find.byType(ChatStatusBanners)).height, 0);
    });

    testWidgets('every decision is there, with its action inside its banner; an error is not', (tester) async {
      messenger
        ..error = 'keystore unavailable'
        ..pending = 1
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
      await tester.pumpWidget(banners());

      expect(find.byType(VeilNotice), findsNWidgets(2));
      expect(find.text(l10n.chatIdentityChangedTitle), findsOneWidget);
      expect(find.text(l10n.chatIdentityChangedBody), findsOneWidget);
      expect(find.text(l10n.chatAccountHoldOtherTitle), findsOneWidget);
      expect(find.text(l10n.chatAccountHoldOtherBody('selene')), findsOneWidget);
      // An error is the chat's toast, not a line above the messages.
      expect(find.text('keystore unavailable'), findsNothing);

      Finder inBanner(String title, String action) => find.descendant(
            of: find.widgetWithText(VeilNotice, title),
            matching: find.text(action),
          );
      await tester.tap(inBanner(l10n.chatIdentityChangedTitle, l10n.chatIdentityChangedReview));
      expect(reviewed, 1);
      await tester.tap(inBanner(l10n.chatAccountHoldOtherTitle, l10n.chatAccountHoldAcknowledge));
      expect(acknowledged.single.$1, same(messenger.hold));
      expect(acknowledged.single.$2, 'selene');
      for (final action in [
        l10n.chatIdentityChangedReview,
        l10n.chatAccountHoldAcknowledge,
      ]) {
        expect(tester.getSize(find.widgetWithText(TextButton, action)).height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('a group never pauses for a peer: no identity change or account hold', (tester) async {
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
      await tester.pumpWidget(banners(type: ConversationType.group));

      expect(find.byType(VeilNotice), findsNothing);
    });

    testWidgets('a change waiting in a group is one line and its Review', (tester) async {
      messenger.changeElsewhere = true;
      await tester.pumpWidget(banners());
      final notice = tester.widget<VeilNotice>(find.byType(VeilNotice));
      expect(notice.dense, isTrue);
      expect(notice.message, l10n.chatIdentityChangedElsewhereTitle);
      await tester.tap(find.text(l10n.chatIdentityChangedReview));
      expect(reviewed, 1);
    });
  });

  group('ChatSearchBar', () {
    Widget bar({bool hasQuery = true, bool searching = false, int count = 0, int index = -1}) => _app(ChatSearchBar(
          hasQuery: hasQuery,
          searching: searching,
          count: count,
          index: index,
          onOlder: () {},
          onNewer: () {},
        ));

    testWidgets('says which hit is shown, or that there is none, in the composer\'s place', (tester) async {
      await tester.pumpWidget(bar(searching: true));
      expect(find.text(l10n.chatSearchSearching), findsOneWidget);

      await tester.pumpWidget(bar());
      expect(find.text('No results'), findsOneWidget);

      await tester.pumpWidget(bar(count: 2, index: 1));
      expect(find.text('2 of 2'), findsOneWidget);
      IconButton arrow(IconData icon) => tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));
      expect(arrow(Icons.keyboard_arrow_up).onPressed, isNotNull, reason: 'an older hit');
      expect(arrow(Icons.keyboard_arrow_down).onPressed, isNull, reason: 'the newest is shown');
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

    testWidgets('shows an attach button only where the screen gives it somewhere to go', (tester) async {
      await tester.pumpWidget(composer());
      expect(find.byTooltip(l10n.chatAttachAction), findsNothing);
      // The composer has no padlock (design system 7.7): nothing before the draft.
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.text(l10n.chatComposeHint), findsOneWidget);

      var attached = 0;
      await tester.pumpWidget(_app(
        ChatComposerBar(
          conversationId: 'conv-1',
          focusNode: focusNode,
          messageTtl: null,
          busy: false,
          onAttach: () => attached++,
        ),
        messenger: messenger,
      ));
      await tester.tap(find.byTooltip(l10n.chatAttachAction));
      expect(attached, 1);
      expect(tester.getSize(find.byTooltip(l10n.chatAttachAction)).shortestSide, greaterThanOrEqualTo(44));
    });
    testWidgets('typing tells the peer; a send carries the timer and clears the draft', (tester) async {
      await tester.pumpWidget(composer(messageTtl: const Duration(minutes: 5)));
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(messenger.typing, isNotEmpty);
      expect(messenger.typing.toSet(), {'conv-1'});

      // The button slides in.
      await tester.pump(VeilMotion.fast);
      await tester.tap(find.byType(SendButton));
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
      expect(tester.widget<SendButton>(find.byType(SendButton)).onPressed, isNull, reason: 'no draft, no send button');
      expect(find.byIcon(Icons.arrow_upward), findsNothing);
      // With no draft the field takes the whole width (iMessage): the
      // button takes no room until there is something to send.
      expect(tester.getSize(find.byType(SendButton)).width, 0);
      final emptyField = tester.getRect(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(tester.widget<SendButton>(find.byType(SendButton)).onPressed, isNull, reason: 'blank is no draft');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(messenger.sent, isEmpty);
      expect(messenger.typing, isEmpty);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.pump(VeilMotion.fast);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget, reason: 'a draft shows the send button');
      expect(tester.getSize(find.byType(SendButton)), const Size.square(44));
      expect(tester.getRect(find.byType(TextField)).width, lessThan(emptyField.width),
          reason: 'the button slid in beside the field');

      await tester.pumpWidget(composer(busy: true));
      expect(tester.widget<SendButton>(find.byType(SendButton)).onPressed, isNull);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.byIcon(Icons.arrow_upward), findsNothing, reason: 'a disabled composer offers no send');
    });
  });

  group('disappearing timer', () {
    test('the label names the preset in force, or says it is off, or names any other timer', () {
      expect(disappearingTimerLabel(l10n, null), l10n.chatTtlDisabledLabel);
      expect(disappearingTimerLabel(l10n, const Duration(minutes: 5)), l10n.chatTtl5m);
      expect(disappearingTimerLabel(l10n, const Duration(days: 7)), l10n.chatTtl1w);
      expect(disappearingTimerLabel(l10n, const Duration(minutes: 7)), '7 minutes');
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
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(
        find.descendant(of: find.widgetWithText(ListTile, l10n.chatTtl1m), matching: find.byIcon(Icons.check)),
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

    testWidgets('the reaction bar closes on a pick and hands the emoji on', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(opener((context) => showMessageActions(
            context,
            anchor: const Rect.fromLTWH(0, 300, 360, 60),
            isMine: false,
            onSelected: picked.add,
          )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(ReactionPickerWidget), findsOneWidget);
      // No "more" button where nothing would open: with it the row was
      // wider than a 360 px phone.
      expect(find.byIcon(Icons.add), findsNothing);
      expect(tester.getSize(find.byType(ReactionPickerWidget)).width, lessThan(360 - 32));

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
