import { createPrivateKey, randomBytes, sign } from 'node:crypto';

import { BadRequestException, HttpStatus, ValidationPipe } from '@nestjs/common';
import { ThrottlerException } from '@nestjs/throttler';

import { IS_PUBLIC_KEY } from '../../common/guards/public.decorator';
import { RetentionFakePrismaService } from '../../../test/support/fake-prisma-retention';
import { FakeEphemeralStoreService } from '../../../test/support/fake-services';
import { DirectoryBudget } from './directory-budget';
import { RotateSignedPrekeyDto } from './dto/keys.dto';
import { KeysController } from './keys.controller';
import { KeysService } from './keys.service';
import { PrekeysController } from './prekeys.controller';
import { PrekeysService } from './prekeys.service';
import { decodeSignedPrekeyBundleV2, verifySignedPrekeyBundleV2 } from './signed-prekey-bundle';

// Contract C1 vector: IK seed 32x0x11, IKx priv 32x0x55, SPK priv 32x0x66,
// spkId 1, spkTs 1767225600000. Reproduced byte for byte by the mobile and
// web implementations.
const VECTOR_IDENTITY_PUBLIC_KEY = '0EqyMnQrtKs6E2i9RhXk5tAiSrcaAWuvhSCjMsl3hzc';
const VECTOR_IKX = 'OKtmS9hvd9fma92a4HkpE6lP2LM6EmACfktGwfSITGc';
const VECTOR_SPK = 'IZ5NgA2paNKl_LAJx4T0dGxxOO257khEtznoMLBc9CQ';
const VECTOR_SPK_TS = 1767225600000;
const VECTOR_BUNDLE =
  'eyJ2IjoyLCJpa3giOiJPS3RtUzlodmQ5Zm1hOTJhNEhrcEU2bFAyTE02RW1BQ2ZrdEd3ZlNJVEdjIiwiaWt4U2lnIjoiUlJEdzVlc05wdXZySjVYQnNlVXRFdVM2SFNjVG1TVjQwdHRsdkc4N0gzWkRQLTZpX2F5bVpvX29TWlVTNWtBRHF2WGZLU1hnX3E3NHZ3R09tNlhuRFEiLCJzcGtJZCI6MSwic3BrIjoiSVo1TmdBMnBhTktsX0xBSng0VDBkR3h4T08yNTdraEV0em5vTUxCYzlDUSIsInNwa1RzIjoxNzY3MjI1NjAwMDAwLCJzcGtTaWciOiJXNTJGa1ZtTTU3YjNaaFBNZkd3NjVNMnB1NHpMUmR3dmpGcWgzc0QzclI0MTRZaU9vWWVicFFBV216U05wX3FEX1JsN2s3a29zdFJVbnNiTzNxQ3NBZyJ9';

const ED25519_PKCS8_PREFIX = Buffer.from('302e020100300506032b657004220420', 'hex');
const ed25519KeyFromSeed = (seed: Buffer) =>
  createPrivateKey({
    key: Buffer.concat([ED25519_PKCS8_PREFIX, seed]),
    format: 'der',
    type: 'pkcs8',
  });
const VECTOR_IDENTITY_KEY = ed25519KeyFromSeed(Buffer.alloc(32, 0x11));

/** Builds a v2 bundle exactly as the clients do (contract C1). */
function buildBundleV2(options: {
  spkId: number;
  spkTs?: number;
  ikx?: string;
  spk?: string;
  identityKey?: ReturnType<typeof createPrivateKey>;
}): string {
  const identityKey = options.identityKey ?? VECTOR_IDENTITY_KEY;
  const ikx = options.ikx ?? VECTOR_IKX;
  const spk = options.spk ?? randomBytes(32).toString('base64url');
  const spkTs = options.spkTs ?? VECTOR_SPK_TS;
  const header = Buffer.alloc(12);
  header.writeUInt32BE(options.spkId, 0);
  header.writeBigUInt64BE(BigInt(spkTs), 4);
  const signature = (...parts: Buffer[]) =>
    sign(null, Buffer.concat(parts), identityKey).toString('base64url');

  const json = JSON.stringify({
    v: 2,
    ikx,
    ikxSig: signature(Buffer.from('veil-ikx-v2'), Buffer.from(ikx, 'base64url')),
    spkId: options.spkId,
    spk,
    spkTs,
    spkSig: signature(Buffer.from('veil-spk-v2'), header, Buffer.from(spk, 'base64url')),
  });
  return Buffer.from(json, 'utf8').toString('base64url');
}

const accepts = (encoded: string): boolean => {
  const bundle = decodeSignedPrekeyBundleV2(encoded);
  return bundle !== null && verifySignedPrekeyBundleV2(bundle, VECTOR_IDENTITY_PUBLIC_KEY);
};

describe('signed prekey bundle v2', () => {
  it('accepts the contract vector and exposes its fields', () => {
    const bundle = decodeSignedPrekeyBundleV2(VECTOR_BUNDLE);

    expect(bundle).not.toBeNull();
    expect(bundle!.spkId).toBe(1);
    expect(bundle!.spkTs).toBe(VECTOR_SPK_TS);
    expect(bundle!.ikx.toString('base64url')).toBe(VECTOR_IKX);
    expect(verifySignedPrekeyBundleV2(bundle!, VECTOR_IDENTITY_PUBLIC_KEY)).toBe(true);
  });

  it('the test builder reproduces the vector byte for byte', () => {
    expect(buildBundleV2({ spkId: 1, spk: VECTOR_SPK })).toBe(VECTOR_BUNDLE);
  });

  it('rejects every single-byte flip of the decoded bundle', () => {
    const bytes = Buffer.from(VECTOR_BUNDLE, 'base64url');
    for (let index = 0; index < bytes.length; index += 1) {
      for (const mask of [0x01, 0x20, 0x80]) {
        const flipped = Buffer.from(bytes);
        flipped[index] ^= mask;
        expect({ index, mask, accepted: accepts(flipped.toString('base64url')) }).toEqual({
          index,
          mask,
          accepted: false,
        });
      }
    }
  });

  it('rejects every single-character flip of the encoded bundle', () => {
    for (let index = 0; index < VECTOR_BUNDLE.length; index += 1) {
      const flipped =
        VECTOR_BUNDLE.slice(0, index) +
        String.fromCharCode(VECTOR_BUNDLE.charCodeAt(index) ^ 0x01) +
        VECTOR_BUNDLE.slice(index + 1);
      expect({ index, accepted: accepts(flipped) }).toEqual({ index, accepted: false });
    }
  });

  it('rejects non-canonical encodings of the same content', () => {
    const json = Buffer.from(VECTOR_BUNDLE, 'base64url').toString('utf8');
    const reencode = (text: string) => Buffer.from(text, 'utf8').toString('base64url');

    expect(decodeSignedPrekeyBundleV2(`${VECTOR_BUNDLE}==`)).toBeNull();
    expect(decodeSignedPrekeyBundleV2(reencode(json.replace('{', '{ ')))).toBeNull();
    expect(
      decodeSignedPrekeyBundleV2(reencode(json.replace('"spkId":1', '"spkId":1.0'))),
    ).toBeNull();
    const reordered = JSON.parse(json);
    expect(
      decodeSignedPrekeyBundleV2(reencode(JSON.stringify({ ikx: reordered.ikx, ...reordered }))),
    ).toBeNull();
  });

  it('treats legacy and malformed bundles as not-v2', () => {
    for (const legacy of ['prekey-1', '', 'not base64!', Buffer.from('[]').toString('base64url')]) {
      expect(decodeSignedPrekeyBundleV2(legacy)).toBeNull();
    }
    const v3 = Buffer.from(VECTOR_BUNDLE, 'base64url').toString('utf8').replace('"v":2', '"v":3');
    expect(decodeSignedPrekeyBundleV2(Buffer.from(v3).toString('base64url'))).toBeNull();
  });

  it('does not verify against another identity key', () => {
    const bundle = decodeSignedPrekeyBundleV2(VECTOR_BUNDLE)!;
    const otherKey = Buffer.alloc(32, 0x22).toString('base64url');

    expect(verifySignedPrekeyBundleV2(bundle, otherKey)).toBe(false);
    expect(verifySignedPrekeyBundleV2(bundle, 'not-a-32-byte-key')).toBe(false);
  });
});

async function setup() {
  const prisma = new RetentionFakePrismaService();
  const budget = new DirectoryBudget(new FakeEphemeralStoreService() as never);
  const prekeys = new PrekeysService(prisma as never, budget);
  const clock = { now: VECTOR_SPK_TS };
  const keys = new KeysService(prisma as never, prekeys, budget, () => clock.now);

  const aliceId = await prisma.addUser('alice');
  const alicePhone = await prisma.addDevice(aliceId);
  const bobId = await prisma.addUser('bob');
  const bobLaptop = await prisma.addDevice(bobId, { trustedAt: new Date('2026-01-01') });
  const bobPhone = await prisma.addDevice(bobId, { trustedAt: new Date('2026-02-01') });

  const seedPrekeys = (deviceId: string, count: number) => {
    for (let keyId = 1; keyId <= count; keyId += 1) {
      prisma.oneTimePrekeys.push({
        id: `${deviceId}-${keyId}`,
        deviceId,
        keyId,
        publicKey: `opk-${deviceId}-${keyId}`,
        consumedAt: null,
        createdAt: new Date(),
      });
    }
  };
  const unconsumed = (deviceId: string) =>
    prisma.oneTimePrekeys.filter((p) => p.deviceId === deviceId && p.consumedAt === null).length;

  return {
    prisma,
    prekeys,
    keys,
    clock,
    alice: { userId: aliceId, deviceId: alicePhone },
    bob: { userId: bobId, laptop: bobLaptop, phone: bobPhone },
    seedPrekeys,
    unconsumed,
  };
}

const requesterNumber = (n: number) => ({
  userId: `requester-user-${n}`,
  deviceId: `requester-${n}`,
});

const errorCode = async (promise: Promise<unknown>) =>
  promise.then(
    () => 'resolved',
    (error) => (error as { response?: { code?: string } }).response?.code ?? String(error),
  );

describe('KeysService.getKeys', () => {
  it('returns trusted devices with the active one flagged and claims only for it by default', async () => {
    const { keys, alice, bob, seedPrekeys, unconsumed } = await setup();
    seedPrekeys(bob.phone, 3);
    seedPrekeys(bob.laptop, 3);

    const result = await keys.getKeys(alice, 'BOB', 'active');

    expect(result.user).toEqual({ id: bob.userId, handle: 'bob', activeDeviceId: bob.phone });
    expect(result.devices.map((d) => [d.deviceId, d.isActive])).toEqual([
      [bob.phone, true],
      [bob.laptop, false],
    ]);
    expect(result.devices[0].oneTimePrekey).toEqual({ keyId: 1, publicKey: `opk-${bob.phone}-1` });
    expect(result.devices[1].oneTimePrekey).toBeNull();
    expect([unconsumed(bob.phone), unconsumed(bob.laptop)]).toEqual([2, 3]);
  });

  it('claim=all returns a distinct OPK per trusted device', async () => {
    const { keys, prisma, alice, bob, seedPrekeys } = await setup();
    seedPrekeys(bob.phone, 2);
    seedPrekeys(bob.laptop, 2);
    const revoked = await prisma.addDevice(bob.userId, { isActive: false, revokedAt: new Date() });
    seedPrekeys(revoked, 2);
    await prisma.user.update({ where: { id: bob.userId }, data: { activeDeviceId: bob.phone } });

    const result = await keys.getKeys(alice, 'bob', 'all');

    expect(result.devices.map((d) => d.deviceId)).toEqual([bob.phone, bob.laptop]);
    expect(result.devices.map((d) => d.oneTimePrekey?.publicKey)).toEqual([
      `opk-${bob.phone}-1`,
      `opk-${bob.laptop}-1`,
    ]);
    expect(prisma.oneTimePrekeys.filter((p) => p.deviceId === revoked && p.consumedAt)).toEqual([]);
  });

  it('claim=all claims in device id order, whatever order the devices are listed in', async () => {
    const { keys, prisma, alice, bob, seedPrekeys } = await setup();
    seedPrekeys(bob.phone, 1);
    seedPrekeys(bob.laptop, 1);
    const [lowId, highId] = [bob.phone, bob.laptop].sort();
    for (const device of prisma.devices) {
      if (device.id === lowId) device.trustedAt = new Date('2026-01-01');
      if (device.id === highId) device.trustedAt = new Date('2026-03-01');
    }
    const findFirst = jest.spyOn(prisma.oneTimePrekey, 'findFirst');

    const result = await keys.getKeys(alice, 'bob', 'all');

    expect(result.devices.map((d) => d.deviceId)).toEqual([highId, lowId]);
    expect(findFirst.mock.calls.map(([args]) => args?.where.deviceId)).toEqual([lowId, highId]);
  });

  it('claim=none returns keys and consumes nothing', async () => {
    const { keys, alice, bob, seedPrekeys, unconsumed } = await setup();
    seedPrekeys(bob.phone, 2);

    const result = await keys.getKeys(alice, 'bob', 'none');

    expect(result.devices.every((d) => d.oneTimePrekey === null)).toBe(true);
    expect(unconsumed(bob.phone)).toBe(2);
  });

  it('claims nothing for your own handle', async () => {
    const { keys, prisma, alice, seedPrekeys, unconsumed } = await setup();
    const aliceLaptop = await prisma.addDevice(alice.userId);
    seedPrekeys(aliceLaptop, 2);

    const result = await keys.getKeys(alice, 'alice', 'all');

    expect(result.devices.every((d) => d.oneTimePrekey === null)).toBe(true);
    expect(unconsumed(aliceLaptop)).toBe(2);
  });

  it('concurrent claims never return the same keyId', async () => {
    const { keys, prisma, bob, seedPrekeys } = await setup();
    seedPrekeys(bob.phone, 30);

    const results = await Promise.all(
      Array.from({ length: 12 }, (_, n) => keys.getKeys(requesterNumber(n), 'bob', 'active')),
    );

    const claimedKeyIds = results
      .map((result) => result.devices[0].oneTimePrekey?.keyId)
      .filter((keyId): keyId is number => keyId !== undefined);
    expect(claimedKeyIds.length).toBeGreaterThan(0);
    expect(new Set(claimedKeyIds).size).toBe(claimedKeyIds.length);
    // Every consumed row was handed to exactly one claimer.
    expect(prisma.oneTimePrekeys.filter((p) => p.consumedAt !== null)).toHaveLength(
      claimedKeyIds.length,
    );
  });

  it('21st claim within an hour returns null and consumes nothing', async () => {
    const { keys, alice, bob, seedPrekeys, unconsumed } = await setup();
    seedPrekeys(bob.phone, 25);

    for (let claim = 1; claim <= 20; claim += 1) {
      const result = await keys.getKeys(alice, 'bob', 'active');
      expect(result.devices[0].oneTimePrekey?.keyId).toBe(claim);
    }
    const overBudget = await keys.getKeys(alice, 'bob', 'active');

    expect(overBudget.devices[0].oneTimePrekey).toBeNull();
    expect(unconsumed(bob.phone)).toBe(5);
    // The budget is per requester: another device still gets a prekey.
    const other = await keys.getKeys(requesterNumber(1), 'bob', 'active');
    expect(other.devices[0].oneTimePrekey?.keyId).toBe(21);
  });

  it('caps claims against one target device at 50 per hour across requesters', async () => {
    const { keys, bob, seedPrekeys, unconsumed } = await setup();
    seedPrekeys(bob.phone, 60);

    for (let n = 0; n < 50; n += 1) {
      await keys.getKeys(requesterNumber(n), 'bob', 'active');
    }
    const overBudget = await keys.getKeys(requesterNumber(50), 'bob', 'active');

    expect(overBudget.devices[0].oneTimePrekey).toBeNull();
    expect(unconsumed(bob.phone)).toBe(10);
  });

  it('shares the requester budget with the legacy claim route', async () => {
    const { keys, prekeys, alice, bob, seedPrekeys } = await setup();
    seedPrekeys(bob.phone, 25);

    for (let claim = 0; claim < 15; claim += 1) {
      await keys.getKeys(alice, 'bob', 'active');
    }
    for (let claim = 0; claim < 5; claim += 1) {
      expect((await prekeys.claim(alice, 'bob')).prekey).not.toBeNull();
    }

    expect(await prekeys.claim(alice, 'bob')).toEqual({ deviceId: bob.phone, prekey: null });
  });

  it('404s an unknown handle', async () => {
    const { keys, alice } = await setup();
    expect(await errorCode(keys.getKeys(alice, 'ghost', 'active'))).toBe('handle_not_found');
  });
});

describe('key directory routes', () => {
  it('claim routes are not @Public', () => {
    for (const handler of [
      KeysController.prototype.getKeys,
      KeysController.prototype.rotateSignedPrekey,
      PrekeysController.prototype.claim,
    ]) {
      expect(Reflect.getMetadata(IS_PUBLIC_KEY, handler)).toBeUndefined();
    }
  });

  it('handle lookups keep a per-minute rate limit', () => {
    // The metadata keys @Throttle writes for the default throttler.
    const perMinuteLimit = (handler: object) => [
      Reflect.getMetadata('THROTTLER:TTLdefault', handler),
      Reflect.getMetadata('THROTTLER:LIMITdefault', handler),
    ];

    expect(perMinuteLimit(KeysController.prototype.getKeys)).toEqual([60_000, 10]);
    expect(perMinuteLimit(PrekeysController.prototype.claim)).toEqual([60_000, 30]);
  });

  it('the rotation body cannot carry an identity key', async () => {
    const pipe = new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    });
    const validate = (body: unknown) =>
      pipe.transform(body, { type: 'body', metatype: RotateSignedPrekeyDto });

    await expect(validate({ signedPrekeyBundle: VECTOR_BUNDLE })).resolves.toBeDefined();
    await expect(
      validate({ signedPrekeyBundle: VECTOR_BUNDLE, identityPublicKey: 'attacker' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('KeysService.rotateSignedPrekey', () => {
  async function setupRotation(currentBundle = 'legacy-v1-bundle') {
    const context = await setup();
    const device = context.prisma.devices.find((d) => d.id === context.alice.deviceId)!;
    device.publicIdentityKey = VECTOR_IDENTITY_PUBLIC_KEY;
    device.signedPrekeyBundle = currentBundle;
    return { ...context, device };
  }

  it('accepts the bundle v2 vector', async () => {
    const { keys, alice, device } = await setupRotation();

    await expect(keys.rotateSignedPrekey(alice, VECTOR_BUNDLE)).resolves.toEqual({
      deviceId: alice.deviceId,
      spkId: 1,
    });
    expect(device.signedPrekeyBundle).toBe(VECTOR_BUNDLE);
    expect(device.publicIdentityKey).toBe(VECTOR_IDENTITY_PUBLIC_KEY);
  });

  it('bad spkSig 400', async () => {
    const { keys, alice, device } = await setupRotation();
    const decode = (encoded: string) =>
      JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));
    const forged = buildBundleV2({
      spkId: 1,
      spk: VECTOR_SPK,
      identityKey: ed25519KeyFromSeed(Buffer.alloc(32, 0x99)),
    });
    const tampered = { ...decode(VECTOR_BUNDLE), spkSig: decode(forged).spkSig };

    const rejection = await keys
      .rotateSignedPrekey(alice, Buffer.from(JSON.stringify(tampered)).toString('base64url'))
      .catch((error) => error);

    expect(rejection).toBeInstanceOf(BadRequestException);
    expect(rejection.getStatus()).toBe(HttpStatus.BAD_REQUEST);
    expect(rejection.response.code).toBe('invalid_device_signature');
    expect(device.signedPrekeyBundle).toBe('legacy-v1-bundle');
  });

  it('rejects a bundle that is not canonical v2', async () => {
    const { keys, alice } = await setupRotation();
    expect(await errorCode(keys.rotateSignedPrekey(alice, 'legacy-v1-bundle'))).toBe(
      'validation_failed',
    );
  });

  it('ikx change rejected for v2 current bundle', async () => {
    const { keys, alice, device } = await setupRotation(VECTOR_BUNDLE);
    const otherIkx = randomBytes(32).toString('base64url');

    expect(
      await errorCode(keys.rotateSignedPrekey(alice, buildBundleV2({ spkId: 2, ikx: otherIkx }))),
    ).toBe('validation_failed');
    expect(device.signedPrekeyBundle).toBe(VECTOR_BUNDLE);
  });

  it('requires spkId to increase over a v2 current bundle', async () => {
    const { keys, alice } = await setupRotation(VECTOR_BUNDLE);

    expect(await errorCode(keys.rotateSignedPrekey(alice, buildBundleV2({ spkId: 1 })))).toBe(
      'validation_failed',
    );
    await expect(keys.rotateSignedPrekey(alice, buildBundleV2({ spkId: 2 }))).resolves.toEqual({
      deviceId: alice.deviceId,
      spkId: 2,
    });
  });

  it('v1 bundle upgraded once', async () => {
    const { keys, alice, device } = await setupRotation('legacy-v1-bundle');
    const upgrade = buildBundleV2({ spkId: 7, ikx: randomBytes(32).toString('base64url') });

    await keys.rotateSignedPrekey(alice, upgrade);
    expect(device.signedPrekeyBundle).toBe(upgrade);

    // v2 is now current, so the X25519 identity key is pinned.
    const secondUpgrade = buildBundleV2({ spkId: 8, ikx: randomBytes(32).toString('base64url') });
    expect(await errorCode(keys.rotateSignedPrekey(alice, secondUpgrade))).toBe(
      'validation_failed',
    );
    expect(device.signedPrekeyBundle).toBe(upgrade);
  });

  it('rejects a signed prekey timestamp more than 10 minutes from now', async () => {
    const { keys, alice, clock } = await setupRotation();
    clock.now = VECTOR_SPK_TS + 10 * 60 * 1000 + 1;

    expect(await errorCode(keys.rotateSignedPrekey(alice, VECTOR_BUNDLE))).toBe(
      'validation_failed',
    );

    clock.now = VECTOR_SPK_TS - 10 * 60 * 1000;
    await expect(keys.rotateSignedPrekey(alice, VECTOR_BUNDLE)).resolves.toBeDefined();
  });

  it('rotation served on next GET /v1/keys', async () => {
    const { keys, alice, bob } = await setupRotation();

    await keys.rotateSignedPrekey(alice, VECTOR_BUNDLE);
    const directory = await keys.getKeys(
      { userId: bob.userId, deviceId: bob.phone },
      'alice',
      'none',
    );

    expect(directory.devices[0]).toMatchObject({
      deviceId: alice.deviceId,
      identityPublicKey: VECTOR_IDENTITY_PUBLIC_KEY,
      signedPrekeyBundle: VECTOR_BUNDLE,
    });
  });

  it('allows 10 rotations per hour per device, then 429', async () => {
    const { keys, alice } = await setupRotation(VECTOR_BUNDLE);

    for (let spkId = 2; spkId <= 11; spkId += 1) {
      await keys.rotateSignedPrekey(alice, buildBundleV2({ spkId }));
    }
    const rejection = await keys
      .rotateSignedPrekey(alice, buildBundleV2({ spkId: 12 }))
      .catch((error) => error);

    expect(rejection).toBeInstanceOf(ThrottlerException);
    expect(rejection.getStatus()).toBe(HttpStatus.TOO_MANY_REQUESTS);
  });

  it('refuses a revoked device', async () => {
    const { keys, alice, device } = await setupRotation();
    device.isActive = false;
    device.revokedAt = new Date();

    expect(await errorCode(keys.rotateSignedPrekey(alice, VECTOR_BUNDLE))).toBe(
      'device_not_active',
    );
  });
});
