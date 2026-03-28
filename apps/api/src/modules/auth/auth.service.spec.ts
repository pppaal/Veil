import { JwtService } from '@nestjs/jwt';

import { AuthService } from './auth.service';
import { MockDeviceAuthVerifier } from './device-auth-verifier';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import { FakeConfigService, FakeEphemeralStoreService } from '../../../test/support/fake-services';

describe('AuthService', () => {
  it('registers a device-bound account and verifies a challenge', async () => {
    const prisma = new FakePrismaService();
    const store = new FakeEphemeralStoreService();
    const config = new FakeConfigService();
    const verifier = new MockDeviceAuthVerifier(config as never);
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
      deviceName: 'Pixel',
      platform: 'android',
      publicIdentityKey: 'pub-id',
      signedPrekeyBundle: 'prekey',
      authPublicKey: 'auth-pub',
      pushToken: undefined,
    });

    expect(registered.handle).toBe('icarus');
    expect(prisma.users).toHaveLength(1);
    expect(prisma.devices).toHaveLength(1);

    const challenge = await service.createChallenge({
      handle: 'icarus',
      deviceId: registered.deviceId,
    });
    const signature = verifier.createProofForDev({
      challenge: challenge.challenge,
      authPublicKey: 'auth-pub',
      deviceId: registered.deviceId,
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
