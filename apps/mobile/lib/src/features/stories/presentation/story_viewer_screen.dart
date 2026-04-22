import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_ui.dart';
import '../data/story_feed_providers.dart';

class StoryViewerScreen extends ConsumerStatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.authorUserId,
  });

  final String authorUserId;

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  static const _autoAdvanceDuration = Duration(seconds: 5);

  final _replyController = TextEditingController();
  final _replyFocusNode = FocusNode();

  int _currentIndex = 0;
  late AnimationController _progressController;
  String? _lastMarkedViewId;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: _autoAdvanceDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _goNext();
        }
      });
  }

  @override
  void dispose() {
    _progressController.dispose();
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  List<StoryFeedEntry> _slidesFor(List<StoryFeedEntry> feed) {
    return feed.where((s) => s.userId == widget.authorUserId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  void _restartProgress() {
    _progressController
      ..stop()
      ..reset()
      ..forward();
  }

  void _goNext() {
    final feed = ref.read(storyFeedProvider).value ?? const [];
    final slides = _slidesFor(feed);
    if (_currentIndex < slides.length - 1) {
      setState(() => _currentIndex++);
      _restartProgress();
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _goPrevious() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _restartProgress();
    } else {
      _restartProgress();
    }
  }

  void _handleTap(TapUpDetails details, BoxConstraints constraints) {
    VeilHaptics.selection();
    final tapX = details.localPosition.dx;
    if (tapX < constraints.maxWidth * 0.35) {
      _goPrevious();
    } else {
      _goNext();
    }
  }

  void _sendReply() {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    VeilHaptics.selection();
    _replyController.clear();
    _replyFocusNode.unfocus();
    VeilToast.show(
      context,
      message: 'Story replies require messaging integration',
      tone: VeilBannerTone.warn,
    );
  }

  String _shortTimeAgo(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _syncViewTracking(StoryFeedEntry currentStory) {
    if (_lastMarkedViewId == currentStory.id) return;
    _lastMarkedViewId = currentStory.id;
    unawaited(markStoryViewed(ref, currentStory.id));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);
    final feedAsync = ref.watch(storyFeedProvider);

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: feedAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(VeilSpace.lg),
              child: VeilInlineBanner(
                title: 'Unable to load stories',
                message: error.toString(),
                tone: VeilBannerTone.danger,
              ),
            ),
          ),
          data: (feed) {
            final slides = _slidesFor(feed);
            if (slides.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(VeilSpace.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.amp_stories_outlined,
                        size: 64,
                        color: palette.textSubtle,
                      ),
                      const SizedBox(height: VeilSpace.md),
                      Text(
                        'No stories from this user',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: VeilSpace.sm),
                      VeilButton(
                        label: 'Close',
                        icon: Icons.close_rounded,
                        tone: VeilButtonTone.secondary,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (_currentIndex >= slides.length) {
              _currentIndex = slides.length - 1;
            }
            final slide = slides[_currentIndex];
            _syncViewTracking(slide);
            if (!_progressController.isAnimating &&
                _progressController.value == 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _progressController.forward();
              });
            }

            final authorLabel = slide.displayName?.isNotEmpty == true
                ? slide.displayName!
                : '@${slide.handle}';
            final avatarGlyph = authorLabel.isNotEmpty
                ? authorLabel.replaceAll('@', '').characters.first.toUpperCase()
                : '?';

            return LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapUp: (details) => _handleTap(details, constraints),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          VeilSpace.sm,
                          VeilSpace.sm,
                          VeilSpace.sm,
                          0,
                        ),
                        child: Row(
                          children: List.generate(slides.length, (i) {
                            return Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(left: i > 0 ? 3 : 0),
                                child: _SegmentedProgressBar(
                                  controller: i == _currentIndex
                                      ? _progressController
                                      : null,
                                  filled: i < _currentIndex,
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: VeilSpace.sm),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: VeilSpace.lg,
                        ),
                        child: Row(
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
                                avatarGlyph,
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
                                    authorLabel,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  Text(
                                    _shortTimeAgo(slide.createdAt),
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: palette.textSubtle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                color: palette.textMuted,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(VeilSpace.lg),
                          padding: const EdgeInsets.all(VeilSpace.xl),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(VeilRadius.lg),
                            color: palette.surfaceAlt,
                            border: Border.all(color: palette.stroke),
                          ),
                          child: _SlideContent(slide: slide),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          VeilSpace.lg,
                          0,
                          VeilSpace.lg,
                          VeilSpace.md,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _replyController,
                                focusNode: _replyFocusNode,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _sendReply(),
                                decoration: const InputDecoration(
                                  hintText: 'Reply to story\u2026',
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: VeilSpace.lg,
                                    vertical: VeilSpace.sm,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: VeilSpace.sm),
                            SizedBox(
                              width: 48,
                              height: 48,
                              child: IconButton(
                                icon: Icon(
                                  Icons.send_rounded,
                                  color: palette.primary,
                                  size: VeilIconSize.md,
                                ),
                                tooltip: 'Send reply',
                                onPressed: _sendReply,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SlideContent extends StatelessWidget {
  const _SlideContent({required this.slide});

  final StoryFeedEntry slide;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);

    switch (slide.contentType) {
      case StoryContentKind.text:
        final body = slide.caption?.isNotEmpty == true
            ? slide.caption!
            : 'Empty story';
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.format_quote_rounded,
              size: 48,
              color: palette.textSubtle,
            ),
            const SizedBox(height: VeilSpace.md),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: palette.text,
              ),
            ),
          ],
        );
      case StoryContentKind.image:
      case StoryContentKind.video:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              slide.contentType == StoryContentKind.video
                  ? Icons.play_circle_outline_rounded
                  : Icons.image_outlined,
              size: 64,
              color: palette.textSubtle,
            ),
            const SizedBox(height: VeilSpace.sm),
            Text(
              slide.contentType == StoryContentKind.video
                  ? 'Video story'
                  : 'Photo story',
              style: theme.textTheme.titleMedium?.copyWith(
                color: palette.textMuted,
              ),
            ),
            if (slide.caption != null && slide.caption!.isNotEmpty) ...[
              const SizedBox(height: VeilSpace.xs),
              Text(
                slide.caption!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
            const SizedBox(height: VeilSpace.md),
            Text(
              'Media rendering not yet connected',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textSubtle,
              ),
            ),
          ],
        );
    }
  }
}

class _SegmentedProgressBar extends StatelessWidget {
  const _SegmentedProgressBar({
    this.controller,
    this.filled = false,
  });

  final AnimationController? controller;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;

    if (controller != null) {
      return AnimatedBuilder(
        animation: controller!,
        builder: (context, _) {
          return _buildBar(palette, controller!.value);
        },
      );
    }

    return _buildBar(palette, filled ? 1.0 : 0.0);
  }

  Widget _buildBar(VeilPalette palette, double progress) {
    return Container(
      height: 3,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VeilRadius.pill),
        color: palette.surfaceOverlay,
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VeilRadius.pill),
            color: palette.text,
          ),
        ),
      ),
    );
  }
}
