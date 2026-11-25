import { Controller, Get, type INestApplication, Req } from '@nestjs/common';
import { APP_INTERCEPTOR } from '@nestjs/core';
import { Test } from '@nestjs/testing';
import request from 'supertest';

import { LoggingInterceptor } from '../interceptors/logging.interceptor';
import { MetricsService } from '../../modules/metrics/metrics.service';
import { AppLoggerService } from './app-logger.service';
import { ActorRefGenerator, routeTemplate, type RoutedRequest } from './request-redactor';

@Controller()
class HandleRoutesController {
  @Get('users/:handle')
  user(@Req() req: RoutedRequest): string {
    return routeTemplate(req);
  }

  @Get('prekeys/claim/:handle')
  claim(@Req() req: RoutedRequest): string {
    return routeTemplate(req);
  }

  @Get('profile/:handle')
  profile(@Req() req: RoutedRequest): string {
    return routeTemplate(req);
  }

  @Get('contacts/:handle')
  contact(@Req() req: RoutedRequest): string {
    return routeTemplate(req);
  }

  @Get('conversations/group/:id/members/:handle')
  member(@Req() req: RoutedRequest): string {
    return routeTemplate(req);
  }
}

describe('request redactor', () => {
  let app: INestApplication;
  let metrics: MetricsService;
  const logged: Array<Record<string, unknown>> = [];

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      controllers: [HandleRoutesController],
      providers: [
        MetricsService,
        { provide: ActorRefGenerator, useValue: new ActorRefGenerator() },
        {
          provide: AppLoggerService,
          useValue: {
            info: (event: string, meta: Record<string, unknown>) => logged.push({ event, ...meta }),
          },
        },
        { provide: APP_INTERCEPTOR, useClass: LoggingInterceptor },
      ],
    }).compile();
    metrics = moduleRef.get(MetricsService);
    app = moduleRef.createNestApplication();
    // Same global prefix as main.ts: the prefix is what defeated the old
    // URL-regex redaction.
    app.setGlobalPrefix('v1');
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => {
    logged.length = 0;
  });

  it.each([
    ['/v1/users/bob', '/v1/users/:handle'],
    ['/v1/prekeys/claim/bob', '/v1/prekeys/claim/:handle'],
    ['/v1/profile/bob', '/v1/profile/:handle'],
    ['/v1/contacts/bob', '/v1/contacts/:handle'],
    [
      '/v1/conversations/group/4f6c2a64-6e2c-4cf5-9a35-0a0e7f1d6f10/members/bob',
      '/v1/conversations/group/:id/members/:handle',
    ],
  ])('%s is reported as %s', async (path, template) => {
    const response = await request(app.getHttpServer()).get(`${path}?q=bob`).expect(200);

    expect(response.text).toBe(template);
    expect(logged).toHaveLength(1);
    expect(logged[0]).toMatchObject({ event: 'request.completed', route: template, status: 200 });
    expect(JSON.stringify(logged)).not.toContain('bob');
    expect(logged[0]).not.toHaveProperty('actorRef');
  });

  it('1000 distinct handles produce one metrics label', async () => {
    const server = app.getHttpServer();
    for (let i = 0; i < 1000; i += 1) {
      await request(server).get(`/v1/users/handle${i}`).expect(200);
    }

    const { values } = await metrics.httpRequestsTotal.get();
    const userSeries = values.filter((value) =>
      String(value.labels.route_class).startsWith('/v1/users/'),
    );
    expect(userSeries).toHaveLength(1);
    expect(userSeries[0]!.labels.route_class).toBe('/v1/users/:handle');
    expect(userSeries[0]!.value).toBeGreaterThanOrEqual(1000);
  });

  it('joins the router mount path and the route path, never the raw URL', () => {
    const mounted = { baseUrl: '/v1', route: { path: '/users/:handle' }, url: '/v1/users/bob' };
    expect(routeTemplate(mounted as RoutedRequest)).toBe('/v1/users/:handle');
    expect(routeTemplate({ url: '/v1/users/bob' } as RoutedRequest)).toBe('unmatched');
  });

  it('actorRef stable within a day, different across days', () => {
    let now = new Date('2026-11-11T00:00:01.000Z');
    const actorRefs = new ActorRefGenerator(() => now);

    const morning = actorRefs.actorRef('user-1');
    now = new Date('2026-11-11T23:59:59.000Z');
    const evening = actorRefs.actorRef('user-1');
    now = new Date('2026-11-12T00:00:00.000Z');
    const nextDay = actorRefs.actorRef('user-1');

    expect(morning).toMatch(/^[0-9a-f]{16}$/);
    expect(evening).toBe(morning);
    expect(actorRefs.actorRef('user-2')).not.toBe(nextDay);
    expect(nextDay).not.toBe(morning);
    expect(morning).not.toContain('user-1');
  });

  it('separate processes cannot join actor references', () => {
    const clock = () => new Date('2026-11-11T12:00:00.000Z');
    expect(new ActorRefGenerator(clock).actorRef('user-1')).not.toBe(
      new ActorRefGenerator(clock).actorRef('user-1'),
    );
  });
});
