import { JwtService } from '@nestjs/jwt';
import { UnauthorizedException } from '@nestjs/common';

import { AuthService } from '../../src/modules/auth/auth.service';
import { Ed25519DeviceAuthVerifier } from '../../src/modules/auth/device-auth-verifier';
import { DeviceAuthTestHelper } from '../support/device-auth-test-helper';
import { FakePrismaService } from '../support/fake-prisma.service';
import { FakeConfigService, FakeEphemeralStoreService } from '../support/fake-services';

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

  it('rejects verification when the device is no longer active', async () => {
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
      handle: 'selene',
      displayName: 'Selene',
      deviceName: 'iPhone',
      platform: 'ios',
      publicIdentityKey: 'pub-id',
      signedPrekeyBundle: 'prekey',
      authPublicKey: keyPair.authPublicKey,
      pushToken: undefined,
    });

    const challenge = await service.createChallenge({
      handle: 'selene',
      deviceId: registered.deviceId,
    });
    const signature = keyHelper.createProof({
      challenge: challenge.challenge,
      authPrivateKey: keyPair.authPrivateKey,
    });

    prisma.devices[0]!.isActive = false;

    await expect(
      service.verify({
        challengeId: challenge.challengeId,
        deviceId: registered.deviceId,
        signature,
      }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('burns the challenge after a failed verification attempt', async () => {
    const prisma = new FakePrismaService();
    const store = new FakeEphemeralStoreService();
    const config = new FakeConfigService();
    const verifier = new Ed25519DeviceAuthVerifier();
    const keyHelper = new DeviceAuthTestHelper();
    const keyPair = keyHelper.createKeyPair();
    const wrongKeyPair = keyHelper.createKeyPair();
    const service = new AuthService(
      prisma as never,
      store as never,
      new JwtService(),
      config as never,
      verifier,
    );

    const registered = await service.register({
      handle: 'burnonce',
      displayName: 'Burn Once',
      deviceName: 'VEIL Desktop',
      platform: 'windows',
      publicIdentityKey: 'pub-id',
      signedPrekeyBundle: 'prekey',
      authPublicKey: keyPair.authPublicKey,
      pushToken: undefined,
    });

    const challenge = await service.createChallenge({
      handle: 'burnonce',
      deviceId: registered.deviceId,
    });

    await expect(
      service.verify({
        challengeId: challenge.challengeId,
        deviceId: registered.deviceId,
        signature: keyHelper.createProof({
          challenge: challenge.challenge,
          authPrivateKey: wrongKeyPair.authPrivateKey,
        }),
      }),
    ).rejects.toBeInstanceOf(UnauthorizedException);

    await expect(
      service.verify({
        challengeId: challenge.challengeId,
        deviceId: registered.deviceId,
        signature: keyHelper.createProof({
          challenge: challenge.challenge,
          authPrivateKey: keyPair.authPrivateKey,
        }),
      }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('invalidates the previous device challenge when a new one is issued', async () => {
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
      handle: 'supersede',
      displayName: 'Supersede',
      deviceName: 'VEIL Desktop',
      platform: 'windows',
      publicIdentityKey: 'pub-id',
      signedPrekeyBundle: 'prekey',
      authPublicKey: keyPair.authPublicKey,
      pushToken: undefined,
    });

    const first = await service.createChallenge({
      handle: 'supersede',
      deviceId: registered.deviceId,
    });
    const second = await service.createChallenge({
      handle: 'supersede',
      deviceId: registered.deviceId,
    });

    await expect(
      service.verify({
        challengeId: first.challengeId,
        deviceId: registered.deviceId,
        signature: keyHelper.createProof({
          challenge: first.challenge,
          authPrivateKey: keyPair.authPrivateKey,
        }),
      }),
    ).rejects.toBeInstanceOf(UnauthorizedException);

    await expect(
      service.verify({
        challengeId: second.challengeId,
        deviceId: registered.deviceId,
        signature: keyHelper.createProof({
          challenge: second.challenge,
          authPrivateKey: keyPair.authPrivateKey,
        }),
      }),
    ).resolves.toMatchObject({
      deviceId: registered.deviceId,
      userId: registered.userId,
    });
  });
});
