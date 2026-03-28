import { createHash } from 'node:crypto';

import { Inject, Injectable } from '@nestjs/common';

import { AppConfigService } from '../../common/config/app-config.service';

export interface DeviceAuthVerifier {
  verifyChallengeResponse(params: {
    challenge: string;
    proof: string;
    authPublicKey: string;
    deviceId: string;
  }): Promise<boolean>;
}

export const DEVICE_AUTH_VERIFIER = Symbol('DEVICE_AUTH_VERIFIER');

const buildMockProof = (
  challenge: string,
  authPublicKey: string,
  deviceId: string,
  sharedSecret: string,
): string =>
  createHash('sha256')
    .update(`${challenge}:${authPublicKey}:${deviceId}:${sharedSecret}`)
    .digest('base64url');

@Injectable()
export class MockDeviceAuthVerifier implements DeviceAuthVerifier {
  constructor(@Inject(AppConfigService) private readonly config: AppConfigService) {}

  async verifyChallengeResponse(params: {
    challenge: string;
    proof: string;
    authPublicKey: string;
    deviceId: string;
  }): Promise<boolean> {
    const expected = buildMockProof(
      params.challenge,
      params.authPublicKey,
      params.deviceId,
      this.config.mockAuthSharedSecret,
    );
    return expected === params.proof;
  }

  createProofForDev(params: {
    challenge: string;
    authPublicKey: string;
    deviceId: string;
  }): string {
    return buildMockProof(
      params.challenge,
      params.authPublicKey,
      params.deviceId,
      this.config.mockAuthSharedSecret,
    );
  }
}
