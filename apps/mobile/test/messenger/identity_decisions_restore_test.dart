import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/core/util/base64url.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';

// A pending identity change the device kept is shown once the app signs in,
// even when nothing at sign-in asks the trust layer for a decision (no
// conversation to open, no frame to check). A sign-in forgets only what the
// trust layer holds in memory, so the messenger reads the record back itself.
void main() {
  String key(int seed) => base64UrlNoPadEncode(List<int>.generate(32, (i) => (seed + i) % 256));

  test('a kept pending change is shown as soon as the app signs in', () async {
    final relay = FakeRelay();
    final atlas = await MessengerParty.join(relay, handle: 'atlas', userId: 'user-atlas', deviceId: 'dev-atlas');
    addTearDown(atlas.dispose);
    // An earlier run of the app held a key change for selene's device.
    final earlier = IdentityTrust(atlas.pins, decisions: atlas.keystore.scoped(SecureScope.identity));
    expect(await earlier.admit('conv-as', 'user-selene', 'dev-selene', key(1)), isTrue);
    expect(await earlier.admit('conv-as', 'user-selene', 'dev-selene', key(2)), isFalse);

    var shown = false;
    atlas.controller.addListener(() {
      if (atlas.controller.pendingIdentityChangeFor('conv-as') != null) shown = true;
    });
    await atlas.signIn();

    await waitFor(() => shown, reason: 'the kept change was not read back after sign-in');
    expect(atlas.controller.pendingIdentityChangeFor('conv-as')?.presentedKey, key(2));
  });
}
