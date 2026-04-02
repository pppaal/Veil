import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/theme/veil_theme.dart';
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
          tooltip: 'Security status',
          onPressed: () => context.push('/security-status'),
          icon: const Icon(Icons.verified_user_outlined),
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.tune),
        ),
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
            const SizedBox(height: VeilSpace.md),
            VeilInlineBanner(
              title: 'Sync issue',
              message: controller.errorMessage!,
              tone: VeilBannerTone.danger,
            ),
          ],
          const SizedBox(height: VeilSpace.md),
          const VeilSectionLabel('CONVERSATIONS'),
          const SizedBox(height: VeilSpace.sm),
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
                      separatorBuilder: (_, __) => const SizedBox(height: VeilSpace.sm),
                      itemBuilder: (context, index) {
                        final item = conversations[index];
                        return VeilConversationCard(
                          title: item.peerDisplayName ?? item.peerHandle,
                          handle: item.peerHandle,
                          subtitle: _subtitleForConversation(item, controller),
                          timestamp: _timeFormat.format(item.updatedAt),
                          expiryLabel: item.lastEnvelope?.expiresAt == null
                              ? null
                              : formatMessageExpiry(item.lastEnvelope!.expiresAt!),
                          onTap: () => context.push('/chat/${item.id}'),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: VeilSpace.sm),
          FilledButton.tonal(
            onPressed: () => context.push('/start-chat'),
            child: const Text('Start direct chat'),
          ),
        ],
      ),
    );
  }
}
