import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../conversations/data/conversation_models.dart';

/// Who of a group wrote each message. A group frame names the device that
/// sealed it, not a person: the member is the one this device has pinned
/// that device for (VeilMessengerController.pinnedDeviceOwners), which is
/// the identity the frame's key was accepted under. A device no pin names
/// gets no name, never a guess.
mixin GroupSenderNames<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  Map<String, String> _nameByDevice = const {};
  String? _namesOf;
  bool _readingNames = false;

  /// The member name to show on [message], or null: a 1:1, or a device this
  /// device has pinned for none of the members.
  String? groupSenderName(ChatMessage message) => _nameByDevice[message.senderDeviceId];

  /// Call when the chat builds. Reads the pins again while [messages] holds
  /// a message from a device with no name yet: its pin appears once its
  /// first frame has opened, which is after the message is listed.
  void syncGroupSenderNames(ConversationPreview? conversation, List<ChatMessage> messages) {
    if (conversation == null || conversation.type != ConversationType.group) {
      _namesOf = null;
      _nameByDevice = const {};
      return;
    }
    if (_namesOf != conversation.id) {
      _namesOf = conversation.id;
      _nameByDevice = const {};
    }
    if (_readingNames) return;
    final unnamed = messages.any(
      (message) => !message.isMine && !message.isLocalNotice && !_nameByDevice.containsKey(message.senderDeviceId),
    );
    if (!unnamed) return;
    _readingNames = true;
    unawaited(_readNames(conversation));
  }

  Future<void> _readNames(ConversationPreview conversation) async {
    try {
      final messenger = ref.read(messengerControllerProvider);
      final localUserId = messenger.localUserId;
      final members = {
        for (final member in conversation.members)
          if (member.userId != localUserId) member.userId: member.title,
      };
      final owners = await messenger.pinnedDeviceOwners(members.keys);
      final names = {
        for (final MapEntry(key: deviceId, value: userId) in owners.entries) deviceId: members[userId]!,
      };
      if (!mounted || _namesOf != conversation.id || mapEquals(names, _nameByDevice)) return;
      setState(() => _nameByDevice = names);
    } finally {
      _readingNames = false;
    }
  }
}
