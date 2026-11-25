// Deterministic keys for known-answer tests. Private scalars and seeds are
// imported as non-extractable CryptoKeys, exactly like generated ones; the
// public halves come from node:crypto, independently of the code under test.

import { createPrivateKey, createPublicKey, webcrypto } from 'node:crypto';

const { subtle } = webcrypto;
const X25519_PKCS8_PREFIX = '302e020100300506032b656e04220420';
const ED25519_PKCS8_PREFIX = '302e020100300506032b657004220420';

export const fromHex = (hex) => Uint8Array.from(Buffer.from(hex, 'hex'));
export const toHex = (bytes) => Buffer.from(bytes).toString('hex');

function rawPublic(der) {
  const spki = createPublicKey(createPrivateKey({ key: der, format: 'der', type: 'pkcs8' }))
    .export({ format: 'der', type: 'spki' });
  return new Uint8Array(spki.subarray(spki.length - 32));
}

async function importPair(prefix, hex, algorithm, usages) {
  const der = Buffer.from(prefix + hex, 'hex');
  const privateKey = await subtle.importKey('pkcs8', der, algorithm, false, usages);
  return { privateKey, publicKey: rawPublic(der) };
}

export const x25519FromHex = (hex) => importPair(X25519_PKCS8_PREFIX, hex, { name: 'X25519' }, ['deriveBits']);
export const ed25519FromHex = (hex) => importPair(ED25519_PKCS8_PREFIX, hex, { name: 'Ed25519' }, ['sign']);

// A key source that replays the given draws in order, then fails loudly: a
// test that draws more than its script is testing something else.
export function scriptedKeySource({ x25519 = [], ed25519 = [], randomBytes = [] }) {
  const queues = { x25519: [...x25519], ed25519: [...ed25519], randomBytes: [...randomBytes] };
  const next = (kind) => {
    if (queues[kind].length === 0) throw new Error(`scripted key source ran out of ${kind} draws`);
    return queues[kind].shift();
  };
  return {
    x25519: () => x25519FromHex(next('x25519')),
    ed25519: () => ed25519FromHex(next('ed25519')),
    randomBytes: (length) => {
      const bytes = fromHex(next('randomBytes'));
      if (bytes.length !== length) throw new Error(`scripted draw has ${bytes.length} bytes, wanted ${length}`);
      return bytes;
    },
  };
}
