import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/network/keys_api.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/peer_bundle_cache.dart';

const _bundle = DirectoryDevice(
  bundle: KeyBundle(
    userId: 'user-selene',
    deviceId: 'dev-selene',
    handle: 'selene',
    identityPublicKey: 'ik',
    signedPrekeyBundle: 'spk',
  ),
  isActive: true,
  oneTimePrekey: OneTimePrekey(keyId: 7, publicKey: 'opk'),
);

void main() {
  test('serves a directory answer for ten minutes, then forgets it', () {
    var now = DateTime.utc(2026, 4, 1, 12);
    final cache = PeerBundleCache(clock: () => now);

    cache.remember('selene', _bundle);
    now = now.add(const Duration(minutes: 9, seconds: 59));
    expect(cache.fresh('selene'), same(_bundle));

    now = now.add(const Duration(seconds: 1));
    expect(cache.fresh('selene'), isNull);
  });

  test('is keyed by handle and can be cleared', () {
    final cache = PeerBundleCache()..remember('selene', _bundle);

    expect(cache.fresh('lyra'), isNull);
    cache.clear();
    expect(cache.fresh('selene'), isNull);
  });

  test('a spent one-time prekey is not offered again', () {
    final cache = PeerBundleCache()..remember('selene', _bundle);

    cache.spendOneTimePrekey('selene');

    expect(cache.fresh('selene')!.oneTimePrekey, isNull);
    expect(cache.fresh('selene')!.bundle, same(_bundle.bundle));
  });
}
