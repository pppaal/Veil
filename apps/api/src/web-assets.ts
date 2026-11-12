import { existsSync } from 'node:fs';
import { join } from 'node:path';

import type { NestExpressApplication } from '@nestjs/platform-express';
import type { NextFunction, Request, Response } from 'express';

// The non-production /demo web client is reachable through a public tunnel,
// and browsers ignore frame-ancestors in a <meta> CSP, so these must be real
// response headers: without them the demo's approve/wipe buttons can be
// clickjacked from any origin.
const DEMO_SECURITY_HEADERS: Readonly<Record<string, string>> = {
  'Content-Security-Policy': [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' blob: data:",
    'media-src blob:',
    "connect-src 'self' ws: wss: http: https:",
    "frame-ancestors 'none'",
    "base-uri 'none'",
    "object-src 'none'",
    "form-action 'none'",
  ].join('; '),
  'X-Frame-Options': 'DENY',
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'Permissions-Policy': 'microphone=(self)',
};

// The one-time link viewer, and only it, is served by a production relay too:
// the app builds links to <relay>/demo/s.html#<id>.<key>, so without it every
// link the app shares opens a JSON 404. These are the page and the modules it
// loads; the key stays in the fragment, which never reaches the server.
export const SECRET_VIEWER_FILES: readonly string[] = [
  's.html',
  's.js',
  'src/crypto/secret-link.js',
  'src/core/base64url.js',
];

// The page's own policy (it repeats it in a <meta> tag), replacing the
// production default-src 'none', which would block its module script.
const SECRET_VIEWER_HEADERS: Readonly<Record<string, string>> = {
  'Content-Security-Policy': [
    "default-src 'none'",
    "script-src 'self'",
    "style-src 'self' 'unsafe-inline'",
    "connect-src 'self'",
    "img-src 'self' data:",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  ].join('; '),
  'X-Frame-Options': 'DENY',
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'Cache-Control': 'no-store',
};

export const findWebDemoRoot = (): string | undefined =>
  [
    join(process.cwd(), 'apps', 'web-demo'),
    join(process.cwd(), '..', 'web-demo'),
    join(__dirname, '..', '..', 'web-demo'),
  ].find((path) => existsSync(path));

/**
 * Serves apps/web-demo under /demo: all of it outside production, only the
 * one-time link viewer (SECRET_VIEWER_FILES) in production. Everything else
 * under /demo falls through to the API's 404.
 */
export const mountWebAssets = (
  app: NestExpressApplication,
  config: { isProduction: boolean },
  webDemoRoot: string | undefined = findWebDemoRoot(),
): void => {
  if (!webDemoRoot) {
    return;
  }

  if (!config.isProduction) {
    app.use('/demo', (_req: Request, res: Response, next: NextFunction) => {
      for (const [name, value] of Object.entries(DEMO_SECURITY_HEADERS)) {
        res.setHeader(name, value);
      }
      next();
    });
    app.useStaticAssets(webDemoRoot, { prefix: '/demo' });
    return;
  }

  app.use('/demo', (req: Request, res: Response, next: NextFunction) => {
    const file = req.path.replace(/^\//, '');
    if ((req.method !== 'GET' && req.method !== 'HEAD') || !SECRET_VIEWER_FILES.includes(file)) {
      next();
      return;
    }
    for (const [name, value] of Object.entries(SECRET_VIEWER_HEADERS)) {
      res.setHeader(name, value);
    }
    // Relative to root, so a dot-directory above the checkout cannot trip the
    // dotfile guard.
    res.sendFile(file, { root: webDemoRoot });
  });
};
