import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_ui.dart';

enum CallScreenState { dialing, ringing, connected, ended }

enum CallType { voice, video }

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.contactName,
    this.contactHandle,
    this.callType = CallType.voice,
  });

  final String contactName;
  final String? contactHandle;
  final CallType callType;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  CallScreenState _callState = CallScreenState.dialing;
  Duration _elapsed = Duration.zero;
  Timer? _dialTimer;
  Timer? _durationTimer;
  bool _isMuted = false;
  bool _isSpeaker = false;
  bool _isVideo = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _isVideo = widget.callType == CallType.video;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    // Simulate call progression: dialing -> ringing -> connected
    _dialTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _callState = CallScreenState.ringing);
      _dialTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _callState = CallScreenState.connected);
        _startDurationTimer();
      });
    });
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final hours = d.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String get _statusText {
    return switch (_callState) {
      CallScreenState.dialing => 'Calling\u2026',
      CallScreenState.ringing => 'Ringing\u2026',
      CallScreenState.connected => 'Connected ${_formatDuration(_elapsed)}',
      CallScreenState.ended => 'Call ended',
    };
  }

  void _endCall() {
    VeilHaptics.medium();
    _dialTimer?.cancel();
    _durationTimer?.cancel();
    setState(() => _callState = CallScreenState.ended);
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _dialTimer?.cancel();
    _durationTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);
    final avatarGlyph = widget.contactName.isNotEmpty
        ? widget.contactName.characters.first.toUpperCase()
        : '?';
    final isActive = _callState == CallScreenState.dialing ||
        _callState == CallScreenState.ringing ||
        _callState == CallScreenState.connected;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              palette.canvasAlt,
              palette.canvas,
              const Color(0xFF0A0F15),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top banner
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  VeilSpace.lg,
                  VeilSpace.md,
                  VeilSpace.lg,
                  0,
                ),
                child: VeilInlineBanner(
                  message:
                      'Calls are routed peer-to-peer when possible. Relay fallback is encrypted.',
                  icon: Icons.security_rounded,
                ),
              ),

              // Spacer
              const Spacer(flex: 2),

              // Avatar
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final scale = _callState == CallScreenState.dialing ||
                          _callState == CallScreenState.ringing
                      ? 1.0 + (_pulseController.value * 0.05)
                      : 1.0;
                  return Transform.scale(scale: scale, child: child);
                },
                child: Container(
                  width: 120,
                  height: 120,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.primarySoft,
                    border: Border.all(
                      color: palette.strokeStrong,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: palette.primary.withValues(alpha: 0.12),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Text(
                    avatarGlyph,
                    style: theme.textTheme.displayLarge?.copyWith(
                      color: palette.primary,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: VeilSpace.xl),

              // Contact name
              Text(
                widget.contactName,
                style: theme.textTheme.headlineLarge,
                textAlign: TextAlign.center,
              ),

              if (widget.contactHandle != null) ...[
                const SizedBox(height: VeilSpace.xxs),
                Text(
                  '@${widget.contactHandle}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.textSubtle,
                  ),
                ),
              ],

              const SizedBox(height: VeilSpace.sm),

              // Status text
              Text(
                _statusText,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: _callState == CallScreenState.ended
                      ? palette.danger
                      : palette.textMuted,
                ),
              ),

              const Spacer(flex: 3),

              // Action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xxl),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallActionButton(
                      icon: _isMuted
                          ? Icons.mic_off_rounded
                          : Icons.mic_none_rounded,
                      label: _isMuted ? 'Unmute' : 'Mute',
                      active: _isMuted,
                      enabled: isActive,
                      onPressed: () {
                        VeilHaptics.selection();
                        setState(() => _isMuted = !_isMuted);
                      },
                    ),
                    _CallActionButton(
                      icon: _isSpeaker
                          ? Icons.volume_up_rounded
                          : Icons.volume_down_rounded,
                      label: 'Speaker',
                      active: _isSpeaker,
                      enabled: isActive,
                      onPressed: () {
                        VeilHaptics.selection();
                        setState(() => _isSpeaker = !_isSpeaker);
                      },
                    ),
                    _CallActionButton(
                      icon: _isVideo
                          ? Icons.videocam_rounded
                          : Icons.videocam_off_rounded,
                      label: 'Video',
                      active: _isVideo,
                      enabled: isActive,
                      onPressed: () {
                        VeilHaptics.selection();
                        setState(() => _isVideo = !_isVideo);
                      },
                    ),
                    _CallActionButton(
                      icon: Icons.call_end_rounded,
                      label: 'End',
                      destructive: true,
                      enabled: isActive,
                      onPressed: _endCall,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: VeilSpace.hero),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.destructive = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;
  final bool destructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final Color bgColor;
    final Color fgColor;

    if (destructive) {
      bgColor = palette.danger;
      fgColor = palette.canvas;
    } else if (active) {
      bgColor = palette.primary;
      fgColor = palette.canvas;
    } else {
      bgColor = palette.surfaceAlt;
      fgColor = palette.textMuted;
    }

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: Material(
              color: bgColor,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? onPressed : null,
                child: Icon(icon, color: fgColor, size: VeilIconSize.lg),
              ),
            ),
          ),
          const SizedBox(height: VeilSpace.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.textSubtle,
                ),
          ),
        ],
      ),
    );
  }
}
