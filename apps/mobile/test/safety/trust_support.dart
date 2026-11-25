import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/safety/data/contact_trust_store.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';

// What the trust layer tests share: parties on the fake relay, a relay
// that opens 1:1 chats by handle, and a message carried end to end.

/// A relay client that also opens a 1:1 by handle (ConversationsService
/// .createDirect): the existing one, or a new one.
class DirectRelayClient extends FakeRelayClient {
  DirectRelayClient(super.relay, super.me);

  @override
  Future<Map<String, dynamic>> createDirectConversation(String accessToken, String peerHandle) async {
    final existing = relay.conversations.values
        .where((conversation) =>
            conversation.type == 'direct' &&
            conversation.memberHandles.contains(me.handle) &&
            conversation.memberHandles.contains(peerHandle))
        .firstOrNull;
    final conversation = existing ?? relay.addDirect('conv-${me.handle}-$peerHandle', me.handle, peerHandle);
    return {
      'conversation': {'id': conversation.id},
    };
  }
}

/// A relay whose clients open 1:1 chats by handle.
FakeRelay trustRelay() => FakeRelay()..newClient = DirectRelayClient.new;

/// [handle]'s phone, as user-[handle] on dev-[handle].
Future<MessengerParty> phone(FakeRelay relay, String handle, {bool requests = false}) =>
    MessengerParty.join(relay, handle: handle, userId: 'user-$handle', deviceId: 'dev-$handle', requests: requests);

/// Sends [body] from [from] in [conversationId] and waits until [to] has
/// it open in a listed chat.
Future<void> deliver(MessengerParty from, MessengerParty to, String conversationId, String body) async {
  if (from.controller.conversationById(conversationId) == null) await from.controller.refreshConversations();
  await from.controller.sendText(conversationId: conversationId, body: body);
  await waitFor(() => from.controller.pendingCountFor(conversationId) == 0, reason: '"$body" was not acked');
  await waitFor(
    () async => to.controller.conversationById(conversationId) != null && (await to.bodies(conversationId)).contains(body),
    reason: '"$body" did not arrive',
  );
}

/// Waits until [party]'s trust layer has read its document and run the
/// baseline.
Future<void> trustReady(MessengerParty party) =>
    waitFor(() => party.contactTrust.ready, reason: 'the trust document was not read or the baseline did not run');

/// The trust document as [party]'s keystore holds it now.
Future<ContactTrustDocument?> storedTrust(MessengerParty party) =>
    ContactTrustStore(party.keystore.scoped(SecureScope.conversationPolicy)).read();
