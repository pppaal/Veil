import { JwtService } from '@nestjs/jwt';

import { AuthService } from './auth.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import { DeviceAuthTestHelper } from '../../../test/support/device-auth-test-helper';
import { FakeConfigService, FakeEphemeralStoreService } from '../../../test/support/fake-services';
import { Ed25519DeviceAuthVerifier } from './device-auth-verifier';

describe('AuthService', () => {
  it('registers a device-bound account and verifies a challenge', async () => {
    const prisma = new FakePrismaService();
    const store = new FakeEphemeralStoreService();
    const config = new FakeConfigService();
    const verifier = new Ed25519DeviceAuthVerifier();
    const keyHelper = new DeviceAuthTestHelper();
    const keyPair = keyHelper.createKeyPair();
    const service = new AuthService(
      prisma as never,
      store as never,
      new JwtService(),
      config as never,
      verifier,
    );

    const registered = await service.register({
      handle: 'icarus',
      displayName: 'Icarus',
      deviceName: 'VEIL Desktop',
      platform: 'windows',
      publicIdentityKey: 'pub-id',
      signedPrekeyBundle: 'prekey',
      authPublicKey: keyPair.authPublicKey,
      pushToken: undefined,
    });

    expect(registered.handle).toBe('icarus');
    expect(prisma.users).toHaveLength(1);
    expect(prisma.devices).toHaveLength(1);

    const challenge = await service.createChallenge({
      handle: 'icarus',
      deviceId: registered.deviceId,
    });
    const signature = keyHelper.createProof({
      challenge: challenge.challenge,
      authPrivateKey: keyPair.authPrivateKey,
    });

    const verified = await service.verify({
      challengeId: challenge.challengeId,
      deviceId: registered.deviceId,
      signature,
    });

    expect(verified.userId).toBe(registered.userId);
    expect(verified.deviceId).toBe(registered.deviceId);
    expect(verified.accessToken).toBeTruthy();
  });
});
