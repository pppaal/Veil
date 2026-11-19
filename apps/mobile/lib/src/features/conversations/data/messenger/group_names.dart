import '../../../../core/network/veil_api_client.dart';
import '../conversation_models.dart';
import 'messenger_api_mapper.dart';
import 'messenger_state_store.dart';

// Groups of each store whose name is on its way, so overlapping refreshes
// ask once.
final Expando<Set<String>> _loading = Expando('group names on their way');

/// Names the groups [store] lists that have no name yet. The relay's
/// conversation list names a group's members but not the group, so each such
/// group is asked for once (GroupsService.getGroup); the name then stays on
/// its preview across refreshes (mergeConversationPreviews) for as long as
/// the app runs. A group whose answer fails keeps showing its members'
/// names, and the next refresh asks again. An answer that comes after
/// [stillCurrent] turned false is dropped.
Future<void> fillGroupNames(
  MessengerStateStore store,
  VeilApiClient apiClient,
  MessengerApiMapper mapper,
  String accessToken,
  bool Function() stillCurrent,
) async {
  final loading = _loading[store] ??= <String>{};
  final unnamed = [
    for (final preview in store.conversations)
      if (preview.type == ConversationType.group && preview.groupMeta == null && loading.add(preview.id)) preview.id,
  ];
  if (unnamed.isEmpty) return;
  try {
    final answers = await Future.wait([
      for (final conversationId in unnamed)
        apiClient
            .getGroup(accessToken, conversationId)
            .then<GroupMeta?>(mapper.groupMeta, onError: (Object _) => null),
    ]);
    if (!stillCurrent()) return;
    for (final (index, conversationId) in unnamed.indexed) {
      final meta = answers[index];
      if (meta == null) continue;
      store.updateConversation(
        conversationId,
        (preview) => preview.type == ConversationType.group && preview.groupMeta == null
            ? preview.copyWith(groupMeta: meta)
            : preview,
      );
    }
  } finally {
    loading.removeAll(unnamed);
  }
}
