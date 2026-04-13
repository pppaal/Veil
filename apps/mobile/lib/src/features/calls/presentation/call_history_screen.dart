import 'package:flutter/material.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

enum _CallDirection { incoming, outgoing, missed }

enum _CallMediaType { voice, video }

class _CallRecord {
  const _CallRecord({
    required this.contactName,
    required this.handle,
    required this.direction,
    required this.mediaType,
    required this.timestamp,
    this.duration,
  });

  final String contactName;
  final String handle;
  final _CallDirection direction;
  final _CallMediaType mediaType;
  final String timestamp;
  final String? duration;
}

const _mockCalls = <_CallRecord>[
  _CallRecord(
    contactName: 'Adriana Voss',
    handle: 'avoss',
    direction: _CallDirection.outgoing,
    mediaType: _CallMediaType.voice,
    timestamp: 'Today, 14:22',
    duration: '4:37',
  ),
  _CallRecord(
    contactName: 'Kieran Lau',
    handle: 'klau',
    direction: _CallDirection.missed,
    mediaType: _CallMediaType.voice,
    timestamp: 'Today, 11:05',
  ),
  _CallRecord(
    contactName: 'Nadia Petrov',
    handle: 'npetrov',
    direction: _CallDirection.incoming,
    mediaType: _CallMediaType.video,
    timestamp: 'Yesterday, 20:18',
    duration: '12:04',
  ),
  _CallRecord(
    contactName: 'Adriana Voss',
    handle: 'avoss',
    direction: _CallDirection.incoming,
    mediaType: _CallMediaType.voice,
    timestamp: 'Yesterday, 09:41',
    duration: '1:58',
  ),
  _CallRecord(
    contactName: 'Marcus Hale',
    handle: 'mhale',
    direction: _CallDirection.missed,
    mediaType: _CallMediaType.video,
    timestamp: 'Apr 10, 17:33',
  ),
];

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final List<_CallRecord> _calls = List.of(_mockCalls);

  IconData _mediaIcon(_CallMediaType type) {
    return switch (type) {
      _CallMediaType.voice => Icons.phone_rounded,
      _CallMediaType.video => Icons.videocam_rounded,
    };
  }

  IconData _directionIcon(_CallDirection dir) {
    return switch (dir) {
      _CallDirection.incoming => Icons.call_received_rounded,
      _CallDirection.outgoing => Icons.call_made_rounded,
      _CallDirection.missed => Icons.call_missed_rounded,
    };
  }

  String _directionLabel(_CallDirection dir) {
    return switch (dir) {
      _CallDirection.incoming => 'Incoming',
      _CallDirection.outgoing => 'Outgoing',
      _CallDirection.missed => 'Missed',
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;

    if (_calls.isEmpty) {
      return VeilShell(
        title: 'Calls',
        child: VeilEmptyState(
          title: 'No call history',
          body: 'Calls you make or receive will appear here.',
          icon: Icons.phone_outlined,
        ),
      );
    }

    return VeilShell(
      title: 'Calls',
      child: ListView.separated(
        itemCount: _calls.length,
        separatorBuilder: (_, __) => const SizedBox(height: VeilSpace.sm),
        itemBuilder: (context, index) {
          final call = _calls[index];
          final isMissed = call.direction == _CallDirection.missed;
          final titleColor = isMissed ? palette.danger : null;

          return VeilListTileCard(
            title: call.contactName,
            subtitle: '${_directionLabel(call.direction)}'
                '${call.duration != null ? '  \u00b7  ${call.duration}' : ''}'
                '  \u00b7  ${call.timestamp}',
            destructive: isMissed,
            leading: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.primarySoft,
                border: Border.all(color: palette.stroke),
              ),
              child: Text(
                call.contactName.characters.first.toUpperCase(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: titleColor ?? palette.primary,
                    ),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _directionIcon(call.direction),
                  size: VeilIconSize.sm,
                  color: isMissed ? palette.danger : palette.textSubtle,
                ),
                const SizedBox(width: VeilSpace.xs),
                Icon(
                  _mediaIcon(call.mediaType),
                  size: VeilIconSize.sm,
                  color: palette.textSubtle,
                ),
              ],
            ),
            onTap: () {
              VeilToast.show(
                context,
                message: 'Call feature requires WebRTC integration',
                tone: VeilBannerTone.warn,
              );
            },
          );
        },
      ),
    );
  }
}
