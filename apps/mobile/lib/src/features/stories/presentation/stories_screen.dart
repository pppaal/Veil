import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/story_feed_providers.dart';

class StoriesScreen extends ConsumerStatefulWidget {
  const StoriesScreen({super.key});

  @override
  ConsumerState<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends ConsumerState<StoriesScreen> {
  bool _posting = false;

  Future<void> _showCreateTextStorySheet() async {
    HapticFeedback.selectionClick();
    final textController = TextEditingController();
    final palette = context.veilPalette;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(VeilSpace.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'New text story',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: VeilSpace.xs),
                  Text(
                    'Text stories disappear after 24 hours. No media capture needed.',
                    style:
                        Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                              color: palette.textSubtle,
                            ),
                  ),
                  const SizedBox(height: VeilSpace.lg),
                  TextField(
                    controller: textController,
                    autofocus: true,
                    maxLines: 4,
                    maxLength: 280,
                    decoration: const InputDecoration(
                      hintText: 'What is going on?',
                    ),
                  ),
                  const SizedBox(height: VeilSpace.md),
                  StatefulBuilder(
                    builder: (builderContext, setLocalState) {
                      return VeilButton(
                        label: _posting ? 'Posting\u2026' : 'Post story',
                        icon: Icons.send_rounded,
                        tone: VeilButtonTone.primary,
                        onPressed: _posting
                            ? null
                            : () async {
                                final body = textController.text.trim();
                                if (body.isEmpty) return;
                                setLocalState(() => _posting = true);
                                final result = await createTextStory(
                                  ref,
                                  body: body,
                                );
                                setLocalState(() => _posting = false);
                                if (!sheetContext.mounted) return;
                                if (result.success) {
                                  Navigator.of(sheetContext).pop();
                                  if (mounted) {
                                    VeilToast.show(
                                      context,
                                      message: 'Story posted',
                                      tone: VeilBannerTone.good,
                                    );
                                  }
                                } else {
                                  VeilToast.show(
                                    sheetContext,
                                    message: result.errorMessage ??
                                        'Failed to post story',
                                    tone: VeilBannerTone.danger,
                                  );
                                }
                              },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    textController.dispose();
  }

  String _shortTimeAgo(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _contentHint(StoryContentKind kind) {
    return switch (kind) {
      StoryContentKind.image => 'Photo moment',
      StoryContentKind.video => 'Video clip',
      StoryContentKind.text => 'Text update',
    };
  }

  IconData _contentIcon(StoryContentKind kind) {
    return switch (kind) {
      StoryContentKind.image => Icons.image_outlined,
      StoryContentKind.video => Icons.play_circle_outline_rounded,
      StoryContentKind.text => Icons.text_snippet_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);
    final storiesAsync = ref.watch(storyFeedProvider);

    return VeilShell(
      title: 'Stories',
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(storyFeedProvider);
          await ref.read(storyFeedProvider.future);
        },
        child: storiesAsync.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: VeilSpace.xl),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            children: [
              const SizedBox(height: VeilSpace.md),
              VeilInlineBanner(
                title: 'Stories unavailable',
                message: error.toString(),
                tone: VeilBannerTone.danger,
              ),
            ],
          ),
          data: (stories) {
            final distinctAuthors = <String, StoryFeedEntry>{};
            for (final story in stories) {
              distinctAuthors.putIfAbsent(story.userId, () => story);
            }
            final authors = distinctAuthors.values.toList();

            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: VeilSpace.lg),
                    child: VeilInlineBanner(
                      message:
                          'Stories expire after 24 hours. Content is stored locally until expiration.',
                      icon: Icons.timer_outlined,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: VeilSpace.lg),
                    child: Row(
                      children: [
                        _StoryCircle(
                          label: 'My Story',
                          isAddButton: true,
                          onTap: _showCreateTextStorySheet,
                        ),
                      ],
                    ),
                  ),
                ),
                if (authors.isEmpty && stories.isEmpty)
                  const SliverToBoxAdapter(
                    child: VeilEmptyState(
                      title: 'No stories yet',
                      body:
                          'Stories from your contacts will appear here when they post.',
                      icon: Icons.amp_stories_outlined,
                    ),
                  ),
                if (authors.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: VeilSpace.sm),
                      child: VeilSectionLabel('Recent stories'),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: authors.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: VeilSpace.md),
                        itemBuilder: (context, index) {
                          final author = authors[index];
                          final label =
                              author.displayName?.split(' ').first ??
                                  author.handle;
                          return _StoryCircle(
                            label: label.isEmpty ? author.handle : label,
                            hasSeen: author.viewedByMe,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              context.push('/story-viewer/${author.userId}');
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: VeilSpace.xl),
                  ),
                ],
                if (stories.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: VeilSpace.sm),
                      child: VeilSectionLabel('Feed'),
                    ),
                  ),
                  SliverList.separated(
                    itemCount: stories.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: VeilSpace.sm),
                    itemBuilder: (context, index) {
                      final story = stories[index];
                      final authorLabel =
                          story.displayName ?? story.handle;
                      final glyph = authorLabel.isEmpty
                          ? '?'
                          : authorLabel.characters.first.toUpperCase();

                      return InkWell(
                        borderRadius: BorderRadius.circular(VeilRadius.lg),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.push('/story-viewer/${story.userId}');
                        },
                        child: VeilSurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: palette.primarySoft,
                                    border:
                                        Border.all(color: palette.stroke),
                                  ),
                                  child: Text(
                                    glyph,
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(color: palette.primary),
                                  ),
                                ),
                                const SizedBox(width: VeilSpace.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        authorLabel.isEmpty
                                            ? '@${story.handle}'
                                            : authorLabel,
                                        style: theme.textTheme.titleSmall,
                                      ),
                                      Text(
                                        _shortTimeAgo(story.createdAt),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: palette.textSubtle,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${story.viewCount} views',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: palette.textSubtle,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: VeilSpace.md),
                            Container(
                              height: 180,
                              width: double.infinity,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(VeilRadius.sm),
                                color: palette.surfaceAlt,
                                border: Border.all(color: palette.stroke),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _contentIcon(story.contentType),
                                    size: VeilIconSize.xl,
                                    color: palette.textSubtle,
                                  ),
                                  const SizedBox(height: VeilSpace.xs),
                                  Text(
                                    _contentHint(story.contentType),
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(
                                      color: palette.textSubtle,
                                    ),
                                  ),
                                  if (story.caption != null &&
                                      story.caption!.isNotEmpty) ...[
                                    const SizedBox(height: VeilSpace.xs),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: VeilSpace.md,
                                      ),
                                      child: Text(
                                        story.caption!,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: palette.textMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        ),
                      );
                    },
                  ),
                ],
                const SliverToBoxAdapter(
                  child: SizedBox(height: VeilSpace.xxl),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StoryCircle extends StatelessWidget {
  const _StoryCircle({
    required this.label,
    this.isAddButton = false,
    this.hasSeen = false,
    this.onTap,
  });

  final String label;
  final bool isAddButton;
  final bool hasSeen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);

    final ringColor = hasSeen ? palette.stroke : palette.primaryStrong;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isAddButton ? palette.stroke : ringColor,
                  width: 2,
                ),
              ),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.surfaceAlt,
                ),
                child: isAddButton
                    ? Icon(
                        Icons.add_rounded,
                        size: VeilIconSize.md,
                        color: palette.primary,
                      )
                    : Text(
                        label.characters.first.toUpperCase(),
                        style: theme.textTheme.titleMedium?.copyWith(
                              color: palette.primary,
                            ),
                      ),
              ),
            ),
            const SizedBox(height: VeilSpace.xxs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
