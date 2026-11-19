import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/local_notice.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';

const conv = 'conv-ab';

// The responder side of the pins: a PreKey frame's handshake proves the
// initiator's identity, and the verifier holds that proof against the pin
// before the adapter keeps any session state.
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

  test('prekey frame with identity mismatching pin yields identityRejected and no session', () async {
    // bob met alice's device under another key before.
    final earlier = await LibCryptoAdapter().identity.generateDeviceIdentity('dev-alice');
    await bob.pins.evaluate('user-alice', 'dev-alice', earlier.identityPublicKey);

    await alice.controller.sendText(conversationId: conv, body: 'hello bob');
    await waitFor(() => alice.controller.pendingCountFor(conv) == 0);
    await waitFor(() => bob.controller.messagesFor(conv).any((m) => !m.isLocalNotice));

    final frame = bob.controller.messagesFor(conv).firstWhere((m) => !m.isLocalNotice);
    final opened = await bob.controller.decryptMessage(frame);
    expect(opened.status, DecryptStatus.identityRejected);
    expect(opened.body, isEmpty);
    expect(bob.lib.sessions.hasSessionFor(conv), isFalse);
    expect(bob.controller.conversations.single.sessionState, isNull);
    final change = bob.controller.pendingIdentityChangeFor(conv)!;
    expect(change.presentedKey, alice.device.identity.identityPublicKey);
    expect(change.previousKey, earlier.identityPublicKey);
    await waitFor(() => bob.controller.messagesFor(conv).any((m) => m.isLocalNotice));
    final notice = bob.controller.messagesFor(conv).firstWhere((m) => m.isLocalNotice);
    expect((await bob.controller.decryptMessage(notice)).body, LocalNoticeCodes.identityChanged);
    expect((await bob.pins.pinFor('user-alice', 'dev-alice'))!.identityKey, earlier.identityPublicKey);
  });

  test('approving the new identity reopens the held-back frame', () async {
    final earlier = await LibCryptoAdapter().identity.generateDeviceIdentity('dev-alice');
    await bob.pins.evaluate('user-alice', 'dev-alice', earlier.identityPublicKey);
    await alice.controller.sendText(conversationId: conv, body: 'it is really me');
    await waitFor(() => bob.controller.pendingIdentityChangeFor(conv) != null);

    await bob.controller.approveIdentityChange(conv);

    await waitFor(() async => (await bob.bodies(conv)).contains('it is really me'));
    expect(bob.lib.sessions.hasSessionFor(conv), isTrue);
    expect(bob.controller.pendingIdentityChangeFor(conv), isNull);
  });
}
