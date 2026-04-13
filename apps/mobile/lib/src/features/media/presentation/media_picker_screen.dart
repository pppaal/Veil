import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class MediaPickerScreen extends StatefulWidget {
  const MediaPickerScreen({super.key});

  @override
  State<MediaPickerScreen> createState() => _MediaPickerScreenState();
}

class _MediaPickerScreenState extends State<MediaPickerScreen> {
  final Set<int> _selected = {};

  static const _placeholderCount = 24;

  void _toggleSelection(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
      } else {
        _selected.add(index);
      }
    });
  }

  void _openCamera(BuildContext context) {
    VeilToast.show(
      context,
      message: 'Camera access requires device permission',
      tone: VeilBannerTone.warn,
    );
  }

  void _sendSelected(BuildContext context) {
    if (_selected.isEmpty) {
      VeilToast.show(
        context,
        message: 'Select at least one item to send',
        tone: VeilBannerTone.info,
      );
      return;
    }
    VeilToast.show(
      context,
      message: '${_selected.length} item(s) queued for encrypted upload',
      tone: VeilBannerTone.good,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);

    return VeilShell(
      title: 'Media',
      padding: EdgeInsets.zero,
      actions: [
        IconButton(
          icon: const Icon(Icons.camera_alt_outlined),
          tooltip: 'Open camera',
          onPressed: () => _openCamera(context),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VeilSpace.lg,
              vertical: VeilSpace.md,
            ),
            child: VeilHeroPanel(
              eyebrow: 'ENCRYPTED MEDIA',
              title: 'Send encrypted media',
              body:
                  'Send encrypted media through the opaque relay. '
                  'Files are sealed on-device before transmission.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VeilSpace.lg),
            child: VeilInlineBanner(
              icon: Icons.lock_outline_rounded,
              message:
                  'Media is encrypted locally before upload. '
                  'The relay never sees plaintext.',
              tone: VeilBannerTone.info,
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VeilSpace.lg),
              child: Row(
                children: [
                  VeilStatusPill(
                    label: '${_selected.length} selected',
                    tone: VeilBannerTone.good,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: VeilSpace.xs),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: VeilSpace.lg),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: VeilSpace.xs,
                crossAxisSpacing: VeilSpace.xs,
              ),
              itemCount: _placeholderCount,
              itemBuilder: (context, index) {
                final isSelected = _selected.contains(index);
                return GestureDetector(
                  onTap: () => _toggleSelection(index),
                  child: AnimatedContainer(
                    duration: VeilMotion.fast,
                    curve: VeilMotion.emphasize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(VeilRadius.sm),
                      border: Border.all(
                        color: isSelected
                            ? palette.primaryStrong
                            : palette.stroke,
                        width: isSelected ? 2 : 1,
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          palette.surfaceAlt,
                          palette.surface,
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Icon(
                            index % 4 == 0
                                ? Icons.videocam_outlined
                                : Icons.image_outlined,
                            size: VeilIconSize.lg,
                            color: palette.textSubtle,
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            top: VeilSpace.xs,
                            right: VeilSpace.xs,
                            child: Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: palette.primary,
                                border: Border.all(
                                  color: palette.primaryStrong,
                                ),
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                size: VeilIconSize.xs,
                                color: palette.canvas,
                              ),
                            ),
                          ),
                        if (index % 4 == 0)
                          Positioned(
                            bottom: VeilSpace.xs,
                            left: VeilSpace.xs,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: VeilSpace.xs,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(VeilRadius.pill),
                                color: palette.canvas.withValues(alpha: 0.7),
                              ),
                              child: Text(
                                '0:${(12 + index).toString().padLeft(2, '0')}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: palette.text,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(VeilSpace.lg),
            decoration: BoxDecoration(
              color: palette.surface.withValues(alpha: 0.9),
              border: Border(top: BorderSide(color: palette.stroke)),
            ),
            child: SafeArea(
              top: false,
              child: VeilButton(
                label: _selected.isEmpty
                    ? 'Select media to send'
                    : 'Send ${_selected.length} selected',
                icon: Icons.send_rounded,
                onPressed:
                    _selected.isEmpty ? null : () => _sendSelected(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
