import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/safety/data/conversation_mutes.dart';
import 'package:veil_mobile/src/features/safety/data/safety_providers.dart';

import '../support/fake_relay.dart';
import '../support/memory_secure_store.dart';

// The mutes and the blocked list belong to the account signed in. A wipe or
// a sign-out takes them away, in memory as well as in the keystore, and an
// answer to a request made before it does not bring them back.

/// The relay's safety routes, able to hold an answer back as a slow network
/// would.
class _HeldClient extends FakeRelayClient {
  _HeldClient(super.relay, super.me);

  Completer<void>? gate;

  @override
  Future<Map<String, dynamic>> setConversationMute(
    String accessToken,
    String conversationId, {
    int? mutedForSeconds,
    required bool unmute,
  }) async {
    await gate?.future;
    return super.setConversationMute(accessToken, conversationId, mutedForSeconds: mutedForSeconds, unmute: unmute);
  }

  @override
  Future<Map<String, dynamic>> listBlockedUsers(String accessToken) async {
    await gate?.future;
    return super.listBlockedUsers(accessToken);
  }
}

/// The app's session controller, signed in as alice; [signIn] signs in
/// again after a wipe.
class _Session extends AppSessionController {
  _Session(super.storage, super.api, super.adapter) {
    signIn();
  }

  void signIn() => state = const AppSessionState(
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

void main() {
  late FakeRelay relay;
  late _HeldClient api;
  late SecureStorageService storage;
  late ProviderContainer container;
  late MuteStore kept;

  setUp(() async {
    relay = FakeRelay();
    final adapter = createDefaultCryptoAdapter();
    for (final handle in ['alice', 'bob', 'carol']) {
      relay.addParty(RelayParty(
        handle: handle,
        userId: 'user-$handle',
        deviceId: 'dev-$handle',
        identity: await adapter.identity.generateDeviceIdentity('dev-$handle'),
      ));
    }
    relay.addDirect('conv-bob', 'alice', 'bob');
    relay.addDirect('conv-carol', 'alice', 'carol');
    api = _HeldClient(relay, relay.partiesByHandle['alice']!);
    storage = SecureStorageService(MemorySecureStore());
    kept = MuteStore(storage.scoped(SecureScope.notifications));
    container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(api),
      appSessionProvider.overrideWith((ref) => _Session(storage, api, adapter)),
    ]);
    addTearDown(container.dispose);
  });

  _Session session() => container.read(appSessionProvider.notifier) as _Session;

  test('wiping the device forgets the mutes, and the next mute writes back none of them', () async {
    final mutes = container.read(conversationMutesProvider);
    expect(await mutes.mute('conv-bob', MuteDuration.always), isTrue);
    expect(mutes.isMuted('conv-bob'), isTrue);
    expect((await kept.read()).keys, ['conv-bob']);

    await session().wipeLocalDeviceState();
    await pumpEventQueue();
    expect(mutes.isMuted('conv-bob'), isFalse, reason: 'the wiped account\'s chat is still muted');
    expect(await kept.read(), isEmpty);

    session().signIn();
    expect(await mutes.mute('conv-carol', MuteDuration.oneHour), isTrue);
    expect((await kept.read()).keys, ['conv-carol'], reason: 'a chat muted before the wipe came back');
    expect(mutes.isMuted('conv-bob'), isFalse);
  });

  test('a mute the server takes after the device was wiped is not kept', () async {
    final mutes = container.read(conversationMutesProvider);
    await mutes.load();
    final gate = api.gate = Completer<void>();
    final muting = mutes.mute('conv-bob', MuteDuration.always);
    await pumpEventQueue();

    await session().wipeLocalDeviceState();
    gate.complete();
    expect(await muting, isFalse);
    expect(mutes.isMuted('conv-bob'), isFalse);
    expect(await kept.read(), isEmpty);
  });

  test('the blocked list is read again at each unlock', () async {
    final blocked = container.read(blockedAccountsProvider);
    await pumpEventQueue();
    expect(blocked.accounts, isEmpty);

    // Blocked from another device of the account while this one was away.
    relay.blocks['user-alice'] = {'user-carol': DateTime.utc(2026, 4, 7)};
    session().lock();
    await pumpEventQueue();
    expect(blocked.isBlocked('user-carol'), isFalse);
    session().unlock();
    await pumpEventQueue();
    expect(blocked.isBlocked('user-carol'), isTrue);
  });

  test('a blocked list the server sends after a sign-out is not kept', () async {
    relay.blocks['user-alice'] = {'user-bob': DateTime.utc(2026, 4, 7)};
    final blocked = container.read(blockedAccountsProvider);
    await pumpEventQueue();
    expect(blocked.isBlocked('user-bob'), isTrue);

    final gate = api.gate = Completer<void>();
    final refreshing = blocked.refresh();
    await pumpEventQueue();
    await session().wipeLocalDeviceState();
    expect(blocked.isBlocked('user-bob'), isFalse);
    gate.complete();
    await refreshing;
    expect(blocked.accounts, isEmpty, reason: 'the list of the account signed out came back');
    expect(blocked.loaded, isFalse);
  });
}
