import { JwtService } from '@nestjs/jwt';
import { UnauthorizedException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHash, randomUUID } from 'node:crypto';

import { AuthService } from './auth.service';
import { EphemeralStoreService } from '../../common/ephemeral-store.service';
import { isAccessTokenRevoked } from '../../common/access-token-revocation';
import { RetiredHandlesService } from '../handles/retired-handles.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import { DeviceAuthTestHelper } from '../../../test/support/device-auth-test-helper';
import { FakeConfigService, FakeEphemeralStoreService } from '../../../test/support/fake-services';
import { Ed25519DeviceAuthVerifier } from './device-auth-verifier';

type KeyPair = ReturnType<DeviceAuthTestHelper['createKeyPair']>;

const registration = (handle: string, keyPair: KeyPair, pushToken?: string) => ({
  handle,
  displayName: handle,
  deviceName: 'VEIL Desktop',
  platform: 'windows' as const,
  publicIdentityKey: 'pub-id',
  signedPrekeyBundle: 'prekey',
  authPublicKey: keyPair.authPublicKey,
  pushToken,
});

const DAY_MS = 24 * 60 * 60 * 1000;

function setup(
  options: {
    prisma?: FakePrismaService;
    config?: FakeConfigService;
    store?: FakeEphemeralStoreService | EphemeralStoreService;
  } = {},
) {
  const prisma = options.prisma ?? new FakePrismaService();
  const store = options.store ?? new FakeEphemeralStoreService();
  const jwt = new JwtService();
  const keyHelper = new DeviceAuthTestHelper();
  const config = options.config ?? new FakeConfigService();
  const retiredHandles = new RetiredHandlesService(prisma as never, config as never);
  const service = new AuthService(
    prisma as never,
    store as never,
    jwt,
    config as never,
    new Ed25519DeviceAuthVerifier(),
    { disconnectDevice: () => 0 } as never,
    retiredHandles,
  );

  const signChallenge = (challenge: { challenge: string }, keyPair: KeyPair): string =>
    keyHelper.createProof({
      challenge: challenge.challenge,
      authPrivateKey: keyPair.authPrivateKey,
    });

  const login = async (handle: string, deviceId: string, keyPair: KeyPair) => {
    const challenge = await service.createChallenge({ handle, deviceId });
    return service.verify({
      challengeId: challenge.challengeId,
      deviceId,
      signature: signChallenge(challenge, keyPair),
    });
  };

  const registerAndLogin = async (handle: string) => {
    const keyPair = keyHelper.createKeyPair();
    const registered = await service.register(registration(handle, keyPair));
    const verified = await login(handle, registered.deviceId, keyPair);
    return { keyPair, registered, verified };
  };

  return {
    prisma,
    store,
    jwt,
    keyHelper,
    service,
    retiredHandles,
    signChallenge,
    login,
    registerAndLogin,
  };
}

describe('AuthService', () => {
  describe('register', () => {
    it('registers a device-bound account and verifies a challenge', async () => {
      const { prisma, registerAndLogin } = setup();

      const { registered, verified } = await registerAndLogin('icarus');

      expect(registered.handle).toBe('icarus');
      expect(prisma.users).toHaveLength(1);
      expect(prisma.devices).toHaveLength(1);
      expect(verified.userId).toBe(registered.userId);
      expect(verified.deviceId).toBe(registered.deviceId);
      expect(verified.accessToken).toBeTruthy();
    });

    it('register ignores displayName', async () => {
      const { prisma, service, keyHelper } = setup();

      const registered = await service.register({
        ...registration('icarus', keyHelper.createKeyPair()),
        displayName: 'Icarus the Bold',
      });

      expect(registered).not.toHaveProperty('displayName');
      expect(JSON.stringify(prisma.users)).not.toContain('Icarus the Bold');
      expect(prisma.users[0]).not.toHaveProperty('displayName');
    });

    it('quarantined handle register 409', async () => {
      const { prisma, service, retiredHandles, keyHelper } = setup();
      const retiredAt = new Date();
      await retiredHandles.retire(prisma as never, 'Phoenix', retiredAt);

      await expect(
        service.register(registration('phoenix', keyHelper.createKeyPair())),
      ).rejects.toMatchObject({ status: 409, response: { code: 'handle_taken' } });
      expect(prisma.users).toHaveLength(0);
      // The quarantine table keeps a digest, never the handle itself.
      expect(JSON.stringify(prisma.retiredHandles).toLowerCase()).not.toContain('phoenix');

      // Once the quarantine has lapsed the handle can be registered again.
      prisma.retiredHandles[0]!.retiredUntil = new Date(Date.now() - 1000);
      await expect(
        service.register(registration('phoenix', keyHelper.createKeyPair())),
      ).resolves.toMatchObject({ handle: 'phoenix' });
    });

    it('stores the device last-seen time as the UTC day only', async () => {
      const { prisma, registerAndLogin } = setup();

      await registerAndLogin('daybound');

      const lastSeenAt = prisma.devices[0]!.lastSeenAt;
      expect(lastSeenAt.toISOString()).toMatch(/T00:00:00\.000Z$/);
    });

    it('concurrent register maps P2002 to handle_taken', async () => {
      // Both registrations pass the handle lookup before either insert lands;
      // the unique index then rejects the second insert.
      const prisma = new FakePrismaService();
      const lookupsInFlight: Array<() => void> = [];
      const findUser = prisma.user.findUnique;
      prisma.user.findUnique = async (args: unknown) => {
        const result = await findUser(args);
        await new Promise<void>((release) => {
          lookupsInFlight.push(release);
          if (lookupsInFlight.length === 2) {
            lookupsInFlight.forEach((resume) => resume());
          }
        });
        return result;
      };
      const createUser = prisma.user.create;
      prisma.user.create = async (args: { data: { handle: string } }) => {
        if (prisma.users.some((user) => user.handle === args.data.handle)) {
          throw new Prisma.PrismaClientKnownRequestError('Unique constraint failed', {
            code: 'P2002',
            clientVersion: 'test',
            meta: { target: ['handle'] },
          });
        }
        return createUser(args);
      };
      const { service, keyHelper } = setup({ prisma });

      const results = await Promise.allSettled([
        service.register(registration('racer', keyHelper.createKeyPair())),
        service.register(registration('racer', keyHelper.createKeyPair())),
      ]);

      expect(results.map((result) => result.status).sort()).toEqual(['fulfilled', 'rejected']);
      const rejected = results.find(
        (result) => result.status === 'rejected',
      ) as PromiseRejectedResult;
      expect(rejected.reason.getStatus()).toBe(409);
      expect(rejected.reason.getResponse()).toMatchObject({ code: 'handle_taken' });
      expect(prisma.users).toHaveLength(1);
    });

    it('rejects a private UnifiedPush endpoint with validation_failed', async () => {
      const config = Object.assign(new FakeConfigService(), {
        pushProvider: 'unifiedpush',
        unifiedPushAllowedHosts: [],
        isProduction: false,
      });
      const { service, prisma, keyHelper } = setup({ config });

      await expect(
        service.register(
          registration('pushy', keyHelper.createKeyPair(), 'https://169.254.169.254/latest'),
        ),
      ).rejects.toMatchObject({ response: { code: 'validation_failed' } });
      expect(prisma.users).toHaveLength(0);
    });
  });

  describe('challenges', () => {
    // A public route: an unknown handle must answer exactly like a known
    // handle with a device it does not have, or it would list handles.
    it('answers an unknown handle exactly like a wrong device for a known one', async () => {
      const { service, keyHelper } = setup();
      await service.register(registration('known', keyHelper.createKeyPair()));
      const refusal = (handle: string) =>
        service.createChallenge({ handle, deviceId: randomUUID() }).catch((error) => ({
          status: error.getStatus(),
          response: error.getResponse(),
        }));

      const unknown = await refusal('nobody');
      expect(unknown).toEqual({
        status: 404,
        response: { code: 'active_device_not_found', message: expect.any(String) },
      });
      expect(await refusal('known')).toEqual(unknown);
    });

    it('rejects verification when the device is no longer active', async () => {
      const { prisma, service, keyHelper, signChallenge } = setup();
      const keyPair = keyHelper.createKeyPair();
      const registered = await service.register(registration('selene', keyPair));
      const challenge = await service.createChallenge({
        handle: 'selene',
        deviceId: registered.deviceId,
      });

      prisma.devices[0]!.isActive = false;

      await expect(
        service.verify({
          challengeId: challenge.challengeId,
          deviceId: registered.deviceId,
          signature: signChallenge(challenge, keyPair),
        }),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    });

    it('burns the challenge after a failed verification attempt', async () => {
      const { service, keyHelper, signChallenge } = setup();
      const keyPair = keyHelper.createKeyPair();
      const registered = await service.register(registration('burnonce', keyPair));
      const challenge = await service.createChallenge({
        handle: 'burnonce',
        deviceId: registered.deviceId,
      });

      await expect(
        service.verify({
          challengeId: challenge.challengeId,
          deviceId: registered.deviceId,
          signature: signChallenge(challenge, keyHelper.createKeyPair()),
        }),
      ).rejects.toThrow('Invalid device signature');

      await expect(
        service.verify({
          challengeId: challenge.challengeId,
          deviceId: registered.deviceId,
          signature: signChallenge(challenge, keyPair),
        }),
      ).rejects.toThrow('Challenge expired or invalid');
    });

    it('rejects a challenge presented for another device', async () => {
      const { service, keyHelper, signChallenge } = setup();
      const keyPair = keyHelper.createKeyPair();
      const owner = await service.register(registration('owner', keyPair));
      const other = await service.register(registration('other', keyHelper.createKeyPair()));
      const challenge = await service.createChallenge({
        handle: 'owner',
        deviceId: owner.deviceId,
      });

      await expect(
        service.verify({
          challengeId: challenge.challengeId,
          deviceId: other.deviceId,
          signature: signChallenge(challenge, keyPair),
        }),
      ).rejects.toMatchObject({ response: { code: 'challenge_invalid' } });
    });

    it('two outstanding challenges both verify once', async () => {
      const { service, keyHelper, signChallenge } = setup();
      const keyPair = keyHelper.createKeyPair();
      const registered = await service.register(registration('twin', keyPair));
      const first = await service.createChallenge({
        handle: 'twin',
        deviceId: registered.deviceId,
      });
      const second = await service.createChallenge({
        handle: 'twin',
        deviceId: registered.deviceId,
      });

      for (const challenge of [first, second]) {
        await expect(
          service.verify({
            challengeId: challenge.challengeId,
            deviceId: registered.deviceId,
            signature: signChallenge(challenge, keyPair),
          }),
        ).resolves.toMatchObject({ deviceId: registered.deviceId });
      }

      for (const challenge of [first, second]) {
        await expect(
          service.verify({
            challengeId: challenge.challengeId,
            deviceId: registered.deviceId,
            signature: signChallenge(challenge, keyPair),
          }),
        ).rejects.toMatchObject({ response: { code: 'challenge_invalid' } });
      }
    });

    it('a fourth outstanding challenge evicts only the oldest', async () => {
      const { service, keyHelper, signChallenge } = setup();
      const keyPair = keyHelper.createKeyPair();
      const registered = await service.register(registration('quartet', keyPair));
      const challenges = [];
      for (let i = 0; i < 4; i += 1) {
        challenges.push(
          await service.createChallenge({ handle: 'quartet', deviceId: registered.deviceId }),
        );
      }
      const [oldest, ...newest] = challenges;

      await expect(
        service.verify({
          challengeId: oldest!.challengeId,
          deviceId: registered.deviceId,
          signature: signChallenge(oldest!, keyPair),
        }),
      ).rejects.toMatchObject({ response: { code: 'challenge_invalid' } });
      for (const challenge of newest) {
        await expect(
          service.verify({
            challengeId: challenge.challengeId,
            deviceId: registered.deviceId,
            signature: signChallenge(challenge, keyPair),
          }),
        ).resolves.toMatchObject({ deviceId: registered.deviceId });
      }
    });
  });

  describe('refresh tokens', () => {
    it('issues a refresh token on verify and rotates it on refresh', async () => {
      const { service, registerAndLogin } = setup();
      const { verified } = await registerAndLogin('rotator');

      expect(verified.refreshToken.length).toBeGreaterThan(32);

      const refreshed = await service.refresh(verified.refreshToken);
      expect(refreshed.accessToken).toBeTruthy();
      expect(refreshed.refreshToken).not.toBe(verified.refreshToken);
      await expect(service.refresh(refreshed.refreshToken)).resolves.toMatchObject({
        accessToken: expect.any(String),
      });
    });

    it('stores only the SHA-256 of refresh tokens', async () => {
      const { store, registerAndLogin } = setup();
      const writes = jest.spyOn(store, 'setJson');
      const { verified } = await registerAndLogin('hashed');

      expect(writes).toHaveBeenCalled();
      for (const [key, value] of writes.mock.calls) {
        expect(key).not.toContain(verified.refreshToken);
        expect(JSON.stringify(value)).not.toContain(verified.refreshToken);
      }
    });

    it('replaying a rotated refresh token revokes the family', async () => {
      const { service, registerAndLogin, login } = setup();
      const { verified, registered, keyPair } = await registerAndLogin('replayed');
      const otherSession = await login('replayed', registered.deviceId, keyPair);
      const rotated = await service.refresh(verified.refreshToken);

      await expect(service.refresh(verified.refreshToken)).rejects.toMatchObject({
        status: 401,
        response: { code: 'refresh_token_invalid' },
      });
      // The newest token of the replayed family is dead too...
      await expect(service.refresh(rotated.refreshToken)).rejects.toMatchObject({
        response: { code: 'refresh_token_invalid' },
      });
      // ...but an independent family of the same device survives.
      await expect(service.refresh(otherSession.refreshToken)).resolves.toMatchObject({
        refreshToken: expect.any(String),
      });
    });

    it('detects a replayed token however many rotations ago it was superseded', async () => {
      const { service, registerAndLogin } = setup();
      const { verified } = await registerAndLogin('longlived');
      let { refreshToken } = verified;
      for (let i = 0; i < 12; i += 1) {
        ({ refreshToken } = await service.refresh(refreshToken));
      }

      await expect(service.refresh(verified.refreshToken)).rejects.toMatchObject({
        response: { code: 'refresh_token_invalid' },
      });
      await expect(service.refresh(refreshToken)).rejects.toMatchObject({
        response: { code: 'refresh_token_invalid' },
      });
    });

    it('rotates a token issued before tokens carried their family, and still catches its replay', async () => {
      // The mobile app cannot log in again without its refresh token, so a
      // pre-upgrade token must keep working once, and its replay must still
      // revoke the family.
      const { service, store, registerAndLogin } = setup();
      const { registered } = await registerAndLogin('legacytoken');
      const [familyId] = (await store.getJson<string[]>(
        `auth:refresh-families:${registered.deviceId}`,
      ))!;
      const legacy = 'a'.repeat(64);
      const legacyHash = createHash('sha256').update(legacy).digest('hex');
      await store.setJson(
        `auth:refresh:${legacyHash}`,
        { userId: registered.userId, deviceId: registered.deviceId, familyId },
        60,
      );
      await store.setJson(
        `auth:refresh-family:${familyId}`,
        { deviceId: registered.deviceId, tokenHash: legacyHash },
        60,
      );

      const rotated = await service.refresh(legacy);
      expect(rotated.refreshToken.startsWith(`${familyId}.`)).toBe(true);

      await expect(service.refresh(legacy)).rejects.toMatchObject({
        response: { code: 'refresh_token_invalid' },
      });
      await expect(service.refresh(rotated.refreshToken)).rejects.toMatchObject({
        response: { code: 'refresh_token_invalid' },
      });
    });

    it('rejects refresh against a revoked device', async () => {
      const { prisma, service, registerAndLogin } = setup();
      const { verified, registered } = await registerAndLogin('revokeme');

      const device = prisma.devices.find((d) => d.id === registered.deviceId)!;
      device.isActive = false;
      device.revokedAt = new Date();

      await expect(service.refresh(verified.refreshToken)).rejects.toThrow('Device is not active');
    });

    it('revokes the oldest family once a device exceeds its family window', async () => {
      const { service, registerAndLogin, login } = setup();
      const { verified: oldest, registered, keyPair } = await registerAndLogin('manylogins');
      const later = [];
      for (let i = 0; i < 5; i += 1) {
        later.push(await login('manylogins', registered.deviceId, keyPair));
      }

      await expect(service.refresh(oldest.refreshToken)).rejects.toMatchObject({
        response: { code: 'refresh_token_invalid' },
      });
      await expect(service.refresh(later[0]!.refreshToken)).resolves.toBeDefined();
    });

    it('keeps a family in active use when later logins overflow the window', async () => {
      const { service, registerAndLogin, login } = setup();
      const { verified: active, registered, keyPair } = await registerAndLogin('busydevice');
      const abandoned = await login('busydevice', registered.deviceId, keyPair);
      for (let i = 0; i < 3; i += 1) {
        await login('busydevice', registered.deviceId, keyPair);
      }
      const rotated = await service.refresh(active.refreshToken);

      await login('busydevice', registered.deviceId, keyPair);

      await expect(service.refresh(rotated.refreshToken)).resolves.toBeDefined();
      await expect(service.refresh(abandoned.refreshToken)).rejects.toMatchObject({
        response: { code: 'refresh_token_invalid' },
      });
    });

    it('refuses a family that the device index no longer lists', async () => {
      const { service, store, registerAndLogin } = setup();
      const { verified, registered } = await registerAndLogin('unlisted');
      // What a lost read-modify-write of the index (a concurrent login) leaves.
      await store.setJson(`auth:refresh-families:${registered.deviceId}`, [], 60);

      await expect(service.refresh(verified.refreshToken)).rejects.toMatchObject({
        response: { code: 'refresh_token_invalid' },
      });
    });
  });

  // Irreversible requests (account deletion, revoking the calling or last
  // device) need the device's signature over a fresh challenge, not only its
  // bearer token.
  describe('verifyDeviceStepUp', () => {
    const production = () => Object.assign(new FakeConfigService(), { isProduction: true });

    const signedStepUp = async (
      context: ReturnType<typeof setup>,
      account: Awaited<ReturnType<ReturnType<typeof setup>['registerAndLogin']>>,
      purpose: string,
      authPrivateKey = account.keyPair.authPrivateKey,
    ) => {
      const challenge = await context.service.createChallenge({
        handle: account.registered.handle,
        deviceId: account.registered.deviceId,
      });
      return {
        challengeId: challenge.challengeId,
        signature: context.keyHelper.createProof({
          challenge: `${purpose}:${challenge.challengeId}:${challenge.challenge}`,
          authPrivateKey,
        }),
      };
    };

    it('accepts a fresh challenge signed by the device for this purpose, once', async () => {
      const context = setup({ config: production() });
      const account = await context.registerAndLogin('stepup');
      const proof = await signedStepUp(context, account, 'account-delete');

      await expect(
        context.service.verifyDeviceStepUp(account.registered.deviceId, 'account-delete', proof),
      ).resolves.toBeUndefined();
      await expect(
        context.service.verifyDeviceStepUp(account.registered.deviceId, 'account-delete', proof),
      ).rejects.toMatchObject({ response: { code: 'challenge_invalid' } });
    });

    it('refuses a missing proof, another key, another purpose and another device', async () => {
      const context = setup({ config: production() });
      const account = await context.registerAndLogin('stepup');
      const other = await context.registerAndLogin('bystander');
      const deviceId = account.registered.deviceId;
      const codeOf = (promise: Promise<unknown>) =>
        promise.then(
          () => 'resolved',
          (error) => (error as { response?: { code?: string } }).response?.code,
        );

      expect(await codeOf(context.service.verifyDeviceStepUp(deviceId, 'account-delete', {}))).toBe(
        'challenge_invalid',
      );
      const byOtherKey = await signedStepUp(
        context,
        account,
        'account-delete',
        other.keyPair.authPrivateKey,
      );
      expect(
        await codeOf(context.service.verifyDeviceStepUp(deviceId, 'account-delete', byOtherKey)),
      ).toBe('invalid_device_signature');
      const forRevoke = await signedStepUp(context, account, `device-revoke:${deviceId}`);
      expect(
        await codeOf(context.service.verifyDeviceStepUp(deviceId, 'account-delete', forRevoke)),
      ).toBe('invalid_device_signature');
      const othersChallenge = await signedStepUp(context, other, 'account-delete');
      expect(
        await codeOf(
          context.service.verifyDeviceStepUp(deviceId, 'account-delete', othersChallenge),
        ),
      ).toBe('challenge_invalid');
    });

    it('requires the proof on a development relay too', async () => {
      const context = setup();
      const account = await context.registerAndLogin('stepup');
      const other = await context.registerAndLogin('bystander');
      const deviceId = account.registered.deviceId;

      for (const missing of [undefined, {}, { challengeId: randomUUID() }, { signature: 'sig' }]) {
        await expect(
          context.service.verifyDeviceStepUp(deviceId, 'account-delete', missing),
        ).rejects.toMatchObject({ response: { code: 'challenge_invalid' } });
      }
      await expect(
        context.service.verifyDeviceStepUp(
          deviceId,
          'account-delete',
          await signedStepUp(context, account, 'account-delete'),
        ),
      ).resolves.toBeUndefined();
      const byOtherKey = await signedStepUp(
        context,
        account,
        'account-delete',
        other.keyPair.authPrivateKey,
      );
      await expect(
        context.service.verifyDeviceStepUp(deviceId, 'account-delete', byOtherKey),
      ).rejects.toMatchObject({ response: { code: 'invalid_device_signature' } });
    });
  });

  describe('logout', () => {
    it('logout without body revokes all device refresh tokens', async () => {
      const { service, store, jwt, registerAndLogin, login } = setup();
      const { verified, registered, keyPair } = await registerAndLogin('logoutcase');
      const secondSession = await login('logoutcase', registered.deviceId, keyPair);
      const bystander = await registerAndLogin('bystander');
      const decoded = jwt.decode(verified.accessToken) as { jti: string; exp: number };

      await expect(
        service.logout({
          userId: registered.userId,
          deviceId: registered.deviceId,
          jti: decoded.jti,
          exp: decoded.exp,
        }),
      ).resolves.toEqual({ ok: true });

      for (const token of [verified.refreshToken, secondSession.refreshToken]) {
        await expect(service.refresh(token)).rejects.toMatchObject({
          response: { code: 'refresh_token_invalid' },
        });
      }
      await expect(service.refresh(bystander.verified.refreshToken)).resolves.toBeDefined();
      await expect(store.getJson(`auth:blacklist:${decoded.jti}`)).resolves.not.toBeNull();
    });

    // The device's other sessions hold access tokens of their own; logout
    // must end those too, not only the token that called it.
    it("revokes the access tokens of every session of the device, and only that device's", async () => {
      const { service, store, jwt, registerAndLogin, login } = setup();
      const { verified, registered, keyPair } = await registerAndLogin('logoutall');
      const secondSession = await login('logoutall', registered.deviceId, keyPair);
      const bystander = await registerAndLogin('bystander');
      const claims = (accessToken: string) =>
        jwt.decode(accessToken) as { jti: string; exp: number; sid: string };
      expect(claims(verified.accessToken).sid).toBe(verified.refreshToken.split('.')[0]);
      for (const token of [verified, secondSession, bystander.verified]) {
        await expect(isAccessTokenRevoked(store, claims(token.accessToken))).resolves.toBe(false);
      }

      const { jti, exp } = claims(verified.accessToken);
      await service.logout({ userId: registered.userId, deviceId: registered.deviceId, jti, exp });

      await expect(isAccessTokenRevoked(store, claims(verified.accessToken))).resolves.toBe(true);
      await expect(isAccessTokenRevoked(store, claims(secondSession.accessToken))).resolves.toBe(
        true,
      );
      await expect(
        isAccessTokenRevoked(store, claims(bystander.verified.accessToken)),
      ).resolves.toBe(false);
    });

    describe('with the TTL-honouring in-memory store', () => {
      // FakeEphemeralStoreService ignores TTLs, which hid an index that expired
      // while the families it listed were kept alive by rotation.
      let now: number;

      beforeEach(() => {
        now = Date.parse('2026-01-01T00:00:00Z');
        jest.spyOn(Date, 'now').mockImplementation(() => now);
      });

      afterEach(() => {
        jest.restoreAllMocks();
      });

      it('keeps no per-refresh record, and gives refresh state an expiry at a UTC midnight', async () => {
        // An odd moment of the day: nothing stored may reveal it.
        now = Date.parse('2026-01-01T13:37:42.123Z');
        const store = new EphemeralStoreService(new FakeConfigService() as never);
        const { service, registerAndLogin } = setup({ store });
        const { verified, registered } = await registerAndLogin('timeline');
        const entries = () => [
          ...(
            store as unknown as { fallback: Map<string, { expiresAt: number }> }
          ).fallback.entries(),
        ];

        let { refreshToken } = verified;
        for (let i = 0; i < 4; i += 1) {
          now += 61_234;
          ({ refreshToken } = await service.refresh(refreshToken));
        }

        const refreshEntries = entries().filter(([key]) => key.startsWith('auth:refresh'));
        expect(refreshEntries.map(([key]) => key.split(':').slice(0, 2).join(':')).sort()).toEqual([
          'auth:refresh',
          'auth:refresh-families',
          'auth:refresh-family',
        ]);
        for (const [, entry] of refreshEntries) {
          expect(new Date(entry.expiresAt).toISOString()).toBe('2026-02-01T00:00:00.000Z');
        }
        expect(entries().filter(([key]) => !key.startsWith('auth:refresh'))).toEqual([]);

        await service.logout({ userId: registered.userId, deviceId: registered.deviceId });
        expect(entries()).toEqual([]);
        await expect(service.refresh(refreshToken)).rejects.toMatchObject({
          response: { code: 'refresh_token_invalid' },
        });
      });

      it('logout revokes a family kept alive past the refresh TTL by refreshes alone', async () => {
        const store = new EphemeralStoreService(new FakeConfigService() as never);
        const { service, registerAndLogin } = setup({ store });
        const { verified, registered } = await registerAndLogin('dailyrefresh');

        let { refreshToken } = verified;
        for (let day = 1; day <= 31; day += 1) {
          now += DAY_MS;
          ({ refreshToken } = await service.refresh(refreshToken));
        }

        await service.logout({ userId: registered.userId, deviceId: registered.deviceId });

        await expect(service.refresh(refreshToken)).rejects.toMatchObject({
          response: { code: 'refresh_token_invalid' },
        });
      });
    });
  });
});
