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
import '../../../l10n/generated/app_localizations.dart';
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
  double _sendScale = 1.0;
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
      final l10n = AppLocalizations.of(context);
      HapticFeedback.heavyImpact();
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
    final l10n = AppLocalizations.of(context);
    final options = _ttlOptions(l10n);
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
                  l10n.chatTtlSheetTitle,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              for (final option in options)
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

  String _ttlLabel(AppLocalizations l10n) {
    final current = _messageTtl;
    if (current == null) return l10n.chatTtlDisabledLabel;
    for (final option in _ttlOptions(l10n)) {
      if (option.duration == current) return option.label;
    }
    return l10n.chatTtlCustom;
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
            l10n: l10n,
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
          ttlLabel: _ttlLabel(l10n),
          ttlActive: _messageTtl != null,
          onTapTtl: _pickDisappearTtl,
          peerOnline: conversation != null &&
              controller.isUserOnline(conversation.recipientBundle.userId),
        ),
        const SizedBox(height: VeilSpace.sm),
        VeilMetricStrip(
          items: [
            VeilMetricItem(
              label: l10n.chatMetricRelay,
              value: controller.realtimeConnected
                  ? l10n.chatMetricRelayLinked
                  : l10n.chatMetricRelayRecovering,
            ),
            VeilMetricItem(
              label: l10n.chatMetricLoaded,
              value: '${messages.length}',
            ),
            VeilMetricItem(
              label: l10n.chatMetricHistory,
              value: historyWindowLabel(
                l10n: l10n,
                isLoadingHistory: isLoadingHistory,
                hasMoreHistory: hasMoreHistory,
              ),
            ),
            VeilMetricItem(
              label: l10n.chatMetricSearch,
              value: hasSearchQuery
                  ? l10n.chatMetricSearchHits(filteredMessages.length)
                  : l10n.chatMetricSearchIdle,
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
            title: l10n.chatBannerConversationIssue,
            message: controller.errorMessage!,
            tone: VeilBannerTone.danger,
          ),
        ],
        if (pendingCount > 0) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: !controller.realtimeConnected
                ? l10n.chatBannerRelayReconnecting
                : failedCount > 0
                    ? l10n.chatBannerDeliveryStalled
                    : l10n.chatBannerQueuedLocally,
            message: !controller.realtimeConnected
                ? _networkRecoveryMessage(
                    l10n: l10n,
                    failedCount: failedCount,
                    queuedCount: queuedCount,
                    uploadingCount: uploadingCount,
                    nextRetryAt: nextRetryAt,
                  )
                : failedCount > 0
                    ? l10n.chatBannerFailedSends(failedCount)
                    : uploadingCount > 0
                        ? l10n.chatBannerUploadingAttachments(uploadingCount)
                        : l10n.chatBannerQueuedMessages(queuedCount),
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
                  child: Text(l10n.chatRetryFailedSendsAction),
                ),
              ),
            ),
        ],
        if (hasSearchQuery) ...[
          const SizedBox(height: VeilSpace.sm),
          VeilInlineBanner(
            title: _isSearchingMessages
                ? l10n.chatSearchBannerSearchingTitle
                : l10n.chatSearchBannerIdleTitle,
            message: _isSearchingMessages
                ? l10n.chatSearchBannerSearchingBody
                : filteredMessages.isEmpty
                    ? l10n.chatSearchBannerEmptyBody
                    : l10n.chatSearchBannerResultBody(filteredMessages.length),
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
              ? l10n.chatComposerExpiryOff
              : l10n.chatComposerExpiryOn(_formatDurationLabel(l10n, _messageTtl!)),
          trailing: AnimatedScale(
            scale: _sendScale,
            duration: VeilMotion.fast,
            curve: VeilMotion.emphasize,
            child: _GradientSendButton(
              onPressed: controller.isBusy ? null : _sendMessage,
              busy: controller.isBusy,
            ),
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
          l10n.chatTitleFallback,
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
    final l10n = AppLocalizations.of(context);

    if (messages.isEmpty && controller.isBusy) {
      return VeilLoadingBlock(
        title: l10n.chatLoadingTitle,
        body: l10n.chatLoadingBody,
      );
    }

    if (messages.isEmpty) {
      return VeilEmptyState(
        title: l10n.chatEmptyTitle,
        body: l10n.chatEmptyBody,
        icon: Icons.chat_bubble_outline_rounded,
        action: FilledButton.tonal(
          onPressed: () => _composerFocusNode.requestFocus(),
          child: Text(l10n.chatSendAction),
        ),
      );
    }

    if (hasSearchQuery && filteredMessages.isEmpty) {
      return VeilEmptyState(
        title: l10n.chatSearchEmptyTitle,
        body: l10n.chatSearchEmptyBody,
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
    final l10n = AppLocalizations.of(context);
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
              label: isLoadingHistory ? l10n.chatLoadingOlder : l10n.chatLoadOlder,
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
        child: _AnimatedBubbleEntry(
          fromRight: message.isMine,
          child: bubbleWithReactions,
        ),
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
            label: isLoadingHistory ? l10n.chatLoadingOlder : l10n.chatLoadOlder,
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

    setState(() => _sendScale = 0.85);
    Future<void>.delayed(VeilMotion.fast, () {
      if (mounted) setState(() => _sendScale = 1.0);
    });

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
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.chatAttachmentTicketTitle),
        content: Text(l10n.chatAttachmentTicketBody(ticketSummary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }

  void _handleReplyGesture(ChatMessage message) {
    HapticFeedback.lightImpact();
    _composerFocusNode.requestFocus();
    final l10n = AppLocalizations.of(context);
    VeilToast.show(
      context,
      message: l10n.chatReplyPrimed,
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
  required AppLocalizations l10n,
  required int failedCount,
  required int queuedCount,
  required int uploadingCount,
  required DateTime? nextRetryAt,
}) {
  final retryLabel = nextRetryAt == null
      ? l10n.chatRetryResumes
      : l10n.chatRetryNextIn(formatRetryCountdown(nextRetryAt));
  if (failedCount > 0) {
    return l10n.chatNetworkRecoveryFailed(failedCount, retryLabel);
  }
  if (uploadingCount > 0) {
    return l10n.chatNetworkRecoveryUploading(uploadingCount, retryLabel);
  }
  return l10n.chatNetworkRecoveryQueued(queuedCount, retryLabel);
}

String historyWindowLabel({
  required AppLocalizations l10n,
  required bool isLoadingHistory,
  required bool hasMoreHistory,
}) {
  if (isLoadingHistory) {
    return l10n.chatMetricHistoryLoading;
  }
  if (hasMoreHistory) {
    return l10n.chatMetricHistoryPaged;
  }
  return l10n.chatMetricHistoryComplete;
}

HistoryWindowBannerSpec? historyWindowBannerSpec({
  required AppLocalizations l10n,
  required bool isLoadingHistory,
  required bool hasMoreHistory,
}) {
  if (isLoadingHistory) {
    return HistoryWindowBannerSpec(
      title: l10n.chatBannerHistoryLoadingTitle,
      message: l10n.chatBannerHistoryLoadingBody,
      tone: VeilBannerTone.info,
      icon: Icons.history_toggle_off_rounded,
    );
  }
  if (!hasMoreHistory) {
    return HistoryWindowBannerSpec(
      title: l10n.chatBannerHistoryCompleteTitle,
      message: l10n.chatBannerHistoryCompleteBody,
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

String messageDeliveryLabel(AppLocalizations l10n, ChatMessage message) {
  switch (message.deliveryState) {
    case MessageDeliveryState.pending:
      return l10n.chatDeliveryQueued;
    case MessageDeliveryState.uploading:
      return l10n.chatDeliveryUploading;
    case MessageDeliveryState.failed:
      return l10n.chatDeliveryFailed;
    case MessageDeliveryState.sent:
      return l10n.chatDeliverySent;
    case MessageDeliveryState.delivered:
      return l10n.chatDeliveryDelivered;
    case MessageDeliveryState.read:
      return l10n.chatDeliveryRead;
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

String messageBubbleSemanticsLabel(AppLocalizations l10n, ChatMessage message) {
  final direction =
      message.isMine ? l10n.chatSemanticsSent : l10n.chatSemanticsReceived;
  final stateSegment = message.isMine
      ? l10n.chatSemanticsStateSegment(messageDeliveryLabel(l10n, message))
      : '';
  return l10n.chatSemanticsBubble(direction, stateSegment);
}

class _TtlOption {
  const _TtlOption({required this.label, required this.duration, this.caption});

  final String label;
  final Duration? duration;
  final String? caption;
}

List<_TtlOption> _ttlOptions(AppLocalizations l10n) => <_TtlOption>[
      _TtlOption(
        label: l10n.chatTtlOff,
        duration: null,
        caption: l10n.chatTtlOffCaption,
      ),
      _TtlOption(
        label: l10n.chatTtl10s,
        duration: const Duration(seconds: 10),
        caption: l10n.chatTtl10sCaption,
      ),
      _TtlOption(
        label: l10n.chatTtl1m,
        duration: const Duration(minutes: 1),
      ),
      _TtlOption(
        label: l10n.chatTtl5m,
        duration: const Duration(minutes: 5),
      ),
      _TtlOption(
        label: l10n.chatTtl1h,
        duration: const Duration(hours: 1),
      ),
      _TtlOption(
        label: l10n.chatTtl1d,
        duration: const Duration(days: 1),
        caption: l10n.chatTtl1dCaption,
      ),
    ];

String _formatDurationLabel(AppLocalizations l10n, Duration duration) {
  if (duration.inDays > 0) return l10n.chatDurationDays(duration.inDays);
  if (duration.inHours > 0) return l10n.chatDurationHours(duration.inHours);
  if (duration.inMinutes > 0) return l10n.chatDurationMinutes(duration.inMinutes);
  return l10n.chatDurationSeconds(duration.inSeconds);
}

IconData _attachmentIcon(String contentType) {
  if (contentType.startsWith('image/')) return Icons.image_rounded;
  if (contentType.startsWith('video/')) return Icons.videocam_rounded;
  if (contentType.startsWith('audio/')) return Icons.audiotrack_rounded;
  if (contentType.contains('pdf')) return Icons.picture_as_pdf_rounded;
  return Icons.insert_drive_file_rounded;
}

String _attachmentLabel(AppLocalizations l10n, String contentType) {
  if (contentType.startsWith('image/')) return l10n.chatAttachmentEncryptedImage;
  if (contentType.startsWith('video/')) return l10n.chatAttachmentEncryptedVideo;
  if (contentType.startsWith('audio/')) return l10n.chatAttachmentEncryptedAudio;
  if (contentType.contains('pdf')) return l10n.chatAttachmentEncryptedDocument;
  return l10n.chatAttachmentEncryptedFile;
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
    final l10n = AppLocalizations.of(context);
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
                            embedded ? title : l10n.chatTitleFallback,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: VeilSpace.xxs),
                    Text(
                      peerOnline
                          ? l10n.chatSubtitleOnline
                          : embedded
                              ? l10n.chatSubtitleEmbedded
                              : l10n.chatSubtitleStandalone,
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
                              tooltip: l10n.chatSearchClearTooltip,
                              onPressed: searchController.clear,
                              icon: const Icon(Icons.close_rounded),
                            ),
                  hintText: l10n.chatSearchHint,
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
                  VeilStatusPill(label: l10n.chatPillAttachmentsEncrypted),
                  VeilStatusPill(label: l10n.chatPillLocalSearchOnly),
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
          eyebrow: l10n.chatHeroEyebrow,
          title: title,
          body: l10n.chatHeroBody,
          bottom: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VeilStatusPill(
                label: ttlLabel,
                tone: ttlActive ? VeilBannerTone.warn : VeilBannerTone.info,
              ),
              VeilStatusPill(label: l10n.chatPillAttachmentsEncrypted),
              VeilStatusPill(label: l10n.chatPillLocalSearchOnly),
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
    final l10n = AppLocalizations.of(context);
    final alignment =
        message.isMine ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: alignment,
      child: Semantics(
        label: messageBubbleSemanticsLabel(l10n, message),
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
                  children: [
                    const Icon(Icons.reply_rounded),
                    const SizedBox(width: VeilSpace.xs),
                    Text(l10n.chatReplyLocally),
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
                  final body = decrypted?.body ?? l10n.chatDecryptingEnvelope;
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
                                          _attachmentLabel(l10n, decrypted.attachment!.contentType),
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
                                  title: l10n.chatAttachmentTicketFailed,
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
                                        ? l10n.chatAttachmentResolvingAction
                                        : l10n.chatAttachmentResolveAction,
                                  ),
                                  if (message.hasFailed && onRetryMessage != null)
                                    VeilButton(
                                      expanded: false,
                                      tone: VeilButtonTone.secondary,
                                      onPressed: onRetryMessage,
                                      label: l10n.chatRetrySend,
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
                          label: l10n.chatRetrySend,
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
                                label: messageDeliveryLabel(l10n, message),
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
    final l10n = AppLocalizations.of(context);
    return Center(
      child: FutureBuilder<DecryptedMessage>(
        future: decryptFuture,
        builder: (context, snapshot) {
          final body = snapshot.data?.body ?? l10n.chatDecryptingSystemNotice;
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
    final l10n = AppLocalizations.of(context);
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
                  snapshot.filename ?? _attachmentLabel(l10n, snapshot.contentType ?? 'application/octet-stream'),
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _phaseDescription(l10n, snapshot),
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
                label: _phaseLabel(l10n, snapshot.phase),
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
              title: l10n.chatAttachmentStateBanner,
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
                    label: l10n.chatRetryUpload,
                  ),
                if (onCancel != null)
                  VeilButton(
                    expanded: false,
                    tone: VeilButtonTone.ghost,
                    onPressed: onCancel,
                    label: l10n.chatCancelAction,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _phaseLabel(AppLocalizations l10n, AttachmentTransferPhase phase) {
    return switch (phase) {
      AttachmentTransferPhase.staged => l10n.chatPhaseStaged,
      AttachmentTransferPhase.preparing => l10n.chatPhasePreparing,
      AttachmentTransferPhase.uploading => l10n.chatPhaseUploading,
      AttachmentTransferPhase.finalizing => l10n.chatPhaseFinalizing,
      AttachmentTransferPhase.failed => l10n.chatPhaseFailed,
      AttachmentTransferPhase.canceled => l10n.chatPhaseCanceled,
    };
  }

  String _phaseDescription(
      AppLocalizations l10n, AttachmentTransferSnapshot snapshot) {
    final sizeLabel = snapshot.sizeBytes == null
        ? ''
        : l10n.chatAttachmentSizeBytes(snapshot.sizeBytes!);
    return switch (snapshot.phase) {
      AttachmentTransferPhase.staged =>
        l10n.chatPhaseDescStaged(sizeLabel),
      AttachmentTransferPhase.preparing => l10n.chatPhaseDescPreparing,
      AttachmentTransferPhase.uploading => l10n.chatPhaseDescUploading,
      AttachmentTransferPhase.finalizing => l10n.chatPhaseDescFinalizing,
      AttachmentTransferPhase.failed =>
        snapshot.errorMessage ?? l10n.chatPhaseDescFailed,
      AttachmentTransferPhase.canceled => l10n.chatPhaseDescCanceled,
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
            AppLocalizations.of(context).chatTypingSuffix(handle!),
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

class _AnimatedBubbleEntry extends StatefulWidget {
  const _AnimatedBubbleEntry({required this.child, this.fromRight = false});

  final Widget child;
  final bool fromRight;

  @override
  State<_AnimatedBubbleEntry> createState() => _AnimatedBubbleEntryState();
}

class _AnimatedBubbleEntryState extends State<_AnimatedBubbleEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: VeilMotion.normal,
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    final dx = widget.fromRight ? 0.08 : -0.08;
    _slide = Tween<Offset>(
      begin: Offset(dx, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: VeilMotion.emphasize,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

class _GradientSendButton extends StatelessWidget {
  const _GradientSendButton({this.onPressed, this.busy = false});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onPressed!();
            }
          : null,
      child: AnimatedContainer(
        duration: VeilMotion.fast,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: enabled
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6C8CFF), Color(0xFF8B5CF6)],
                )
              : null,
          color: enabled ? null : const Color(0xFF1F293A),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: const Color(0xFF6C8CFF).withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Icon(
          busy ? Icons.more_horiz_rounded : Icons.arrow_upward_rounded,
          color: enabled ? Colors.white : const Color(0xFF5E6B7F),
          size: 22,
        ),
      ),
    );
  }
}
