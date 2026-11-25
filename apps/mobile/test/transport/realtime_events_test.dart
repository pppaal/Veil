import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/realtime/realtime_events.dart';

const _timestamp = '2026-11-11T09:30:00.000Z';

/// One valid payload per typed event, with the variant it must parse into.
final _validPayloads = <String, (Map<String, dynamic>, TypeMatcher<RealtimeEvent>)>{
  'message.new': (
    {
      'id': 'msg-1',
      'clientMessageId': 'client-1',
      'conversationId': 'conv-1',
      'senderDeviceId': 'device-2',
      'conversationOrder': 7,
      'ciphertext': 'ct',
      'nonce': 'n',
      'messageType': 'text',
      'version': 'veil-envelope-v2',
      'attachment': {'attachmentId': 'att-1'},
      'expiresAt': null,
      'serverReceivedAt': _timestamp,
      'deliveredAt': null,
      'readAt': null,
    },
    isA<MessageNewEvent>()
        .having((e) => e.messageId, 'messageId', 'msg-1')
        .having((e) => e.conversationOrder, 'conversationOrder', 7)
        .having((e) => e.serverReceivedAt, 'serverReceivedAt', DateTime.parse(_timestamp)),
  ),
  'message.delivered': (
    {'messageId': 'msg-1', 'userId': 'user-2', 'deliveredAt': _timestamp},
    isA<MessageDeliveredEvent>().having((e) => e.deliveredAt, 'deliveredAt', DateTime.parse(_timestamp)),
  ),
  'message.read': (
    {'messageId': 'msg-1', 'userId': 'user-2', 'readAt': _timestamp},
    isA<MessageReadEvent>().having((e) => e.userId, 'userId', 'user-2'),
  ),
  'message.reaction': (
    {'messageId': 'msg-1', 'userId': 'user-2', 'emoji': '', 'action': 'remove'},
    isA<MessageReactionEvent>().having((e) => e.added, 'added', isFalse),
  ),
  'presence.update': (
    {'userId': 'user-2', 'status': 'online', 'updatedAt': _timestamp},
    isA<PresenceUpdateEvent>().having((e) => e.online, 'online', isTrue),
  ),
  'typing.start': (
    {'conversationId': 'conv-1', 'userId': 'user-2', 'handle': 'atlas'},
    isA<TypingEvent>().having((e) => e.started, 'started', isTrue),
  ),
  'typing.stop': (
    {'conversationId': 'conv-1', 'userId': 'user-2', 'handle': 'atlas'},
    isA<TypingEvent>().having((e) => e.name, 'name', 'typing.stop'),
  ),
  'conversation.sync': (
    {'conversationId': 'conv-1', 'reason': 'membership'},
    isA<ConversationSyncEvent>().having((e) => e.reason, 'reason', ConversationSyncReason.membership),
  ),
  'conversation.timer.changed': (
    {'conversationId': 'conv-1', 'disappearingTimerSeconds': null},
    isA<ConversationTimerChangedEvent>()
        .having((e) => e.disappearingTimerSeconds, 'disappearingTimerSeconds', isNull),
  ),
  'group.key.distribution': (
    {
      'conversationId': 'group-1',
      'epoch': 0,
      'fromUserId': 'user-2',
      'fromDeviceId': 'device-2',
      'encryptedChainKey': 'sealed',
      'nonce': 'n',
      'version': 'veil-group-v1',
      'recipientDeviceId': 'device-1',
    },
    isA<GroupKeyDistributionEvent>().having((e) => e.epoch, 'epoch', 0),
  ),
  'group.epoch.bumped': (
    {'conversationId': 'group-1', 'epoch': 4, 'reason': 'leave', 'userId': 'user-3'},
    isA<GroupEpochBumpedEvent>().having((e) => e.reason, 'reason', GroupMembershipChange.leave),
  ),
};

/// Payloads that must be dropped: (event, payload, why).
final _malformedPayloads = <(String, Object?, String)>[
  ('message.new', {'id': 'msg-1'}, 'missing required fields'),
  ('message.new', _with('message.new', {'conversationOrder': '7'}), 'order as string'),
  ('message.new', _with('message.new', {'serverReceivedAt': 'yesterday'}), 'bad timestamp'),
  ('message.new', _with('message.new', {'readAt': 12}), 'optional timestamp of wrong type'),
  ('message.new', _with('message.new', {'attachment': 'att-1'}), 'attachment not an object'),
  ('message.new', _with('message.new', {'id': ''}), 'empty id'),
  ('message.delivered', _with('message.delivered', {'deliveredAt': 'soon'}), 'bad timestamp'),
  ('message.read', _with('message.read', {'userId': 42}), 'user id not a string'),
  ('message.reaction', _with('message.reaction', {'action': 'toggle'}), 'unknown action'),
  ('presence.update', _with('presence.update', {'status': 'away'}), 'unknown status'),
  ('typing.start', _with('typing.start', {'handle': ''}), 'empty handle'),
  ('conversation.sync', _with('conversation.sync', {'reason': 'other'}), 'unknown reason'),
  ('conversation.timer.changed', {'conversationId': 'conv-1'}, 'timer key absent'),
  ('conversation.timer.changed', _with('conversation.timer.changed', {'disappearingTimerSeconds': 1.5}), 'fractional seconds'),
  ('conversation.timer.changed', _with('conversation.timer.changed', {'disappearingTimerSeconds': -5}), 'negative seconds'),
  ('group.key.distribution', _with('group.key.distribution', {'epoch': -1}), 'negative epoch'),
  ('group.key.distribution', _with('group.key.distribution', {'encryptedChainKey': ''}), 'empty chain key'),
  ('group.epoch.bumped', _with('group.epoch.bumped', {'reason': 'kick'}), 'unknown reason'),
  ('group.epoch.bumped', _with('group.epoch.bumped', {'epoch': '4'}), 'epoch as string'),
  ('presence.update', 'online', 'payload not a map'),
  ('typing.stop', null, 'null payload'),
  ('message.read', <Object?, Object?>{'messageId': 'm', 'userId': 'u', 'readAt': _timestamp}, 'map without string keys'),
];

Map<String, dynamic> _with(String event, Map<String, dynamic> overrides) {
  return {..._validPayloads[event]!.$1, ...overrides};
}

void main() {
  test('every contract event is either typed or explicitly ignored', () {
    final ignored = kIgnoredRealtimeEvents.keys.toSet();
    final typed = _validPayloads.keys.toSet();

    expect(ignored.intersection(typed), isEmpty);
    expect(ignored.union(typed), kRealtimeEventNames);
    expect(kIgnoredRealtimeEvents.values, everyElement(isNotEmpty));
  });

  group('valid payloads parse into their typed variant', () {
    for (final MapEntry(key: event, value: (payload, matcher)) in _validPayloads.entries) {
      test(event, () {
        final parsed = RealtimeEvent.tryParse(event, payload);
        expect(parsed, matcher);
        expect(parsed!.name, event);
      });
    }
  });

  group('malformed payloads are rejected without throwing', () {
    for (final (event, payload, why) in _malformedPayloads) {
      test('$event: $why', () {
        expect(RealtimeEvent.tryParse(event, payload), isNull);
      });
    }
  });

  test('ignored and unknown events pass through as UnknownRealtimeEvent', () {
    for (final event in [...kIgnoredRealtimeEvents.keys, 'not.in.contract']) {
      final parsed = RealtimeEvent.tryParse(event, 'any payload');
      expect(
        parsed,
        isA<UnknownRealtimeEvent>()
            .having((e) => e.name, 'name', event)
            .having((e) => e.payload, 'payload', 'any payload'),
      );
    }
  });

  test('message.new keeps the whole summary for the envelope codec', () {
    final payload = _validPayloads['message.new']!.$1;

    final parsed = RealtimeEvent.tryParse('message.new', payload) as MessageNewEvent;

    expect(parsed.summary, same(payload));
  });
}
