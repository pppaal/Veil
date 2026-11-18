import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../safety/data/safety_providers.dart';
import '../data/conversation_models.dart';
import '../data/messenger_providers.dart';

/// How many chats the Chats tab calls unread, as WhatsApp counts them: each
/// chat with unread messages or marked unread once, muted chats and 1:1s
/// with someone blocked left out (their rows show a grey badge instead).
final unreadChatsProvider = Provider<int>((ref) {
  final mutes = ref.watch(conversationMutesProvider);
  final blocked = ref.watch(blockedAccountsProvider);
  final messenger = ref.watch(messengerControllerProvider);
  return messenger.reads.unreadChats(
    excluded: (conversationId) {
      if (mutes.isMuted(conversationId)) return true;
      final conversation = messenger.conversationById(conversationId);
      return conversation != null &&
          conversation.type == ConversationType.direct &&
          blocked.isBlocked(conversation.recipientBundle.userId);
    },
  );
});
