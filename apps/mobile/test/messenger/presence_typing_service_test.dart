import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/realtime/realtime_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/presence_typing_service.dart';

class _RecordingRealtime extends RealtimeService {
  final List<(String, Map<String, dynamic>)> emitted = [];

  @override
  void emit(String event, Map<String, dynamic> payload) => emitted.add((event, payload));
}

void main() {
  late _RecordingRealtime realtime;
  late PresenceTypingService presence;
  var connected = true;
  var typingEnabled = true;

  setUp(() {
    realtime = _RecordingRealtime();
    connected = true;
    typingEnabled = true;
    presence = PresenceTypingService(
      realtime: realtime,
      isConnected: () => connected,
      typingIndicatorsEnabled: () => typingEnabled,
    );
  });

  tearDown(() => presence.dispose());

  test('two conversations clear independently after 5s', () {
    fakeAsync((async) {
      presence.typingStarted('conv-a', 'atlas');
      async.elapse(const Duration(seconds: 3));
      presence.typingStarted('conv-b', 'selene');

      async.elapse(const Duration(seconds: 2));
      expect(presence.typingHandleFor('conv-a'), isNull, reason: 'conv-a went quiet 5s ago');
      expect(presence.typingHandleFor('conv-b'), 'selene', reason: "conv-b's indicator is its own");

      async.elapse(const Duration(seconds: 3));
      expect(presence.typingHandleFor('conv-b'), isNull);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('a renewed signal restarts only its own timeout', () {
    fakeAsync((async) {
      presence.typingStarted('conv-a', 'atlas');
      presence.typingStarted('conv-b', 'selene');
      async.elapse(const Duration(seconds: 4));
      presence.typingStarted('conv-a', 'atlas');

      async.elapse(const Duration(seconds: 1));
      expect(presence.typingHandleFor('conv-a'), 'atlas');
      expect(presence.typingHandleFor('conv-b'), isNull);

      async.elapse(const Duration(seconds: 4));
      expect(presence.typingHandleFor('conv-a'), isNull);
    });
  });

  test('typing.stop clears at once and notifies', () {
    var notifications = 0;
    presence.addListener(() => notifications += 1);

    presence.typingStarted('conv-a', 'atlas');
    presence.typingStopped('conv-a');

    expect(presence.typingHandleFor('conv-a'), isNull);
    expect(notifications, 2);
  });

  test('presence follows the latest update per user', () {
    presence.presenceChanged('user-atlas', online: true);
    presence.presenceChanged('user-selene', online: true);
    presence.presenceChanged('user-atlas', online: false);

    expect(presence.isUserOnline('user-atlas'), isFalse);
    expect(presence.isUserOnline('user-selene'), isTrue);
  });

  test('local typing emits start once and stop after a pause or a send', () {
    fakeAsync((async) {
      presence.localTyping('conv-a');
      presence.localTyping('conv-a');
      expect(realtime.emitted.map((event) => event.$1), ['typing.start']);

      async.elapse(const Duration(seconds: 3));
      expect(realtime.emitted.map((event) => event.$1), ['typing.start', 'typing.stop']);

      presence.localTyping('conv-a');
      presence.localTypingEnded('conv-a');
      async.elapse(const Duration(seconds: 3));
      expect(realtime.emitted.map((event) => event.$1), ['typing.start', 'typing.stop', 'typing.start', 'typing.stop']);
    });
  });

  test('local typing says nothing when disconnected or switched off', () {
    connected = false;
    presence.localTyping('conv-a');
    connected = true;
    typingEnabled = false;
    presence.localTyping('conv-a');

    expect(realtime.emitted, isEmpty);
  });
}
