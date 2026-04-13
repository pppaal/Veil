import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

enum _RecordingState { idle, recording, preview }

class VoiceRecorderScreen extends StatefulWidget {
  const VoiceRecorderScreen({super.key});

  @override
  State<VoiceRecorderScreen> createState() => _VoiceRecorderScreenState();
}

class _VoiceRecorderScreenState extends State<VoiceRecorderScreen>
    with SingleTickerProviderStateMixin {
  _RecordingState _state = _RecordingState.idle;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  bool _previewPlaying = false;

  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _waveController.dispose();
    super.dispose();
  }

  void _startRecording() {
    HapticFeedback.mediumImpact();
    setState(() {
      _state = _RecordingState.recording;
      _elapsed = Duration.zero;
    });
    _waveController.repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  void _stopRecording() {
    HapticFeedback.selectionClick();
    _timer?.cancel();
    _waveController.stop();
    setState(() => _state = _RecordingState.preview);
  }

  void _cancelRecording() {
    _timer?.cancel();
    _waveController.stop();
    setState(() {
      _state = _RecordingState.idle;
      _elapsed = Duration.zero;
      _previewPlaying = false;
    });
  }

  void _togglePreviewPlayback() {
    HapticFeedback.selectionClick();
    setState(() => _previewPlaying = !_previewPlaying);
  }

  void _sendVoiceMessage(BuildContext context) {
    VeilToast.show(
      context,
      message: 'Voice message encrypted and queued for relay',
      tone: VeilBannerTone.good,
    );
    Navigator.of(context).pop();
  }

  String get _formattedTime {
    final minutes = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);

    return VeilShell(
      title: 'Voice Message',
      child: Column(
        children: [
          const Spacer(flex: 1),
          VeilInlineBanner(
            icon: Icons.lock_outline_rounded,
            message: 'Voice data is encrypted on this device before relay.',
            tone: VeilBannerTone.info,
          ),
          const SizedBox(height: VeilSpace.xxl),
          Text(
            _formattedTime,
            style: theme.textTheme.displayLarge?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: _state == _RecordingState.recording
                  ? palette.text
                  : palette.textMuted,
            ),
          ),
          const SizedBox(height: VeilSpace.xl),
          SizedBox(
            height: 64,
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, _) {
                return CustomPaint(
                  size: const Size(double.infinity, 64),
                  painter: _WaveformPainter(
                    progress: _waveController.value,
                    active: _state == _RecordingState.recording,
                    color: palette.primary,
                    mutedColor: palette.textSubtle,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: VeilSpace.xxxl),
          _buildCenterControl(palette, theme),
          const Spacer(flex: 2),
          _buildBottomActions(context, palette),
          const SizedBox(height: VeilSpace.lg),
        ],
      ),
    );
  }

  Widget _buildCenterControl(VeilPalette palette, ThemeData theme) {
    switch (_state) {
      case _RecordingState.idle:
        return _RecordButton(
          onTap: _startRecording,
          palette: palette,
          icon: Icons.mic_rounded,
          label: 'Tap to record',
          glowing: false,
        );
      case _RecordingState.recording:
        return _RecordButton(
          onTap: _stopRecording,
          palette: palette,
          icon: Icons.stop_rounded,
          label: 'Recording...',
          glowing: true,
        );
      case _RecordingState.preview:
        return _RecordButton(
          onTap: _togglePreviewPlayback,
          palette: palette,
          icon: _previewPlaying
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          label: _previewPlaying ? 'Playing' : 'Tap to preview',
          glowing: false,
        );
    }
  }

  Widget _buildBottomActions(BuildContext context, VeilPalette palette) {
    if (_state == _RecordingState.idle) {
      return const SizedBox.shrink();
    }

    return VeilActionRow(
      children: [
        VeilButton(
          label: 'Cancel',
          tone: VeilButtonTone.secondary,
          icon: Icons.close_rounded,
          onPressed: _cancelRecording,
        ),
        if (_state == _RecordingState.preview)
          VeilButton(
            label: 'Send',
            tone: VeilButtonTone.primary,
            icon: Icons.send_rounded,
            onPressed: () => _sendVoiceMessage(context),
          ),
      ],
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.onTap,
    required this.palette,
    required this.icon,
    required this.label,
    required this.glowing,
  });

  final VoidCallback onTap;
  final VeilPalette palette;
  final IconData icon;
  final String label;
  final bool glowing;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: VeilMotion.normal,
            curve: VeilMotion.emphasize,
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: glowing ? palette.danger : palette.primarySoft,
              border: Border.all(
                color: glowing ? palette.danger : palette.strokeStrong,
                width: 2,
              ),
              boxShadow: glowing
                  ? [
                      BoxShadow(
                        color: palette.danger.withValues(alpha: 0.3),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              size: VeilIconSize.xl,
              color: glowing ? palette.canvas : palette.primary,
            ),
          ),
        ),
        const SizedBox(height: VeilSpace.md),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.textMuted,
              ),
        ),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.progress,
    required this.active,
    required this.color,
    required this.mutedColor,
  });

  final double progress;
  final bool active;
  final Color color;
  final Color mutedColor;

  static const _barCount = 32;
  static const _barWidth = 3.0;
  static const _barGap = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = active ? color : mutedColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _barWidth;

    final rng = Random(42);
    final totalBarWidth = _barCount * (_barWidth + _barGap) - _barGap;
    final startX = (size.width - totalBarWidth) / 2;

    for (var i = 0; i < _barCount; i++) {
      final seed = rng.nextDouble();
      final amplitude = active
          ? 0.2 + 0.8 * seed * (0.5 + 0.5 * sin(progress * pi * 2 + i * 0.4))
          : 0.1 + 0.15 * seed;
      final barHeight = max(4.0, size.height * amplitude);
      final x = startX + i * (_barWidth + _barGap);
      final y = (size.height - barHeight) / 2;

      canvas.drawLine(
        Offset(x, y),
        Offset(x, y + barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.active != active;
}
