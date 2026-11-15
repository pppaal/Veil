import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/security/platform_security_service.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../attachments/attachments_feature.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/messenger/conversation_peer_bindings.dart';
import '../../conversations/data/veil_messenger_controller.dart';
import 'active_conversation_binding.dart';
import 'chat_composer_bar.dart';
import 'chat_header.dart';
import 'chat_message_list.dart';
import 'chat_message_search.dart';
import 'chat_phone_layout.dart';
import 'chat_room_dialogs.dart';
import 'chat_status_banners.dart';
import 'disappearing_timer_sheet.dart';
import 'message_expiration.dart';
import 'navigation_target_jump.dart';
import 'presence_selector.dart';
import 'typing_indicator.dart';

// These were declared here before the screen was split up.
export 'chat_room_labels.dart'
    show
        HistoryWindowBannerSpec,
        formatRetryCountdown,
        historyWindowBannerSpec,
        historyWindowLabel,
        messageBubbleSemanticsLabel,
        messageDeliveryLabel,
        messageDeliveryTone;

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
        NavigationTargetJump {
  final _composerFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _sentAtFormat = DateFormat('HH:mm');
  StreamSubscription<PlatformSecurityEvent>? _securityEventSub;
  Duration? _messageTtl;
  int? _observedConversationTimer;
  // Whether every pinned device of the 1:1 peer was verified out of band,
  // for the mark under the header; read again after the safety numbers and
  // whenever a question about who the peer is has been settled.
  bool _peerVerified = false;
  bool _peerInQuestion = false;

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

  void _handlePlatformSecurityEvent(PlatformSecurityEvent event) {
    if (!mounted) return;
    if (event == PlatformSecurityEvent.screenshotDetected) {
      final l10n = AppLocalizations.of(context);
      VeilHaptics.heavy();
      VeilToast.show(
        context,
        message: l10n.chatScreenshotToast,
        tone: VeilBannerTone.danger,
      );
      unawaited(
        ref.read(messengerControllerProvider).sendSystemNotice(
              conversationId: widget.conversationId,
              body: l10n.chatScreenshotSystemNotice,
            ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant ChatRoomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      releaseActiveConversation(oldWidget.conversationId);
      resetNavigationTarget();
      resetSearch();
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

    final banners = ChatStatusBanners(
      compact: !widget.embedded,
      controller: controller,
      conversationId: widget.conversationId,
      conversation: conversation,
      messages: messages,
      hasMoreHistory: hasMoreHistory,
      isLoadingHistory: isLoadingHistory,
      peerVerified: peerVerified,
      hasSearchQuery: hasSearchQuery,
      searching: isSearchingMessages,
      searchHitCount: filteredMessages.length,
      onReviewIdentity: _openSafetyNumbers,
      onAcknowledgeHold: _acknowledgePeerAccount,
      onRetryFailed: () => ref.read(messengerControllerProvider).retryPendingMessages(widget.conversationId),
    );
    final messageList = ChatMessageList(
      conversationId: widget.conversationId,
      controller: controller,
      messages: messages,
      filteredMessages: filteredMessages,
      hasMoreHistory: hasMoreHistory,
      isLoadingHistory: isLoadingHistory,
      hasSearchQuery: hasSearchQuery,
      scrollController: _scrollController,
      messageKeys: messageKeys,
      highlightedMessageId: highlightedMessageId,
      sentAtFormat: _sentAtFormat,
      onStartMessage: () => _composerFocusNode.requestFocus(),
      onResolveAttachment: _showAttachmentTicket,
      onReact: _showReactionPicker,
      padding: widget.embedded
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: VeilSpace.sm, vertical: VeilSpace.sm),
    );
    final typing = PresenceSelector<String?>(
      presence: controller.presenceTyping,
      select: (presence) => presence.typingHandleFor(widget.conversationId),
      builder: (context, handle) => TypingIndicator(handle: handle),
    );
    final composer = ChatComposerBar(
      conversationId: widget.conversationId,
      focusNode: _composerFocusNode,
      messageTtl: _messageTtl,
      busy: controller.isBusy,
      onAttach: widget.embedded || !kAttachmentsEnabled
          ? null
          : () => context.push('/attachment/${widget.conversationId}'),
    );

    // A phone shows the conversation first: the bar carries what the header
    // cards carry in the wide layout.
    if (!widget.embedded) {
      return ChatPhoneScaffold(
        conversation: conversation,
        presence: controller.presenceTyping,
        peerVerified: peerVerified,
        messageTtl: _messageTtl,
        searchController: searchController,
        searching: isSearchingMessages,
        onPickTimer: _pickDisappearTtl,
        onOpenSafetyNumbers: _openSafetyNumbers,
        banners: banners,
        messages: messageList,
        typing: typing,
        composer: composer,
      );
    }

    final peerUserId = conversation?.recipientBundle.userId;
    return Column(
      children: [
        PresenceSelector<bool>(
          presence: controller.presenceTyping,
          select: (presence) => peerUserId != null && presence.isUserOnline(peerUserId),
          builder: (context, peerOnline) => ChatHeader(
            title: conversation?.peerDisplayName ?? '@${conversation?.peerHandle ?? 'unknown'}',
            searchController: searchController,
            searching: isSearchingMessages,
            ttlLabel: disappearingTimerLabel(l10n, _messageTtl),
            ttlActive: _messageTtl != null,
            onTapTtl: _pickDisappearTtl,
            peerOnline: peerOnline,
          ),
        ),
        banners,
        const SizedBox(height: VeilSpace.md),
        Expanded(child: messageList),
        typing,
        const SizedBox(height: VeilSpace.md),
        composer,
      ],
    );
  }

  // Hidden once expired on the messenger's expiry clock, as the messenger
  // retires them, never on the device clock.
  List<ChatMessage> _filteredMessages(List<ChatMessage> messages, {required DateTime now}) {
    return searchMatches(messages
        .where((message) => !isMessageExpired(message.expiresAt, now: now))
        .toList());
  }

  Future<void> _loadConversationState() async {
    final controller = ref.read(messengerControllerProvider);
    syncActiveConversation();
    unawaited(_loadPeerVerified());
    await controller.loadConversationMessages(widget.conversationId);
    await _markLatestRemoteMessageRead(controller);
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

  Future<void> _markLatestRemoteMessageRead(
      VeilMessengerController controller) async {
    if (controller.activeConversationId != widget.conversationId) {
      return;
    }
    for (final message
        in controller.messagesFor(widget.conversationId).reversed) {
      if (!message.isMine) {
        await controller.markRead(message.id);
        break;
      }
    }
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

  Future<void> _showAttachmentTicket(String attachmentId) async {
    final url = await ref
        .read(messengerControllerProvider)
        .getAttachmentDownloadUrl(attachmentId);
    if (!mounted || url == null) {
      return;
    }
    await showAttachmentTicketDialog(context, url);
  }

  Future<void> _showReactionPicker(ChatMessage message) async {
    final controller = ref.read(messengerControllerProvider);
    final decrypted = await controller.decryptMessage(message);
    if (!mounted || !decrypted.isOk || decrypted.messageKind == MessageKind.system) {
      return;
    }
    VeilHaptics.selection();
    await showReactionPickerSheet(
      context,
      onSelected: (emoji) => controller.toggleReaction(message, emoji),
    );
  }
}
