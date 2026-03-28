import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../conversations/data/mock_messenger_repository.dart';
import 'message_expiration.dart';
import '../../../shared/presentation/veil_shell.dart';

class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final _messageController = TextEditingController();
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
          Card(
            child: ListTile(
              title: const Text('Disappearing messages'),
              subtitle: Text(_disappearing ? '30 seconds' : 'Off'),
              trailing: Switch(
                value: _disappearing,
                onChanged: (value) => setState(() => _disappearing = value),
              ),
            ),
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  controller.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: messages.isEmpty && controller.isBusy
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: messages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final alignment =
                          message.isMine ? Alignment.centerRight : Alignment.centerLeft;
                      final color = message.isMine
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
                          : Theme.of(context).cardColor;
                      return Align(
                        alignment: alignment,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 300),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Theme.of(context).dividerColor),
                          ),
                          child: FutureBuilder<DecryptedMessage>(
                            future: controller.decryptEnvelope(message.envelope),
                            builder: (context, snapshot) {
                              final decrypted = snapshot.data;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(decrypted?.body ?? 'Decrypting...'),
                                  if (decrypted?.attachment != null) ...[
                                    const SizedBox(height: 10),
                                    OutlinedButton(
                                      onPressed: () async {
                                        final url = await ref
                                            .read(messengerControllerProvider)
                                            .getAttachmentDownloadUrl(
                                              decrypted!.attachment!.attachmentId,
                                            );
                                        if (!context.mounted || url == null) {
                                          return;
                                        }
                                        await showDialog<void>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Encrypted attachment'),
                                            content: Text(url),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(context).pop(),
                                                child: const Text('Close'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      child: const Text('Resolve download ticket'),
                                    ),
                                  ],
                                  if (message.expiresAt != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      formatMessageExpiry(message.expiresAt!),
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(hintText: 'Send opaque text'),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: controller.isBusy
                    ? null
                    : () async {
                        await ref.read(messengerControllerProvider).sendText(
                              conversationId: widget.conversationId,
                              body: _messageController.text.trim(),
                              disappearAfter:
                                  _disappearing ? const Duration(seconds: 30) : null,
                            );
                        _messageController.clear();
                      },
                child: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
