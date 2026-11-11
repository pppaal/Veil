import {
  type CanActivate,
  Controller,
  type ExecutionContext,
  Get,
  type INestApplication,
  Injectable,
} from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { Test } from '@nestjs/testing';
import { Prisma } from '@prisma/client';
import request from 'supertest';

import { notFound } from '../errors/api-error';
import { AppLoggerService } from '../logger/app-logger.service';
import { ActorRefGenerator } from '../logger/request-redactor';
import { ApiExceptionFilter } from './api-exception.filter';

const prismaError = (code: string) =>
  new Prisma.PrismaClientKnownRequestError(`Invalid value for handle "bob" (${code})`, {
    code,
    clientVersion: 'test',
  });

@Controller()
class FailingController {
  @Get('users/:handle')
  user(): never {
    throw notFound('handle_not_found', 'Handle not found');
  }

  @Get('conversations/:id')
  conversation(): never {
    throw prismaError('P2023');
  }

  @Get('contacts/:handle')
  contact(): never {
    throw prismaError('P2002');
  }

  @Get('stories/:id')
  story(): never {
    throw prismaError('P2025');
  }

  @Get('messages/:id')
  message(): never {
    throw prismaError('P2003');
  }

  @Get('profile/:handle')
  crash(): never {
    throw new Error('database exploded');
  }
}

// Stands in for JwtAuthGuard so the failing handler runs with an actor.
@Injectable()
class FixedActorGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    context.switchToHttp().getRequest().auth = { userId: 'user-7d3c', deviceId: 'device-1' };
    return true;
  }
}

describe('ApiExceptionFilter', () => {
  let app: INestApplication;
  const actorRefs = new ActorRefGenerator();
  const entries: Array<{ level: string; event: string; meta: Record<string, unknown> }> = [];
  const logger = {
    info: (event: string, meta: Record<string, unknown>) =>
      entries.push({ level: 'info', event, meta }),
    warn: (event: string, meta: Record<string, unknown>) =>
      entries.push({ level: 'warn', event, meta }),
    error: (event: string, meta: Record<string, unknown>) =>
      entries.push({ level: 'error', event, meta }),
  } as unknown as AppLoggerService;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      controllers: [FailingController],
      providers: [{ provide: APP_GUARD, useClass: FixedActorGuard }],
    }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    app.useGlobalFilters(new ApiExceptionFilter(logger, actorRefs));
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => {
    entries.length = 0;
  });

  it('404 on /v1/users/bob logs no bob', async () => {
    const response = await request(app.getHttpServer()).get('/v1/users/bob?ref=bob').expect(404);

    expect(response.body).toMatchObject({ code: 'handle_not_found', path: '/v1/users/:handle' });
    expect(entries).toEqual([
      {
        level: 'warn',
        event: 'request.rejected',
        meta: expect.objectContaining({ route: '/v1/users/:handle', statusCode: 404 }),
      },
    ]);
    expect(JSON.stringify(entries)).not.toContain('bob');
    expect(entries[0]!.meta).not.toHaveProperty('actorUserId');
  });

  it('logs unmatched routes without echoing the path', async () => {
    const response = await request(app.getHttpServer()).get('/v1/nothing/bob').expect(404);

    expect(response.body.path).toBe('unmatched');
    expect(entries[0]!.meta).toMatchObject({ route: 'unmatched' });
    expect(JSON.stringify(entries)).not.toContain('bob');
  });

  it('P2023 -> 400 validation_failed', async () => {
    const response = await request(app.getHttpServer())
      .get('/v1/conversations/not-a-uuid')
      .expect(400);

    expect(response.body).toMatchObject({ statusCode: 400, code: 'validation_failed' });
    expect(response.body.message).not.toContain('bob');
    expect(entries[0]).toMatchObject({ level: 'warn' });
  });

  it('P2003 -> 400 validation_failed', async () => {
    const response = await request(app.getHttpServer()).get('/v1/messages/m1').expect(400);
    expect(response.body.code).toBe('validation_failed');
  });

  it('P2002 -> 409 resource_conflict', async () => {
    const response = await request(app.getHttpServer()).get('/v1/contacts/bob').expect(409);
    expect(response.body).toMatchObject({ statusCode: 409, code: 'resource_conflict' });
  });

  it('P2025 -> 404 resource_not_found', async () => {
    const response = await request(app.getHttpServer()).get('/v1/stories/s1').expect(404);
    expect(response.body).toMatchObject({ statusCode: 404, code: 'resource_not_found' });
  });

  it('5xx log has actorRef not userId', async () => {
    const response = await request(app.getHttpServer()).get('/v1/profile/bob').expect(500);

    expect(response.body).toMatchObject({
      code: 'internal_error',
      message: 'Internal server error',
    });
    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({
      level: 'error',
      event: 'request.failed',
      meta: { route: '/v1/profile/:handle', actorRef: actorRefs.actorRef('user-7d3c') },
    });
    const serialized = JSON.stringify(entries);
    expect(serialized).not.toContain('user-7d3c');
    expect(serialized).not.toContain('bob');
  });
});
