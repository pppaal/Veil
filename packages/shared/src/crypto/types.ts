import type { DevicePlatform, MessageType } from '../domain/enums';

export interface PublicKeyBundle {
  userId: string;
  deviceId: string;
  handle: string;
  identityPublicKey: string;
  signedPrekeyBundle: string;
  platform: DevicePlatform;
  isActive: boolean;
  updatedAt: string;
}

export interface AttachmentUploadTicket {
  attachmentId: string;
  storageKey: string;
  uploadUrl: string;
  headers: Record<string, string>;
  contentType: string;
  sizeBytes: number;
  expiresAt: string;
}

export interface AttachmentDownloadTicket {
  attachmentId: string;
  downloadUrl: string;
  expiresAt: string;
}

export interface AttachmentEncryptionMaterial {
  encryptedKey: string;
  nonce: string;
  algorithmHint: string;
}

export interface EncryptedAttachmentReference {
  attachmentId: string;
  storageKey: string;
  contentType: string;
  sizeBytes: number;
  sha256: string;
  encryption: AttachmentEncryptionMaterial;
}

export interface CryptoEnvelope {
  version: string;
  conversationId: string;
  senderDeviceId: string;
  recipientUserId: string;
  ciphertext: string;
  nonce: string;
  messageType: MessageType;
  expiresAt?: string | null;
  attachment?: EncryptedAttachmentReference | null;
}

export interface PlaintextMessageInput {
  conversationId: string;
  senderDeviceId: string;
  recipientUserId: string;
  body: string;
  messageType: Exclude<MessageType, 'system'>;
  expiresAt?: string | null;
  attachment?: EncryptedAttachmentReference | null;
}

export interface DecryptedMessage {
  body: string;
  messageType: MessageType;
  expiresAt?: string | null;
  attachment?: EncryptedAttachmentReference | null;
}

export interface DeviceIdentityMaterial {
  identityPublicKey: string;
  identityPrivateKeyRef: string;
  signedPrekeyBundle: string;
}

export interface DeviceAuthKeyMaterial {
  publicKey: string;
  privateKey: string;
}

export interface DeviceIdentityProvider {
  generateDeviceIdentity(deviceId: string): Promise<DeviceIdentityMaterial>;
}

export interface DeviceAuthChallengeSigner {
  generateAuthKeyMaterial(): Promise<DeviceAuthKeyMaterial>;
  signChallenge(input: {
    challenge: string;
    keyMaterial: DeviceAuthKeyMaterial;
  }): Promise<string>;
}

export interface KeyBundleCodec {
  decodeDirectoryBundle(json: Record<string, unknown>): PublicKeyBundle;
}

export interface CryptoEnvelopeCodec {
  readonly defaultEnvelopeVersion: string;
  readonly defaultAttachmentWrapAlgorithmHint?: string;
  decodeApiEnvelope(json: Record<string, unknown>): CryptoEnvelope;
  encodeApiEnvelope(envelope: CryptoEnvelope): Record<string, unknown>;
  decodeAttachmentReference(
    json: Record<string, unknown> | null | undefined,
  ): EncryptedAttachmentReference | null;
  encodeAttachmentReference(
    attachment: EncryptedAttachmentReference | null | undefined,
  ): Record<string, unknown> | null;
}

export interface MessageCryptoEngine {
  encryptMessage(
    input: PlaintextMessageInput,
    recipientBundle: PublicKeyBundle,
  ): Promise<CryptoEnvelope>;
  decryptMessage(envelope: CryptoEnvelope): Promise<DecryptedMessage>;
  encryptAttachmentKey(
    contentKey: string,
    recipientBundle: PublicKeyBundle,
  ): Promise<AttachmentEncryptionMaterial>;
}

export interface CryptoAdapter {
  readonly adapterId: string;
  readonly identity: DeviceIdentityProvider;
  readonly deviceAuth: DeviceAuthChallengeSigner;
  readonly keyBundles: KeyBundleCodec;
  readonly envelopeCodec: CryptoEnvelopeCodec;
  readonly messaging: MessageCryptoEngine;
}
