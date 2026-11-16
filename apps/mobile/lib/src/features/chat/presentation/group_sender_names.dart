import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../conversations/data/conversation_models.dart';
import '../../conversations/presentation/peer_names.dart';

/// Who of a group wrote each message. A group frame names the device that
/// sealed it, not a person: the member is the one this device has pinned
/// that device for (VeilMessengerController.pinnedDeviceOwners), which is
/// the identity the frame's key was accepted under. A device no pin names
/// gets no name, never a guess.
mixin GroupSenderNames<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  Map<String, GroupMember> _memberByDevice = const {};
  String? _namesOf;
  bool _readingNames = false;
  bool _namesRead = false;

  /// What [message]'s sender is called, by [names] (their nickname, or
  /// their handle), or null: a 1:1, or a device this device has pinned for
  /// none of the members.
  String? groupSenderName(ChatMessage message, PeerNames names) => switch (_memberByDevice[message.senderDeviceId]) {
        final member? => names.memberTitle(member),
        null => null,
      };

  /// The handle of the member who wrote [message], which their avatar and
  /// the tint of their name are drawn from; null where [groupSenderName]
  /// is.
  String? groupSenderHandle(ChatMessage message) => _memberByDevice[message.senderDeviceId]?.handle;

  /// The account of the member who wrote [message], which a report of it
  /// names; null where [groupSenderName] is.
  String? groupSenderUserId(ChatMessage message) => _memberByDevice[message.senderDeviceId]?.userId;

  /// Whether the pins of the open group have been read at least once. From
  /// then on a message with no name is one this device cannot attribute,
  /// and the chat says so instead of leaving it under the name above it.
  bool get groupSenderNamesRead => _namesRead;

  /// Call when the chat builds. Reads the pins again while [messages] holds
  /// a message from a device with no name yet: its pin appears once its
  /// first frame has opened, which is after the message is listed.
  void syncGroupSenderNames(ConversationPreview? conversation, List<ChatMessage> messages) {
    if (conversation == null || conversation.type != ConversationType.group) {
      _namesOf = null;
      _memberByDevice = const {};
      _namesRead = false;
      return;
    }
    if (_namesOf != conversation.id) {
      _namesOf = conversation.id;
      _memberByDevice = const {};
      _namesRead = false;
    }
    if (_readingNames) return;
    final unnamed = messages.any(
      (message) => !message.isMine && !message.isLocalNotice && !_memberByDevice.containsKey(message.senderDeviceId),
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
          if (member.userId != localUserId) member.userId: member,
      };
      final owners = await messenger.pinnedDeviceOwners(members.keys);
      final byDevice = {
        for (final MapEntry(key: deviceId, value: userId) in owners.entries) deviceId: members[userId]!,
      };
      if (!mounted || _namesOf != conversation.id) return;
      if (_namesRead && _sameMembers(byDevice, _memberByDevice)) return;
      setState(() {
        _memberByDevice = byDevice;
        _namesRead = true;
      });
    } finally {
      _readingNames = false;
    }
  }
}

bool _sameMembers(Map<String, GroupMember> a, Map<String, GroupMember> b) =>
    a.length == b.length &&
    a.entries.every((entry) => b[entry.key]?.userId == entry.value.userId && b[entry.key]?.handle == entry.value.handle);
