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
    ).rejects.toThrow('Invalid device signature');

    await expect(
      service.verify({
        challengeId: challenge.challengeId,
        deviceId: registered.deviceId,
        signature: keyHelper.createProof({
          challenge: challenge.challenge,
          authPrivateKey: keyPair.authPrivateKey,
        }),
      }),
    ).rejects.toThrow('Challenge expired or invalid');
  });

  it('issues a refresh token on verify and rotates it on refresh', async () => {
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
      handle: 'rotator',
      displayName: 'Rotator',
      deviceName: 'VEIL Desktop',
      platform: 'windows',
      publicIdentityKey: 'pub-id',
      signedPrekeyBundle: 'prekey',
      authPublicKey: keyPair.authPublicKey,
      pushToken: undefined,
    });

    const challenge = await service.createChallenge({
      handle: 'rotator',
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

    expect(verified.refreshToken).toBeTruthy();
    expect(verified.refreshToken.length).toBeGreaterThan(32);

    const refreshed = await service.refresh(verified.refreshToken);
    expect(refreshed.accessToken).toBeTruthy();
    expect(refreshed.refreshToken).toBeTruthy();
    expect(refreshed.refreshToken).not.toBe(verified.refreshToken);

    // Presenting the old refresh token after rotation must fail.
    await expect(service.refresh(verified.refreshToken)).rejects.toThrow(
      'Refresh token invalid',
    );
  });

  it('rejects refresh against a revoked device', async () => {
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
      handle: 'revokeme',
      displayName: 'Revoke Me',
      deviceName: 'VEIL Desktop',
      platform: 'windows',
      publicIdentityKey: 'pub-id',
      signedPrekeyBundle: 'prekey',
      authPublicKey: keyPair.authPublicKey,
      pushToken: undefined,
    });

    const challenge = await service.createChallenge({
      handle: 'revokeme',
      deviceId: registered.deviceId,
    });
    const verified = await service.verify({
      challengeId: challenge.challengeId,
      deviceId: registered.deviceId,
      signature: keyHelper.createProof({
        challenge: challenge.challenge,
        authPrivateKey: keyPair.authPrivateKey,
      }),
    });

    const device = prisma.devices.find((d) => d.id === registered.deviceId)!;
    device.isActive = false;
    device.revokedAt = new Date();

    await expect(service.refresh(verified.refreshToken)).rejects.toThrow(
      'Device is not active',
    );
  });

  it('logout revokes the presented refresh token and blacklists jti', async () => {
    const prisma = new FakePrismaService();
    const store = new FakeEphemeralStoreService();
    const config = new FakeConfigService();
    const verifier = new Ed25519DeviceAuthVerifier();
    const keyHelper = new DeviceAuthTestHelper();
    const keyPair = keyHelper.createKeyPair();
    const jwt = new JwtService();
    const service = new AuthService(
      prisma as never,
      store as never,
      jwt,
      config as never,
      verifier,
    );

    const registered = await service.register({
      handle: 'logoutcase',
      displayName: 'Logout Case',
      deviceName: 'VEIL Desktop',
      platform: 'windows',
      publicIdentityKey: 'pub-id',
      signedPrekeyBundle: 'prekey',
      authPublicKey: keyPair.authPublicKey,
      pushToken: undefined,
    });

    const challenge = await service.createChallenge({
      handle: 'logoutcase',
      deviceId: registered.deviceId,
    });
    const verified = await service.verify({
      challengeId: challenge.challengeId,
      deviceId: registered.deviceId,
      signature: keyHelper.createProof({
        challenge: challenge.challenge,
        authPrivateKey: keyPair.authPrivateKey,
      }),
    });

    const decoded = jwt.decode(verified.accessToken) as {
      jti: string;
      exp: number;
    };
    expect(decoded.jti).toBeTruthy();

    const result = await service.logout(
      {
        userId: registered.userId,
        deviceId: registered.deviceId,
        jti: decoded.jti,
        exp: decoded.exp,
      },
      { refreshToken: verified.refreshToken },
    );
    expect(result.ok).toBe(true);

    await expect(service.refresh(verified.refreshToken)).rejects.toThrow(
      'Refresh token invalid',
    );

    const blacklisted = await store.getJson<unknown>(
      `auth:blacklist:${decoded.jti}`,
    );
    expect(blacklisted).not.toBeNull();
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
    ).rejects.toThrow('Challenge expired or invalid');

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
