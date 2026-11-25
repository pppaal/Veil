import 'package:flutter_test/flutter_test.dart';

import '../layout/support/layout_seed.dart';
import '../layout/support/layout_world.dart';

// The verified mark says "this is the person whose number you compared".
// While a key change of theirs waits for review that is exactly what is in
// question, so nothing may show them as verified: not the chat they wrote
// in, not another chat with them, not a group's member list.

void main() {
  late LayoutIdentities identities;

  setUpAll(() async => identities = await LayoutIdentities.generate());

  test('a contact with an identity change pending is not verified, in any conversation', () async {
    final world = await LayoutWorld.create(
      identities: identities,
      account: LayoutAccount.signedIn,
      locale: 'en',
      withGroup: true,
    );
    addTearDown(world.dispose);
    final messenger = world.messenger;
    final peer = world.relay.partiesByHandle[peerHandle]!;

    // The seeded peer was compared out of band.
    expect(await messenger.isPeerVerified(chatConversationId), isTrue);
    expect(await messenger.isUserVerified(peer.userId), isTrue);

    // Their device presents another key: held for review. The pin the user
    // verified is untouched, and still reads "verified" on its own.
    final anotherKey = identities.self.identityPublicKey;
    expect(await world.trust.admit(chatConversationId, peer.userId, peer.deviceId, anotherKey), isFalse);
    final change = messenger.pendingIdentityChangeFor(chatConversationId);
    expect(change, isNotNull);
    expect((await world.trust.resolver.pinsForUser(peer.userId)).every((pin) => pin.isVerified), isTrue,
        reason: 'the old pin stays verified while the change is pending');

    expect(await messenger.isPeerVerified(chatConversationId), isFalse);
    expect(await messenger.isUserVerified(peer.userId), isFalse);

    // Accepted after a fresh comparison, they are verified again.
    await messenger.approveIdentityChange(chatConversationId, reverified: true, reviewed: change);
    expect(messenger.pendingIdentityChangeFor(chatConversationId), isNull);
    expect(await messenger.isPeerVerified(chatConversationId), isTrue);
  });

  test('a change raised in one conversation takes the mark away in the others', () async {
    final world = await LayoutWorld.create(
      identities: identities,
      account: LayoutAccount.signedIn,
      locale: 'en',
      withGroup: true,
    );
    addTearDown(world.dispose);
    final messenger = world.messenger;
    final peer = world.relay.partiesByHandle[peerHandle]!;

    // Raised through the group they are both in, not through their 1:1.
    final anotherKey = identities.self.identityPublicKey;
    expect(await world.trust.admit(groupConversationId, peer.userId, peer.deviceId, anotherKey), isFalse);
    expect(messenger.pendingIdentityChangeFor(chatConversationId), isNull);
    expect(messenger.pendingIdentityChangeFor(groupConversationId), isNotNull);

    expect(await messenger.isPeerVerified(chatConversationId), isFalse);
    expect(await messenger.isUserVerified(peer.userId), isFalse);

    // A contact nobody raised a change about is not affected.
    final other = world.relay.partiesByHandle['priya']!;
    expect(world.trust.hasPendingChangeAbout(other.userId), isFalse);
  });

  test('a group is never "verified" as a whole', () async {
    final world = await LayoutWorld.create(
      identities: identities,
      account: LayoutAccount.signedIn,
      locale: 'en',
      withGroup: true,
    );
    addTearDown(world.dispose);
    expect(await world.messenger.isPeerVerified(groupConversationId), isFalse);
    expect(await world.messenger.isUserVerified(''), isFalse);
  });
}
