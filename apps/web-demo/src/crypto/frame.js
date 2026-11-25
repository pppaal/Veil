// Protocol v2 wire frame and its AEAD associated data
// (docs/crypto-envelope-spec.md §Frame, §AEAD associated data (v4)):
//
//   frame = 0x02 || type || [PreKey header (168)] || ratchetPub(32)
//           || u32be(PN) || u32be(N) || ciphertext || tag(16)
//   type  = 0x01 PreKey (initiator not yet acknowledged) | 0x02 Normal
//   aad   = "veil-frame-aad-v4" || lp(version) || lp(conversationId)
//           || lp(senderDeviceId) || lp(messageType) || header || AD
//
// The AAD binds every routing field the server relays in clear, so
// re-labelling a frame (another conversation, sender, kind or version) breaks
// the tag. expiresAt is deliberately absent (contract C4): the server may
// clamp the outer value and the authenticated expiry rides in the payload.

import { concatBytes, lengthPrefixed, readU32be, u32be, utf8 } from './bytes.js';
import { GCM_TAG_BYTES, KEY_BYTES } from './keys.js';
import { decodePreKeyHeader, PRE_KEY_HEADER_BYTES } from './x3dh.js';

export const ENVELOPE_VERSION_V2 = 'veil-envelope-v2';
// Mobile's pre-v2 protocol, which the web client never spoke. An envelope
// without a version predates the server storing one and is read as this.
export const LEGACY_ENVELOPE_VERSION = 'veil-envelope-v1';
const FRAME_AAD_LABEL = utf8('veil-frame-aad-v4');
const FRAME_VERSION = 0x02;
const FRAME_TYPE_PREKEY = 0x01;
const FRAME_TYPE_NORMAL = 0x02;
const COUNTERS_BYTES = 8;

class FrameFormatError extends Error {
  constructor(message) {
    super(message);
    this.name = 'FrameFormatError';
  }
}

export function encodeFrameHeader({ preKeyHeader = null, ratchetPublic, previousCounter, counter }) {
  return concatBytes([
    Uint8Array.of(FRAME_VERSION, preKeyHeader ? FRAME_TYPE_PREKEY : FRAME_TYPE_NORMAL),
    ...(preKeyHeader ? [preKeyHeader] : []),
    ratchetPublic,
    u32be(previousCounter),
    u32be(counter),
  ]);
}

// header is every byte before the ciphertext; sealed is ciphertext || tag.
export function decodeFrame(bytes) {
  if (bytes.length < 2 || bytes[0] !== FRAME_VERSION) throw new FrameFormatError('not a v2 frame');
  const type = bytes[1];
  if (type !== FRAME_TYPE_PREKEY && type !== FRAME_TYPE_NORMAL) throw new FrameFormatError('unknown v2 frame type');
  const ratchetOffset = 2 + (type === FRAME_TYPE_PREKEY ? PRE_KEY_HEADER_BYTES : 0);
  const headerLength = ratchetOffset + KEY_BYTES + COUNTERS_BYTES;
  if (bytes.length < headerLength + GCM_TAG_BYTES) throw new FrameFormatError('v2 frame truncated');
  return {
    header: bytes.slice(0, headerLength),
    preKey: type === FRAME_TYPE_PREKEY ? decodePreKeyHeader(bytes, 2) : null,
    ratchetPublic: bytes.slice(ratchetOffset, ratchetOffset + KEY_BYTES),
    previousCounter: readU32be(bytes, ratchetOffset + KEY_BYTES),
    counter: readU32be(bytes, ratchetOffset + KEY_BYTES + 4),
    sealed: bytes.slice(headerLength),
  };
}

export function buildFrameAad({ version, conversationId, senderDeviceId, messageType, header, associatedData }) {
  return concatBytes([
    FRAME_AAD_LABEL,
    lengthPrefixed(version),
    lengthPrefixed(conversationId),
    lengthPrefixed(senderDeviceId),
    lengthPrefixed(messageType),
    header,
    associatedData,
  ]);
}
