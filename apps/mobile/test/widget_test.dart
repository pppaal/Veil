import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_expiration.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

void main() {
  test('formats message expiration in seconds', () {
    final now = DateTime.utc(2026, 3, 27, 10, 0, 0);
    final expiresAt = now.add(const Duration(seconds: 30));

    expect(formatMessageExpiry(lookupAppLocalizations(const Locale('en')), expiresAt, now: now), 'Expires in 30s');
    expect(formatMessageExpiry(lookupAppLocalizations(const Locale('ko')), expiresAt, now: now), '30초 후 만료');
  });

  test('marks expired messages as expired', () {
    final now = DateTime.utc(2026, 3, 27, 10, 0, 0);
    final expiresAt = now.subtract(const Duration(seconds: 1));

    expect(isMessageExpired(expiresAt, now: now), isTrue);
  });
}
