import { createHash, webcrypto } from 'node:crypto';

import { describe, expect, it } from 'vitest';

import { encodeBase64Url } from '../src/core/base64url.js';
import { toHex } from '../src/crypto/bytes.js';
import { encodeTransferCode, parseTransferCode, transferFingerprint } from '../src/features/device-transfer.js';

describe('device-transfer codes', () => {
  const session = { sessionId: '3f2a8c4e-1111-4222-8333-444455556666', transferToken: '9d1c2b3a-aaaa-4bbb-8ccc-dddddddddddd' };

  it('round-trip the session and its token as unpadded base64', () => {
    const code = encodeTransferCode({ ...session, expiresAt: 'ignored' });
    expect(code).toMatch(/^[A-Za-z0-9+/]+$/);
    expect(code.endsWith('=')).toBe(false);
    expect(parseTransferCode(code)).toEqual(session);
  });

  it('refuse what is not a code', () => {
    for (const code of ['not a code', btoa('null'), btoa('{"sessionId":"x"}'), btoa('{"transferToken":"y"}'), '']) {
      expect(parseTransferCode(code)).toBeNull();
    }
  });
});

describe('transferFingerprint', () => {
  it('is the server claimantFingerprint: SHA-256 over the auth key, then the identity key, in groups of four', async () => {
    const authKey = new Uint8Array(32).fill(0x11);
    const identityKey = new Uint8Array(32).fill(0x22);
    const fingerprint = await transferFingerprint(webcrypto.subtle, {
      authPublicKey: encodeBase64Url(authKey),
      publicIdentityKey: encodeBase64Url(identityKey),
    });
    const expected = createHash('sha256').update(authKey).update(identityKey).digest('hex').replace(/(.{4})(?!$)/g, '$1 ');
    expect(fingerprint).toBe(expected);
    expect(fingerprint).toMatch(/^([0-9a-f]{4} ){15}[0-9a-f]{4}$/);
  });
});

describe('toHex', () => {
  it('writes bytes as lowercase hex, two digits each', () => {
    expect(toHex(new Uint8Array([0, 15, 16, 255]))).toBe('000f10ff');
    expect(toHex(new Uint8Array())).toBe('');
  });
});
