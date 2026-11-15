import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';

/// One story as the relay lists it for this account: who posted it and
/// when. The relay sends the story itself as a sealed envelope
/// (`ciphertext`, `envelopeVersion`) it cannot read, and this build has
/// nothing that opens one, so no field here is the story's content.
class StoryFeedEntry {
  const StoryFeedEntry({
    required this.id,
    required this.userId,
    required this.handle,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String userId;
  final String handle;
  final DateTime createdAt;
  final DateTime expiresAt;

  static StoryFeedEntry fromJson(Map<String, dynamic> json) {
    return StoryFeedEntry(
      id: json['id'] as String,
      userId: json['userId'] as String,
      handle: (json['handle'] as String?) ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}

/// The stories one person has up, as the feed lists them.
class StoryAuthor {
  const StoryAuthor({required this.userId, required this.handle, required this.count, required this.latest});

  final String userId;
  final String handle;

  /// How many of their stories have not expired.
  final int count;

  /// When they posted the newest one.
  final DateTime latest;
}

/// [stories] by author, the author of the newest story first.
List<StoryAuthor> storyAuthors(List<StoryFeedEntry> stories) {
  final byUser = <String, List<StoryFeedEntry>>{};
  for (final story in stories) {
    byUser.putIfAbsent(story.userId, () => []).add(story);
  }
  DateTime newest(List<StoryFeedEntry> of) =>
      of.map((story) => story.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
  final authors = [
    for (final entry in byUser.entries)
      StoryAuthor(
        userId: entry.key,
        handle: entry.value.first.handle,
        count: entry.value.length,
        latest: newest(entry.value),
      ),
  ];
  return authors..sort((a, b) => b.latest.compareTo(a.latest));
}

final storyFeedProvider =
    FutureProvider<List<StoryFeedEntry>>((ref) async {
  final session = ref.watch(appSessionProvider);
  if (!session.isAuthenticated || session.accessToken == null) {
    return const <StoryFeedEntry>[];
  }
  final apiClient = ref.read(apiClientProvider);
  final raw = await apiClient.getStories(session.accessToken!);
  return raw
      .whereType<Map<String, dynamic>>()
      .map(StoryFeedEntry.fromJson)
      .toList();
});

class StoryMutationResult {
  const StoryMutationResult({required this.success, this.errorMessage});

  final bool success;
  final String? errorMessage;
}

/// Posting is refused on this device: the relay takes a story only as one
/// end-to-end encrypted envelope for a named audience ({ciphertext,
/// envelopeVersion, audienceUserIds}), and this build has no story sealer.
/// It used to post the text in the clear; nothing is sent at all until a
/// sealer exists (see kStoriesEnabled). No screen offers to post one.
Future<StoryMutationResult> createTextStory(
  WidgetRef ref, {
  required String body,
}) async =>
    const StoryMutationResult(
      success: false,
      errorMessage: 'Stories are not end-to-end encrypted yet, so they cannot be posted.',
    );
