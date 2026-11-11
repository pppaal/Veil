// Safety number v2 cross-language vectors (contract C8).
//
// Safety numbers v2 follow Signal's NumericFingerprint construction:
//   per party: h = SHA-512(0x00 0x02 || identityKey(32) || utf8(userId));
//              5200 times: h = SHA-512(h || identityKey);
//              30 digits = six 5-byte big-endian chunks of h, each mod 100000,
//              zero-padded to 5 digits;
//   number:    the two 30-digit halves joined, lexicographically smaller first.
// The verification QR code is
//   b64url("VEILSN" || 0x02 || localKey(32) || u8 len || localUserId ||
//          remoteKey(32) || u8 len || remoteUserId)
// and a scanner accepts only the role-swapped payload of its own view.
//
// This script is the reference implementation on node:crypto. The mobile
// client (apps/mobile/lib/src/features/security/domain/safety_numbers.dart)
// and the web client must reproduce every value in the emitted JSON.
//
// Usage:
//   node scripts/safety-number-vectors.mjs            # (re)generate the JSON
//   node scripts/safety-number-vectors.mjs --check    # verify committed JSON reproduces

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const CHECK = process.argv.includes('--check');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'packages/shared/test-vectors/safety-number-v2.json');

const VERSION = 2;
const ITERATIONS = 5200;
const QR_MAGIC = Buffer.from('VEILSN', 'utf8');
const ED25519_PKCS8 = '302e020100300506032b657004220420';

const toHex = (buf) => Buffer.from(buf).toString('hex');
const b64u = (buf) => Buffer.from(buf).toString('base64url');

function ed25519PublicFromSeed(seed) {
  const privateKey = crypto.createPrivateKey({
    key: Buffer.concat([Buffer.from(ED25519_PKCS8, 'hex'), seed]),
    format: 'der',
    type: 'pkcs8',
  });
  const spki = crypto.createPublicKey(privateKey).export({ format: 'der', type: 'spki' });
  return spki.subarray(spki.length - 32);
}

const sha512 = (...parts) => crypto.createHash('sha512').update(Buffer.concat(parts)).digest();

function fingerprint(identityKey, userId, version = VERSION) {
  const versionBytes = Buffer.alloc(2);
  versionBytes.writeUInt16BE(version);
  let hash = sha512(versionBytes, identityKey, Buffer.from(userId, 'utf8'));
  for (let i = 0; i < ITERATIONS; i += 1) {
    hash = sha512(hash, identityKey);
  }
  let digits = '';
  for (let chunk = 0; chunk < 6; chunk += 1) {
    digits += String(hash.readUIntBE(chunk * 5, 5) % 100000).padStart(5, '0');
  }
  return digits;
}

const safetyNumber = (a, b) => (a <= b ? a + b : b + a);

function lengthPrefixed(userId) {
  const bytes = Buffer.from(userId, 'utf8');
  if (bytes.length < 1 || bytes.length > 255) throw new Error(`userId out of range: ${userId}`);
  return Buffer.concat([Buffer.from([bytes.length]), bytes]);
}

function qrPayload(local, remote) {
  return b64u(
    Buffer.concat([
      QR_MAGIC,
      Buffer.from([VERSION]),
      local.identityKey,
      lengthPrefixed(local.userId),
      remote.identityKey,
      lengthPrefixed(remote.userId),
    ]),
  );
}

function assertEq(label, actual, expected) {
  if (actual !== expected) {
    throw new Error(`anchor mismatch for ${label}:\n  got      ${actual}\n  expected ${expected}`);
  }
}

function party(name, seedByte, userId) {
  const seed = Buffer.alloc(32, seedByte);
  const identityKey = ed25519PublicFromSeed(seed);
  return { name, seed, identityKey, userId, fingerprint: fingerprint(identityKey, userId) };
}

function build() {
  // RFC 8032 §7.1 TEST 1 anchors the Ed25519 key derivation of the oracle.
  assertEq(
    'RFC 8032 TEST 1 public key',
    toHex(
      ed25519PublicFromSeed(
        Buffer.from('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60', 'hex'),
      ),
    ),
    'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
  );

  const alice = party('alice', 0x11, '00000000-0000-4000-8000-00000000000a');
  const bob = party('bob', 0x22, '00000000-0000-4000-8000-00000000000b');
  // The alice identity is the bundle-v2 vector's identity (contract C1).
  assertEq('alice identity key', b64u(alice.identityKey), '0EqyMnQrtKs6E2i9RhXk5tAiSrcaAWuvhSCjMsl3hzc');

  const number = safetyNumber(alice.fingerprint, bob.fingerprint);
  const formatted = number.match(/\d{5}/g).join(' ');
  const aliceKeyBobUser = fingerprint(alice.identityKey, bob.userId);
  const versionThree = fingerprint(alice.identityKey, alice.userId, 3);
  if (aliceKeyBobUser === alice.fingerprint || versionThree === alice.fingerprint) {
    throw new Error('fingerprint does not bind userId and version');
  }

  const describe = (p) => ({
    seed: toHex(p.seed),
    identityPublicKey: toHex(p.identityKey),
    userId: p.userId,
    fingerprint: p.fingerprint,
  });

  return {
    schema: 'veil-safety-number-v2',
    description:
      'Safety number v2 (Signal NumericFingerprint) and verification QR vectors. ' +
      'Hex unless noted. Regenerate/verify with scripts/safety-number-vectors.mjs.',
    generator: `node ${process.version} / node:crypto`,
    construction: {
      version: VERSION,
      iterations: ITERATIONS,
      fingerprint:
        'h = SHA-512(u16be(version) || identityKey(32) || utf8(userId)); repeat iterations ' +
        'times h = SHA-512(h || identityKey); 30 digits = h[0..30] as six 5-byte big-endian ' +
        'integers, each mod 100000, zero-padded to 5 digits.',
      safetyNumber: 'The two 30-digit fingerprints joined, lexicographically smaller first.',
      qrPayload:
        'base64url-nopad("VEILSN" || u8(version) || localKey(32) || u8(len) || utf8(localUserId) ' +
        '|| remoteKey(32) || u8(len) || utf8(remoteUserId)). A scanner accepts only the ' +
        'role-swapped payload of its own view.',
    },
    vectors: {
      alice: describe(alice),
      bob: describe(bob),
      safetyNumber: number,
      formatted,
      userIdBinding: {
        note: "alice's identity key with bob's userId",
        identityPublicKey: toHex(alice.identityKey),
        userId: bob.userId,
        fingerprint: aliceKeyBobUser,
      },
      versionBinding: {
        note: "alice's identity and userId under version 3",
        version: 3,
        fingerprint: versionThree,
      },
      qr: {
        aliceView: qrPayload(alice, bob),
        bobView: qrPayload(bob, alice),
      },
    },
  };
}

const stableStringify = (obj) => JSON.stringify(obj, null, 2) + '\n';
const generated = build();

if (CHECK) {
  if (!fs.existsSync(OUT)) {
    console.error(`safety-number-v2: committed vectors missing at ${path.relative(ROOT, OUT)}`);
    process.exit(1);
  }
  // The generator string carries the Node version, which legitimately varies.
  const strip = ({ generator, ...rest }) => stableStringify(rest);
  if (strip(JSON.parse(fs.readFileSync(OUT, 'utf8'))) !== strip(generated)) {
    console.error('safety-number-v2: committed vectors do NOT reproduce. Regenerate and review the diff.');
    process.exit(1);
  }
  console.log('safety-number-v2: committed vectors reproduce exactly.');
} else {
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, stableStringify(generated));
  console.log(`safety-number-v2: wrote ${path.relative(ROOT, OUT)}`);
}
