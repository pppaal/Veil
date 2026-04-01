import { randomUUID } from 'node:crypto';

import type {
  AttachmentEncryptionMaterial,
  CryptoEngine,
  CryptoEnvelope,
  DecryptedMessage,
  DeviceIdentityMaterial,
  PlaintextMessageInput,
  PublicKeyBundle,
} from './types';
import {
  DEV_ATTACHMENT_WRAP_ALGORITHM_HINT,
  DEV_ENVELOPE_VERSION,
} from '../domain/protocol';

const toMockBlob = (value: string): string =>
  Buffer.from(value, 'utf8').toString('base64url');

const fromMockBlob = (value: string): string => Buffer.from(value, 'base64url').toString('utf8');
const plaintextRegistry = new Map<string, DecryptedMessage>();
const opaqueToken = (byteLength: number): string =>
  Buffer.from(Array.from({ length: byteLength }, () => Math.floor(Math.random() * 256))).toString(
    'base64url',
  );

export class MockCryptoEngine implements CryptoEngine {
  readonly adapterId = 'mock-dev-adapter';

  async generateDeviceIdentity(deviceId: string): Promise<DeviceIdentityMaterial> {
    // TODO(security): Replace this entire adapter with audited production crypto.
    return {
      identityPublicKey: `mock-id-pub-${deviceId}`,
      identityPrivateKeyRef: `secure-store://identity/${deviceId}`,
      authPublicKey: `mock-auth-pub-${deviceId}`,
      authPrivateKeyRef: `secure-store://auth/${deviceId}`,
      signedPrekeyBundle: toMockBlob(JSON.stringify({ deviceId, prekeyId: randomUUID() })),
    };
  }

  async encryptMessage(
    input: PlaintextMessageInput,
    recipientBundle: PublicKeyBundle,
  ): Promise<CryptoEnvelope> {
    const ciphertext = opaqueToken(48);
    plaintextRegistry.set(ciphertext, {
      body: input.body,
      messageType: input.messageType,
      expiresAt: input.expiresAt ?? null,
      attachment: input.attachment ?? null,
    });

    return {
      version: DEV_ENVELOPE_VERSION,
      conversationId: input.conversationId,
      senderDeviceId: input.senderDeviceId,
      recipientUserId: recipientBundle.userId,
      ciphertext,
      nonce: `mock-nonce-${randomUUID()}`,
      messageType: input.messageType,
      expiresAt: input.expiresAt ?? null,
      attachment: input.attachment ?? null,
    };
  }

  async decryptMessage(envelope: CryptoEnvelope): Promise<DecryptedMessage> {
    const parsed = plaintextRegistry.get(envelope.ciphertext);
    if (!parsed) {
      return {
        body: envelope.messageType === 'file' ? 'Encrypted attachment' : 'Encrypted message',
        messageType: envelope.messageType,
        expiresAt: envelope.expiresAt ?? null,
        attachment: envelope.attachment ?? null,
      };
    }

    return {
      body: parsed.body,
      messageType: parsed.messageType,
      expiresAt: parsed.expiresAt ?? null,
      attachment: parsed.attachment ?? null,
    };
  }

  async encryptAttachmentKey(
    contentKey: string,
    recipientBundle: PublicKeyBundle,
  ): Promise<AttachmentEncryptionMaterial> {
    return {
      encryptedKey: opaqueToken(32),
      nonce: `mock-attachment-nonce-${randomUUID()}`,
      algorithmHint: DEV_ATTACHMENT_WRAP_ALGORITHM_HINT,
    };
  }
}
