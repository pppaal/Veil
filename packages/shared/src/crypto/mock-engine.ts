import type {
  AttachmentEncryptionMaterial,
  CryptoAdapter,
  CryptoEnvelope,
  CryptoEnvelopeCodec,
  DecryptedMessage,
  DeviceAuthChallengeSigner,
  DeviceAuthKeyMaterial,
  DeviceIdentityMaterial,
  DeviceIdentityProvider,
  EncryptedAttachmentReference,
  KeyBundleCodec,
  MessageCryptoEngine,
  PlaintextMessageInput,
  PublicKeyBundle,
} from './types';
import {
  DEV_ATTACHMENT_WRAP_ALGORITHM_HINT,
  DEV_ENVELOPE_VERSION,
} from '../domain/protocol';

const plaintextRegistry = new Map<string, DecryptedMessage>();
const opaqueToken = (byteLength: number): string =>
  Buffer.from(
    Array.from({ length: byteLength }, () => Math.floor(Math.random() * 256)),
  ).toString('base64url');

class MockDeviceIdentityProvider implements DeviceIdentityProvider {
  async generateDeviceIdentity(deviceId: string): Promise<DeviceIdentityMaterial> {
    // TODO(security): Replace this entire adapter with audited production crypto.
    return {
      identityPublicKey: `mock-id-pub-${deviceId}`,
      identityPrivateKeyRef: `secure-store://identity/${deviceId}`,
      signedPrekeyBundle: opaqueToken(32),
    };
  }
}

class MockDeviceAuthChallengeSigner implements DeviceAuthChallengeSigner {
  async generateAuthKeyMaterial(): Promise<DeviceAuthKeyMaterial> {
    return {
      publicKey: opaqueToken(32),
      privateKey: opaqueToken(32),
    };
  }

  async signChallenge(input: {
    challenge: string;
    keyMaterial: DeviceAuthKeyMaterial;
  }): Promise<string> {
    void input.challenge;
    return opaqueToken(64);
  }
}

class MockKeyBundleCodec implements KeyBundleCodec {
  decodeDirectoryBundle(json: Record<string, unknown>): PublicKeyBundle {
    return {
      userId: json.userId as string,
      deviceId: json.deviceId as string,
      handle: json.handle as string,
      identityPublicKey: json.identityPublicKey as string,
      signedPrekeyBundle: json.signedPrekeyBundle as string,
      platform: json.platform as PublicKeyBundle['platform'],
      isActive: json.isActive as boolean,
      updatedAt: json.updatedAt as string,
    };
  }
}

class MockCryptoEnvelopeCodec implements CryptoEnvelopeCodec {
  readonly defaultEnvelopeVersion = DEV_ENVELOPE_VERSION;
  readonly defaultAttachmentWrapAlgorithmHint = DEV_ATTACHMENT_WRAP_ALGORITHM_HINT;

  decodeApiEnvelope(json: Record<string, unknown>): CryptoEnvelope {
    return {
      version: (json.version as string | undefined) ?? DEV_ENVELOPE_VERSION,
      conversationId: json.conversationId as string,
      senderDeviceId: json.senderDeviceId as string,
      recipientUserId: (json.recipientUserId as string | undefined) ?? '',
      ciphertext: json.ciphertext as string,
      nonce: json.nonce as string,
      messageType: json.messageType as CryptoEnvelope['messageType'],
      expiresAt: (json.expiresAt as string | null | undefined) ?? null,
      attachment: this.decodeAttachmentReference(
        (json.attachment as Record<string, unknown> | undefined) ?? null,
      ),
    };
  }

  encodeApiEnvelope(envelope: CryptoEnvelope): Record<string, unknown> {
    return {
      version: envelope.version,
      conversationId: envelope.conversationId,
      senderDeviceId: envelope.senderDeviceId,
      recipientUserId: envelope.recipientUserId,
      ciphertext: envelope.ciphertext,
      nonce: envelope.nonce,
      messageType: envelope.messageType,
      expiresAt: envelope.expiresAt ?? null,
      attachment: this.encodeAttachmentReference(envelope.attachment),
    };
  }

  decodeAttachmentReference(
    json: Record<string, unknown> | null | undefined,
  ): EncryptedAttachmentReference | null {
    if (!json) {
      return null;
    }

    const encryption =
      (json.encryption as Record<string, unknown> | undefined) ?? {};
    return {
      attachmentId: json.attachmentId as string,
      storageKey: json.storageKey as string,
      contentType: json.contentType as string,
      sizeBytes: json.sizeBytes as number,
      sha256: json.sha256 as string,
      encryption: {
        encryptedKey: encryption.encryptedKey as string,
        nonce: encryption.nonce as string,
        algorithmHint:
          (encryption.algorithmHint as string | undefined) ??
          DEV_ATTACHMENT_WRAP_ALGORITHM_HINT,
      },
    };
  }

  encodeAttachmentReference(
    attachment: EncryptedAttachmentReference | null | undefined,
  ): Record<string, unknown> | null {
    if (!attachment) {
      return null;
    }

    return {
      attachmentId: attachment.attachmentId,
      storageKey: attachment.storageKey,
      contentType: attachment.contentType,
      sizeBytes: attachment.sizeBytes,
      sha256: attachment.sha256,
      encryption: {
        encryptedKey: attachment.encryption.encryptedKey,
        nonce: attachment.encryption.nonce,
        algorithmHint:
          attachment.encryption.algorithmHint ??
          DEV_ATTACHMENT_WRAP_ALGORITHM_HINT,
      },
    };
  }
}

class MockMessageCryptoEngine implements MessageCryptoEngine {
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
      nonce: `mock-nonce-${opaqueToken(12)}`,
      messageType: input.messageType,
      expiresAt: input.expiresAt ?? null,
      attachment: input.attachment ?? null,
    };
  }

  async decryptMessage(envelope: CryptoEnvelope): Promise<DecryptedMessage> {
    const parsed = plaintextRegistry.get(envelope.ciphertext);
    if (!parsed) {
      return {
        body:
          envelope.messageType === 'file'
            ? 'Encrypted attachment'
            : 'Encrypted message',
        messageType: envelope.messageType,
        expiresAt: envelope.expiresAt ?? null,
        attachment: envelope.attachment ?? null,
      };
    }

    return parsed;
  }

  async encryptAttachmentKey(
    contentKey: string,
    recipientBundle: PublicKeyBundle,
  ): Promise<AttachmentEncryptionMaterial> {
    void contentKey;
    void recipientBundle;
    return {
      encryptedKey: opaqueToken(32),
      nonce: `mock-attachment-nonce-${opaqueToken(12)}`,
      algorithmHint: DEV_ATTACHMENT_WRAP_ALGORITHM_HINT,
    };
  }
}

export class MockCryptoAdapter implements CryptoAdapter {
  readonly adapterId = 'mock-dev-adapter';
  readonly identity = new MockDeviceIdentityProvider();
  readonly deviceAuth = new MockDeviceAuthChallengeSigner();
  readonly keyBundles = new MockKeyBundleCodec();
  readonly envelopeCodec = new MockCryptoEnvelopeCodec();
  readonly messaging = new MockMessageCryptoEngine();
}
