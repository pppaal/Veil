import { Controller, Get, type INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';

import { corsOptions } from '../../src/common/config/cors-options';
import { ApiExceptionFilter } from '../../src/common/filters/api-exception.filter';
import { ActorRefGenerator } from '../../src/common/logger/request-redactor';

let probed = 0;
let logged: Array<{ level: string; event: string }> = [];

@Controller('probe')
class ProbeController {
  @Get()
  probe(): { ok: true } {
    probed += 1;
    return { ok: true };
  }
}

const WEB_ORIGIN = 'https://web.veil.example';

// Clients stamp signed prekeys with the server clock read from the HTTP Date
// header (contract C-SPK). A browser hides every non-safelisted response
// header from cross-origin script unless the server exposes it.
describe('corsOptions', () => {
  let app: INestApplication;

  beforeEach(async () => {
    probed = 0;
    logged = [];
    const moduleRef = await Test.createTestingModule({ controllers: [ProbeController] }).compile();
    app = moduleRef.createNestApplication({ logger: false });
    app.enableCors(corsOptions({ isOriginAllowed: (origin) => !origin || origin === WEB_ORIGIN }));
    // As main.ts registers it, with a logger that records each level.
    const record = (level: string) => (event: string) => logged.push({ level, event });
    app.useGlobalFilters(
      new ApiExceptionFilter(
        { error: record('error'), warn: record('warn') } as never,
        new ActorRefGenerator(),
      ),
    );
    await app.init();
  });

  afterEach(async () => {
    await app.close();
  });

  it('lets a cross-origin web client read the Date header', async () => {
    const response = await request(app.getHttpServer()).get('/probe').set('Origin', WEB_ORIGIN);

    expect(response.status).toBe(200);
    expect(response.headers['access-control-allow-origin']).toBe(WEB_ORIGIN);
    expect(Number.isNaN(Date.parse(response.headers.date))).toBe(false);
    const exposed = (response.headers['access-control-expose-headers'] ?? '')
      .split(',')
      .map((name: string) => name.trim().toLowerCase());
    expect(exposed).toContain('date');
  });

  // Any page a user visits can make their browser send these, so they must
  // not count as server errors.
  it('refuses an origin the configuration does not allow with a 403, before the handler', async () => {
    const response = await request(app.getHttpServer())
      .get('/probe')
      .set('Origin', 'https://evil.example');

    expect(response.status).toBe(403);
    expect(response.body.code).toBe('origin_not_allowed');
    expect(response.headers['access-control-allow-origin']).toBeUndefined();
    expect(probed).toBe(0);
    expect(logged).toEqual([{ level: 'warn', event: 'request.rejected' }]);
  });

  it('refuses the preflight of a disallowed origin the same way', async () => {
    const response = await request(app.getHttpServer())
      .options('/probe')
      .set('Origin', 'https://evil.example')
      .set('Access-Control-Request-Method', 'POST');

    expect(response.status).toBe(403);
    expect(response.headers['access-control-allow-origin']).toBeUndefined();
  });
});
