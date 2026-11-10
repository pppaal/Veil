import 'crypto_engine.dart';
import 'lib_crypto_adapter.dart' as lib_adapter;
import 'libsignal_bridge_adapter.dart' as libsignal_adapter;

/// Build-time adapter selection.
///
///   flutter build apk --dart-define=VEIL_CRYPTO_ADAPTER=libsignal
///
/// `lib` (default) is the in-Dart Double Ratchet (`LibCryptoAdapter`).
/// `libsignal` routes all key/session operations to the native libsignal
/// bridge. The default stays `lib` until the bridge has passed the
/// interop + migration gates in docs/libsignal-migration-implementation.md.
const String kCryptoAdapterSelection =
    String.fromEnvironment('VEIL_CRYPTO_ADAPTER', defaultValue: 'lib');

CryptoAdapter createConfiguredCryptoAdapter() =>
    createCryptoAdapterFor(kCryptoAdapterSelection);

CryptoAdapter createCryptoAdapterFor(String selection) {
  switch (selection) {
    case 'libsignal':
      return libsignal_adapter.createLibsignalBridgeAdapter();
    case 'lib':
    case '':
      return lib_adapter.createDefaultCryptoAdapter();
    default:
      // Fail loud: a typo in a release build must not silently pick an
      // adapter the operator did not intend.
      throw ArgumentError.value(
        selection,
        'VEIL_CRYPTO_ADAPTER',
        'unknown crypto adapter (expected "lib" or "libsignal")',
      );
  }
}
