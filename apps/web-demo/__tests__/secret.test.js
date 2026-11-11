import { describe, expect, it } from 'vitest';
import { webcrypto } from 'node:crypto';

import { decodeBase64Url } from '../src/core/base64url.js';
import {
  formatSecretFragment,
  openSecret,
  parseSecretFragment,
  PBKDF2_ITERATIONS,
  sealSecret,
} from '../src/crypto/secret-link.js';

const ID = '0f8fad5b-d9cb-469f-a165-70867728950e';
const KEY_43 = 'A'.repeat(43);

// Sealed by the mobile app's OneTimeLink.seal
// (apps/mobile/lib/src/features/secret_link/data/one_time_link.dart).
const MOBILE_V1_KEY_MODE = {
  blob: 'v1.5ldEQUcZK-3iql7-.xvkLID9AD4_RLaUJ2XbygV-sNVfaspU1RjWdPsURSkxfGxjQpqjGuKA',
  fragment: `${ID}.k.PFFXUvdnJ4Lnt51Bb0SOefEYhWCRpHoVTqIEIJyuWbM`,
  plaintext: 'mobile v1 key-mode secret',
};
const MOBILE_V1_PASSPHRASE_MODE = {
  blob: 'v1.6XEZCMBdJo4HL53z.qzY_fHsmCPM7yNAyZP3OkMVrgizhsWaRaw54g3o60qoxgQQfzSh0SN6IGw.KmFEJn9NrUW8LT_jhHSsSA',
  fragment: `${ID}.p`,
  passphrase: 'correct horse battery staple',
  plaintext: 'mobile v1 passphrase secret',
};

async function seal(text, passphrase) {
  const sealed = await sealSecret(webcrypto, text, passphrase);
  return { ...sealed, link: parseSecretFragment(formatSecretFragment(ID, sealed.fragmentSecret)) };
}

describe('one-time secret links', () => {
  it('always puts a random 32-byte key in the fragment', async () => {
    const a = await seal('one');
    const b = await seal('two', 'correct horse');
    for (const { link } of [a, b]) {
      expect(link.id).toBe(ID);
      expect(link.fragmentKey).toHaveLength(32);
    }
    expect(a.link.needsPassphrase).toBe(false);
    expect(b.link.needsPassphrase).toBe(true);
    expect(a.link.fragmentKey).not.toEqual(b.link.fragmentKey);
    // Nothing the server stores identifies the key.
    expect(a.blob).not.toContain(a.fragmentSecret.split('.')[1]);
  });

  it('seals only the v2 format', async () => {
    const a = await seal('one');
    const b = await seal('two', 'correct horse');
    expect(a.blob.split('.')[0]).toBe('v2');
    expect(b.blob.split('.')[0]).toBe('v2');
    expect(a.fragmentSecret.split('.')[0]).toBe('k2');
    expect(b.fragmentSecret.split('.')[0]).toBe('p2');
    expect(a.link.version).toBe('v2');
    expect(b.link.version).toBe('v2');
  });

  it('opens with the fragment key alone when no passphrase was set', async () => {
    const { blob, link } = await seal('hunter2 for the wifi');
    expect(await openSecret(webcrypto, blob, link)).toBe('hunter2 for the wifi');
  });

  it('passphrase alone cannot decrypt', async () => {
    const passphrase = 'correct horse battery staple';
    const { blob, link } = await seal('vault code 4471', passphrase);
    expect(PBKDF2_ITERATIONS).toBe(600_000);

    // The server holds the blob (with its salt) and may guess the passphrase,
    // but without the fragment key every attempt fails.
    const wrongKey = webcrypto.getRandomValues(new Uint8Array(32));
    await expect(openSecret(webcrypto, blob, { ...link, fragmentKey: wrongKey }, passphrase)).rejects.toThrow();
    await expect(openSecret(webcrypto, blob, { ...link, fragmentKey: new Uint8Array(32) }, passphrase)).rejects.toThrow();

    // A passphrase-only key (the v1 design) does not open it either.
    const [, salt, iv, sealed] = blob.split('.');
    const base = await webcrypto.subtle.importKey('raw', new TextEncoder().encode(passphrase), 'PBKDF2', false, ['deriveKey']);
    const passphraseOnlyKey = await webcrypto.subtle.deriveKey(
      { name: 'PBKDF2', salt: decodeBase64Url(salt), iterations: PBKDF2_ITERATIONS, hash: 'SHA-256' },
      base,
      { name: 'AES-GCM', length: 256 },
      false,
      ['decrypt'],
    );
    await expect(webcrypto.subtle.decrypt({ name: 'AES-GCM', iv: decodeBase64Url(iv) }, passphraseOnlyKey, decodeBase64Url(sealed)))
      .rejects.toThrow();

    // The fragment key without the passphrase fails too: both factors are needed.
    await expect(openSecret(webcrypto, blob, link)).rejects.toThrow();
    await expect(openSecret(webcrypto, blob, link, 'wrong')).rejects.toThrow();
    expect(await openSecret(webcrypto, blob, link, passphrase)).toBe('vault code 4471');
  });

  it('rejects malformed links before anything is fetched', () => {
    expect(parseSecretFragment('')).toBeNull();
    expect(parseSecretFragment(ID)).toBeNull();
    expect(parseSecretFragment(`.k2.${KEY_43}`)).toBeNull();
    expect(parseSecretFragment(`${ID}.k2`)).toBeNull();
    expect(parseSecretFragment(`${ID}.k2.AAAA`)).toBeNull();
    expect(parseSecretFragment(`${ID}.k2.${KEY_43}.extra`)).toBeNull();
    expect(parseSecretFragment(`${ID}.k2.${'A'.repeat(42)}+`)).toBeNull();
    expect(parseSecretFragment(`${ID}.p2`)).toBeNull();
    expect(parseSecretFragment(`${ID}.k`)).toBeNull();
    expect(parseSecretFragment(`${ID}.k.AAAA`)).toBeNull();
    expect(parseSecretFragment(`${ID}.p.${KEY_43}`)).toBeNull();
    expect(parseSecretFragment(`${ID}.x.${KEY_43}`)).toBeNull();
    expect(parseSecretFragment(`${ID}.constructor.${KEY_43}`)).toBeNull();
    expect(parseSecretFragment(`${ID}.__proto__`)).toBeNull();
    expect(parseSecretFragment(`${ID}.k2.${KEY_43}`)).toMatchObject({ id: ID, version: 'v2', needsPassphrase: false });
    expect(parseSecretFragment(`${ID}.p2.${KEY_43}`)).toMatchObject({ id: ID, version: 'v2', needsPassphrase: true });
  });

  it('a link opens only blobs of its own format', async () => {
    const v2 = await seal('x');
    const v1Key = parseSecretFragment(MOBILE_V1_KEY_MODE.fragment);
    const v1Pass = parseSecretFragment(MOBILE_V1_PASSPHRASE_MODE.fragment);
    const unsupported = 'unsupported secret format';

    await expect(openSecret(webcrypto, MOBILE_V1_KEY_MODE.blob, v2.link)).rejects.toThrow(unsupported);
    await expect(openSecret(webcrypto, v2.blob, v1Key)).rejects.toThrow(unsupported);
    await expect(openSecret(webcrypto, v2.blob, v1Pass, 'pass')).rejects.toThrow(unsupported);
    await expect(openSecret(webcrypto, `v3${v2.blob.slice(2)}`, v2.link)).rejects.toThrow(unsupported);
    await expect(openSecret(webcrypto, `${v2.blob}.extra`, v2.link)).rejects.toThrow(unsupported);
    // A key-mode link never falls back to a passphrase-derived key, or the reverse.
    await expect(openSecret(webcrypto, MOBILE_V1_PASSPHRASE_MODE.blob, v1Key)).rejects.toThrow(unsupported);
    await expect(openSecret(webcrypto, MOBILE_V1_KEY_MODE.blob, v1Pass, 'pass')).rejects.toThrow(unsupported);
  });
});

// Links the mobile app produces today must keep opening until it seals v2.
describe('legacy v1 links (read-only)', () => {
  it('parses the mobile fragment modes', () => {
    expect(parseSecretFragment(MOBILE_V1_KEY_MODE.fragment)).toMatchObject({ id: ID, version: 'v1', needsPassphrase: false });
    expect(parseSecretFragment(MOBILE_V1_KEY_MODE.fragment).fragmentKey).toHaveLength(32);
    expect(parseSecretFragment(MOBILE_V1_PASSPHRASE_MODE.fragment)).toEqual({
      id: ID,
      version: 'v1',
      needsPassphrase: true,
      fragmentKey: null,
    });
  });

  it('opens a v1 key-mode vector with the raw fragment key', async () => {
    const { blob, fragment, plaintext } = MOBILE_V1_KEY_MODE;
    const link = parseSecretFragment(fragment);
    expect(await openSecret(webcrypto, blob, link)).toBe(plaintext);
    await expect(openSecret(webcrypto, blob, { ...link, fragmentKey: new Uint8Array(32) })).rejects.toThrow();
  });

  it('opens a v1 passphrase vector through PBKDF2-SHA256 at 210000 iterations', async () => {
    const { blob, fragment, passphrase, plaintext } = MOBILE_V1_PASSPHRASE_MODE;
    const link = parseSecretFragment(fragment);
    expect(await openSecret(webcrypto, blob, link, passphrase)).toBe(plaintext);
    await expect(openSecret(webcrypto, blob, link, 'wrong passphrase')).rejects.toThrow();
    await expect(openSecret(webcrypto, blob, link)).rejects.toThrow();
  });
});
