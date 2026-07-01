import { UnauthorizedException } from '@nestjs/common';

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
  const prisma = {
    device: { findUnique: async () => opts.device ?? activeDevice },
  } as never;
  const ephemeralStore = { getJson: async () => opts.blacklisted ?? null } as never;
  return new JwtAuthGuard(reflector, jwtService, config, prisma, ephemeralStore);
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
