import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_session_state.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';

// The relay closes a socket itself once the access token it authenticated
// with expires, and socket.io does not reconnect after a disconnect the
// server asked for. An idle app must get a fresh token and reconnect on its
// own, or it stops receiving messages until something else wakes it.

const conv = 'conv-ab';

void main() {
  late FakeRelay relay;
  late MessengerParty alice;
  late MessengerParty bob;

  setUp(() async {
    relay = FakeRelay();
    alice = await MessengerParty.join(relay, handle: 'alice', userId: 'user-alice', deviceId: 'dev-alice');
    bob = await MessengerParty.join(relay, handle: 'bob', userId: 'user-bob', deviceId: 'dev-bob');
    relay.addDirect(conv, 'alice', 'bob');
    await alice.signIn();
    await bob.signIn();
  });

  tearDown(() async {
    await alice.dispose();
    await bob.dispose();
  });

  Future<void> deliver(MessengerParty from, MessengerParty to, String body) async {
    await from.controller.sendText(conversationId: conv, body: body);
    await waitFor(() => from.controller.pendingCountFor(conv) == 0, reason: '"$body" was not acked');
    await waitFor(() async => (await to.bodies(conv)).contains(body), reason: '"$body" is not readable');
  }

  test('a socket the relay closed at token expiry comes back with a fresh token', () async {
    await deliver(alice, bob, 'before expiry');
    final stale = bob.realtime.lastAccessToken!;
    final connects = bob.realtime.connectCount;
    bob.api.refreshTo = (_) => 'token-bob-fresh';

    bob.realtime.serverDisconnect();
    await waitFor(() => bob.realtime.isConnected, timeout: const Duration(seconds: 5), reason: 'bob never reconnected');

    expect(bob.api.tokenRefreshes, [stale]);
    expect(bob.realtime.lastAccessToken, 'token-bob-fresh');
    expect(bob.realtime.connectCount, connects + 1);
    // Live delivery works again.
    await deliver(alice, bob, 'after expiry');
  });

  test('a session that cannot be refreshed stops trying', () async {
    await deliver(alice, bob, 'before expiry');

    bob.realtime.serverDisconnect();
    await waitFor(() => bob.api.tokenRefreshes.isNotEmpty, timeout: const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(seconds: 3));

    expect(bob.api.tokenRefreshes, hasLength(1));
    expect(bob.realtime.isConnected, isFalse);
  });

  test('a disconnect this side made, or a sign-out, refreshes nothing', () async {
    bob.api.refreshTo = (_) => 'token-bob-fresh';
    // The transport dropping is socket.io's to reconnect.
    bob.realtime.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(bob.api.tokenRefreshes, isEmpty);

    await bob.controller.handleAppResumed();
    bob.realtime.serverDisconnect();
    await bob.controller.applySession(const AppSessionState(locked: false, initializing: false));
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(bob.api.tokenRefreshes, isEmpty);
    expect(bob.realtime.isConnected, isFalse);
  });
}
