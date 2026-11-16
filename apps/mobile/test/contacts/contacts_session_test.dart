import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/contacts/data/contacts_providers.dart';

import '../support/fake_relay.dart';
import '../support/memory_secure_store.dart';

// The contact list belongs to the account signed in: a sign-out takes it
// away, and an answer to a read made before it does not bring it back.

/// The relay's contact list, able to hold an answer back as a slow network
/// would.
class _HeldClient extends FakeRelayClient {
  _HeldClient(super.relay, super.me);

  Completer<void>? gate;

  @override
  Future<List<dynamic>> getContacts(String accessToken) async {
    await gate?.future;
    return [
      {'handle': 'bob', 'addedAt': DateTime.utc(2026, 4, 7).toIso8601String()},
    ];
  }
}

/// The app's session controller, signed in as alice.
class _Session extends AppSessionController {
  _Session(super.storage, super.api, super.adapter) {
    state = const AppSessionState(
      accessToken: 'token-alice',
      userId: 'user-alice',
      deviceId: 'dev-alice',
      handle: 'alice',
      onboardingAccepted: true,
      privacyConsentAccepted: true,
      locked: false,
      initializing: false,
    );
  }
}

void main() {
  test('a contact list the server sends after a sign-out is not kept', () async {
    final relay = FakeRelay();
    final adapter = createDefaultCryptoAdapter();
    relay.addParty(RelayParty(
      handle: 'alice',
      userId: 'user-alice',
      deviceId: 'dev-alice',
      identity: await adapter.identity.generateDeviceIdentity('dev-alice'),
    ));
    final api = _HeldClient(relay, relay.partiesByHandle['alice']!);
    final storage = SecureStorageService(MemorySecureStore());
    final container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(api),
      appSessionProvider.overrideWith((ref) => _Session(storage, api, adapter)),
    ]);
    addTearDown(container.dispose);

    final contacts = container.read(contactsControllerProvider);
    await pumpEventQueue();
    expect(contacts.contacts.map((contact) => contact.handle), ['bob']);

    final gate = api.gate = Completer<void>();
    final refreshing = contacts.refresh();
    await pumpEventQueue();
    await (container.read(appSessionProvider.notifier) as _Session).wipeLocalDeviceState();
    await pumpEventQueue();
    expect(contacts.contacts, isEmpty);
    gate.complete();
    await refreshing;
    expect(contacts.contacts, isEmpty, reason: 'the list of the account signed out came back');
    expect(contacts.isLoading, isFalse);
  });
}
