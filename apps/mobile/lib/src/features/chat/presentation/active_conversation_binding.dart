import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../conversations/data/messenger/read_state_service.dart';
import '../../conversations/data/veil_messenger_controller.dart';

/// Keeps a chat's conversation the messenger's active one only while the
/// user can actually see it: the app in the foreground and the chat's route
/// the current one. What is active is read (ReadStateService: the read mark,
/// the read receipt, the notification) and raises no notification, so the
/// flag is handed back as soon as the chat stops being visible, and when the
/// chat goes away.
///
/// The chat's unread divider is taken here too, when the screen begins
/// showing a conversation and before it first becomes active (initState
/// runs before the first didChangeDependencies), so it says what was unread
/// before the chat was read. It stays while this screen shows the chat,
/// whatever covers it for a while (a sheet, the photo viewer, background);
/// a lock takes the chat off screen and unlock puts it back, and its
/// divider comes back with it. The next time the chat opens it is gone.
mixin ActiveConversationBinding<W extends ConsumerStatefulWidget>
    on ConsumerState<W>, WidgetsBindingObserver {
  // Controller this screen marked its conversation active on, so it can
  // hand the flag back when it stops being visible.
  VeilMessengerController? _activeOn;
  bool _appInForeground = true;
  // The read state the divider was taken from, and whether the session is
  // locked: neither can be asked for once the screen is being disposed.
  late ReadStateService _reads;
  late bool Function() _sessionLocked;

  /// The conversation the chat shows.
  String get conversationId;

  /// Where the unread messages started when this screen began showing the
  /// chat, if any were.
  UnreadDivider? get unreadDivider => _reads.dividerFor(conversationId, viewer: this);

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appInForeground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    final container = ProviderScope.containerOf(context, listen: false);
    _sessionLocked = () => container.exists(appSessionProvider) && container.read(appSessionProvider).locked;
    _reads = ref.read(messengerControllerProvider).reads..beginViewing(conversationId, viewer: this);
  }

  // Also runs when this route stops or starts being the current one, which
  // is what decides whether incoming messages count as seen.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncActiveConversation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
    syncActiveConversation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    releaseActiveConversation(conversationId);
    _reads.endViewing(conversationId, viewer: this, keep: _sessionLocked());
    super.dispose();
  }

  /// Marks [conversationId] active if the chat is visible, and hands the
  /// flag back if it is not.
  void syncActiveConversation() {
    if (!mounted) {
      return;
    }
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (!_appInForeground || !routeIsCurrent) {
      releaseActiveConversation(conversationId);
      return;
    }
    final controller = ref.read(messengerControllerProvider);
    controller.setActiveConversation(conversationId);
    _activeOn = controller;
  }

  /// Hands the flag back if [conversationId] still holds it, as when the
  /// chat switches to another conversation.
  void releaseActiveConversation(String conversationId) {
    final controller = _activeOn;
    if (controller != null && controller.activeConversationId == conversationId) {
      controller.setActiveConversation(null);
    }
    _activeOn = null;
  }

  /// The screen now shows [conversationId] in place of [previous]: the flag
  /// goes back, and the divider of the new one is taken before it is read.
  void switchConversation(String previous) {
    releaseActiveConversation(previous);
    _reads
      ..endViewing(previous, viewer: this)
      ..beginViewing(conversationId, viewer: this);
  }
}
