import 'package:flutter/foundation.dart';

import '../../../core/storage/secure_storage_service.dart';

/// What this device tells peers about the user's reading and typing, kept in
/// the keystore. The messenger reads the switches on every use, so a change
/// applies at once.
///
/// Until the stored choice has loaded both switches read off: a device must
/// never send a receipt or a typing signal the user had turned off just
/// because it asked before the keystore answered.
class PrivacyPreferences extends ChangeNotifier {
  PrivacyPreferences(this._store);

  static const _sendReadReceiptsKey = 'send_read_receipts';
  static const _sendTypingIndicatorsKey = 'send_typing_indicators';

  final ScopedSecureStore _store;
  bool _loaded = false;
  bool _sendReadReceipts = true;
  bool _sendTypingIndicators = false;

  bool get sendReadReceipts => _loaded && _sendReadReceipts;

  bool get sendTypingIndicators => _loaded && _sendTypingIndicators;

  Future<void> load() async {
    _sendReadReceipts = await _readSwitch(_sendReadReceiptsKey) ?? true;
    _sendTypingIndicators = await _readSwitch(_sendTypingIndicatorsKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setSendReadReceipts(bool value) async {
    await _store.write(_sendReadReceiptsKey, '$value');
    _sendReadReceipts = value;
    notifyListeners();
  }

  Future<void> setSendTypingIndicators(bool value) async {
    await _store.write(_sendTypingIndicatorsKey, '$value');
    _sendTypingIndicators = value;
    notifyListeners();
  }

  Future<bool?> _readSwitch(String key) async => switch (await _store.read(key)) {
        'true' => true,
        'false' => false,
        _ => null,
      };
}
