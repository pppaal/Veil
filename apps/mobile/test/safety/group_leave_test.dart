import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/safety/data/group_leave.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';
import 'trust_support.dart';

// Leaving a group from its message request bar (GroupLeave), on a real
// messenger over the fake relay: the existing leave route, then the list.

void main() {
  late FakeRelay relay;
  late MessengerParty alice;
  late MessengerParty dave;

  setUp(() async {
    relay = trustRelay();
    alice = await phone(relay, 'alice', requests: true);
    dave = await phone(relay, 'dave');
    await alice.signIn();
    await dave.signIn();
    await trustReady(alice);
  });

  tearDown(() async {
    await alice.dispose();
    await dave.dispose();
  });

  test('leaving a group request posts the leave route and drops the chat', () async {
    // A stranger adds alice to a group.
    relay.addGroup('grp-dave', ['dave', 'alice'], useSenderKeys: false, name: 'Prize draw');
    await alice.controller.refreshConversations();
    await waitFor(() => alice.controller.conversationById('grp-dave') != null, reason: 'the group was not listed');
    expect(alice.contactTrust.isRequest('grp-dave'), isTrue);

    final leave = GroupLeave(
      api: alice.api,
      accessToken: () => alice.session().accessToken,
      refreshConversations: alice.controller.refreshConversations,
    );
    expect(await leave.leave('grp-dave'), isTrue);
    expect(alice.api.leaveCalls, ['grp-dave']);
    expect(relay.conversations['grp-dave']!.memberHandles, isNot(contains('alice')));
    expect(alice.controller.conversationById('grp-dave'), isNull, reason: 'the chat stayed in the list');

    // A group the relay no longer lets alice leave: false, nothing changes.
    expect(await leave.leave('grp-dave'), isFalse);
    expect(alice.api.leaveCalls, ['grp-dave', 'grp-dave']);
  });
}
