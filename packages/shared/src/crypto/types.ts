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

export interface AttachmentUploadTicket {
  attachmentId: string;
  storageKey: string;
  uploadUrl: string;
  headers: Record<string, string>;
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
  authPublicKey: string;
  authPrivateKeyRef: string;
  signedPrekeyBundle: string;
}

export interface CryptoEngine {
  readonly adapterId: string;
  generateDeviceIdentity(deviceId: string): Promise<DeviceIdentityMaterial>;
  encryptMessage(input: PlaintextMessageInput, recipientBundle: PublicKeyBundle): Promise<CryptoEnvelope>;
  decryptMessage(envelope: CryptoEnvelope): Promise<DecryptedMessage>;
  encryptAttachmentKey(contentKey: string, recipientBundle: PublicKeyBundle): Promise<AttachmentEncryptionMaterial>;
}
