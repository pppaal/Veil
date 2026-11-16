import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';

/// The first name of the member who sent [deviceId]'s message in the group
/// [conversationId], for the list's "Omar: …" preview. A group frame names
/// the device that sealed it, not a person: the member is the one this
/// device has pinned that device for, as the chat names them (see
/// GroupSenderNames). Null for a device no pin names: no guess.
final groupLastSenderProvider =
    FutureProvider.autoDispose.family<String?, ({String conversationId, String deviceId})>((ref, key) async {
  final messenger = ref.read(messengerControllerProvider);
  final conversation = messenger.conversationById(key.conversationId);
  if (conversation == null) return null;
  final localUserId = messenger.localUserId;
  final members = {
    for (final member in conversation.members)
      if (member.userId != localUserId) member.userId: member,
  };
  final owners = await messenger.pinnedDeviceOwners(members.keys);
  final userId = owners[key.deviceId];
  if (userId == null) return null;
  // A handle has no space, so it is kept whole.
  return members[userId]!.title.split(' ').first;
});
