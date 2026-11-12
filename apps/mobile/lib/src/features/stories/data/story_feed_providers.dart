import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';

enum StoryContentKind { text, image, video }

class StoryFeedEntry {
  const StoryFeedEntry({
    required this.id,
    required this.userId,
    required this.handle,
    required this.displayName,
    required this.contentType,
    required this.contentUrl,
    required this.caption,
    required this.viewCount,
    required this.viewedByMe,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String userId;
  final String handle;
  final String? displayName;
  final StoryContentKind contentType;
  final String contentUrl;
  final String? caption;
  final int viewCount;
  final bool viewedByMe;
  final DateTime createdAt;
  final DateTime expiresAt;

  static StoryFeedEntry fromJson(Map<String, dynamic> json) {
    final rawType = (json['contentType'] as String?) ?? 'text';
    return StoryFeedEntry(
      id: json['id'] as String,
      userId: json['userId'] as String,
      handle: (json['handle'] as String?) ?? '',
      displayName: json['displayName'] as String?,
      contentType: switch (rawType) {
        'image' => StoryContentKind.image,
        'video' => StoryContentKind.video,
        _ => StoryContentKind.text,
      },
      contentUrl: (json['contentUrl'] as String?) ?? '',
      caption: json['caption'] as String?,
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      viewedByMe: json['viewedByMe'] == true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')
              ?.toLocal() ??
          DateTime.now(),
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '')
              ?.toLocal() ??
          DateTime.now(),
    );
  }
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
/// sealer exists (see kStoriesEnabled).
Future<StoryMutationResult> createTextStory(
  WidgetRef ref, {
  required String body,
}) async =>
    const StoryMutationResult(
      success: false,
      errorMessage: 'Stories are not end-to-end encrypted yet, so they cannot be posted.',
    );

Future<void> markStoryViewed(WidgetRef ref, String storyId) async {
  final session = ref.read(appSessionProvider);
  if (!session.isAuthenticated || session.accessToken == null) return;
  try {
    await ref.read(apiClientProvider).viewStory(session.accessToken!, storyId);
  } catch (_) {
    // View tracking is best effort.
  }
}
