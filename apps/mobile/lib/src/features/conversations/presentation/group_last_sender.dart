import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../data/conversation_models.dart';
import 'peer_names.dart';

typedef GroupMessageKey = ({String conversationId, String deviceId});

/// The first name of the member who sent [deviceId]'s message in the group
/// [conversationId], for the list's "Omar: …" preview: the first word of
/// what PeerNames calls them, the nickname the user gave them or their
/// handle. A group frame names the device that sealed it, not a person: the
/// member is the one this device has pinned that device for, as the chat
/// names them (see GroupSenderNames). Null for a device no pin names: no
/// guess. Named anew whenever the names change: a nickname, or what this
/// phone bound or holds.
final groupLastSenderProvider = Provider.autoDispose.family<AsyncValue<String?>, GroupMessageKey>((ref, key) {
  final names = ref.watch(peerNamesProvider);
  // A handle has no space, so it is kept whole.
  return ref
      .watch(_groupWriterProvider(key))
      .whenData((member) => member == null ? null : names.memberTitle(member).split(' ').first);
});

// Who of the group sent the message: looked up once, not each time the
// messenger changes.
final _groupWriterProvider = FutureProvider.autoDispose.family<GroupMember?, GroupMessageKey>((ref, key) async {
  final messenger = ref.read(messengerControllerProvider);
  final conversation = messenger.conversationById(key.conversationId);
  if (conversation == null) return null;
  final localUserId = messenger.localUserId;
  final members = {
    for (final member in conversation.members)
      if (member.userId != localUserId) member.userId: member,
  };
  final owners = await messenger.pinnedDeviceOwners(members.keys);
  return members[owners[key.deviceId]];
});
