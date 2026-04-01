import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../conversations/data/conversation_models.dart';
import 'message_expiration.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final _messageController = TextEditingController();
  final _composerFocusNode = FocusNode();
  final _sentAtFormat = DateFormat('HH:mm');
  bool _disappearing = false;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() async {
      final controller = ref.read(messengerControllerProvider);
      controller.setActiveConversation(widget.conversationId);
      await controller.loadConversationMessages(widget.conversationId);
      for (final message in controller.messagesFor(widget.conversationId).reversed) {
        if (!message.isMine) {
          await controller.markRead(message.id);
          break;
        }
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(messengerControllerProvider);
    final conversations = controller.conversations;
    ConversationPreview? conversation;
    for (final item in conversations) {
      if (item.id == widget.conversationId) {
        conversation = item;
        break;
      }
    }
    final messages = controller.messagesFor(widget.conversationId);
    final hasMoreHistory = controller.hasMoreHistoryFor(widget.conversationId);
    final isLoadingHistory = controller.isLoadingHistoryFor(widget.conversationId);
    final pendingCount = controller.pendingCountFor(widget.conversationId);
    final failedCount = messages.where((message) => message.hasFailed).length;

    return VeilShell(
      title: conversation?.peerDisplayName ?? conversation?.peerHandle ?? 'Secure channel',
      actions: [
        IconButton(
          onPressed: () => context.push('/attachment/${widget.conversationId}'),
          icon: const Icon(Icons.attach_file),
        ),
      ],
      child: Column(
        children: [
          VeilHeroPanel(
            eyebrow: 'SECURE CHANNEL',
            title: conversation?.peerDisplayName ?? '@${conversation?.peerHandle ?? 'unknown'}',
            body:
                'Direct 1:1 exchange only. Message bodies remain opaque to the server and expire locally when configured.',
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(
                  label: _disappearing ? 'Disappear in 30s' : 'Disappear off',
                  tone: _disappearing ? VeilBannerTone.warn : VeilBannerTone.info,
                ),
                const VeilStatusPill(label: 'Attachments encrypted'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Disappearing messages', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          _disappearing
                              ? 'Messages in this channel expire 30 seconds after send.'
                              : 'Messages stay until this device deletes them locally.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch(
                    value: _disappearing,
                    onChanged: (value) => setState(() => _disappearing = value),
                  ),
                ],
              ),
            ),
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 12),
            VeilInlineBanner(
              title: 'Channel issue',
              message: controller.errorMessage!,
              tone: VeilBannerTone.danger,
            ),
          ],
          if (pendingCount > 0) ...[
            const SizedBox(height: 12),
            VeilInlineBanner(
              title: failedCount > 0 ? 'Delivery stalled' : 'Queued locally',
              message: failedCount > 0
                  ? '$failedCount message(s) failed to send. Retry when the relay is reachable.'
                  : '$pendingCount message(s) are staged locally and will retry after reconnect.',
              tone: failedCount > 0 ? VeilBannerTone.warn : VeilBannerTone.info,
            ),
            if (failedCount > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton(
                    onPressed: () => ref
                        .read(messengerControllerProvider)
                        .retryPendingMessages(widget.conversationId),
                    child: const Text('Retry failed sends'),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: messages.isEmpty && controller.isBusy
                ? const VeilLoadingBlock(
                    title: 'Decrypting channel state',
                    body: 'Pulling the latest message envelopes from the relay.',
                  )
                : messages.isEmpty
                    ? VeilEmptyState(
                        title: 'No messages yet',
                        body:
                            'This channel is open, but no encrypted envelopes have been sent yet.',
                        icon: Icons.chat_bubble_outline_rounded,
                        action: FilledButton.tonal(
                          onPressed: () => _composerFocusNode.requestFocus(),
                          child: const Text('Send first message'),
                        ),
                      )
                    : ListView.separated(
                        itemCount: messages.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        padding: EdgeInsets.zero,
                        itemBuilder: (context, index) {
                          if (index == 0 && hasMoreHistory) {
                            return Column(
                              children: [
                                OutlinedButton(
                                  onPressed: isLoadingHistory
                                      ? null
                                      : () => ref
                                          .read(messengerControllerProvider)
                                          .loadOlderConversationMessages(widget.conversationId),
                                  child: Text(isLoadingHistory ? 'Loading older' : 'Load older'),
                                ),
                                const SizedBox(height: 12),
                                _MessageBubble(
                                  message: messages[index],
                                  sentAtFormat: _sentAtFormat,
                                  decryptFuture: controller.decryptEnvelope(messages[index].envelope),
                                  onResolveAttachment: (attachmentId) async {
                                    final url = await ref
                                        .read(messengerControllerProvider)
                                        .getAttachmentDownloadUrl(attachmentId);
                                    if (!context.mounted || url == null) {
                                      return;
                                    }
                                    await showDialog<void>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Attachment ticket'),
                                        content: SelectableText(url),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(context).pop(),
                                            child: const Text('Close'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            );
                          }
                          final message = messages[index];
                          return _MessageBubble(
                            message: message,
                            sentAtFormat: _sentAtFormat,
                            decryptFuture: controller.decryptEnvelope(message.envelope),
                            onResolveAttachment: (attachmentId) async {
                              final url = await ref
                                  .read(messengerControllerProvider)
                                  .getAttachmentDownloadUrl(attachmentId);
                              if (!context.mounted || url == null) {
                                return;
                              }
                              await showDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Attachment ticket'),
                                  content: SelectableText(url),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      child: const Text('Close'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  TextField(
                    controller: _messageController,
                    focusNode: _composerFocusNode,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: const InputDecoration(
                      hintText: 'Send opaque text',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _disappearing
                              ? 'This send expires in 30 seconds.'
                              : 'This send does not expire.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: controller.isBusy ? null : _sendMessage,
                        child: Text(controller.isBusy ? 'Sending' : 'Send'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final body = _messageController.text.trim();
    if (body.isEmpty) {
      return;
    }

    await ref.read(messengerControllerProvider).sendText(
          conversationId: widget.conversationId,
          body: body,
          disappearAfter: _disappearing ? const Duration(seconds: 30) : null,
        );
    _messageController.clear();
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.sentAtFormat,
    required this.decryptFuture,
    required this.onResolveAttachment,
  });

  final ChatMessage message;
  final DateFormat sentAtFormat;
  final Future<DecryptedMessage> decryptFuture;
  final Future<void> Function(String attachmentId) onResolveAttachment;

  @override
  Widget build(BuildContext context) {
    final alignment = message.isMine ? Alignment.centerRight : Alignment.centerLeft;
    final color = message.isMine
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.17)
        : Theme.of(context).cardColor;

    return Align(
      alignment: alignment,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: FutureBuilder<DecryptedMessage>(
          future: decryptFuture,
          builder: (context, snapshot) {
            final decrypted = snapshot.data;
            final body = decrypted?.body ?? 'Decrypting envelope...';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(body),
                if (decrypted?.attachment != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.24,
                          ),
                      border: Border.all(color: Theme.of(context).colorScheme.outline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Encrypted attachment', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        Text(
                          '${decrypted!.attachment!.contentType} - ${decrypted.attachment!.sizeBytes} bytes',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: () => onResolveAttachment(decrypted.attachment!.attachmentId),
                          child: const Text('Resolve download ticket'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(sentAtFormat.format(message.sentAt),
                        style: Theme.of(context).textTheme.bodyMedium),
                    if (message.isMine) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _deliveryLabel(message),
                          style: Theme.of(context).textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    if (message.expiresAt != null) ...[
                      const SizedBox(width: 8),
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
    );
  }

  String _deliveryLabel(ChatMessage message) {
    switch (message.deliveryState) {
      case MessageDeliveryState.pending:
        return 'Queued';
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
}
