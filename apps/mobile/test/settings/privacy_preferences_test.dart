import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';
import 'package:veil_mobile/src/features/settings/data/privacy_preferences.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/memory_secure_store.dart';
import '../support/mock_relay_parties.dart';

const conv = 'conv-1';

void main() {
  late FakeRelay relay;
  late SecureStorageService keystore;

  setUp(() {
    relay = FakeRelay();
    seedMockParties(relay, conv, ['atlas', 'selene']);
    keystore = SecureStorageService(MemorySecureStore());
  });

  Future<PrivacyPreferences> loadedPreferences([SecureStorageService? deviceKeystore]) async {
    final preferences = PrivacyPreferences((deviceKeystore ?? keystore).scoped(SecureScope.privacy));
    await preferences.load();
    return preferences;
  }

  Future<VeilMessengerController> signedIn(String handle, PrivacyPreferences preferences) async {
    final controller = mockPartyController(
      relay,
      handle,
      readReceiptsEnabled: () => preferences.sendReadReceipts,
      typingIndicatorsEnabled: () => preferences.sendTypingIndicators,
    );
    addTearDown(controller.dispose);
    await controller.applySession(mockPartySession(handle));
    return controller;
  }

  test('receipts off sends no markRead', () async {
    final preferences = await loadedPreferences();
    await preferences.setSendReadReceipts(false);
    final atlas = await signedIn('atlas', preferences);
    // selene's own device, with the default choices.
    final selene = await signedIn('selene', await loadedPreferences(SecureStorageService(MemorySecureStore())));
    atlas.setActiveConversation(conv);

    await selene.sendText(conversationId: conv, body: 'did you read this?');
    await waitFor(() => atlas.messagesFor(conv).length == 1);
    await atlas.markRead(atlas.messagesFor(conv).single.id);
    await settle();
    expect(relay.clientFor('atlas').markReadCalls, isEmpty);

    // Nor does atlas learn what selene read: her read shows as delivered.
    await atlas.sendText(conversationId: conv, body: 'and this?');
    await waitFor(() => atlas.pendingCountFor(conv) == 0);
    selene.setActiveConversation(conv);
    await waitFor(() => selene.messagesFor(conv).length == 2);
    await selene.markRead(selene.messagesFor(conv).last.id);
    await waitFor(() => atlas.messagesFor(conv).last.deliveryState == MessageDeliveryState.delivered);
    await settle();
    expect(atlas.messagesFor(conv).last.deliveryState, MessageDeliveryState.delivered);
    expect(atlas.messagesFor(conv).last.readAt, isNull);
  });

  test('typing default off emits nothing', () async {
    final preferences = await loadedPreferences();
    expect(preferences.sendTypingIndicators, isFalse);
    expect(preferences.sendReadReceipts, isTrue);
    final atlas = await signedIn('atlas', preferences);

    atlas.notifyTyping(conv);
    await settle();
    expect(relay.realtimeFor('atlas').emittedEvents, isEmpty);

    await preferences.setSendTypingIndicators(true);
    atlas.notifyTyping(conv);
    expect(relay.realtimeFor('atlas').emittedEvents, ['typing.start']);
  });

  test('choices persist, and both switches read off until the keystore answered', () async {
    final preferences = PrivacyPreferences(keystore.scoped(SecureScope.privacy));
    expect(preferences.sendReadReceipts, isFalse);
    expect(preferences.sendTypingIndicators, isFalse);
    await preferences.load();
    await preferences.setSendReadReceipts(false);
    await preferences.setSendTypingIndicators(true);

    final reloaded = await loadedPreferences();
    expect(reloaded.sendReadReceipts, isFalse);
    expect(reloaded.sendTypingIndicators, isTrue);
  });
}
