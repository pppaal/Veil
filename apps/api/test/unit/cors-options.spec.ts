import { Controller, Get, type INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';

import { corsOptions } from '../../src/common/config/cors-options';

@Controller('probe')
class ProbeController {
  @Get()
  probe(): { ok: true } {
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
    const moduleRef = await Test.createTestingModule({ controllers: [ProbeController] }).compile();
    // The refused origin surfaces as a logged handler error; keep the run quiet.
    app = moduleRef.createNestApplication({ logger: false });
    app.enableCors(corsOptions({ isOriginAllowed: (origin) => !origin || origin === WEB_ORIGIN }));
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

  it('still refuses an origin the configuration does not allow', async () => {
    const response = await request(app.getHttpServer())
      .get('/probe')
      .set('Origin', 'https://evil.example');

    expect(response.headers['access-control-allow-origin']).toBeUndefined();
  });
});
