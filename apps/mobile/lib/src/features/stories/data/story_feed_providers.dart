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
    FutureProvider.autoDispose<List<StoryFeedEntry>>((ref) async {
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
