import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class _StoryAuthor {
  const _StoryAuthor({
    required this.name,
    required this.handle,
    this.hasSeen = false,
  });

  final String name;
  final String handle;
  final bool hasSeen;
}

class _StoryCard {
  const _StoryCard({
    required this.authorName,
    required this.authorHandle,
    required this.timeAgo,
    required this.viewCount,
    required this.contentHint,
  });

  final String authorName;
  final String authorHandle;
  final String timeAgo;
  final int viewCount;
  final String contentHint;
}

const _mockAuthors = <_StoryAuthor>[
  _StoryAuthor(name: 'Adriana Voss', handle: 'avoss'),
  _StoryAuthor(name: 'Kieran Lau', handle: 'klau'),
  _StoryAuthor(name: 'Nadia Petrov', handle: 'npetrov', hasSeen: true),
  _StoryAuthor(name: 'Marcus Hale', handle: 'mhale'),
];

const _mockStoryCards = <_StoryCard>[
  _StoryCard(
    authorName: 'Adriana Voss',
    authorHandle: 'avoss',
    timeAgo: '12m ago',
    viewCount: 14,
    contentHint: 'Photo moment',
  ),
  _StoryCard(
    authorName: 'Kieran Lau',
    authorHandle: 'klau',
    timeAgo: '1h ago',
    viewCount: 38,
    contentHint: 'Text update',
  ),
  _StoryCard(
    authorName: 'Marcus Hale',
    authorHandle: 'mhale',
    timeAgo: '3h ago',
    viewCount: 7,
    contentHint: 'Photo moment',
  ),
  _StoryCard(
    authorName: 'Nadia Petrov',
    authorHandle: 'npetrov',
    timeAgo: '8h ago',
    viewCount: 52,
    contentHint: 'Video clip',
  ),
];

class StoriesScreen extends StatelessWidget {
  const StoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);

    return VeilShell(
      title: 'Stories',
      child: CustomScrollView(
        slivers: [
          // Privacy banner
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: VeilSpace.lg),
              child: VeilInlineBanner(
                message:
                    'Stories expire after 24 hours. Content is stored locally until expiration.',
                icon: Icons.timer_outlined,
              ),
            ),
          ),

          // My Story section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: VeilSpace.lg),
              child: Row(
                children: [
                  _StoryCircle(
                    label: 'My Story',
                    isAddButton: true,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      VeilToast.show(
                        context,
                        message: 'Story creation requires media capture',
                        tone: VeilBannerTone.warn,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Section label
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: VeilSpace.sm),
              child: VeilSectionLabel('Recent stories'),
            ),
          ),

          // Horizontal story circles
          SliverToBoxAdapter(
            child: SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _mockAuthors.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: VeilSpace.md),
                itemBuilder: (context, index) {
                  final author = _mockAuthors[index];
                  return _StoryCircle(
                    label: author.name.split(' ').first,
                    hasSeen: author.hasSeen,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      VeilToast.show(
                        context,
                        message: 'Story viewer not yet connected',
                        tone: VeilBannerTone.info,
                      );
                    },
                  );
                },
              ),
            ),
          ),

          const SliverToBoxAdapter(
            child: SizedBox(height: VeilSpace.xl),
          ),

          // Feed section label
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: VeilSpace.sm),
              child: VeilSectionLabel('Feed'),
            ),
          ),

          // Story feed cards
          SliverList.separated(
            itemCount: _mockStoryCards.length,
            separatorBuilder: (_, __) => const SizedBox(height: VeilSpace.sm),
            itemBuilder: (context, index) {
              final card = _mockStoryCards[index];
              final glyph =
                  card.authorName.characters.first.toUpperCase();

              return VeilSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Author row
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette.primarySoft,
                            border: Border.all(color: palette.stroke),
                          ),
                          child: Text(
                            glyph,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: palette.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: VeilSpace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                card.authorName,
                                style: theme.textTheme.titleSmall,
                              ),
                              Text(
                                card.timeAgo,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: palette.textSubtle,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${card.viewCount} views',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.textSubtle,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: VeilSpace.md),

                    // Content placeholder
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
                            card.contentHint.contains('Video')
                                ? Icons.play_circle_outline_rounded
                                : Icons.image_outlined,
                            size: VeilIconSize.xl,
                            color: palette.textSubtle,
                          ),
                          const SizedBox(height: VeilSpace.xs),
                          Text(
                            card.contentHint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: palette.textSubtle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SliverToBoxAdapter(
            child: SizedBox(height: VeilSpace.xxl),
          ),
        ],
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

    final ringColor =
        hasSeen ? palette.stroke : palette.primaryStrong;

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
