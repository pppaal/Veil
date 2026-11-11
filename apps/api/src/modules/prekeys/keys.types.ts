import type { OneTimePrekeyUpload } from '@veil/contracts';

// Wire types for the authenticated /v1/keys directory. They live here until
// both clients switch over and the types move into @veil/contracts.

/**
 * Which devices of the target get a one-time prekey claimed:
 * - active: only the user's active device (the default);
 * - all: every trusted device, for per-device sessions;
 * - none: identity and signed prekeys only, nothing consumed.
 */
export const KEY_CLAIM_MODES = ['active', 'all', 'none'] as const;
export type KeyClaimMode = (typeof KEY_CLAIM_MODES)[number];

export interface DirectoryDeviceKeys {
  deviceId: string;
  identityPublicKey: string;
  signedPrekeyBundle: string;
  /** True for the device that represents the user right now (user.activeDeviceId). */
  isActive: boolean;
  /**
   * Null when the mode did not select this device, the pool is empty, or a
   * claim budget is spent; the initiator then runs signed-prekey-only X3DH.
   */
  oneTimePrekey: OneTimePrekeyUpload | null;
}

export interface KeyDirectoryResponse {
  user: {
    id: string;
    handle: string;
    activeDeviceId: string;
  };
  /** Trusted, non-revoked devices, most recently trusted first. */
  devices: DirectoryDeviceKeys[];
}

export interface RotateSignedPrekeyRequest {
  signedPrekeyBundle: string;
}

export interface RotateSignedPrekeyResponse {
  deviceId: string;
  spkId: number;
}
