import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../conversations/data/veil_messenger_controller.dart';

/// Keeps a chat's conversation the messenger's active one only while the
/// user can actually see it: the app in the foreground and the chat's route
/// the current one. Auto read receipts and notification suppression follow
/// that flag, so it is handed back as soon as the chat stops being visible,
/// and when the chat goes away.
mixin ActiveConversationBinding<W extends ConsumerStatefulWidget>
    on ConsumerState<W>, WidgetsBindingObserver {
  // Controller this screen marked its conversation active on, so it can
  // hand the flag back when it stops being visible.
  VeilMessengerController? _activeOn;
  bool _appInForeground = true;

  /// The conversation the chat shows.
  String get conversationId;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appInForeground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
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
}
