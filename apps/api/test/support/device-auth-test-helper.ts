import {
  createPrivateKey,
  generateKeyPairSync,
  sign,
} from 'node:crypto';

import { ED25519_SPKI_PREFIX } from '../../src/modules/auth/device-auth-verifier';

export class DeviceAuthTestHelper {
  createKeyPair(): {
    authPublicKey: string;
    authPrivateKey: string;
  } {
    const { publicKey, privateKey } = generateKeyPairSync('ed25519');
    return {
      authPublicKey: publicKey
        .export({ format: 'der', type: 'spki' })
        .subarray(ED25519_SPKI_PREFIX.length)
        .toString('base64url'),
      authPrivateKey: privateKey.export({ format: 'der', type: 'pkcs8' }).toString('base64url'),
    };
  }

  createProof(params: {
    challenge: string;
    authPrivateKey: string;
  }): string {
    const privateKey = createPrivateKey({
      key: Buffer.from(params.authPrivateKey, 'base64url'),
      format: 'der',
      type: 'pkcs8',
    });
    return sign(null, Buffer.from(params.challenge, 'utf8'), privateKey).toString('base64url');
  }
}
