import 'crypto_engine.dart';
import 'lib_crypto_adapter.dart' as lib_adapter;
import 'libsignal_bridge_adapter.dart';

// Selects the crypto adapter at build time. The default keeps the existing
// self-implemented adapter so normal builds are unchanged; opt into the
// native libsignal bridge (WIP, Android-first) with:
//   --dart-define=VEIL_CRYPTO_ADAPTER=libsignal
const _selectedAdapter = String.fromEnvironment(
  'VEIL_CRYPTO_ADAPTER',
  defaultValue: 'lib',
);

CryptoAdapter createConfiguredCryptoAdapter() {
  switch (_selectedAdapter) {
    case 'libsignal':
      return LibsignalBridgeAdapter();
    case 'lib':
    default:
      return lib_adapter.createDefaultCryptoAdapter();
  }
}
