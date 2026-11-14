// Reproduces packages/shared/test-vectors/safety-number-v2.json (contract C8),
// the vectors scripts/safety-number-vectors.mjs and the mobile client pin.

import { describe, expect, it } from 'vitest';
import { webcrypto } from 'node:crypto';
import { readFileSync } from 'node:fs';

import {
  fingerprint,
  formatSafetyNumber,
  matchesPeerCode,
  safetyNumber,
  verificationCode,
} from '../src/crypto/safety-number.js';
import { ed25519FromHex, fromHex, toHex } from './support/keys.js';

const { subtle } = webcrypto;
const VECTORS = JSON.parse(
  readFileSync(new URL('../../../packages/shared/test-vectors/safety-number-v2.json', import.meta.url), 'utf8'),
).vectors;

const party = (vector) => ({ identityKey: fromHex(vector.identityPublicKey), userId: vector.userId });
const ALICE = party(VECTORS.alice);
const BOB = party(VECTORS.bob);

describe('safety numbers v2', () => {
  it('identity keys derive from the vector seeds', async () => {
    for (const vector of [VECTORS.alice, VECTORS.bob]) {
      expect(toHex((await ed25519FromHex(vector.seed)).publicKey)).toBe(vector.identityPublicKey);
    }
  });

  it('reproduces both fingerprints and the joined, formatted number', async () => {
    expect(await fingerprint(subtle, ALICE.identityKey, ALICE.userId)).toBe(VECTORS.alice.fingerprint);
    expect(await fingerprint(subtle, BOB.identityKey, BOB.userId)).toBe(VECTORS.bob.fingerprint);
    const number = await safetyNumber(subtle, ALICE, BOB);
    expect(number).toBe(VECTORS.safetyNumber);
    expect(await safetyNumber(subtle, BOB, ALICE)).toBe(number);
    expect(formatSafetyNumber(number)).toBe(VECTORS.formatted);
  });

  it('binds the user id and the version', async () => {
    const { userIdBinding, versionBinding } = VECTORS;
    expect(await fingerprint(subtle, fromHex(userIdBinding.identityPublicKey), userIdBinding.userId))
      .toBe(userIdBinding.fingerprint);
    expect(await fingerprint(subtle, ALICE.identityKey, ALICE.userId, versionBinding.version))
      .toBe(versionBinding.fingerprint);
  });

  it('verification codes match the QR vectors and accept only the role-swapped view', () => {
    expect(verificationCode(ALICE, BOB)).toBe(VECTORS.qr.aliceView);
    expect(verificationCode(BOB, ALICE)).toBe(VECTORS.qr.bobView);
    expect(matchesPeerCode(ALICE, BOB, VECTORS.qr.bobView)).toBe(true);
    expect(matchesPeerCode(ALICE, BOB, VECTORS.qr.aliceView)).toBe(false);
    const impostor = { ...BOB, identityKey: ALICE.identityKey };
    expect(matchesPeerCode(ALICE, impostor, VECTORS.qr.bobView)).toBe(false);
  });
});
