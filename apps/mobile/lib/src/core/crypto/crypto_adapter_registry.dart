import 'crypto_engine.dart';
import 'lib_crypto_adapter.dart' as lib_adapter;

CryptoAdapter createConfiguredCryptoAdapter() {
  return lib_adapter.createDefaultCryptoAdapter();
}
