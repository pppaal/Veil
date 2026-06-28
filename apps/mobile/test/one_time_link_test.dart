import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/secret_link/data/one_time_link.dart';

void main() {
  const secret = '넷플릭스 비번 Vx9\$kQ2! / 계좌 3333-04 🔐';

  test('key mode round-trips and keeps the key out of the blob', () async {
    final sealed = await OneTimeLink.seal(secret);
    expect(sealed.blob, startsWith('v1.'));
    expect(sealed.fragment, startsWith('k.'));
    // server blob must not contain the key or plaintext
    expect(sealed.blob.contains(sealed.fragment.substring(2)), isFalse);
    expect(sealed.blob.contains('3333-04'), isFalse);

    final opened = await OneTimeLink.open(sealed.blob, sealed.fragment);
    expect(opened, secret);
  });

  test('passphrase mode keeps the key out of the link (salt only)', () async {
    final sealed = await OneTimeLink.seal(secret, passphrase: 'open-sesame');
    expect(sealed.fragment, 'p');
    expect(sealed.blob.split('.'), hasLength(4)); // v1.iv.ct.salt

    final opened =
        await OneTimeLink.open(sealed.blob, 'p', passphrase: 'open-sesame');
    expect(opened, secret);
  });

  test('wrong passphrase is rejected', () async {
    final sealed = await OneTimeLink.seal(secret, passphrase: 'right');
    await expectLater(
      OneTimeLink.open(sealed.blob, 'p', passphrase: 'wrong'),
      throwsA(anything),
    );
  });

  test('ciphertext carries the appended 16-byte GCM tag (WebCrypto layout)',
      () async {
    final sealed = await OneTimeLink.seal('hi'); // 2-byte plaintext
    final ctB64 = sealed.blob.split('.')[2];
    final ctLen =
        base64Url.decode(ctB64.padRight((ctB64.length + 3) & ~3, '=')).length;
    expect(ctLen, 2 + 16); // plaintext + tag
  });
}
