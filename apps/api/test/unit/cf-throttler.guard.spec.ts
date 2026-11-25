import { Controller, Get, type INestApplication, type Provider, type Type } from '@nestjs/common';
import { APP_GUARD, Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { Test } from '@nestjs/testing';
import { ThrottlerModule } from '@nestjs/throttler';
import request from 'supertest';

import { AppConfigService } from '../../src/common/config/app-config.service';
import type { ClientIpSource } from '../../src/common/config/env.schema';
import { EphemeralStoreService } from '../../src/common/ephemeral-store.service';
import { CfThrottlerGuard } from '../../src/common/guards/cf-throttler.guard';
import { JwtAuthGuard } from '../../src/common/guards/jwt-auth.guard';
import { Public } from '../../src/common/guards/public.decorator';
import { utcDayStart } from '../../src/common/device-activity';
import { PrismaService } from '../../src/common/prisma.service';
import { FakeEphemeralStoreService } from '../support/fake-services';

const JWT = {
  secret: 'throttle-spec-secret-0123456789abcdef',
  audience: 'veil-mobile',
  issuer: 'veil-api',
};

// getTracker is protected on ThrottlerGuard; tests reach it through this view.
interface TrackerSource {
  getTracker(req: unknown): Promise<string>;
}

function trackerFor(source: ClientIpSource, req: unknown): Promise<string> {
  const guard = new CfThrottlerGuard(
    { throttlers: [] },
    { increment: jest.fn() },
    new Reflector(),
    { clientIpSource: source } as AppConfigService,
  );
  return (guard as unknown as TrackerSource).getTracker(req);
}

describe('CfThrottlerGuard.getTracker', () => {
  it('prefers the authenticated device id over any header or address', async () => {
    await expect(
      trackerFor('cf-connecting-ip', {
        auth: { deviceId: 'd1' },
        headers: { 'cf-connecting-ip': '1.2.3.4' },
        ip: '9.9.9.9',
        socket: { remoteAddress: '127.0.0.1' },
      }),
    ).resolves.toBe('dev:d1');
  });

  it('socket source ignores every forwarding header', async () => {
    await expect(
      trackerFor('socket', {
        headers: { 'cf-connecting-ip': '1.2.3.4', 'x-forwarded-for': '5.6.7.8' },
        ip: '5.6.7.8',
        socket: { remoteAddress: '203.0.113.10' },
      }),
    ).resolves.toBe('ip:203.0.113.10');
  });

  it('x-forwarded-for source ignores spoofed cf-connecting-ip', async () => {
    // req.ip is what Express derived from X-Forwarded-For with the
    // configured trusted hop count.
    await expect(
      trackerFor('x-forwarded-for', {
        headers: { 'cf-connecting-ip': '1.2.3.4', 'x-forwarded-for': '203.0.113.7' },
        ip: '203.0.113.7',
        socket: { remoteAddress: '172.18.0.5' },
      }),
    ).resolves.toBe('ip:203.0.113.7');
  });

  it('cf-connecting-ip source rejects non-IP header', async () => {
    for (const spoofed of ['not-an-ip', '1.2.3.4, 5.6.7.8', '', '1.2.3.4.5']) {
      await expect(
        trackerFor('cf-connecting-ip', {
          headers: { 'cf-connecting-ip': spoofed },
          ip: '9.9.9.9',
          socket: { remoteAddress: '127.0.0.1' },
        }),
      ).resolves.toBe('ip:127.0.0.1');
    }
  });

  it('cf-connecting-ip source uses a well-formed IPv4 or IPv6 header', async () => {
    for (const address of ['198.51.100.9', '2001:db8::7']) {
      await expect(
        trackerFor('cf-connecting-ip', {
          headers: { 'cf-connecting-ip': ` ${address} ` },
          socket: { remoteAddress: '127.0.0.1' },
        }),
      ).resolves.toBe(`ip:${address}`);
    }
  });

  it('falls back to ip:unknown when no address is known', async () => {
    await expect(trackerFor('socket', { headers: {} })).resolves.toBe('ip:unknown');
  });
});

@Controller('probe')
class ProbeController {
  @Get()
  authenticated(): { ok: true } {
    return { ok: true };
  }

  @Public()
  @Get('public')
  open(): { ok: true } {
    return { ok: true };
  }
}

describe('CfThrottlerGuard with the app.module guard chain', () => {
  let app: INestApplication;
  let trackers: string[];
  const jwt = new JwtService();

  const tokenFor = (deviceId: string): Promise<string> =>
    jwt.signAsync(
      { sub: `user-${deviceId}`, deviceId, handle: `handle-${deviceId}` },
      { secret: JWT.secret, audience: JWT.audience, issuer: JWT.issuer, expiresIn: 60 },
    );

  beforeAll(async () => {
    // AppModule validates the environment when it is imported.
    Object.assign(process.env, {
      VEIL_DATABASE_URL: 'postgresql://veil:veil@localhost:5432/veil',
      VEIL_JWT_SECRET: JWT.secret,
      VEIL_S3_ENDPOINT: 'http://localhost:9000',
      VEIL_S3_REGION: 'us-east-1',
      VEIL_S3_ACCESS_KEY: 'minioadmin',
      VEIL_S3_SECRET_KEY: 'minioadmin',
      VEIL_S3_BUCKET: 'veil-encrypted',
    });
    const { AppModule } = await import('../../src/app.module');
    const appGuards = (Reflect.getMetadata('providers', AppModule) as Provider[]).filter(
      (provider): provider is { provide: typeof APP_GUARD; useClass: Type } =>
        typeof provider === 'object' && 'provide' in provider && provider.provide === APP_GUARD,
    );
    expect(appGuards.map((guard) => guard.useClass)).toEqual([JwtAuthGuard, CfThrottlerGuard]);

    // Record every tracker the real implementation computes. The spy must be
    // installed before init: ThrottlerGuard binds getTracker in onModuleInit.
    trackers = [];
    const prototype = CfThrottlerGuard.prototype as unknown as TrackerSource;
    const getTracker = prototype.getTracker;
    jest.spyOn(prototype, 'getTracker').mockImplementation(async function (
      this: TrackerSource,
      req: unknown,
    ) {
      const tracker = await getTracker.call(this, req);
      trackers.push(tracker);
      return tracker;
    });

    // Already seen today, so the guard has no activity to record.
    const activeDevice = (id: string) => ({
      id,
      userId: `user-${id}`,
      isActive: true,
      revokedAt: null,
      lastSeenAt: utcDayStart(new Date()),
      user: { status: 'active' },
    });
    const moduleRef = await Test.createTestingModule({
      imports: [ThrottlerModule.forRoot({ throttlers: [{ ttl: 60_000, limit: 1 }] })],
      controllers: [ProbeController],
      providers: [
        ...appGuards,
        {
          provide: AppConfigService,
          useValue: {
            jwtSecret: JWT.secret,
            jwtAudience: JWT.audience,
            jwtIssuer: JWT.issuer,
            clientIpSource: 'socket',
          },
        },
        { provide: JwtService, useValue: jwt },
        {
          provide: PrismaService,
          useValue: {
            device: {
              findUnique: async ({ where }: { where: { id: string } }) => activeDevice(where.id),
            },
          },
        },
        { provide: EphemeralStoreService, useValue: new FakeEphemeralStoreService() },
      ],
    }).compile();
    app = moduleRef.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    jest.restoreAllMocks();
    await app.close();
  });

  beforeEach(() => {
    trackers.length = 0;
  });

  it('authenticated request tracks dev:<deviceId> with guards in app.module order (TestingModule + supertest)', async () => {
    await request(app.getHttpServer())
      .get('/probe')
      .set('Authorization', `Bearer ${await tokenFor('device-a')}`)
      .expect(200);

    expect(trackers).toEqual(['dev:device-a']);
  });

  it('two devices behind one IP get independent buckets', async () => {
    const server = app.getHttpServer();
    const deviceB = `Bearer ${await tokenFor('device-b')}`;
    const deviceC = `Bearer ${await tokenFor('device-c')}`;

    await request(server).get('/probe').set('Authorization', deviceB).expect(200);
    await request(server).get('/probe').set('Authorization', deviceB).expect(429);
    await request(server).get('/probe').set('Authorization', deviceC).expect(200);

    expect(trackers).toEqual(['dev:device-b', 'dev:device-b', 'dev:device-c']);
  });

  it('@Public routes leave req.auth unset and fall back to the IP bucket', async () => {
    await request(app.getHttpServer()).get('/probe/public').expect(200);

    expect(trackers).toHaveLength(1);
    expect(trackers[0]).toMatch(/^ip:(::ffff:)?127\.0\.0\.1$/);
  });

  it('rejects an unauthenticated request before it reaches the throttler', async () => {
    await request(app.getHttpServer()).get('/probe').expect(401);
    expect(trackers).toEqual([]);
  });
});
