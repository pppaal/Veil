import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_nicknames.dart';
import 'package:veil_mobile/src/features/contacts/data/contacts_providers.dart';

import '../support/fake_relay.dart';
import '../support/memory_secure_store.dart';

// The contact list belongs to the account signed in: a sign-out takes it
// away, and an answer to a read or an add made before it, or a rename
// saved once it has begun, does not bring it, or a nickname, back.

/// The relay's contact list, able to hold an answer back as a slow network
/// would.
class _HeldClient extends FakeRelayClient {
  _HeldClient(super.relay, super.me);

  Completer<void>? gate;
  Completer<void>? addGate;

  @override
  Future<List<dynamic>> getContacts(String accessToken) async {
    await gate?.future;
    return [
      {'handle': 'bob', 'addedAt': DateTime.utc(2026, 4, 7).toIso8601String()},
    ];
  }

  @override
  Future<Map<String, dynamic>> addContact(String accessToken, Map<String, dynamic> body) async {
    await addGate?.future;
    return {'handle': body['handle'], 'addedAt': DateTime.utc(2026, 4, 7).toIso8601String()};
  }
}

/// A keystore whose wipe lets a held answer in right after the keystore is
/// wiped, while the sign-out still has the chat cache and the attachments
/// to wipe before the session reads signed out.
class _Storage extends SecureStorageService {
  _Storage(super.storage);

  Completer<void>? releaseOnWipe;

  @override
  Future<void> wipeLocalDeviceState({bool preserveOnboardingAccepted = true, bool preservePin = false}) async {
    await super.wipeLocalDeviceState(preserveOnboardingAccepted: preserveOnboardingAccepted, preservePin: preservePin);
    releaseOnWipe?.complete();
    // The cache and attachment wipes that follow in _clearLocalState.
    await pumpEventQueue();
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
  late _HeldClient api;
  late _Storage storage;
  late ProviderContainer container;

  setUp(() async {
    final relay = FakeRelay();
    final adapter = createDefaultCryptoAdapter();
    relay.addParty(RelayParty(
      handle: 'alice',
      userId: 'user-alice',
      deviceId: 'dev-alice',
      identity: await adapter.identity.generateDeviceIdentity('dev-alice'),
    ));
    api = _HeldClient(relay, relay.partiesByHandle['alice']!);
    storage = _Storage(MemorySecureStore());
    container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(api),
      appSessionProvider.overrideWith((ref) => _Session(storage, api, adapter)),
    ]);
    addTearDown(container.dispose);
  });

  test('a contact list the server sends after a sign-out is not kept', () async {
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

  // The next account made on this phone would find the nickname, naming no
  // account, for the first list that shows the handle to give one.
  test('a nickname saved with a contact the server adds after a sign-out is not written into the wiped keystore', () async {
    final contacts = container.read(contactsControllerProvider);
    await pumpEventQueue();
    final gate = api.addGate = Completer<void>();
    final adding = contacts.addContact(handle: 'dana', nickname: 'Dana Park');
    await pumpEventQueue();
    await (container.read(appSessionProvider.notifier) as _Session).wipeLocalDeviceState();
    await pumpEventQueue();
    gate.complete();
    expect(await adding, isFalse);
    expect(await ContactNicknames(storage.scoped(SecureScope.contacts)).readAll(), isEmpty);
    expect(contacts.contacts, isEmpty);
  });

  // The same, with the answer coming while the sign-out is still wiping:
  // the keystore is clear, but the session does not read signed out yet.
  test('a nickname saved with a contact the server adds while a sign-out is wiping is not written into the wiped keystore', () async {
    final contacts = container.read(contactsControllerProvider);
    await pumpEventQueue();
    final gate = api.addGate = Completer<void>();
    storage.releaseOnWipe = gate;
    final adding = contacts.addContact(handle: 'dana', nickname: 'Dana Park');
    await pumpEventQueue();
    await (container.read(appSessionProvider.notifier) as _Session).wipeLocalDeviceState();
    expect(await adding, isFalse);
    expect(await ContactNicknames(storage.scoped(SecureScope.contacts)).readAll(), isEmpty);
  });

  // A rename saved from a sheet opened before a wipe began, as a wipe set
  // off elsewhere while the sheet is open, writes nothing either.
  test('a nickname renamed once a wipe has begun is not written into the wiped keystore', () async {
    final contacts = container.read(contactsControllerProvider);
    await pumpEventQueue();
    final wipesSeen = storage.wipesBegun;
    final gate = storage.releaseOnWipe = Completer<void>();
    final renaming = gate.future.then((_) => contacts.renameContact('bob', 'Bob Smith', wipesSeen: wipesSeen));
    await (container.read(appSessionProvider.notifier) as _Session).wipeLocalDeviceState();
    await renaming;
    expect(await ContactNicknames(storage.scoped(SecureScope.contacts)).readAll(), isEmpty);
  });
}
