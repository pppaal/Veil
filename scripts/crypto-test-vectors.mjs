// Crypto known-answer test (KAT) vectors for external audit.
//
// Produces a machine-checkable, independently-reproducible set of vectors for
// the primitives VEIL's message crypto is built on: X25519 (ECDH), Ed25519
// (sign/verify), HKDF-SHA256, and AES-256-GCM, plus full protocol transcripts
// for the legacy v1 schedule and protocol v2. An auditor — or a replacement
// engine (mobile Dart adapter, or a future libsignal build) — feeds the same
// fixed inputs to their implementation and must reproduce every output here.
//
// Trust anchoring: the generator is Node's own crypto (OpenSSL). To prove that
// oracle is itself correct, the set pins published RFC test vectors
// (RFC 7748 §6.1 X25519, RFC 5869 §A.1 HKDF-SHA256) and asserts Node reproduces
// them before emitting anything. The remaining vectors use fixed inputs; every
// primitive here is deterministic (Ed25519 per RFC 8032, and fixed-nonce
// AES-GCM / HKDF), so any correct implementation yields identical outputs.
//
// Usage:
//   node scripts/crypto-test-vectors.mjs            # (re)generate the JSON
//   node scripts/crypto-test-vectors.mjs --check    # verify committed JSON reproduces
//
// The --check mode is what CI / an auditor runs: it regenerates in memory and
// byte-compares against the committed file, failing on any drift.

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const CHECK = process.argv.includes('--check');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'packages/shared/test-vectors/crypto-kat.json');

const toHex = (buf) => Buffer.from(buf).toString('hex');
const fromHex = (h) => Buffer.from(h, 'hex');

// Fixed DER wrappers so we can import raw 32-byte scalars/seeds/points without
// needing a matching public half in the import material.
const X25519_PKCS8 = '302e020100300506032b656e04220420';
const X25519_SPKI = '302a300506032b656e032100';
const ED25519_PKCS8 = '302e020100300506032b657004220420';
const ED25519_SPKI = '302a300506032b6570032100';

function importX25519Priv(scalarHex) {
  return crypto.createPrivateKey({
    key: fromHex(X25519_PKCS8 + scalarHex),
    format: 'der',
    type: 'pkcs8',
  });
}
function importX25519Pub(pubHex) {
  return crypto.createPublicKey({
    key: fromHex(X25519_SPKI + pubHex),
    format: 'der',
    type: 'spki',
  });
}
function x25519PubFromPriv(priv) {
  const spki = crypto.createPublicKey(priv).export({ format: 'der', type: 'spki' });
  return toHex(spki.subarray(spki.length - 32));
}
function x25519Shared(privHex, pubHex) {
  return toHex(
    crypto.diffieHellman({
      privateKey: importX25519Priv(privHex),
      publicKey: importX25519Pub(pubHex),
    }),
  );
}

function importEd25519Priv(seedHex) {
  return crypto.createPrivateKey({
    key: fromHex(ED25519_PKCS8 + seedHex),
    format: 'der',
    type: 'pkcs8',
  });
}
function ed25519PubFromSeed(seedHex) {
  const spki = crypto.createPublicKey(importEd25519Priv(seedHex)).export({
    format: 'der',
    type: 'spki',
  });
  return toHex(spki.subarray(spki.length - 32));
}
function ed25519Sign(seedHex, msgHex) {
  return toHex(crypto.sign(null, fromHex(msgHex), importEd25519Priv(seedHex)));
}
function ed25519Verify(pubHex, msgHex, sigHex) {
  const pub = crypto.createPublicKey({
    key: fromHex(ED25519_SPKI + pubHex),
    format: 'der',
    type: 'spki',
  });
  return crypto.verify(null, fromHex(msgHex), pub, fromHex(sigHex));
}

function hkdfSha256(ikmHex, saltHex, infoHex, length) {
  return toHex(
    Buffer.from(
      crypto.hkdfSync('sha256', fromHex(ikmHex), fromHex(saltHex), fromHex(infoHex), length),
    ),
  );
}

function aes256gcmEncrypt(keyHex, ivHex, aadHex, plaintextHex) {
  const cipher = crypto.createCipheriv('aes-256-gcm', fromHex(keyHex), fromHex(ivHex));
  if (aadHex) cipher.setAAD(fromHex(aadHex));
  const ct = Buffer.concat([cipher.update(fromHex(plaintextHex)), cipher.final()]);
  return { ciphertext: toHex(ct), tag: toHex(cipher.getAuthTag()) };
}

function aes256gcmDecrypt(keyHex, ivHex, aadHex, ciphertextHex, tagHex) {
  const decipher = crypto.createDecipheriv('aes-256-gcm', fromHex(keyHex), fromHex(ivHex));
  if (aadHex) decipher.setAAD(fromHex(aadHex));
  decipher.setAuthTag(fromHex(tagHex));
  return toHex(Buffer.concat([decipher.update(fromHex(ciphertextHex)), decipher.final()]));
}

const utf8Hex = (s) => toHex(Buffer.from(s, 'utf8'));

// ISO/IEC 7816-4 padding to the 256-byte bucket, exactly as the adapter pads
// payload JSON before AES-GCM (message_padding.dart): append 0x80, then 0x00
// filler to the smallest bucket that fits len + 1.
function pad7816ToBucket(plainBuf, bucket) {
  if (plainBuf.length + 1 > bucket) {
    throw new Error(`KAT plaintext exceeds the ${bucket}-byte padding bucket`);
  }
  return Buffer.concat([plainBuf, Buffer.from([0x80]), Buffer.alloc(bucket - plainBuf.length - 1)]);
}

function assertEq(label, actual, expected) {
  if (actual !== expected) {
    throw new Error(
      `RFC anchor mismatch for ${label}:\n  got      ${actual}\n  expected ${expected}`,
    );
  }
}

function build() {
  // --- RFC anchors: prove the Node/OpenSSL oracle matches published vectors ---

  // RFC 7748 §6.1 — X25519 Alice/Bob.
  const alicePriv = '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a';
  const alicePub = '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a';
  const bobPriv = '5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb';
  const bobPub = 'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f';
  const x25519SharedRfc = '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742';
  assertEq(
    'RFC7748 alice pub derivation',
    x25519PubFromPriv(importX25519Priv(alicePriv)),
    alicePub,
  );
  assertEq('RFC7748 bob pub derivation', x25519PubFromPriv(importX25519Priv(bobPriv)), bobPub);
  assertEq('RFC7748 shared (alice x bob)', x25519Shared(alicePriv, bobPub), x25519SharedRfc);
  assertEq('RFC7748 shared (bob x alice)', x25519Shared(bobPriv, alicePub), x25519SharedRfc);

  // RFC 5869 §A.1 — HKDF-SHA256 basic test case.
  const hkdfRfcOkm =
    '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865';
  assertEq(
    'RFC5869 A.1 HKDF-SHA256',
    hkdfSha256('0b'.repeat(22), '000102030405060708090a0b0c', 'f0f1f2f3f4f5f6f7f8f9', 42),
    hkdfRfcOkm,
  );

  // --- Deterministic KATs from fixed inputs (Node computes the outputs) ---

  // Ed25519 is deterministic (RFC 8032): fixed seed + message => fixed signature.
  const edSeed = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
  const edMsg = toHex(Buffer.from('veil-kat: the quick brown fox', 'utf8'));
  const edPub = ed25519PubFromSeed(edSeed);
  const edSig = ed25519Sign(edSeed, edMsg);
  const edTamperedMsg = toHex(Buffer.from('veil-kat: the quick brown FOX', 'utf8'));

  // AES-256-GCM with a fixed key/nonce/AAD (deterministic given fixed nonce).
  const gcmKey = '0101020305080d1522375990e97962db3d61a3e5c8f1e2d4b6a89b7c5e3f1a2b3';
  const gcmIv = '111213141516171819202122';
  const gcmAad = toHex(Buffer.from('veil-frame-aad-v3|kat', 'utf8'));
  const gcmPlain = toHex(Buffer.from('attack at dawn — veil KAT plaintext', 'utf8'));
  const gcm = aes256gcmEncrypt(gcmKey, gcmIv, gcmAad, gcmPlain);

  // --- Protocol-level KATs: the legacy v1 (lib-x25519-aes256gcm-v3) schedule ---
  //
  // These compose the primitives above exactly the way the production adapter
  // still does for legacy v1 sessions (docs/crypto-envelope-spec.md § Legacy
  // protocol v1; reference lib_crypto_adapter.dart). Protocol v2 has its own
  // vectors (vectors.protocolV2).
  // Every HKDF label below ("veil-root-v2", "veil-chain-A-v2", ...) is wire
  // format: an implementation that drifts on any label, salt, field order, or
  // counter encoding will fail these vectors — which is the point.

  // Session bootstrap: sharedSecret = X25519(initiatorRatchetPriv, responderPub).
  const conversationId = 'veil-kat-conversation-01';
  const initiatorDeviceId = 'device-a-0001'; // lexicographically smaller => "A"
  const responderDeviceId = 'device-b-0002';
  const initRatchetPriv = 'a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf';
  const respPriv = 'c0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedf';
  const initRatchetPub = x25519PubFromPriv(importX25519Priv(initRatchetPriv));
  const respPub = x25519PubFromPriv(importX25519Priv(respPriv));
  const x3dhShared = x25519Shared(initRatchetPriv, respPub);
  // Both sides must agree on the shared secret before anything is emitted.
  assertEq(
    'protocol bootstrap shared symmetric',
    x25519Shared(respPriv, initRatchetPub),
    x3dhShared,
  );

  const convSalt = utf8Hex(conversationId);
  const rootKey = hkdfSha256(x3dhShared, convSalt, utf8Hex('veil-root-v2'), 32);
  const chainKeyA = hkdfSha256(x3dhShared, convSalt, utf8Hex('veil-chain-A-v2'), 32);
  const chainKeyB = hkdfSha256(x3dhShared, convSalt, utf8Hex('veil-chain-B-v2'), 32);

  // DH ratchet step: fresh keypair × last seen peer pub, mixed with the root.
  const stepPriv = '404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f';
  const stepPub = x25519PubFromPriv(importX25519Priv(stepPriv));
  const dhOut = x25519Shared(stepPriv, respPub);
  const dhKdfOut = hkdfSha256(dhOut, rootKey, utf8Hex('veil-dh-rk-v2'), 64);
  const newRootKey = dhKdfOut.slice(0, 64);
  const newSendChainKey = dhKdfOut.slice(64, 128);

  // Symmetric (hash) ratchet: three steps of the initiator's send chain.
  const chainSteps = [];
  let chainKey = chainKeyA;
  for (let counter = 0; counter <= 2; counter += 1) {
    const messageKey = hkdfSha256(
      chainKey,
      utf8Hex(`veil-msg-n${counter}`),
      utf8Hex('veil-msg-v1'),
      32,
    );
    chainSteps.push({ counter, chainKey, messageKey });
    chainKey = hkdfSha256(chainKey, '00', utf8Hex('veil-chain-next-v1'), 32);
  }

  // Full frame under veil-frame-aad-v3 header binding, keyed by the chain
  // step whose counter matches the frame header (counter = 2).
  const frameStep = chainSteps[2];
  const frameNonce = '000102030405060708090a0b';
  const framePayloadJson = '{"body":"hello from the veil KAT","kind":"text"}';
  const framePadded = pad7816ToBucket(Buffer.from(framePayloadJson, 'utf8'), 256);
  const frameCounterBe = Buffer.alloc(4);
  frameCounterBe.writeUInt32BE(frameStep.counter);
  const frameAad = Buffer.concat([
    Buffer.from('veil-frame-aad-v3', 'utf8'),
    fromHex(initRatchetPub),
    frameCounterBe,
    Buffer.from(initiatorDeviceId, 'utf8'),
  ]);
  const frameEnc = aes256gcmEncrypt(
    frameStep.messageKey,
    frameNonce,
    toHex(frameAad),
    toHex(framePadded),
  );
  const frameHex = initRatchetPub + toHex(frameCounterBe) + frameEnc.ciphertext + frameEnc.tag;

  // Tampered header: same ciphertext/tag, AAD rebuilt with counter+1. The GCM
  // tag must not verify. Prove both directions with the oracle before emitting.
  const tamperedCounterBe = Buffer.alloc(4);
  tamperedCounterBe.writeUInt32BE(frameStep.counter + 1);
  const tamperedAad = Buffer.concat([
    Buffer.from('veil-frame-aad-v3', 'utf8'),
    fromHex(initRatchetPub),
    tamperedCounterBe,
    Buffer.from(initiatorDeviceId, 'utf8'),
  ]);
  assertEq(
    'frame decrypt with bound header',
    aes256gcmDecrypt(
      frameStep.messageKey,
      frameNonce,
      toHex(frameAad),
      frameEnc.ciphertext,
      frameEnc.tag,
    ),
    toHex(framePadded),
  );
  let tamperedDecryptFails = false;
  try {
    aes256gcmDecrypt(
      frameStep.messageKey,
      frameNonce,
      toHex(tamperedAad),
      frameEnc.ciphertext,
      frameEnc.tag,
    );
  } catch {
    tamperedDecryptFails = true;
  }
  if (!tamperedDecryptFails) {
    throw new Error('tampered-header frame unexpectedly decrypted — AAD binding is broken');
  }

  return {
    schema: 'veil-crypto-kat-v2',
    description:
      'Known-answer test vectors for VEIL message-crypto primitives, the legacy ' +
      'veil-envelope-v1 derivation schedule (protocol) and the veil-envelope-v2 handshake, ' +
      'ratchet, frame, payload and attachment formats (protocolV2). Hex unless a field says b64u. ' +
      'Reproduce every output by feeding the inputs to the target implementation. ' +
      'Regenerate/verify with scripts/crypto-test-vectors.mjs.',
    generator: `node ${process.version} / OpenSSL via node:crypto`,
    rfcAnchors: ['RFC 7748 §6.1 (X25519)', 'RFC 5869 §A.1 (HKDF-SHA256)'],
    vectors: {
      x25519: {
        algorithm: 'X25519 (RFC 7748)',
        cases: [
          {
            note: 'RFC 7748 §6.1 anchor',
            alicePrivate: alicePriv,
            alicePublic: alicePub,
            bobPrivate: bobPriv,
            bobPublic: bobPub,
            sharedSecret: x25519SharedRfc,
          },
        ],
      },
      ed25519: {
        algorithm: 'Ed25519 (RFC 8032, deterministic)',
        cases: [
          {
            note: 'fixed seed + utf8 message',
            seed: edSeed,
            publicKey: edPub,
            messageHex: edMsg,
            signature: edSig,
            verifies: ed25519Verify(edPub, edMsg, edSig),
            tamperedMessageHex: edTamperedMsg,
            tamperedVerifies: ed25519Verify(edPub, edTamperedMsg, edSig),
          },
        ],
      },
      hkdfSha256: {
        algorithm: 'HKDF-SHA256 (RFC 5869)',
        cases: [
          {
            note: 'RFC 5869 §A.1 anchor',
            ikm: '0b'.repeat(22),
            salt: '000102030405060708090a0b0c',
            info: 'f0f1f2f3f4f5f6f7f8f9',
            length: 42,
            okm: hkdfRfcOkm,
          },
        ],
      },
      aes256gcm: {
        algorithm: 'AES-256-GCM',
        cases: [
          {
            note: 'fixed key/nonce/aad',
            key: gcmKey,
            nonce: gcmIv,
            aad: gcmAad,
            plaintextHex: gcmPlain,
            ciphertext: gcm.ciphertext,
            tag: gcm.tag,
          },
        ],
      },
      protocol: {
        algorithm:
          'veil-envelope-v1 / lib-x25519-aes256gcm-v3 derivation schedule ' +
          '(docs/crypto-envelope-spec.md; reference lib_crypto_adapter.dart)',
        sessionSetup: {
          note:
            'Bootstrap: sharedSecret = X25519(initiatorRatchetPriv, responderPub); ' +
            'rootKey / chainKeyA / chainKeyB = HKDF-SHA256(ikm=sharedSecret, ' +
            'salt=utf8(conversationId), info=label, L=32) with labels ' +
            '"veil-root-v2" / "veil-chain-A-v2" / "veil-chain-B-v2". The peer with ' +
            'the lexicographically smaller deviceId is "A": sends on chainKeyA, ' +
            'receives on chainKeyB; the other peer mirrors.',
          conversationId,
          initiatorDeviceId,
          responderDeviceId,
          initiatorRatchetPrivate: initRatchetPriv,
          initiatorRatchetPublic: initRatchetPub,
          responderPrivate: respPriv,
          responderPublic: respPub,
          sharedSecret: x3dhShared,
          rootKey,
          chainKeyA,
          chainKeyB,
        },
        dhRatchetStep: {
          note:
            'DH ratchet: kdfOutput = HKDF-SHA256(ikm=X25519(newRatchetPriv, peerPub), ' +
            'salt=previousRootKey, info="veil-dh-rk-v2", L=64); newRootKey = ' +
            'kdfOutput[0..32], newSendChainKey = kdfOutput[32..64]; the send counter ' +
            'resets to 0 and newRatchetPublic goes on the next frame wire.',
          newRatchetPrivate: stepPriv,
          newRatchetPublic: stepPub,
          peerPublic: respPub,
          dhOutput: dhOut,
          previousRootKey: rootKey,
          newRootKey,
          newSendChainKey,
        },
        messageChain: {
          note:
            'Symmetric ratchet from sessionSetup.chainKeyA: messageKey_n = ' +
            'HKDF-SHA256(ikm=chainKey_n, salt=utf8("veil-msg-n"+decimal(n)), ' +
            'info="veil-msg-v1", L=32); chainKey_{n+1} = HKDF-SHA256(ikm=chainKey_n, ' +
            'salt=[0x00], info="veil-chain-next-v1", L=32).',
          steps: chainSteps,
        },
        frame: {
          note:
            'Full wire frame: plaintext payload JSON is ISO/IEC 7816-4 padded to the ' +
            '256-byte bucket (append 0x80 then 0x00 filler), then AES-256-GCM with ' +
            'AAD = utf8("veil-frame-aad-v3") || ratchetPub(32) || counter(4 BE) || ' +
            'utf8(senderDeviceId). Key is messageChain steps[counter].messageKey. ' +
            'frameHex = ratchetPub || counter || ciphertext || tag.',
          senderDeviceId: initiatorDeviceId,
          ratchetPublic: initRatchetPub,
          counter: frameStep.counter,
          key: frameStep.messageKey,
          nonce: frameNonce,
          payloadJson: framePayloadJson,
          paddedPlaintextHex: toHex(framePadded),
          aad: toHex(frameAad),
          ciphertext: frameEnc.ciphertext,
          tag: frameEnc.tag,
          frameHex,
          tamperedHeader: {
            note:
              'Same key/nonce/ciphertext/tag with the AAD rebuilt from a header whose ' +
              'counter was flipped to 3. GCM tag verification MUST fail: the message ' +
              'does not decrypt and the receiver rolls back ratchet state.',
            counter: frameStep.counter + 1,
            aad: toHex(tamperedAad),
            decryptFails: tamperedDecryptFails,
          },
        },
      },
      protocolV2: buildProtocolV2(),
    },
  };
}

// --- Protocol v2 (veil-envelope-v2) reference ------------------------------
//
// An independent node:crypto implementation of docs/crypto-envelope-spec.md
// §"Protocol v2": bundle v2 (contract C1), X3DH with SPK + OPK, the Double
// Ratchet with PN, frame v2 + AAD v4, the inner payload, Padmé and the
// attachment pointer cipher. Every key and nonce is fixed and listed in the
// order the Dart adapter draws them from its random source, so
// apps/mobile/test/crypto/crypto_kat_v2_test.dart can replay the scenario
// and must reproduce every byte.

const b64u = (buf) => Buffer.from(buf).toString('base64url');
const fill = (byteHex, length) => byteHex.repeat(length);
const u16be = (n) => {
  const b = Buffer.alloc(2);
  b.writeUInt16BE(n);
  return b;
};
const u32be = (n) => {
  const b = Buffer.alloc(4);
  b.writeUInt32BE(n);
  return b;
};
const u64be = (n) => {
  const b = Buffer.alloc(8);
  b.writeBigUInt64BE(BigInt(n));
  return b;
};
const lp = (s) => {
  const bytes = Buffer.from(s, 'utf8');
  return Buffer.concat([u16be(bytes.length), bytes]);
};
const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest();

// message_padding.dart bucketFor: powers of two from 256 up to 64 KiB, then
// multiples of 64 KiB.
function bucketFor(n) {
  let b = 256;
  while (b < n && b < 65536) b <<= 1;
  if (n <= b) return b;
  return Math.ceil(n / 65536) * 65536;
}
function pad7816(plainBuf, target) {
  return Buffer.concat([plainBuf, Buffer.from([0x80]), Buffer.alloc(target - plainBuf.length - 1)]);
}
// Padmé (PETS 2019) with integer log2: E = floor(log2 L), S = floor(log2 E)+1.
function padme(length) {
  if (length < 2) return length;
  const e = 31 - Math.clz32(length);
  const s = 32 - Math.clz32(e);
  const mask = 2 ** (e - s) - 1;
  return (length + mask) & ~mask;
}

const kdfRoot = (rootKeyHex, dhHex) => {
  const out = hkdfSha256(dhHex, rootKeyHex, utf8Hex('veil-dh-rk-v2'), 64);
  return { rootKey: out.slice(0, 64), chainKey: out.slice(64) };
};
const messageKey = (chainKeyHex, n) =>
  hkdfSha256(chainKeyHex, utf8Hex(`veil-msg-n${n}`), utf8Hex('veil-msg-v1'), 32);
const nextChainKey = (chainKeyHex) =>
  hkdfSha256(chainKeyHex, '00', utf8Hex('veil-chain-next-v1'), 32);

function buildProtocolV2() {
  const envelopeVersion = 'veil-envelope-v2';
  const conversationId = 'veil-kat-conversation-v2';
  const aliceDeviceId = 'device-a-0001';
  const bobDeviceId = 'device-b-0002';

  // (A) Bob's identity and bundle: the contract C1 vector.
  const bobSeed = fill('11', 32);
  const bobIkxPriv = fill('55', 32);
  const bobSpkPriv = fill('66', 32);
  const spkId = 1;
  const spkTs = 1767225600000;
  const bobIdentity = ed25519PubFromSeed(bobSeed);
  const bobIkx = x25519PubFromPriv(importX25519Priv(bobIkxPriv));
  const bobSpk = x25519PubFromPriv(importX25519Priv(bobSpkPriv));
  const ikxSignedMessage = (ikxHex) =>
    toHex(Buffer.concat([Buffer.from('veil-ikx-v2'), fromHex(ikxHex)]));
  const bobIkxMessage = ikxSignedMessage(bobIkx);
  const bobIkxSig = ed25519Sign(bobSeed, bobIkxMessage);
  const spkMessage = toHex(
    Buffer.concat([Buffer.from('veil-spk-v2'), u32be(spkId), u64be(spkTs), fromHex(bobSpk)]),
  );
  const spkSig = ed25519Sign(bobSeed, spkMessage);
  const bundleJson = JSON.stringify({
    v: 2,
    ikx: b64u(fromHex(bobIkx)),
    ikxSig: b64u(fromHex(bobIkxSig)),
    spkId,
    spk: b64u(fromHex(bobSpk)),
    spkTs,
    spkSig: b64u(fromHex(spkSig)),
  });
  const signedPrekeyBundle = b64u(Buffer.from(bundleJson, 'utf8'));
  assertEq(
    'contract C1 bundle vector',
    signedPrekeyBundle,
    'eyJ2IjoyLCJpa3giOiJPS3RtUzlodmQ5Zm1hOTJhNEhrcEU2bFAyTE02RW1BQ2ZrdEd3ZlNJVEdjIiwiaWt4U2lnIjoiUlJEdzVl' +
      'c05wdXZySjVYQnNlVXRFdVM2SFNjVG1TVjQwdHRsdkc4N0gzWkRQLTZpX2F5bVpvX29TWlVTNWtBRHF2WGZLU1hnX3E3NHZ3R09tNlhu' +
      'RFEiLCJzcGtJZCI6MSwic3BrIjoiSVo1TmdBMnBhTktsX0xBSng0VDBkR3h4T08yNTdraEV0em5vTUxCYzlDUSIsInNwa1RzIjoxNzY3' +
      'MjI1NjAwMDAwLCJzcGtTaWciOiJXNTJGa1ZtTTU3YjNaaFBNZkd3NjVNMnB1NHpMUmR3dmpGcWgzc0QzclI0MTRZaU9vWWVicFFBV216' +
      'U05wX3FEX1JsN2s3a29zdFJVbnNiTzNxQ3NBZyJ9',
  );
  const bobOpkId = 1;
  const bobOpkPriv = fill('77', 32);
  const bobOpk = x25519PubFromPriv(importX25519Priv(bobOpkPriv));

  // Alice: identity (her own SPK is drawn but unused here), then the
  // handshake ephemeral EK and her first ratchet key, in draw order.
  const aliceSeed = fill('21', 32);
  const aliceIkxPriv = fill('22', 32);
  const aliceSpkPriv = fill('23', 32);
  const aliceClockMs = spkTs + 3600 * 1000;
  const aliceIdentity = ed25519PubFromSeed(aliceSeed);
  const aliceIkx = x25519PubFromPriv(importX25519Priv(aliceIkxPriv));
  const aliceIkxSig = ed25519Sign(aliceSeed, ikxSignedMessage(aliceIkx));
  const ekPriv = fill('31', 32);
  const ek = x25519PubFromPriv(importX25519Priv(ekPriv));

  // (C) X3DH.
  const dh1 = x25519Shared(aliceIkxPriv, bobSpk);
  const dh2 = x25519Shared(ekPriv, bobIkx);
  const dh3 = x25519Shared(ekPriv, bobSpk);
  const dh4 = x25519Shared(ekPriv, bobOpk);
  assertEq('X3DH DH1 symmetric', x25519Shared(bobSpkPriv, aliceIkx), dh1);
  assertEq('X3DH DH2 symmetric', x25519Shared(bobIkxPriv, ek), dh2);
  assertEq('X3DH DH3 symmetric', x25519Shared(bobSpkPriv, ek), dh3);
  assertEq('X3DH DH4 symmetric', x25519Shared(bobOpkPriv, ek), dh4);
  const x3dhIkm = fill('ff', 32) + dh1 + dh2 + dh3 + dh4;
  const x3dhSalt = fill('00', 32);
  const x3dhInfo = utf8Hex('veil-x3dh-v2') + aliceIdentity + bobIdentity;
  const sharedKey = hkdfSha256(x3dhIkm, x3dhSalt, x3dhInfo, 32);
  const associatedData = aliceIdentity + aliceIkx + bobIdentity + bobIkx;
  const preKeyHeader = toHex(
    Buffer.concat([
      fromHex(aliceIdentity),
      fromHex(aliceIkx),
      fromHex(aliceIkxSig),
      fromHex(ek),
      u32be(spkId),
      u32be(bobOpkId),
    ]),
  );

  // Ratchet init: Alice DHs0 against SPK_B; Bob's DHs is the SPK pair.
  const aliceRatchet0Priv = fill('32', 32);
  const aliceRatchet0 = x25519PubFromPriv(importX25519Priv(aliceRatchet0Priv));
  const initDh = x25519Shared(aliceRatchet0Priv, bobSpk);
  assertEq('ratchet init DH symmetric', x25519Shared(bobSpkPriv, aliceRatchet0), initDh);
  const init = kdfRoot(sharedKey, initDh);

  // (D)+(E) One frame: header, AAD, padded inner payload, AES-256-GCM.
  function seal({ label, sender, kind, preKey, ratchetPublic, pn, n, chainKey, nonce, payload }) {
    const header = toHex(
      Buffer.concat([
        Buffer.from([0x02, preKey ? 0x01 : 0x02]),
        preKey ? fromHex(preKey) : Buffer.alloc(0),
        fromHex(ratchetPublic),
        u32be(pn),
        u32be(n),
      ]),
    );
    const aad = toHex(
      Buffer.concat([
        Buffer.from('veil-frame-aad-v4', 'utf8'),
        lp(envelopeVersion),
        lp(conversationId),
        lp(sender),
        lp(kind),
        fromHex(header),
        fromHex(associatedData),
      ]),
    );
    const innerPayloadJson = JSON.stringify(payload);
    const plain = Buffer.from(innerPayloadJson, 'utf8');
    const padded = toHex(pad7816(plain, bucketFor(plain.length + 1)));
    const key = messageKey(chainKey, n);
    const enc = aes256gcmEncrypt(key, nonce, aad, padded);
    assertEq(
      `${label} decrypts`,
      aes256gcmDecrypt(key, nonce, aad, enc.ciphertext, enc.tag),
      padded,
    );
    const frame = header + enc.ciphertext + enc.tag;
    return {
      label,
      senderDeviceId: sender,
      messageKind: kind,
      frameType: preKey ? 'prekey' : 'normal',
      ratchetPublic,
      previousCounter: pn,
      counter: n,
      chainKey,
      messageKey: key,
      nonce,
      innerPayloadJson,
      paddedPlaintext: padded,
      header,
      aad,
      ciphertext: enc.ciphertext,
      tag: enc.tag,
      frame,
      envelopeCiphertext: b64u(fromHex(frame)),
      envelopeNonce: b64u(fromHex(nonce)),
    };
  }

  // (K) Attachment carried by A2: Padmé-padded, AAD-bound to its id.
  const attachmentId = 'att-kat-0001';
  const attachmentKey = fill('61', 32);
  const attachmentNonce = fill('62', 12);
  const attachmentPlain = Buffer.from(Array.from({ length: 100 }, (_, i) => i));
  const attachmentPadded = pad7816(attachmentPlain, padme(attachmentPlain.length + 1));
  const attachmentAad = toHex(
    Buffer.concat([Buffer.from('veil-att-v2', 'utf8'), Buffer.from(attachmentId, 'utf8')]),
  );
  const attachmentEnc = aes256gcmEncrypt(
    attachmentKey,
    attachmentNonce,
    attachmentAad,
    toHex(attachmentPadded),
  );
  const attachmentBlob = attachmentEnc.ciphertext + attachmentEnc.tag;
  const attachmentPointer = {
    id: attachmentId,
    ck: b64u(fromHex(attachmentKey)),
    n: b64u(fromHex(attachmentNonce)),
    d: b64u(sha256(fromHex(attachmentBlob))),
    ct: 'application/pdf',
    sz: attachmentPlain.length,
    alg: 'aes256gcm-v2',
  };

  // (F) Turns: A0, A1 (PreKey frames; A1 is delivered late), Bob replies B0
  // (his send step), Alice answers A2 (her send step, PN = 2).
  const a0Expiry = spkTs + 2 * 3600 * 1000;
  const a0 = seal({
    label: 'A0',
    sender: aliceDeviceId,
    kind: 'text',
    preKey: preKeyHeader,
    ratchetPublic: aliceRatchet0,
    pn: 0,
    n: 0,
    chainKey: init.chainKey,
    nonce: fill('41', 12),
    payload: { pv: 2, b: 'hello bob, this is alice (v2 KAT)', k: 'text', x: a0Expiry, att: null },
  });
  const aliceChain1 = nextChainKey(init.chainKey);
  const a1 = seal({
    label: 'A1',
    sender: aliceDeviceId,
    kind: 'text',
    preKey: preKeyHeader,
    ratchetPublic: aliceRatchet0,
    pn: 0,
    n: 1,
    chainKey: aliceChain1,
    nonce: fill('42', 12),
    payload: { pv: 2, b: 'A1 straggler 안녕', k: 'text', x: null, att: null },
  });

  const bobRatchet1Priv = fill('51', 32);
  const bobRatchet1 = x25519PubFromPriv(importX25519Priv(bobRatchet1Priv));
  const bobStepDh = x25519Shared(bobRatchet1Priv, aliceRatchet0);
  const bobStep = kdfRoot(init.rootKey, bobStepDh);
  const b0 = seal({
    label: 'B0',
    sender: bobDeviceId,
    kind: 'text',
    preKey: null,
    ratchetPublic: bobRatchet1,
    pn: 0,
    n: 0,
    chainKey: bobStep.chainKey,
    nonce: fill('52', 12),
    payload: { pv: 2, b: 'hi alice, bob here', k: 'text', x: null, att: null },
  });

  const aliceRatchet1Priv = fill('33', 32);
  const aliceRatchet1 = x25519PubFromPriv(importX25519Priv(aliceRatchet1Priv));
  const aliceStepDh = x25519Shared(aliceRatchet1Priv, bobRatchet1);
  assertEq('A2 send-step DH symmetric', x25519Shared(bobRatchet1Priv, aliceRatchet1), aliceStepDh);
  const aliceStep = kdfRoot(bobStep.rootKey, aliceStepDh);
  const a2 = seal({
    label: 'A2',
    sender: aliceDeviceId,
    kind: 'file',
    preKey: null,
    ratchetPublic: aliceRatchet1,
    pn: 2,
    n: 0,
    chainKey: aliceStep.chainKey,
    nonce: fill('43', 12),
    payload: { pv: 2, b: 'Encrypted attachment', k: 'file', x: null, att: attachmentPointer },
  });

  const padmeSizes = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 100, 1000, 65537, 1000000];

  return {
    algorithm:
      'veil-envelope-v2: X3DH (SPK + OPK, both identities authenticated) + Double Ratchet with PN; ' +
      'docs/crypto-envelope-spec.md §Protocol v2; reference lib_crypto_adapter.dart',
    constants: {
      envelopeVersion,
      frameAadLabel: 'veil-frame-aad-v4',
      x3dhInfoLabel: 'veil-x3dh-v2',
      ikxSignatureLabel: 'veil-ikx-v2',
      spkSignatureLabel: 'veil-spk-v2',
      attachmentAadLabel: 'veil-att-v2',
      attachmentAlgorithm: 'aes256gcm-v2',
      noOneTimePrekeyId: 4294967295,
      innerPayloadVersion: 2,
    },
    bundle: {
      note:
        'Contract C1. identityPublicKey = b64u(Ed25519 public of identitySeed); ikxSig = Ed25519(IK, ' +
        'utf8("veil-ikx-v2") || ikx); spkSig = Ed25519(IK, utf8("veil-spk-v2") || u32be(spkId) || ' +
        'u64be(spkTs) || spk); signedPrekeyBundle = b64u(compact JSON, keys v, ikx, ikxSig, spkId, ' +
        'spk, spkTs, spkSig). The Dart adapter draws identitySeed, ikxPrivate, spkPrivate in that order.',
      identitySeed: bobSeed,
      identityPublic: bobIdentity,
      identityPublicKey: b64u(fromHex(bobIdentity)),
      ikxPrivate: bobIkxPriv,
      ikxPublic: bobIkx,
      ikxSignedMessage: bobIkxMessage,
      ikxSignature: bobIkxSig,
      spkPrivate: bobSpkPriv,
      spkPublic: bobSpk,
      spkId,
      spkTs,
      spkSignedMessage: spkMessage,
      spkSignature: spkSig,
      bundleJson,
      signedPrekeyBundle,
    },
    oneTimePrekey: {
      keyId: bobOpkId,
      private: bobOpkPriv,
      public: bobOpk,
      publicKey: b64u(fromHex(bobOpk)),
    },
    alice: {
      note: 'Initiator identity; clockMs is her wall clock (within the SPK freshness window).',
      identitySeed: aliceSeed,
      identityPublic: aliceIdentity,
      ikxPrivate: aliceIkxPriv,
      ikxPublic: aliceIkx,
      ikxSignature: aliceIkxSig,
      spkPrivate: aliceSpkPriv,
      clockMs: aliceClockMs,
    },
    x3dh: {
      note:
        'DH1 = X25519(IKx_A, SPK_B), DH2 = X25519(EK, IKx_B), DH3 = X25519(EK, SPK_B), DH4 = ' +
        'X25519(EK, OPK_B). sharedKey = HKDF-SHA256(ikm = 0xFF*32 || DH1 || DH2 || DH3 || DH4, ' +
        'salt = 0x00*32, info = utf8("veil-x3dh-v2") || IKed_A || IKed_B, L = 32). associatedData = ' +
        'IKed_A || IKx_A || IKed_B || IKx_B. preKeyHeader = IKed_A || IKx_A || ikxSig_A || EK || ' +
        'u32be(spkId) || u32be(opkId).',
      ephemeralPrivate: ekPriv,
      ephemeralPublic: ek,
      dh1,
      dh2,
      dh3,
      dh4,
      ikm: x3dhIkm,
      salt: x3dhSalt,
      info: x3dhInfo,
      sharedKey,
      associatedData,
      preKeyHeader,
    },
    ratchetInit: {
      note:
        'Alice: (rootKey, sendChainKey) = HKDF-SHA256(ikm = X25519(DHs0, SPK_B), salt = sharedKey, ' +
        'info = "veil-dh-rk-v2", L = 64). Bob starts with DHs = SPK_B, rootKey = sharedKey.',
      aliceRatchetPrivate: aliceRatchet0Priv,
      aliceRatchetPublic: aliceRatchet0,
      dhOutput: initDh,
      rootKey: init.rootKey,
      sendChainKey: init.chainKey,
    },
    sendSteps: {
      bob: {
        note: "Bob's first send: fresh DHs1; (rootKey, chainKey) = KDF_RK(ratchetInit.rootKey, X25519(DHs1, aliceRatchet0)).",
        ratchetPrivate: bobRatchet1Priv,
        ratchetPublic: bobRatchet1,
        dhOutput: bobStepDh,
        rootKey: bobStep.rootKey,
        chainKey: bobStep.chainKey,
      },
      alice: {
        note: "Alice's turn after B0: PN = 2; fresh DHs1; (rootKey, chainKey) = KDF_RK(bob.rootKey, X25519(DHs1, bobRatchet1)).",
        ratchetPrivate: aliceRatchet1Priv,
        ratchetPublic: aliceRatchet1,
        dhOutput: aliceStepDh,
        rootKey: aliceStep.rootKey,
        chainKey: aliceStep.chainKey,
      },
    },
    frames: {
      note:
        'frame = 0x02 || type (0x01 PreKey, 0x02 Normal) || [preKeyHeader] || ratchetPub || ' +
        'u32be(PN) || u32be(N) || ciphertext || tag. AAD = utf8("veil-frame-aad-v4") || ' +
        'lp(version) || lp(conversationId) || lp(senderDeviceId) || lp(messageKind) || header || ' +
        'associatedData, lp(s) = u16be(len) || utf8(s). Plaintext = innerPayloadJson ISO/IEC 7816-4 ' +
        'padded to bucketFor(len + 1). Bob receives A0, A2, then A1: A2 carries PN = 2, so Bob ' +
        'stashes the key for (aliceRatchet0, N = 1) before his DH step and A1 still decrypts.',
      conversationId,
      aliceDeviceId,
      bobDeviceId,
      deliveryOrderToBob: ['A0', 'A2', 'A1'],
      messages: [a0, a1, b0, a2],
    },
    attachment: {
      note:
        'padded = ISO/IEC 7816-4 to padmeLength(len + 1); blob = AES-256-GCM(key, nonce, padded, ' +
        'aad = utf8("veil-att-v2") || utf8(attachmentId)) as ciphertext || tag; digest = SHA-256(blob). ' +
        'pointer is the inner-payload "att" object A2 carries.',
      attachmentId,
      key: attachmentKey,
      nonce: attachmentNonce,
      plaintextHex: toHex(attachmentPlain),
      paddedLength: attachmentPadded.length,
      aad: attachmentAad,
      blob: attachmentBlob,
      digest: toHex(sha256(fromHex(attachmentBlob))),
      pointer: attachmentPointer,
    },
    padme: padmeSizes.map((n) => ({ n, padme: padme(n) })),
  };
}

function stableStringify(obj) {
  return JSON.stringify(obj, null, 2) + '\n';
}

const generated = build();

if (CHECK) {
  if (!fs.existsSync(OUT)) {
    console.error(`crypto-kat: committed vectors missing at ${path.relative(ROOT, OUT)}`);
    process.exit(1);
  }
  const committed = fs.readFileSync(OUT, 'utf8');
  // Compare on the vectors payload (ignore generator string, which carries the
  // Node version and legitimately varies across runners).
  const strip = (o) => {
    const { generator, ...rest } = o;
    return stableStringify(rest);
  };
  if (strip(JSON.parse(committed)) !== strip(generated)) {
    console.error(
      'crypto-kat: committed vectors do NOT reproduce. Regenerate and review the diff.',
    );
    process.exit(1);
  }
  console.log(
    'crypto-kat: committed vectors reproduce exactly (RFC anchors + deterministic KATs).',
  );
} else {
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, stableStringify(generated));
  console.log(`crypto-kat: wrote ${path.relative(ROOT, OUT)}`);
}
