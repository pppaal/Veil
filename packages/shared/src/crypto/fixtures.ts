import type {
  AttachmentEncryptionMaterial,
  CryptoEnvelope,
  DeviceAuthKeyMaterial,
  DeviceIdentityMaterial,
  PublicKeyBundle,
  SessionBootstrapMaterial,
  SessionBootstrapRequest,
} from './types';

export interface CryptoInteropFixtureIdentityCase {
  deviceId: string;
  identity: DeviceIdentityMaterial;
  authKeyMaterial: DeviceAuthKeyMaterial;
}

export interface CryptoInteropFixtureBundleCase {
  ownerDeviceId: string;
  bundle: PublicKeyBundle;
}

export interface CryptoInteropFixtureSessionCase {
  request: SessionBootstrapRequest;
  result: SessionBootstrapMaterial;
  persistenceExpectation: {
    localDeviceId: string;
    remoteDeviceId: string;
    remoteIdentityFingerprint: string;
    sessionSchemaVersion: number;
  };
}

export interface CryptoInteropFixtureAttachmentCase {
  attachmentId: string;
  storageKey: string;
  contentType: string;
  sizeBytes: number;
  sha256: string;
  wrappedKey: AttachmentEncryptionMaterial;
}

export interface CryptoInteropFixtureMessageCase {
  envelope: CryptoEnvelope;
  decryptedBody: string;
}

export interface CryptoInteropFixture {
  fixtureId: string;
  adapterId: string;
  generatedAt: string;
  identity: CryptoInteropFixtureIdentityCase;
  recipientBundle: CryptoInteropFixtureBundleCase;
  session: CryptoInteropFixtureSessionCase;
  attachment: CryptoInteropFixtureAttachmentCase;
  message: CryptoInteropFixtureMessageCase;
}
