import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/security/platform_security_service.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_error_text.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../attachments/presentation/save_media.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/conversation_peer_bindings.dart';
import '../../conversations/presentation/peer_names.dart';
import 'active_conversation_binding.dart';
import 'chat_composer_bar.dart';
import 'chat_message_list.dart';
import 'chat_message_search.dart';
import 'chat_phone_layout.dart';
import 'chat_request_actions.dart';
import 'chat_room_dialogs.dart';
import 'chat_room_labels.dart';
import 'chat_safety_menu.dart';
import 'chat_search_bar.dart';
import 'chat_status_banners.dart';
import 'chat_trust_notice.dart';
import 'disappearing_timer_sheet.dart';
import 'group_sender_names.dart';
import 'message_expiration.dart';
import 'message_time.dart';
import 'navigation_target_jump.dart';
import 'presence_selector.dart';
import 'typing_indicator.dart';

// These were declared here before the screen was split up.
export 'chat_room_labels.dart' show messageBubbleSemanticsLabel, messageDeliveryLabel, messageDeliveryTone;

/// A chat. On a phone it is a screen of its own; [embedded], it is the
/// second pane of the wide layout, beside the conversation list. Both show
/// the same thing (see ChatPhoneScaffold).
class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.conversationId,
    this.embedded = false,
    this.navigationTarget,
  });

  final String conversationId;
  final bool embedded;
  final MessageNavigationTarget? navigationTarget;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen>
    with
        WidgetsBindingObserver,
        ActiveConversationBinding,
        ChatMessageSearch,
        NavigationTargetJump,
        GroupSenderNames,
        ChatSafetyMenu,
        ChatRequestActions,
        ChatTrustNotices {
  final _composerFocusNode = FocusNode();
  final _scrollController = ScrollController();
  StreamSubscription<PlatformSecurityEvent>? _securityEventSub;
  Duration? _messageTtl;
  int? _observedConversationTimer;
  // Whether every pinned device of the 1:1 peer was verified out of band,
  // for the mark under the header; read again after the safety numbers and
  // whenever a question about who the peer is has been settled.
  bool _peerVerified = false;
  bool _peerInQuestion = false;
  // Whether the last fetch of this chat's history failed.
  bool _loadFailed = false;

  @override
  String get conversationId => widget.conversationId;

  @override
  MessageNavigationTarget? get navigationTarget => widget.navigationTarget;

  @override
  ScrollController get messageScrollController => _scrollController;

  @override
  List<String> get shownMessageIds {
    final controller = ref.read(messengerControllerProvider);
    final shown = _filteredMessages(controller.messagesFor(widget.conversationId), now: controller.expiryNow());
    return [for (final message in shown) message.id];
  }

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() => _loadConversationState());
    _securityEventSub = ref
        .read(platformSecurityServiceProvider)
        .events
        .listen(_handlePlatformSecurityEvent);
  }

  // A screenshot of the chat is a line in it on both sides, as Telegram and
  // Session do it: "@sam took a screenshot" for the others, "You took a
  // screenshot" here. The haptic is the only other sign; in a request, the only one.
  void _handlePlatformSecurityEvent(PlatformSecurityEvent event) {
    if (!mounted) return;
    if (event == PlatformSecurityEvent.screenshotDetected) {
      final l10n = AppLocalizations.of(context);
      final handle = ref.read(appSessionProvider).handle ?? '';
      VeilHaptics.heavy();
      if (inRequest) return;
      unawaited(
        ref.read(messengerControllerProvider).sendSystemNotice(
              conversationId: widget.conversationId,
              body: l10n.chatScreenshotSystemNotice(handle),
            ),
      );
    }
  }

  @override
  void showSearchHit(String messageId) => unawaited(scrollToMessage(messageId));

  @override
  void didUpdateWidget(covariant ChatRoomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      switchConversation(oldWidget.conversationId);
      resetNavigationTarget();
      resetSearch();
      _loadFailed = false;
      resetTrustNotices();
      scheduleMicrotask(() => _loadConversationState());
    }
    if (oldWidget.navigationTarget?.requestId != widget.navigationTarget?.requestId ||
        oldWidget.navigationTarget?.messageId != widget.navigationTarget?.messageId) {
      scheduleMicrotask(jumpToNavigationTarget);
    }
  }

  @override
  void dispose() {
    _securityEventSub?.cancel();
    _composerFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickDisappearTtl() async {
    VeilHaptics.selection();
    final choice = await showDisappearingTimerSheet(context, current: () => _messageTtl);
    if (!mounted || choice == null) return;
    final nextTtl = choice.ttl;
    setState(() => _messageTtl = nextTtl);
    try {
      await ref.read(messengerControllerProvider).setDisappearingTimer(
            widget.conversationId,
            nextTtl?.inSeconds,
          );
    } catch (_) {
      // Controller already surfaces the error through errorMessage.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.watch(messengerControllerProvider);
    final names = ref.watch(peerNamesProvider);
    ConversationPreview? conversation;
    for (final item in controller.conversations) {
      if (item.id == widget.conversationId) {
        conversation = item;
        break;
      }
    }
    // Keep the composer TTL in sync with the conversation's default so the
    // header shows the current setting when navigating in/out or when another
    // device changes it via realtime.
    final conversationTimer = conversation?.disappearingTimerSeconds;
    if (_observedConversationTimer != conversationTimer) {
      _observedConversationTimer = conversationTimer;
      _messageTtl = conversationTimer == null
          ? null
          : Duration(seconds: conversationTimer);
    }
    final messages = controller.messagesFor(widget.conversationId);
    final filteredMessages = _filteredMessages(messages, now: controller.expiryNow());
    final hasMoreHistory = controller.hasMoreHistoryFor(widget.conversationId);
    final isLoadingHistory =
        controller.isLoadingHistoryFor(widget.conversationId);

    // Read when the chat opened; a change that arrives later, in this chat
    // or in any other with the peer, takes the mark away at once, before
    // anything is read again. Once it is settled the pins are read again.
    final peerInQuestion = controller.peerIdentityInQuestion(widget.conversationId);
    if (_peerInQuestion && !peerInQuestion) scheduleMicrotask(_loadPeerVerified);
    _peerInQuestion = peerInQuestion;
    final peerVerified = _peerVerified && !peerInQuestion;

    final isDirect = conversation?.type == ConversationType.direct;
    final title = conversation == null
        ? l10n.chatTitleFallback
        : conversationTitle(l10n, conversation, names, localUserId: controller.localUserId);
    // A group message this device can attribute to none of the members
    // says so, once the members' devices have been read.
    final String? Function(ChatMessage)? groupMemberName = isDirect
        ? null
        : (message) => groupSenderName(message, names) ?? (groupSenderNamesRead ? l10n.chatGroupUnknownSender : null);
    syncGroupSenderNames(conversation, messages);
    // A failure while the chat is open is a toast, as in Signal; a history
    // that could not load says so in the message area instead.
    ref.listen<String?>(messengerControllerProvider.select((messenger) => messenger.errorMessage), (previous, next) {
      final messenger = ref.read(messengerControllerProvider);
      if (next == null || next == previous || messenger.errorIsRelayInterruption) return;
      if (_loadFailed && messenger.messagesFor(widget.conversationId).isEmpty) return;
      showVeilToast(context, veilErrorText(AppLocalizations.of(context), next));
    });

    final otherNotices = ChatStatusBanners.showsIdentityNotice(controller, widget.conversationId, conversation);
    final trustNotice = trustNoticeFor(conversation, messages, otherNotices: otherNotices);
    final banners = ChatStatusBanners(
      controller: controller,
      conversationId: widget.conversationId,
      conversation: conversation,
      onReviewIdentity: _openSafetyNumbers,
      onAcknowledgeHold: _acknowledgePeerAccount,
      trustNotice: trustNotice,
      onVerify: () => unawaited(verifyFromTrustNotice(conversation, then: _loadPeerVerified)),
    );
    ChatMessageList messageList(double sideRoom) => ChatMessageList(
      conversationId: widget.conversationId,
      controller: controller,
      messages: messages,
      filteredMessages: filteredMessages,
      hasMoreHistory: hasMoreHistory,
      isLoadingHistory: isLoadingHistory,
      hasSearchQuery: hasSearchQuery,
      scrollController: _scrollController,
      messageKeys: messageKeys,
      highlightedMessageId: currentSearchHit ?? highlightedMessageId,
      sentAtFormat: MessageTimeFormat.of(context),
      loadFailed: _loadFailed,
      onRetryLoad: () => unawaited(_loadConversationState()),
      searchQuery: hasSearchQuery ? searchController.text : null,
      senderNameOf: groupMemberName,
      authorNameOf: groupMemberName ?? (_) => title,
      senderHandleOf: isDirect ? null : groupSenderHandle,
      // Asked here, above the shell, whose body no longer sees the keyboard.
      keyboardUp: MediaQuery.viewInsetsOf(context).bottom > 0,
      onReact: _showReactionPicker,
      padding: const EdgeInsets.symmetric(horizontal: VeilSpace.sm, vertical: VeilSpace.sm),
      sideRoom: sideRoom,
      unreadDivider: unreadDivider,
    );
    final typing = PresenceSelector<(String?, String?)>(
      presence: controller.presenceTyping,
      select: (presence) =>
          (presence.typingHandleFor(widget.conversationId), presence.typingUserIdFor(widget.conversationId)),
      builder: (context, typist) {
        final (handle, userId) = typist;
        if (handle == null || isDirect || conversation == null) return TypingIndicator(handle: handle);
        // In a group, by its name; an account the group does not list is
        // no member typing, and shows nothing.
        final name = typingMemberTitle(conversation, handle, names, userId: userId ?? '');
        return TypingIndicator(handle: name == null ? null : handle, name: name);
      },
    );

    // The same chat on a phone and in the wide layout's second pane. The
    // messages keep to the chat's column; the unread band runs past it to
    // the edges of a wider screen or pane.
    final column = widget.embedded ? ChatPhoneScaffold.paneContentWidth : ChatPhoneScaffold.screenContentWidth;
    return LayoutBuilder(builder: (context, constraints) {
      final room = constraints.hasBoundedWidth ? (constraints.maxWidth - column) / 2 : 0.0;
      final sideRoom = room > 0 ? room : 0.0;
      return ChatPhoneScaffold(
        pane: widget.embedded,
        conversation: conversation,
        title: title,
        connecting: !controller.realtimeConnected,
        peerVerified: peerVerified,
        messageTtl: _messageTtl,
        searchController: searchController,
        searching: isSearchingMessages,
        menu: chatMenuEntries(conversation, onPickTimer: _pickDisappearTtl),
        onOpenSafetyNumbers: _openSafetyNumbers,
        banners: banners,
        messages: messageList(sideRoom),
        typing: typing,
        composer: blockedComposer(conversation) ??
            requestComposer(conversation, plainAccept: trustNotice?.warns ?? false) ??
            ChatComposerBar(
              conversationId: widget.conversationId,
              focusNode: _composerFocusNode,
              messageTtl: _messageTtl,
              busy: controller.isBusy,
            ),
        searchBar: ChatSearchBar(
          hasQuery: hasSearchQuery,
          searching: isSearchingMessages,
          count: searchHitCount,
          index: searchHitIndex,
          onOlder: showOlderSearchHit,
          onNewer: showNewerSearchHit,
        ),
      );
    });
  }

  // Hidden once expired on the messenger's expiry clock, as the messenger
  // retires them, never on the device clock.
  List<ChatMessage> _filteredMessages(List<ChatMessage> messages, {required DateTime now}) {
    return messages.where((message) => !isMessageExpired(message.expiresAt, now: now)).toList();
  }

  Future<void> _loadConversationState() async {
    final controller = ref.read(messengerControllerProvider);
    syncActiveConversation();
    unawaited(_loadPeerVerified());
    final conversationId = widget.conversationId;
    await controller.loadConversationMessages(conversationId);
    // The load reports its failure as the messenger's error line; with
    // nothing on screen yet, the message area says so and offers to retry.
    final failed = controller.errorMessage != null && !controller.errorIsRelayInterruption;
    if (mounted && conversationId == widget.conversationId && failed != _loadFailed) {
      setState(() => _loadFailed = failed);
    }
    if (hasSearchQuery) {
      await runSearch();
    }
    await jumpToNavigationTarget();
  }

  Future<void> _loadPeerVerified() async {
    final conversationId = widget.conversationId;
    final verified = await ref.read(messengerControllerProvider).isPeerVerified(conversationId);
    if (mounted && conversationId == widget.conversationId && verified != _peerVerified) {
      setState(() => _peerVerified = verified);
    }
  }

  Future<void> _openSafetyNumbers() async {
    await context.push('/safety-numbers/${widget.conversationId}');
    if (mounted) await _loadPeerVerified();
  }

  // Binds the held 1:1 to the account it is listed with. Another account
  // under the user's own handle is something no honest relay lists, so that
  // one is confirmed first, as the web client confirms every hold.
  Future<void> _acknowledgePeerAccount(PeerAccountHold hold, String handle) async {
    if (hold.reason == PeerAccountHoldReason.ownHandle) {
      final confirmed = await confirmOwnHandleHold(context, handle);
      if (!confirmed || !mounted) return;
    }
    await ref.read(messengerControllerProvider).acknowledgePeerAccount(widget.conversationId);
  }

  Future<void> _showReactionPicker(ChatMessage message, Rect anchor) async {
    final controller = ref.read(messengerControllerProvider);
    final decrypted = await controller.decryptMessage(message);
    if (!mounted || (decrypted.isOk && decrypted.messageKind == MessageKind.system)) {
      return;
    }
    final conversation = controller.conversationById(widget.conversationId);
    // A message that did not open can still be reported, by who sent it;
    // only one that opened takes a reaction: not from someone blocked, nor in a request.
    final canReact = decrypted.isOk && !peerBlocked(conversation) && !inRequest;
    final report = messageReport(message, conversation,
        groupSenderUserId: groupSenderUserId,
        groupSenderHandle: groupSenderHandle,
        groupSenderTitle: (message) => groupSenderName(message, ref.read(peerNamesProvider)));
    // A photo or file that opened is saved from here too (D30).
    final save =
        mediaSaveAction(context, ref, conversationId: widget.conversationId, message: message, decrypted: decrypted);
    if (!canReact && report == null && save == null) return;
    VeilHaptics.selection();
    // The message list on screen, so a menu that shows alone keeps clear of
    // what is under the list.
    final list = _scrollController.hasClients ? _scrollController.position.context.notificationContext : null;
    final box = list?.findRenderObject();
    await showMessageActions(
      context,
      anchor: anchor,
      isMine: message.isMine,
      onSelected: canReact ? (emoji) => controller.toggleReaction(message, emoji) : null,
      onReport: report,
      onSave: save,
      messages: box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null,
    );
  }
}
