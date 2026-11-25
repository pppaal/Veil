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

/// What protects a build's messages, as a status screen tells the user.
enum CryptoAdapterKind {
  /// VEIL's own X3DH and Double Ratchet ([lib_adapter.LibCryptoAdapter]).
  veilRatchet,

  /// Signal's libsignal through the native bridge.
  libsignal,

  /// Anything else: a development or test adapter, not production crypto.
  development,
}

CryptoAdapterKind cryptoAdapterKindOf(String adapterId) => switch (adapterId) {
      lib_adapter.kLibCryptoAdapterId => CryptoAdapterKind.veilRatchet,
      libsignal_adapter.kLibsignalAdapterId => CryptoAdapterKind.libsignal,
      _ => CryptoAdapterKind.development,
    };

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
