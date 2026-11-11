import { UnauthorizedException } from '@nestjs/common';

import { utcDayStart } from '../../src/common/device-activity';
import { JwtAuthGuard } from '../../src/common/guards/jwt-auth.guard';

type Req = { headers: Record<string, string | undefined>; auth?: unknown };

function ctx(request: Req, type: 'http' | 'ws' = 'http') {
  return {
    getType: () => type,
    getHandler: () => 'handler',
    getClass: () => 'class',
    switchToHttp: () => ({ getRequest: () => request }),
  } as never;
}

const activeDevice = {
  id: 'd1',
  userId: 'u1',
  isActive: true,
  revokedAt: null,
  lastSeenAt: utcDayStart(new Date()),
  user: { status: 'active' },
};

function build(
  opts: {
    isPublic?: boolean;
    verify?: () => Promise<unknown>;
    blacklisted?: unknown;
    device?: unknown;
  } = {},
) {
  const reflector = { getAllAndOverride: () => opts.isPublic ?? false } as never;
  const jwtService = {
    verifyAsync:
      opts.verify ?? (async () => ({ sub: 'u1', deviceId: 'd1', handle: 'alice', jti: 'j1' })),
  } as never;
  const config = { jwtSecret: 's', jwtAudience: 'a', jwtIssuer: 'i' } as never;
  const activityWrites: unknown[] = [];
  const prisma = {
    device: {
      findUnique: async () => opts.device ?? activeDevice,
      updateMany: async (args: unknown) => {
        activityWrites.push(args);
        return { count: 1 };
      },
    },
  } as never;
  const ephemeralStore = { getJson: async () => opts.blacklisted ?? null } as never;
  return Object.assign(new JwtAuthGuard(reflector, jwtService, config, prisma, ephemeralStore), {
    activityWrites,
  });
}

const authed = () => ctx({ headers: { authorization: 'Bearer t' } });

describe('JwtAuthGuard', () => {
  it('lets non-http contexts (ws/rpc) through untouched', async () => {
    expect(await build().canActivate(ctx({ headers: {} }, 'ws'))).toBe(true);
  });

  it('lets @Public routes through without a token', async () => {
    expect(await build({ isPublic: true }).canActivate(ctx({ headers: {} }))).toBe(true);
  });

  it('rejects a missing bearer token', async () => {
    await expect(build().canActivate(ctx({ headers: {} }))).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('rejects a blacklisted (logged-out) jti', async () => {
    await expect(
      build({ blacklisted: { revoked: true } }).canActivate(authed()),
    ).rejects.toMatchObject({ response: { code: 'token_revoked' } });
  });

  it('rejects a revoked / inactive device', async () => {
    const guard = build({
      device: { ...activeDevice, isActive: false, revokedAt: new Date() },
    });
    await expect(guard.canActivate(authed())).rejects.toMatchObject({
      response: { code: 'device_not_active' },
    });
  });

  it('rejects a locked/non-active user even with a live device', async () => {
    const guard = build({ device: { ...activeDevice, user: { status: 'locked' } } });
    await expect(guard.canActivate(authed())).rejects.toMatchObject({
      response: { code: 'device_not_active' },
    });
  });

  it('rejects a device whose owner does not match the token sub', async () => {
    const guard = build({ device: { ...activeDevice, userId: 'someone-else' } });
    await expect(guard.canActivate(authed())).rejects.toMatchObject({
      response: { code: 'device_not_active' },
    });
  });

  it('populates request.auth on a valid token', async () => {
    const req: Req = { headers: { authorization: 'Bearer t' } };
    expect(await build().canActivate(ctx(req))).toBe(true);
    expect(req.auth).toMatchObject({
      userId: 'u1',
      deviceId: 'd1',
      handle: 'alice',
      jti: 'j1',
    });
  });

  it('records the day a device was last seen, at most once a day', async () => {
    const today = utcDayStart(new Date());
    const seenToday = build();
    await seenToday.canActivate(authed());
    expect(seenToday.activityWrites).toEqual([]);

    const seenYesterday = build({
      device: { ...activeDevice, lastSeenAt: new Date(today.getTime() - 3_600_000) },
    });
    await seenYesterday.canActivate(authed());
    expect(seenYesterday.activityWrites).toEqual([
      { where: { id: 'd1', lastSeenAt: { not: today } }, data: { lastSeenAt: today } },
    ]);
  });

  it('maps a token-verify failure to a generic unauthorized', async () => {
    const guard = build({
      verify: async () => {
        throw new Error('bad signature');
      },
    });
    await expect(guard.canActivate(authed())).rejects.toMatchObject({
      response: { code: 'unauthorized' },
    });
  });
});
