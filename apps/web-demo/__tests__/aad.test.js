import { describe, it, expect } from 'vitest';
import { buildAad } from '../lib/aad.js';

function hex(u8) {
  return Array.from(u8).map((b) => b.toString(16).padStart(2, '0')).join('');
}

describe('buildAad', () => {
  it('is deterministic for identical inputs', () => {
    const a = buildAad({ conversationId: 'c1', senderDeviceId: 'd1', recipientUserId: 'u1' });
    const b = buildAad({ conversationId: 'c1', senderDeviceId: 'd1', recipientUserId: 'u1' });
    expect(hex(a)).toBe(hex(b));
  });

  it('differs when conversationId differs', () => {
    const a = buildAad({ conversationId: 'c1', senderDeviceId: 'd1', recipientUserId: 'u1' });
    const b = buildAad({ conversationId: 'c2', senderDeviceId: 'd1', recipientUserId: 'u1' });
    expect(hex(a)).not.toBe(hex(b));
  });

  it('differs when senderDeviceId differs', () => {
    const a = buildAad({ conversationId: 'c1', senderDeviceId: 'd1', recipientUserId: 'u1' });
    const b = buildAad({ conversationId: 'c1', senderDeviceId: 'd2', recipientUserId: 'u1' });
    expect(hex(a)).not.toBe(hex(b));
  });

  it('differs when recipientUserId differs', () => {
    const a = buildAad({ conversationId: 'c1', senderDeviceId: 'd1', recipientUserId: 'u1' });
    const b = buildAad({ conversationId: 'c1', senderDeviceId: 'd1', recipientUserId: 'u2' });
    expect(hex(a)).not.toBe(hex(b));
  });

  it('resists field-boundary confusion (length-prefix canonicalization)', () => {
    // Without length prefixing, "ab"+"c" and "a"+"bc" could collide.
    const a = buildAad({ conversationId: 'ab', senderDeviceId: 'c', recipientUserId: '' });
    const b = buildAad({ conversationId: 'a', senderDeviceId: 'bc', recipientUserId: '' });
    expect(hex(a)).not.toBe(hex(b));
  });

  it('treats missing fields as empty strings without throwing', () => {
    const a = buildAad({ conversationId: 'c1' });
    const b = buildAad({ conversationId: 'c1', senderDeviceId: '', recipientUserId: '' });
    expect(hex(a)).toBe(hex(b));
  });

  it('starts with the version tag so a future v2 cannot collide', () => {
    const a = buildAad({ conversationId: 'c1', senderDeviceId: 'd1', recipientUserId: 'u1' });
    const tag = new TextEncoder().encode('veil-aad-v1');
    expect(hex(a.slice(0, tag.length))).toBe(hex(tag));
  });
});
