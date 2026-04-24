import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/backup/backup_envelope.dart';

void main() {
  group('BackupEnvelope', () {
    test('round-trips a plaintext through the passphrase', () async {
      final original = utf8.encode('{"hello":"world"}');
      final sealed = await BackupEnvelope.seal('correct horse battery staple', original);
      expect(sealed, startsWith('veilbak:v1:'));
      final opened = await BackupEnvelope.open('correct horse battery staple', sealed);
      expect(opened, equals(original));
    });

    test('rejects the wrong passphrase', () async {
      final sealed = await BackupEnvelope.seal('s3cret', utf8.encode('body'));
      expect(
        () => BackupEnvelope.open('wrong', sealed),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('produces a fresh salt/nonce per seal so two seals differ', () async {
      final a = await BackupEnvelope.seal('p', utf8.encode('same'));
      final b = await BackupEnvelope.seal('p', utf8.encode('same'));
      expect(a, isNot(equals(b)));
    });

    test('rejects a malformed envelope', () async {
      await expectLater(
        () => BackupEnvelope.open('p', 'not-a-veil-envelope'),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        () => BackupEnvelope.open('p', 'veilbak:v1:too:few:fields'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an empty passphrase on both seal and open', () async {
      expect(
        () => BackupEnvelope.seal('', utf8.encode('x')),
        throwsA(isA<ArgumentError>()),
      );
      final sealed = await BackupEnvelope.seal('p', utf8.encode('x'));
      expect(
        () => BackupEnvelope.open('', sealed),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
