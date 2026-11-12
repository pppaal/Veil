import { join } from 'node:path';

import { Module } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import helmet from 'helmet';
import request from 'supertest';

import { mountWebAssets } from '../../src/web-assets';

// The app shares one-time links as <relay>/demo/s.html#<id>.<key>. A
// production relay must serve that page and the modules it loads, and nothing
// else of the web demo.

const WEB_DEMO_ROOT = join(__dirname, '..', '..', '..', 'web-demo');

@Module({})
class EmptyModule {}

const boot = async (isProduction: boolean): Promise<NestExpressApplication> => {
  const app = await NestFactory.create<NestExpressApplication>(EmptyModule, { logger: false });
  // As main.ts sets it up for production, so the test sees the viewer's
  // policy replace the relay's default-src 'none'.
  app.use(
    helmet({
      contentSecurityPolicy: isProduction
        ? { directives: { defaultSrc: ["'none'"], frameAncestors: ["'none'"] } }
        : false,
      crossOriginEmbedderPolicy: isProduction,
    }),
  );
  mountWebAssets(app, { isProduction }, WEB_DEMO_ROOT);
  await app.init();
  return app;
};

describe('mountWebAssets', () => {
  describe('in production', () => {
    let app: NestExpressApplication;

    beforeAll(async () => {
      app = await boot(true);
    });

    afterAll(async () => {
      await app.close();
    });

    it('serves the one-time link viewer with a policy that lets its module script run', async () => {
      const page = await request(app.getHttpServer()).get('/demo/s.html').expect(200);

      expect(page.headers['content-type']).toMatch(/^text\/html/);
      expect(page.text).toContain('./s.js');
      const csp = page.headers['content-security-policy'];
      expect(csp).toContain("script-src 'self'");
      expect(csp).toContain("frame-ancestors 'none'");
      expect(page.headers['referrer-policy']).toBe('no-referrer');
      expect(page.headers['cache-control']).toBe('no-store');
    });

    it.each(['/demo/s.js', '/demo/src/crypto/secret-link.js', '/demo/src/core/base64url.js'])(
      'serves the module %s',
      async (path) => {
        const module = await request(app.getHttpServer()).get(path).expect(200);
        expect(module.headers['content-type']).toMatch(/javascript/);
      },
    );

    it.each([
      '/demo/',
      '/demo/index.html',
      '/demo/app.js',
      '/demo/src/app/main.js',
      '/demo/../package.json',
    ])('serves nothing else of the web demo: %s', async (path) => {
      await request(app.getHttpServer()).get(path).expect(404);
    });
  });

  it('serves the whole web demo outside production', async () => {
    const app = await boot(false);
    try {
      await request(app.getHttpServer()).get('/demo/index.html').expect(200);
      const page = await request(app.getHttpServer()).get('/demo/s.html').expect(200);
      expect(page.headers['x-frame-options']).toBe('DENY');
    } finally {
      await app.close();
    }
  });
});
