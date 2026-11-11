import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/mock_relay_parties.dart';

const conv = 'conv-1';

void main() {
  late FakeRelay relay;

  setUp(() {
    relay = FakeRelay();
    seedMockParties(relay, conv, ['atlas', 'selene']);
  });

  Future<VeilMessengerController> signedIn(
    String handle, {
    bool Function()? readReceiptsEnabled,
    bool Function()? typingIndicatorsEnabled,
  }) async {
    final controller = mockPartyController(
      relay,
      handle,
      readReceiptsEnabled: readReceiptsEnabled,
      typingIndicatorsEnabled: typingIndicatorsEnabled,
    );
    addTearDown(controller.dispose);
    await controller.applySession(mockPartySession(handle));
    return controller;
  }

  test('readReceiptsEnabled false sends no markRead', () async {
    var receipts = false;
    final atlas = await signedIn('atlas', readReceiptsEnabled: () => receipts);
    final selene = await signedIn('selene');
    atlas.setActiveConversation(conv);

    await selene.sendText(conversationId: conv, body: 'are you there?');
    await waitFor(() => atlas.messagesFor(conv).length == 1);
    await atlas.markRead(atlas.messagesFor(conv).single.id);
    await settle();
    expect(relay.clientFor('atlas').markReadCalls, isEmpty);

    // Read on every use: switching receipts back on applies immediately.
    receipts = true;
    await selene.sendText(conversationId: conv, body: 'now?');
    await waitFor(() => relay.clientFor('atlas').markReadCalls.length == 1);
    expect(relay.clientFor('atlas').markReadCalls.single, atlas.messagesFor(conv).last.id);
  });

  test('typingIndicatorsEnabled false emits nothing', () async {
    var typing = false;
    final atlas = await signedIn('atlas', typingIndicatorsEnabled: () => typing);
    final socket = relay.realtimeFor('atlas');

    atlas.notifyTyping(conv);
    await atlas.sendText(conversationId: conv, body: 'typed quietly');
    await settle();
    expect(socket.emittedEvents, isEmpty);

    typing = true;
    atlas.notifyTyping(conv);
    expect(socket.emittedEvents, ['typing.start']);
  });
}
