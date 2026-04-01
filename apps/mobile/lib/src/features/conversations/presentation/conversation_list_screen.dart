import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../../chat/presentation/message_expiration.dart';
import '../data/conversation_models.dart';
import '../data/veil_messenger_controller.dart';

class ConversationListScreen extends ConsumerStatefulWidget {
  const ConversationListScreen({super.key});

  @override
  ConsumerState<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends ConsumerState<ConversationListScreen> {
  final _timeFormat = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() async {
      await ref.read(messengerControllerProvider).refreshConversations();
    });
  }

  String _subtitleForConversation(
    ConversationPreview item,
    VeilMessengerController controller,
  ) {
    final pendingCount = controller.pendingCountFor(item.id);
    if (pendingCount > 0) {
      return pendingCount == 1 ? '1 message queued locally' : '$pendingCount messages queued locally';
    }

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
          VeilHeroPanel(
            eyebrow: 'DIRECT CHANNELS',
            title: session.displayName?.isNotEmpty == true
                ? session.displayName!
                : '@${session.handle ?? 'unbound'}',
            body: controller.realtimeConnected
                ? 'Relay connected. Opaque envelopes only.'
                : 'Relay idle. Pulling the latest encrypted state.',
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(
                  label: controller.realtimeConnected ? 'Relay linked' : 'Relay idle',
                  tone: controller.realtimeConnected
                      ? VeilBannerTone.good
                      : VeilBannerTone.warn,
                ),
                const VeilStatusPill(label: '1:1 only'),
                const VeilStatusPill(label: 'No backup'),
              ],
            ),
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 16),
            VeilInlineBanner(
              title: 'Sync issue',
              message: controller.errorMessage!,
              tone: VeilBannerTone.danger,
            ),
          ],
          const SizedBox(height: 16),
          const VeilSectionLabel('CONVERSATIONS'),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refreshConversations,
              child: conversations.isEmpty && controller.isBusy
                  ? const VeilLoadingBlock(
                      title: 'Loading direct channels',
                      body: 'Refreshing the latest encrypted conversation state.',
                    )
                  : conversations.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 96),
                            VeilEmptyState(
                              title: 'No direct channels yet',
                              body:
                                  'Start with a handle. VEIL keeps discovery manual and private.',
                              icon: Icons.forum_outlined,
                              action: FilledButton.tonal(
                                onPressed: () => context.push('/start-chat'),
                                child: const Text('Start direct chat'),
                              ),
                            ),
                          ],
                        )
                  : ListView.separated(
                      itemCount: conversations.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = conversations[index];
                        return Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(22),
                            onTap: () => context.push('/chat/${item.id}'),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.12),
                                      border: Border.all(
                                        color: Theme.of(context).colorScheme.outline,
                                      ),
                                    ),
                                    child: Text(
                                      (item.peerDisplayName ?? item.peerHandle)
                                          .characters
                                          .first
                                          .toUpperCase(),
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.peerDisplayName ?? item.peerHandle,
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '@${item.peerHandle}',
                                          style: Theme.of(context).textTheme.bodyMedium,
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _subtitleForConversation(item, controller),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (item.lastEnvelope?.expiresAt != null)
                                              Padding(
                                                padding: const EdgeInsets.only(left: 8),
                                                child: VeilStatusPill(
                                                  label: formatMessageExpiry(
                                                    item.lastEnvelope!.expiresAt!,
                                                  ),
                                                  tone: VeilBannerTone.warn,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        _timeFormat.format(item.updatedAt),
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                      const SizedBox(height: 12),
                                      Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 14,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.46),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.tonal(
            onPressed: () => context.push('/start-chat'),
            child: const Text('Start direct chat'),
          ),
        ],
      ),
    );
  }
}
