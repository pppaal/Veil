import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../chat/presentation/message_expiration.dart';
import '../data/mock_messenger_repository.dart';

class ConversationListScreen extends ConsumerStatefulWidget {
  const ConversationListScreen({super.key});

  @override
  ConsumerState<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends ConsumerState<ConversationListScreen> {
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() async {
      await ref.read(messengerControllerProvider).refreshConversations();
    });
  }

  String _subtitleForConversation(ConversationPreview item) {
    final envelope = item.lastEnvelope;
    if (envelope == null) {
      return 'No messages yet';
    }

    if (isMessageExpired(envelope.expiresAt)) {
      return 'Expired locally';
    }

    switch (envelope.messageKind) {
      case MessageKind.image:
        return 'Encrypted image';
      case MessageKind.file:
        return 'Encrypted attachment';
      case MessageKind.system:
        return 'System envelope';
      case MessageKind.text:
        return 'Encrypted message';
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);
    final controller = ref.watch(messengerControllerProvider);
    final conversations = controller.conversations;

    return VeilShell(
      title: 'VEIL',
      actions: [
        IconButton(
          onPressed: () => context.push('/security-status'),
          icon: const Icon(Icons.verified_user_outlined),
        ),
        IconButton(onPressed: () => context.push('/settings'), icon: const Icon(Icons.tune)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(session.handle == null ? 'Direct channels only.' : '@${session.handle}'),
          const SizedBox(height: 4),
          Text(
            controller.realtimeConnected
                ? 'Relay connected. Opaque envelopes only.'
                : 'Relay idle. Refreshing encrypted state.',
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 16),
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
            child: RefreshIndicator(
              onRefresh: controller.refreshConversations,
              child: conversations.isEmpty && controller.isBusy
                  ? const Center(child: CircularProgressIndicator())
                  : conversations.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('No direct channels yet.')),
                          ],
                        )
                  : ListView.separated(
                      itemCount: conversations.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = conversations[index];
                        return Card(
                          child: ListTile(
                            onTap: () => context.push('/chat/${item.id}'),
                            title: Text(item.peerDisplayName ?? item.peerHandle),
                            subtitle: Text(_subtitleForConversation(item)),
                            trailing: Text(
                              '${item.updatedAt.hour.toString().padLeft(2, '0')}:${item.updatedAt.minute.toString().padLeft(2, '0')}',
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          FilledButton.tonal(
            onPressed: () => context.push('/start-chat'),
            child: const SizedBox(width: double.infinity, child: Center(child: Text('Start direct chat'))),
          ),
        ],
      ),
    );
  }
}
