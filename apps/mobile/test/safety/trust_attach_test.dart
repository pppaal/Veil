import 'package:flutter_test/flutter_test.dart';

import '../layout/support/layout_world.dart';
import '../support/layout_trust.dart';

// The trust layer listens to the messenger it is attached to: attached
// twice it would hear every change, every identity event and every
// nickname twice. The app attaches it once (messengerControllerProvider),
// the layout world once (LayoutWorld.create), and a second attach is
// refused.

void main() {
  late LayoutIdentities identities;

  setUpAll(() async => identities = await LayoutIdentities.generate());

  test('the layout world attaches the trust layer once, and a second attach is refused', () async {
    final world = await LayoutWorld.create(identities: identities, account: LayoutAccount.signedIn, locale: 'en');
    addTearDown(world.dispose);
    expect(world.contactTrust.ready, isTrue, reason: 'attached and read by create');

    // What the phone tests call reads the same trust layer and attaches
    // nothing more.
    expect(await attachContactTrust(world), same(world.contactTrust));
    expect(
      () => world.contactTrust.attach(world.messenger, trustEvents: world.trust.events),
      throwsA(isA<AssertionError>()),
    );
  });
}
