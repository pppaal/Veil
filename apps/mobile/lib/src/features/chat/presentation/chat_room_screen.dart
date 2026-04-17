import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/security/platform_security_service.dart';
import '../../../core/security/sensitive_text_redactor.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/data/veil_messenger_controller.dart';
import '../../reactions/presentation/reaction_picker_widget.dart';
import 'message_expiration.dart';

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

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final _messageController = TextEditingController();
  final _searchController = TextEditingController();
  final _composerFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _sentAtFormat = DateFormat('HH:mm');
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  Timer? _searchDebounce;
  Timer? _highlightClearTimer;
  Timer? _expirationTicker;
  StreamSubscription<PlatformSecurityEvent>? _securityEventSub;
  Duration? _messageTtl;
  bool _isSearchingMessages = false;
  Set<String> _matchingMessageIds = <String>{};
  String? _highlightedMessageId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _messageController.addListener(_handleComposerChanged);
    scheduleMicrotask(() => _loadConversationState());
    _securityEventSub = ref
        .read(platformSecurityServiceProvider)
        .events
        .listen(_handlePlatformSecurityEvent);
  }

  void _handlePlatformSecurityEvent(PlatformSecurityEvent event) {
    if (!mounted) return;
    if (event == PlatformSecurityEvent.screenshotDetected) {
      HapticFeedback.heavyImpact();
      VeilToast.show(
        context,
        message:
            'Screenshot detected in this conversation. Veil cannot prevent it on this device — the other side has been notified.',
        tone: VeilBannerTone.danger,
      );
      unawaited(
        ref.read(messengerControllerProvider).sendSystemNotice(
              conversationId: widget.conversationId,
              body:
                  'Peer took a screenshot of this conversation on their device.',
            ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant ChatRoomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _matchingMessageIds = <String>{};
      _highlightedMessageId = null;
      _messageKeys.clear();
      _searchController.clear();
      scheduleMicrotask(() => _loadConversationState());
    }
    if (oldWidget.navigationTarget?.requestId != widget.navigationTarget?.requestId ||
        oldWidget.navigationTarget?.messageId != widget.navigationTarget?.messageId) {
      scheduleMicrotask(_jumpToNavigationTarget);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _highlightClearTimer?.cancel();
    _expirationTicker?.cancel();
    _securityEventSub?.cancel();
    _messageController.dispose();
    _searchController.dispose();
    _composerFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _ensureExpirationTicker(bool hasExpiringMessages) {
    if (hasExpiringMessages) {
      _expirationTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
      });
    } else {
      _expirationTicker?.cancel();
      _expirationTicker = null;
    }
  }

  Future<void> _pickDisappearTtl() async {
    HapticFeedback.selectionClick();
    final selected = await showModalBottomSheet<Duration?>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(VeilSpace.lg),
                child: Text(
                  'Disappearing messages',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              for (final option in _ttlOptions)
                ListTile(
                  leading: Icon(
                    _messageTtl == option.duration
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                  ),
                  title: Text(option.label),
                  subtitle: option.caption == null ? null : Text(option.caption!),
                  onTap: () =>
                      Navigator.of(sheetContext).pop<Duration?>(option.duration),
                ),
              const SizedBox(height: VeilSpace.sm),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    setState(() => _messageTtl = selected);
  }

  String _ttlLabel() {
    final current = _messageTtl;
    if (current == null) return 'Disappear off';
    for (final option in _ttlOptions) {
      if (option.duration == current) return option.label;
    }
    return 'Custom TTL';
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(messengerControllerProvider);
    ConversationPreview? conversation;
    for (final item in controller.conversations) {
      if (item.id == widget.conversationId) {
        conversation = item;
        break;
      }
    }
    final messages = controller.messagesFor(widget.conversationId);
    final filteredMessages = _filteredMessages(messages);
    final hasMoreHistory = controller.hasMoreHistoryFor(widget.conversationId);
    final isLoadingHistory =
        controller.isLoadingHistoryFor(widget.conversationId);
    final pendingCount = controller.pendingCountFor(widget.conversationId);
    final failedCount = messages.where((message) => message.hasFailed).length;
    final uploadingCount = messages
        .where((message) =>
            message.deliveryState == MessageDeliveryState.uploading)
        .length;
    final queuedCount = messages
        .where(
            (message) => message.deliveryState == MessageDeliveryState.pending)
        .length;
    final hasSearchQuery = _searchController.text.trim().isNotEmpty;
    final nextRetryAt = controller.nextRetryAtForConversation(widget.conversationId);
    final historyBanner = !hasSearchQuery && messages.isNotEmpty
        ? historyWindowBannerSpec(
            isLoadingHistory: isLoadingHistory,
            hasMoreHistory: hasMoreHistory,
          )
        : null;

    final content = Column(
      children: [
        _ChatHeader(
          embedded: widget.embedded,
          title: conversation?.peerDisplayName ??
              '@${conversation?.peerHandle ?? 'unknown'}',
          searchController: _searchController,
          searching: _isSearchingMessages,
          ttlLabel: _ttlLabel(),
          ttlActive: _messageTtl != null,
          onTapTtl: _pickDisappearTtl,
          peerOnline: conversation != null &&
              controller.isUserOnline(conversation.recipientBundle.userId),
        ),
        const SizedBox(height: VeilSpace.sm),
        VeilMetricStrip(
          items: [
            VeilMetricItem(
              label: 'Relay',
              value: controller.realtimeConnected ? 'Linked' : 'Recovering',
            ),
            VeilMetricItem(
              label: 'Loaded',
              value: '${messages.length}',
            ),
            VeilMetricItem(
              label: 'History',
              value: historyWindowLabel(
                isLoadingHistory: isLoadingHistory,
                hasMoreHistory: hasMoreHistory,
              ),
            ),
            VeilMetricItem(
              label: 'Search',
              value: hasSearchQuery ? '${filteredMessages.length} hits' : 'Idle',
            ),
          ],
        ),
        if (historyBanner != null) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: historyBanner.title,
            message: historyBanner.message,
            tone: historyBanner.tone,
            icon: historyBanner.icon,
          ),
        ],
        if (controller.errorMessage != null) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: 'Conversation issue',
            message: controller.errorMessage!,
            tone: VeilBannerTone.danger,
          ),
        ],
        if (pendingCount > 0) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: !controller.realtimeConnected
                ? 'Relay reconnecting'
                : failedCount > 0
                    ? 'Delivery stalled'
                    : 'Queued locally',
            message: !controller.realtimeConnected
                ? _networkRecoveryMessage(
                    failedCount: failedCount,
                    queuedCount: queuedCount,
                    uploadingCount: uploadingCount,
                    nextRetryAt: nextRetryAt,
                  )
                : failedCount > 0
                    ? '$failedCount message(s) failed to send. Retry when the relay is reachable.'
                    : uploadingCount > 0
                        ? '$uploadingCount attachment message(s) are uploading opaque blobs before send.'
                        : '$queuedCount message(s) are staged locally and will retry after reconnect.',
            tone: !controller.realtimeConnected
                ? VeilBannerTone.warn
                : failedCount > 0
                    ? VeilBannerTone.warn
                    : VeilBannerTone.info,
          ),
          if (failedCount > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: VeilSpace.xs),
                child: TextButton(
                  onPressed: () => ref
                      .read(messengerControllerProvider)
                      .retryPendingMessages(widget.conversationId),
                  child: const Text('Retry failed sends'),
                ),
              ),
            ),
        ],
        if (hasSearchQuery) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: _isSearchingMessages ? 'Searching locally' : 'Local message search',
            message: _isSearchingMessages
                ? 'Scanning cached message text on this device. Relay state does not change.'
                : filteredMessages.isEmpty
                    ? 'No cached message text matched this query in the current conversation.'
                    : 'Showing ${filteredMessages.length} cached match(es). Clear search to return to full conversation context.',
            tone: VeilBannerTone.info,
            icon: Icons.manage_search_rounded,
          ),
        ],
        const SizedBox(height: VeilSpace.md),
        Expanded(
          child: _buildMessageRegion(
            controller: controller,
            messages: messages,
            filteredMessages: filteredMessages,
            hasMoreHistory: hasMoreHistory,
            isLoadingHistory: isLoadingHistory,
            hasSearchQuery: hasSearchQuery,
          ),
        ),
        _TypingIndicator(
          handle: controller.typingHandleFor(widget.conversationId),
        ),
        const SizedBox(height: VeilSpace.md),
        VeilComposer(
          controller: _messageController,
          focusNode: _composerFocusNode,
          enabled: !controller.isBusy,
          onSubmit: _sendMessage,
          helper: _messageTtl == null
              ? 'This send does not expire unless you change the rule.'
              : 'This send expires in ${_formatDurationLabel(_messageTtl!)} on every device that sees it.',
          trailing: VeilButton(
            expanded: false,
            onPressed: controller.isBusy ? null : _sendMessage,
            label: controller.isBusy ? 'Sending' : 'Send',
            icon: Icons.arrow_upward_rounded,
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return content;
    }

    return VeilShell(
      title: conversation?.peerDisplayName ??
          conversation?.peerHandle ??
          'Secure conversation',
      actions: [
        IconButton(
          onPressed: () => context.push('/attachment/${widget.conversationId}'),
          icon: const Icon(Icons.attach_file),
        ),
      ],
      child: content,
    );
  }

  Widget _buildMessageRegion({
    required VeilMessengerController controller,
    required List<ChatMessage> messages,
    required List<ChatMessage> filteredMessages,
    required bool hasMoreHistory,
    required bool isLoadingHistory,
    required bool hasSearchQuery,
  }) {
    if (messages.isEmpty && controller.isBusy) {
      return const VeilLoadingBlock(
        title: 'Decrypting conversation state',
        body: 'Pulling the latest message envelopes from the relay.',
      );
    }

    if (messages.isEmpty) {
      return VeilEmptyState(
        title: 'No messages yet',
        body:
            'This conversation is open, but no encrypted envelopes have been sent yet.',
        icon: Icons.chat_bubble_outline_rounded,
        action: FilledButton.tonal(
          onPressed: () => _composerFocusNode.requestFocus(),
          child: const Text('Send first message'),
        ),
      );
    }

    if (hasSearchQuery && filteredMessages.isEmpty) {
      return const VeilEmptyState(
        title: 'No local matches',
        body:
            'This device did not find a matching cached message in the current conversation.',
        icon: Icons.search_off_rounded,
      );
    }

    final validIds = filteredMessages.map((message) => message.id).toSet();
    _messageKeys.removeWhere((messageId, _) => !validIds.contains(messageId));

    final useBottomAnchoredLayout =
        !hasSearchQuery && !hasMoreHistory && filteredMessages.length <= 6;

    if (useBottomAnchoredLayout) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            controller: _scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: _buildMessageEntries(
                  controller: controller,
                  filteredMessages: filteredMessages,
                  hasMoreHistory: hasMoreHistory,
                  isLoadingHistory: isLoadingHistory,
                  hasSearchQuery: hasSearchQuery,
                ),
              ),
            ),
          );
        },
      );
    }

    return ListView.separated(
      controller: _scrollController,
      key: PageStorageKey<String>('chat-${widget.conversationId}'),
      cacheExtent: 1200,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: filteredMessages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        return _buildMessageEntry(
          controller: controller,
          message: filteredMessages[index],
          index: index,
          filteredMessages: filteredMessages,
          hasMoreHistory: hasMoreHistory,
          isLoadingHistory: isLoadingHistory,
          hasSearchQuery: hasSearchQuery,
        );
      },
    );
  }

  List<Widget> _buildMessageEntries({
    required VeilMessengerController controller,
    required List<ChatMessage> filteredMessages,
    required bool hasMoreHistory,
    required bool isLoadingHistory,
    required bool hasSearchQuery,
  }) {
    return List<Widget>.generate(filteredMessages.length, (index) {
      return _buildMessageEntry(
        controller: controller,
        message: filteredMessages[index],
        index: index,
        filteredMessages: filteredMessages,
        hasMoreHistory: hasMoreHistory,
        isLoadingHistory: isLoadingHistory,
        hasSearchQuery: hasSearchQuery,
      );
    }, growable: false);
  }

  Widget _buildMessageEntry({
    required VeilMessengerController controller,
    required ChatMessage message,
    required int index,
    required List<ChatMessage> filteredMessages,
    required bool hasMoreHistory,
    required bool isLoadingHistory,
    required bool hasSearchQuery,
  }) {
    final showLoadOlder = index == 0 && hasMoreHistory && !hasSearchQuery;

    if (message.envelope.messageKind == MessageKind.system) {
      final systemNotice = _SystemNoticeBubble(
        message: message,
        decryptFuture: controller.decryptMessage(message),
      );
      final keyedNotice = RepaintBoundary(
        child: KeyedSubtree(
          key: _messageKeys.putIfAbsent(message.id, () => GlobalKey()),
          child: systemNotice,
        ),
      );
      if (!showLoadOlder) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: index == filteredMessages.length - 1 ? 0 : 12),
          child: keyedNotice,
        );
      }
      return Padding(
        padding: EdgeInsets.only(
            bottom: index == filteredMessages.length - 1 ? 0 : 12),
        child: Column(
          children: [
            VeilButton(
              onPressed: isLoadingHistory
                  ? null
                  : () => ref
                      .read(messengerControllerProvider)
                      .loadOlderConversationMessages(widget.conversationId),
              tone: VeilButtonTone.secondary,
              label: isLoadingHistory ? 'Loading older' : 'Load older',
            ),
            const SizedBox(height: VeilSpace.sm),
            keyedNotice,
          ],
        ),
      );
    }

    final bubble = _MessageBubble(
      message: message,
      highlighted: message.id == _highlightedMessageId,
      sentAtFormat: _sentAtFormat,
      decryptFuture: controller.decryptMessage(message),
      onResolveAttachment: _showAttachmentTicket,
      onReplyGesture: () => _handleReplyGesture(message),
      onCancelAttachment: message.clientMessageId == null
          ? null
          : () => ref
              .read(messengerControllerProvider)
              .cancelPendingAttachment(message.clientMessageId!),
      attachmentResolving: message.envelope.attachment != null &&
          controller.isResolvingAttachment(
              message.envelope.attachment!.attachmentId),
      attachmentDownloadError: message.envelope.attachment == null
          ? null
          : controller.attachmentDownloadError(
              message.envelope.attachment!.attachmentId),
      transferSnapshot: message.clientMessageId == null
          ? null
          : controller.attachmentTransferForMessage(message.clientMessageId!),
      onRetryMessage: message.hasFailed
          ? () => ref
              .read(messengerControllerProvider)
              .retryPendingMessages(widget.conversationId)
          : null,
    );
    final reactive = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => _showReactionPicker(message),
      child: bubble,
    );
    final bubbleWithReactions = message.reactions.isEmpty
        ? reactive
        : Column(
            crossAxisAlignment: message.isMine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              reactive,
              const SizedBox(height: VeilSpace.xs),
              _ReactionChipsRow(
                message: message,
                myUserId: ref.watch(appSessionProvider).userId,
                onChipTap: (emoji) => controller.toggleReaction(message, emoji),
              ),
            ],
          );
    final keyedBubble = RepaintBoundary(
      child: KeyedSubtree(
        key: _messageKeys.putIfAbsent(message.id, () => GlobalKey()),
        child: bubbleWithReactions,
      ),
    );

    if (!showLoadOlder) {
      return Padding(
        padding: EdgeInsets.only(bottom: index == filteredMessages.length - 1 ? 0 : 12),
        child: keyedBubble,
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: index == filteredMessages.length - 1 ? 0 : 12),
      child: Column(
        children: [
          VeilButton(
            onPressed: isLoadingHistory
                ? null
                : () => ref
                    .read(messengerControllerProvider)
                    .loadOlderConversationMessages(widget.conversationId),
            tone: VeilButtonTone.secondary,
            label: isLoadingHistory ? 'Loading older' : 'Load older',
          ),
          const SizedBox(height: VeilSpace.sm),
          keyedBubble,
        ],
      ),
    );
  }

  List<ChatMessage> _filteredMessages(List<ChatMessage> messages) {
    final now = DateTime.now();
    final visible = messages
        .where((message) => !isMessageExpired(message.expiresAt, now: now))
        .toList();
    final hasExpiring = visible.any((message) => message.expiresAt != null);
    scheduleMicrotask(() => _ensureExpirationTicker(hasExpiring));
    if (_searchController.text.trim().isEmpty) {
      return visible;
    }
    return visible
        .where((message) => _matchingMessageIds.contains(message.id))
        .toList();
  }

  Future<void> _loadConversationState() async {
    final controller = ref.read(messengerControllerProvider);
    controller.setActiveConversation(widget.conversationId);
    await controller.loadConversationMessages(widget.conversationId);
    await _markLatestRemoteMessageRead(controller);
    if (_searchController.text.trim().isNotEmpty) {
      await _runSearch();
    }
    await _jumpToNavigationTarget();
  }

  Future<void> _markLatestRemoteMessageRead(
      VeilMessengerController controller) async {
    for (final message
        in controller.messagesFor(widget.conversationId).reversed) {
      if (!message.isMine) {
        await controller.markRead(message.id);
        break;
      }
    }
  }

  void _handleSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(_runSearch()),
    );
  }

  void _handleComposerChanged() {
    if (_messageController.text.trim().isNotEmpty) {
      ref.read(messengerControllerProvider).notifyTyping(widget.conversationId);
    }
  }

  Future<void> _runSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _matchingMessageIds = <String>{};
        _isSearchingMessages = false;
      });
      return;
    }

    if (mounted) {
      setState(() => _isSearchingMessages = true);
    }

    final matches =
        await ref.read(messengerControllerProvider).searchLoadedMessageIds(
              widget.conversationId,
              query: query,
            );

    if (!mounted || _searchController.text.trim() != query) {
      return;
    }

    setState(() {
      _matchingMessageIds = matches.toSet();
      _isSearchingMessages = false;
    });
  }

  Future<void> _sendMessage() async {
    final body = _messageController.text.trim();
    if (body.isEmpty) {
      return;
    }

    await ref.read(messengerControllerProvider).sendText(
          conversationId: widget.conversationId,
          body: body,
          disappearAfter: _messageTtl,
        );
    _messageController.clear();
  }

  Future<void> _showAttachmentTicket(String attachmentId) async {
    final url = await ref
        .read(messengerControllerProvider)
        .getAttachmentDownloadUrl(attachmentId);
    if (!mounted || url == null) {
      return;
    }
    final ticketSummary = summarizeSensitiveUrl(url);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Attachment ticket ready'),
        content: Text(
          'A short-lived local download ticket was resolved for this device.\n\n'
          'Summary: $ticketSummary\n\n'
          'Copying and sharing the raw ticket is intentionally disabled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _handleReplyGesture(ChatMessage message) {
    HapticFeedback.lightImpact();
    _composerFocusNode.requestFocus();
    VeilToast.show(
      context,
      message: 'Composer primed for a quick response in this conversation.',
      tone: VeilBannerTone.info,
    );
  }

  Future<void> _jumpToNavigationTarget() async {
    final target = widget.navigationTarget;
    if (target == null || !mounted) {
      return;
    }

    final controller = ref.read(messengerControllerProvider);
    var attempts = 0;
    while (!controller.messagesFor(widget.conversationId).any((message) => message.id == target.messageId) &&
        controller.hasMoreHistoryFor(widget.conversationId) &&
        attempts < 4) {
      attempts += 1;
      await controller.loadOlderConversationMessages(widget.conversationId);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _highlightedMessageId = target.messageId;
    });

    await Future<void>.delayed(const Duration(milliseconds: 24));
    final targetContext = _messageKeys[target.messageId]?.currentContext;
    if (targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: VeilMotion.normal,
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
    }

    _highlightClearTimer?.cancel();
    _highlightClearTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _highlightedMessageId != target.messageId) {
        return;
      }
      setState(() => _highlightedMessageId = null);
    });
  }

  Future<void> _showReactionPicker(ChatMessage message) async {
    if (message.envelope.messageKind == MessageKind.system) {
      return;
    }
    HapticFeedback.selectionClick();
    final controller = ref.read(messengerControllerProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(VeilSpace.md),
            child: ReactionPickerWidget(
              onReactionSelected: (emoji) {
                Navigator.of(sheetContext).pop();
                controller.toggleReaction(message, emoji);
              },
            ),
          ),
        );
      },
    );
  }
}

String _networkRecoveryMessage({
  required int failedCount,
  required int queuedCount,
  required int uploadingCount,
  required DateTime? nextRetryAt,
}) {
  final retryLabel = nextRetryAt == null
      ? 'Retry resumes when the relay reconnects.'
      : 'Next retry in ${formatRetryCountdown(nextRetryAt)}.';
  if (failedCount > 0) {
    return '$failedCount message(s) are waiting on relay recovery. $retryLabel';
  }
  if (uploadingCount > 0) {
    return '$uploadingCount attachment message(s) are paused while the relay reconnects. $retryLabel';
  }
  return '$queuedCount message(s) remain queued on this device. $retryLabel';
}

String historyWindowLabel({
  required bool isLoadingHistory,
  required bool hasMoreHistory,
}) {
  if (isLoadingHistory) {
    return 'Loading older';
  }
  if (hasMoreHistory) {
    return 'Paged';
  }
  return 'Complete';
}

HistoryWindowBannerSpec? historyWindowBannerSpec({
  required bool isLoadingHistory,
  required bool hasMoreHistory,
}) {
  if (isLoadingHistory) {
    return const HistoryWindowBannerSpec(
      title: 'Syncing older history',
      message:
          'Pulling older encrypted history from the relay for this trusted device.',
      tone: VeilBannerTone.info,
      icon: Icons.history_toggle_off_rounded,
    );
  }
  if (!hasMoreHistory) {
    return const HistoryWindowBannerSpec(
      title: 'Conversation window complete',
      message:
          'The currently trusted device-local window is fully loaded. Older history is not pending right now.',
      tone: VeilBannerTone.info,
      icon: Icons.done_all_rounded,
    );
  }
  return null;
}

class HistoryWindowBannerSpec {
  const HistoryWindowBannerSpec({
    required this.title,
    required this.message,
    required this.tone,
    required this.icon,
  });

  final String title;
  final String message;
  final VeilBannerTone tone;
  final IconData icon;
}

String formatRetryCountdown(DateTime nextRetryAt) {
  final difference = nextRetryAt.difference(DateTime.now());
  if (difference.inSeconds <= 0) {
    return '0s';
  }
  if (difference.inSeconds < 60) {
    return '${difference.inSeconds}s';
  }
  final minutes = difference.inMinutes;
  final seconds = difference.inSeconds - (minutes * 60);
  if (seconds <= 0) {
    return '${minutes}m';
  }
  return '${minutes}m ${seconds}s';
}

String messageDeliveryLabel(ChatMessage message) {
  switch (message.deliveryState) {
    case MessageDeliveryState.pending:
      return 'Queued';
    case MessageDeliveryState.uploading:
      return 'Uploading';
    case MessageDeliveryState.failed:
      return 'Retry required';
    case MessageDeliveryState.sent:
      return 'Sent';
    case MessageDeliveryState.delivered:
      return 'Delivered';
    case MessageDeliveryState.read:
      return 'Read';
  }
}

VeilBannerTone messageDeliveryTone(ChatMessage message) {
  switch (message.deliveryState) {
    case MessageDeliveryState.pending:
    case MessageDeliveryState.uploading:
      return VeilBannerTone.warn;
    case MessageDeliveryState.failed:
      return VeilBannerTone.danger;
    case MessageDeliveryState.sent:
      return VeilBannerTone.info;
    case MessageDeliveryState.delivered:
    case MessageDeliveryState.read:
      return VeilBannerTone.good;
  }
}

String messageBubbleSemanticsLabel(ChatMessage message) {
  final direction = message.isMine ? 'Sent' : 'Received';
  final stateSegment = message.isMine ? ' ${messageDeliveryLabel(message)}.' : '';
  return '$direction message bubble.$stateSegment';
}

class _TtlOption {
  const _TtlOption({required this.label, required this.duration, this.caption});

  final String label;
  final Duration? duration;
  final String? caption;
}

const List<_TtlOption> _ttlOptions = <_TtlOption>[
  _TtlOption(
    label: 'Off',
    duration: null,
    caption: 'Messages remain until manually deleted.',
  ),
  _TtlOption(
    label: '10 seconds',
    duration: Duration(seconds: 10),
    caption: 'Strongest ephemerality. Expect the recipient to be looking.',
  ),
  _TtlOption(
    label: '1 minute',
    duration: Duration(minutes: 1),
  ),
  _TtlOption(
    label: '5 minutes',
    duration: Duration(minutes: 5),
  ),
  _TtlOption(
    label: '1 hour',
    duration: Duration(hours: 1),
  ),
  _TtlOption(
    label: '1 day',
    duration: Duration(days: 1),
    caption: 'Default for casual private conversations.',
  ),
];

String _formatDurationLabel(Duration duration) {
  if (duration.inDays > 0) return '${duration.inDays} day(s)';
  if (duration.inHours > 0) return '${duration.inHours} hour(s)';
  if (duration.inMinutes > 0) return '${duration.inMinutes} minute(s)';
  return '${duration.inSeconds} second(s)';
}

IconData _attachmentIcon(String contentType) {
  if (contentType.startsWith('image/')) return Icons.image_rounded;
  if (contentType.startsWith('video/')) return Icons.videocam_rounded;
  if (contentType.startsWith('audio/')) return Icons.audiotrack_rounded;
  if (contentType.contains('pdf')) return Icons.picture_as_pdf_rounded;
  return Icons.insert_drive_file_rounded;
}

String _attachmentLabel(String contentType) {
  if (contentType.startsWith('image/')) return 'Encrypted image';
  if (contentType.startsWith('video/')) return 'Encrypted video';
  if (contentType.startsWith('audio/')) return 'Encrypted audio';
  if (contentType.contains('pdf')) return 'Encrypted document';
  return 'Encrypted file';
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.embedded,
    required this.title,
    required this.searchController,
    required this.searching,
    required this.ttlLabel,
    required this.ttlActive,
    required this.onTapTtl,
    this.peerOnline = false,
  });

  final bool embedded;
  final String title;
  final TextEditingController searchController;
  final bool searching;
  final String ttlLabel;
  final bool ttlActive;
  final VoidCallback onTapTtl;
  final bool peerOnline;

  @override
  Widget build(BuildContext context) {
    final header = Column(
      children: [
        VeilSurfaceCard(
          padding: const EdgeInsets.symmetric(
            horizontal: VeilSpace.lg,
            vertical: VeilSpace.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (peerOnline) ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4CAF50),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: VeilSpace.xs),
                        ],
                        Expanded(
                          child: Text(
                            embedded ? title : 'Secure conversation',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: VeilSpace.xxs),
                    Text(
                      peerOnline
                          ? 'Online now'
                          : embedded
                              ? 'Local search stays on this device. Message bodies remain opaque to the relay.'
                              : 'Direct 1:1 exchange only. Message bodies remain opaque to the server.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: peerOnline ? const Color(0xFF4CAF50) : null,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: VeilSpace.sm),
              VeilButton(
                expanded: false,
                tone: ttlActive
                    ? VeilButtonTone.primary
                    : VeilButtonTone.secondary,
                icon: Icons.timer_outlined,
                onPressed: onTapTtl,
                label: ttlLabel,
              ),
            ],
          ),
        ),
        const SizedBox(height: VeilSpace.sm),
        VeilSurfaceCard(
          padding: const EdgeInsets.all(VeilSpace.md),
          child: Column(
            children: [
              TextField(
                controller: searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : searchController.text.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: searchController.clear,
                              icon: const Icon(Icons.close_rounded),
                            ),
                  hintText: 'Search cached messages on this device',
                ),
              ),
              const SizedBox(height: VeilSpace.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  VeilStatusPill(
                    label: ttlLabel,
                    tone: ttlActive
                        ? VeilBannerTone.warn
                        : VeilBannerTone.info,
                  ),
                  const VeilStatusPill(label: 'Attachments encrypted'),
                  const VeilStatusPill(label: 'Local search only'),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    if (embedded) {
      return header;
    }

    return Column(
      children: [
        VeilHeroPanel(
          eyebrow: 'SECURE CONVERSATION',
          title: title,
          body:
              'Direct 1:1 exchange only. Message bodies remain opaque to the server and expire locally when configured.',
          bottom: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VeilStatusPill(
                label: ttlLabel,
                tone: ttlActive ? VeilBannerTone.warn : VeilBannerTone.info,
              ),
              const VeilStatusPill(label: 'Attachments encrypted'),
              const VeilStatusPill(label: 'Local search only'),
            ],
          ),
        ),
        const SizedBox(height: VeilSpace.sm),
        header,
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.highlighted,
    required this.sentAtFormat,
    required this.decryptFuture,
    required this.onResolveAttachment,
    required this.onCancelAttachment,
    required this.attachmentResolving,
    required this.attachmentDownloadError,
    required this.transferSnapshot,
    required this.onReplyGesture,
    this.onRetryMessage,
  });

  final ChatMessage message;
  final bool highlighted;
  final DateFormat sentAtFormat;
  final Future<DecryptedMessage> decryptFuture;
  final Future<void> Function(String attachmentId) onResolveAttachment;
  final VoidCallback? onCancelAttachment;
  final bool attachmentResolving;
  final String? attachmentDownloadError;
  final AttachmentTransferSnapshot? transferSnapshot;
  final VoidCallback onReplyGesture;
  final VoidCallback? onRetryMessage;

  @override
  Widget build(BuildContext context) {
    final alignment =
        message.isMine ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: alignment,
      child: Semantics(
        label: messageBubbleSemanticsLabel(message),
        child: AnimatedContainer(
          duration: VeilMotion.normal,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VeilRadius.lg + 2),
            border: highlighted
                ? Border.all(color: context.veilPalette.primary, width: 1.2)
                : null,
            color: highlighted ? context.veilPalette.primarySoft : Colors.transparent,
          ),
            child: Dismissible(
              key: ValueKey('reply-${message.id}'),
              direction: DismissDirection.startToEnd,
              confirmDismiss: (_) async {
                onReplyGesture();
              return false;
            },
              background: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: VeilSpace.lg),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(VeilRadius.lg),
                color: context.veilPalette.primarySoft,
                border: Border.all(color: context.veilPalette.strokeStrong),
              ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.reply_rounded),
                    SizedBox(width: VeilSpace.xs),
                    Text('Reply locally'),
                  ],
                ),
              ),
              child: VeilMessageBubbleCard(
                isMine: message.isMine,
                highlighted: highlighted,
                child: FutureBuilder<DecryptedMessage>(
                  future: decryptFuture,
                  builder: (context, snapshot) {
                  final decrypted = snapshot.data;
                  final body = decrypted?.body ?? 'Decrypting envelope...';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(body),
                      if (transferSnapshot != null) ...[
                        const SizedBox(height: 12),
                        _AttachmentTransferPanel(
                          snapshot: transferSnapshot!,
                          onRetry: onRetryMessage,
                          onCancel: transferSnapshot!.canCancel
                              ? onCancelAttachment
                              : null,
                        ),
                      ],
                      if (decrypted?.attachment != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.24),
                            border: Border.all(
                                color: Theme.of(context).colorScheme.outline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _attachmentIcon(decrypted!.attachment!.contentType),
                                    size: 28,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _attachmentLabel(decrypted.attachment!.contentType),
                                          style: Theme.of(context).textTheme.titleSmall,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_formatFileSize(decrypted.attachment!.sizeBytes)} · ${decrypted.attachment!.contentType}',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.5),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (attachmentDownloadError != null) ...[
                                const SizedBox(height: 10),
                                VeilInlineBanner(
                                  title: 'Attachment ticket failed',
                                  message: attachmentDownloadError!,
                                  tone: VeilBannerTone.warn,
                                ),
                              ],
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  VeilButton(
                                    expanded: false,
                                    tone: VeilButtonTone.secondary,
                                    onPressed: attachmentResolving
                                        ? null
                                        : () => onResolveAttachment(
                                              decrypted.attachment!.attachmentId,
                                            ),
                                    label: attachmentResolving
                                        ? 'Resolving ticket'
                                        : 'Resolve download ticket',
                                  ),
                                  if (message.hasFailed && onRetryMessage != null)
                                    VeilButton(
                                      expanded: false,
                                      tone: VeilButtonTone.secondary,
                                      onPressed: onRetryMessage,
                                      label: 'Retry send',
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (message.hasFailed &&
                          decrypted?.attachment == null &&
                          onRetryMessage != null) ...[
                        const SizedBox(height: VeilSpace.sm),
                        VeilButton(
                          expanded: false,
                          tone: VeilButtonTone.ghost,
                          onPressed: onRetryMessage,
                          label: 'Retry send',
                        ),
                      ],
                      const SizedBox(height: VeilSpace.sm),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            sentAtFormat.format(message.sentAt),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (message.isMine) ...[
                            const SizedBox(width: VeilSpace.xs),
                            Flexible(
                              child: VeilStatusPill(
                                label: messageDeliveryLabel(message),
                                tone: messageDeliveryTone(message),
                              ),
                            ),
                          ],
                          if (message.expiresAt != null) ...[
                            const SizedBox(width: VeilSpace.xs),
                            Flexible(
                              child: Text(
                                formatMessageExpiry(message.expiresAt!),
                                style: Theme.of(context).textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemNoticeBubble extends StatelessWidget {
  const _SystemNoticeBubble({
    required this.message,
    required this.decryptFuture,
  });

  final ChatMessage message;
  final Future<DecryptedMessage> decryptFuture;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);
    return Center(
      child: FutureBuilder<DecryptedMessage>(
        future: decryptFuture,
        builder: (context, snapshot) {
          final body = snapshot.data?.body ?? 'Decrypting system notice...';
          return Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(
              horizontal: VeilSpace.md,
              vertical: VeilSpace.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(VeilRadius.pill),
              color: palette.surfaceOverlay,
              border: Border.all(color: palette.strokeStrong),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.camera_alt_outlined,
                  size: VeilIconSize.sm,
                  color: palette.warning,
                ),
                const SizedBox(width: VeilSpace.sm),
                Flexible(
                  child: Text(
                    body,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AttachmentTransferPanel extends StatelessWidget {
  const _AttachmentTransferPanel({
    required this.snapshot,
    this.onRetry,
    this.onCancel,
  });

  final AttachmentTransferSnapshot snapshot;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressLabel = '${(snapshot.progress * 100).round()}%';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.24),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _attachmentIcon(snapshot.contentType ?? 'application/octet-stream'),
                size: 22,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  snapshot.filename ?? _attachmentLabel(snapshot.contentType ?? 'application/octet-stream'),
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _phaseDescription(snapshot),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: switch (snapshot.phase) {
              AttachmentTransferPhase.staged => 0,
              AttachmentTransferPhase.preparing => null,
              AttachmentTransferPhase.uploading => snapshot.progress,
              AttachmentTransferPhase.finalizing => null,
              AttachmentTransferPhase.failed => snapshot.progress.clamp(0, 1),
              AttachmentTransferPhase.canceled => snapshot.progress.clamp(0, 1),
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VeilStatusPill(
                label: _phaseLabel(snapshot.phase),
                tone: switch (snapshot.phase) {
                  AttachmentTransferPhase.failed ||
                  AttachmentTransferPhase.canceled =>
                    VeilBannerTone.warn,
                  AttachmentTransferPhase.finalizing => VeilBannerTone.good,
                  _ => VeilBannerTone.info,
                },
              ),
              VeilStatusPill(
                label: progressLabel,
                tone: VeilBannerTone.info,
              ),
            ],
          ),
          if (snapshot.errorMessage != null) ...[
            const SizedBox(height: 10),
            VeilInlineBanner(
              title: 'Attachment state',
              message: snapshot.errorMessage!,
              tone: VeilBannerTone.warn,
            ),
          ],
          if (onRetry != null || onCancel != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
              if (onRetry != null)
                  VeilButton(
                    expanded: false,
                    tone: VeilButtonTone.secondary,
                    onPressed: onRetry,
                    label: 'Retry upload',
                  ),
                if (onCancel != null)
                  VeilButton(
                    expanded: false,
                    tone: VeilButtonTone.ghost,
                    onPressed: onCancel,
                    label: 'Cancel',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _phaseLabel(AttachmentTransferPhase phase) {
    return switch (phase) {
      AttachmentTransferPhase.staged => 'Staged',
      AttachmentTransferPhase.preparing => 'Preparing',
      AttachmentTransferPhase.uploading => 'Uploading',
      AttachmentTransferPhase.finalizing => 'Finalizing',
      AttachmentTransferPhase.failed => 'Retry required',
      AttachmentTransferPhase.canceled => 'Canceled',
    };
  }

  String _phaseDescription(AttachmentTransferSnapshot snapshot) {
    final sizeLabel =
        snapshot.sizeBytes == null ? '' : ' ${snapshot.sizeBytes} bytes.';
    return switch (snapshot.phase) {
      AttachmentTransferPhase.staged =>
        'Opaque blob staged locally.$sizeLabel Upload begins when the relay is reachable.',
      AttachmentTransferPhase.preparing =>
        'Refreshing upload authorization and validating encrypted metadata.',
      AttachmentTransferPhase.uploading =>
        'Sending ciphertext-like bytes to object storage. The relay never sees plaintext.',
      AttachmentTransferPhase.finalizing =>
        'Binding the uploaded blob into an encrypted message envelope.',
      AttachmentTransferPhase.failed => snapshot.errorMessage ??
          'Upload failed. Retry will reuse the local encrypted temp blob.',
      AttachmentTransferPhase.canceled =>
        'Upload stopped on this device. Retry will request a fresh ticket and reuse the local blob.',
    };
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator({required this.handle});

  final String? handle;

  @override
  Widget build(BuildContext context) {
    if (handle == null || handle!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: VeilSpace.md, top: VeilSpace.xs),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 12,
            child: _TypingDots(),
          ),
          const SizedBox(width: VeilSpace.xs),
          Text(
            '@$handle is typing',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final t = (_controller.value - delay) % 1.0;
            final scale = (t < 0.5 ? t : 1.0 - t) * 0.6 + 0.7;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _ReactionChipsRow extends StatelessWidget {
  const _ReactionChipsRow({
    required this.message,
    required this.myUserId,
    required this.onChipTap,
  });

  final ChatMessage message;
  final String? myUserId;
  final ValueChanged<String> onChipTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final grouped = <String, List<Reaction>>{};
    for (final reaction in message.reactions) {
      grouped.putIfAbsent(reaction.emoji, () => []).add(reaction);
    }
    if (grouped.isEmpty) {
      return const SizedBox.shrink();
    }

    final entries = grouped.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return Wrap(
      spacing: VeilSpace.xs,
      runSpacing: VeilSpace.xs,
      children: [
        for (final entry in entries)
          _ReactionChip(
            emoji: entry.key,
            count: entry.value.length,
            mine: myUserId != null &&
                entry.value.any((reaction) => reaction.userId == myUserId),
            palette: palette,
            onTap: () {
              HapticFeedback.selectionClick();
              onChipTap(entry.key);
            },
          ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.mine,
    required this.palette,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool mine;
  final VeilPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = mine ? palette.primarySoft : palette.surfaceAlt;
    final border = mine ? palette.primary : palette.stroke;
    final textColor = mine ? palette.primaryStrong : palette.textMuted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(VeilRadius.pill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: VeilSpace.sm,
            vertical: VeilSpace.xs,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(VeilRadius.pill),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
