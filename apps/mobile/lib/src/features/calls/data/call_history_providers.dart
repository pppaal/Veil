import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';

enum CallMediaKind { voice, video }

enum CallDirection { incoming, outgoing }

enum CallOutcome { completed, missed, declined, ringing }

class CallHistoryEntry {
  const CallHistoryEntry({
    required this.id,
    required this.conversationId,
    required this.counterparty,
    required this.counterpartyHandle,
    required this.media,
    required this.direction,
    required this.outcome,
    required this.startedAt,
    this.duration,
  });

  final String id;
  final String conversationId;
  final String counterparty;
  final String? counterpartyHandle;
  final CallMediaKind media;
  final CallDirection direction;
  final CallOutcome outcome;
  final DateTime startedAt;
  final Duration? duration;

  static CallHistoryEntry fromJson(Map<String, dynamic> json) {
    final rawType = (json['callType'] as String?) ?? 'voice';
    final rawStatus = (json['status'] as String?) ?? 'ended';
    final initiatedByMe = json['initiatedByMe'] == true;
    final durationSec = json['duration'] as int?;
    return CallHistoryEntry(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      counterparty: (json['counterparty'] as String?) ?? 'Unknown',
      counterpartyHandle: json['counterpartyHandle'] as String?,
      media: rawType == 'video' ? CallMediaKind.video : CallMediaKind.voice,
      direction:
          initiatedByMe ? CallDirection.outgoing : CallDirection.incoming,
      outcome: switch (rawStatus) {
        'missed' => CallOutcome.missed,
        'declined' => CallOutcome.declined,
        'ringing' => CallOutcome.ringing,
        _ => CallOutcome.completed,
      },
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '')
              ?.toLocal() ??
          DateTime.now(),
      duration: durationSec != null ? Duration(seconds: durationSec) : null,
    );
  }
}

final callHistoryProvider =
    FutureProvider.autoDispose<List<CallHistoryEntry>>((ref) async {
  final session = ref.watch(appSessionProvider);
  if (!session.isAuthenticated || session.accessToken == null) {
    return const <CallHistoryEntry>[];
  }
  final apiClient = ref.read(apiClientProvider);
  final raw = await apiClient.getCallHistory(session.accessToken!);
  return raw
      .whereType<Map<String, dynamic>>()
      .map(CallHistoryEntry.fromJson)
      .toList();
});
