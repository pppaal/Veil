import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_ui.dart';

class _StorySlide {
  const _StorySlide({
    required this.contentHint,
    required this.timeAgo,
  });

  final String contentHint;
  final String timeAgo;
}

class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.authorName,
    this.authorHandle,
  });

  final String authorName;
  final String? authorHandle;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  static const _autoAdvanceDuration = Duration(seconds: 5);

  final _replyController = TextEditingController();
  final _replyFocusNode = FocusNode();

  final _slides = const <_StorySlide>[
    _StorySlide(contentHint: 'Photo moment', timeAgo: '12m ago'),
    _StorySlide(contentHint: 'Text update', timeAgo: '45m ago'),
    _StorySlide(contentHint: 'Video clip', timeAgo: '2h ago'),
  ];

  int _currentIndex = 0;
  late AnimationController _progressController;
  Timer? _autoAdvanceTimer;

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
    _startAutoAdvance();
  }

  void _startAutoAdvance() {
    _progressController.forward(from: 0);
  }

  void _goNext() {
    if (_currentIndex < _slides.length - 1) {
      setState(() => _currentIndex++);
      _startAutoAdvance();
    } else {
      // Last slide - close viewer
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _goPrevious() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _startAutoAdvance();
    }
  }

  void _handleTap(TapUpDetails details, BoxConstraints constraints) {
    HapticFeedback.selectionClick();
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
    HapticFeedback.selectionClick();
    _replyController.clear();
    _replyFocusNode.unfocus();
    VeilToast.show(
      context,
      message: 'Story replies require messaging integration',
      tone: VeilBannerTone.warn,
    );
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _progressController.dispose();
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);
    final slide = _slides[_currentIndex];
    final avatarGlyph = widget.authorName.isNotEmpty
        ? widget.authorName.characters.first.toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              onTapUp: (details) => _handleTap(details, constraints),
              child: Column(
                children: [
                  // Progress bars
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      VeilSpace.sm,
                      VeilSpace.sm,
                      VeilSpace.sm,
                      0,
                    ),
                    child: Row(
                      children: List.generate(_slides.length, (i) {
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: i > 0 ? 3 : 0,
                            ),
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

                  // Author row
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
                                widget.authorName,
                                style: theme.textTheme.titleSmall,
                              ),
                              Text(
                                slide.timeAgo,
                                style: theme.textTheme.bodySmall?.copyWith(
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

                  // Story content area
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(VeilSpace.lg),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(VeilRadius.lg),
                        color: palette.surfaceAlt,
                        border: Border.all(color: palette.stroke),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            slide.contentHint.contains('Video')
                                ? Icons.play_circle_outline_rounded
                                : Icons.image_outlined,
                            size: 56,
                            color: palette.textSubtle,
                          ),
                          const SizedBox(height: VeilSpace.sm),
                          Text(
                            slide.contentHint,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                          const SizedBox(height: VeilSpace.xxs),
                          Text(
                            '${_currentIndex + 1} of ${_slides.length}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: palette.textSubtle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Reply bar
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
        ),
      ),
    );
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
