import { createPublicKey, verify } from 'node:crypto';
import { Injectable } from '@nestjs/common';

export interface DeviceAuthVerifier {
  verifyChallengeResponse(params: {
    challenge: string;
    proof: string;
    authPublicKey: string;
    deviceId: string;
  }): Promise<boolean>;
}

export const DEVICE_AUTH_VERIFIER = Symbol('DEVICE_AUTH_VERIFIER');

export const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');

@Injectable()
export class Ed25519DeviceAuthVerifier implements DeviceAuthVerifier {
  async verifyChallengeResponse(params: {
    challenge: string;
    proof: string;
    authPublicKey: string;
    deviceId: string;
  }): Promise<boolean> {
    void params.deviceId;

    try {
      const publicKey = createPublicKey({
        key: Buffer.concat([
          ED25519_SPKI_PREFIX,
          Buffer.from(params.authPublicKey, 'base64url'),
        ]),
        format: 'der',
        type: 'spki',
      });
      return verify(
        null,
        Buffer.from(params.challenge, 'utf8'),
        publicKey,
        Buffer.from(params.proof, 'base64url'),
      );
    } catch {
      return false;
    }
  }
}
