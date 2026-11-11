import { RequestMethod, type DynamicModule, type Type } from '@nestjs/common';
import { METHOD_METADATA, MODULE_METADATA, PATH_METADATA } from '@nestjs/common/constants';

import { IS_PUBLIC_KEY } from '../../src/common/guards/public.decorator';

// Every route reachable without a bearer token. Adding one widens the
// unauthenticated attack surface (enumeration, abuse, metadata leaks), so a
// new entry here needs a security review, not just a passing test.
const PUBLIC_ROUTES: ReadonlySet<string> = new Set([
  'GET /v1/health',
  'GET /v1/metrics',
  'POST /v1/auth/register',
  'POST /v1/auth/challenge',
  'POST /v1/auth/verify',
  'POST /v1/auth/refresh',
  'GET /v1/users/:handle',
  'GET /v1/users/:handle/key-bundle',
  'POST /v1/prekeys/claim/:handle',
  'POST /v1/device-transfer/claim',
  'POST /v1/device-transfer/complete',
  'POST /v1/s',
  'GET /v1/s/:id',
]);

const GLOBAL_PREFIX = 'v1';

interface Route {
  route: string;
  isPublic: boolean;
}

type ModuleEntry = Type | DynamicModule | { forwardRef: () => ModuleEntry } | undefined;

const isForwardRef = (entry: object): entry is { forwardRef: () => ModuleEntry } =>
  'forwardRef' in entry && typeof entry.forwardRef === 'function';

const isDynamicModule = (entry: object): entry is DynamicModule => 'module' in entry;

const metadataList = <T>(key: string, target: object): T[] =>
  (Reflect.getMetadata(key, target) as T[] | undefined) ?? [];

// Walks the module graph from module metadata alone, without instantiating
// anything, so the matrix covers exactly what Nest would mount.
function collectControllers(root: Type): Type[] {
  const visited = new Set<unknown>();
  const controllers = new Set<Type>();
  const visit = (entry: ModuleEntry): void => {
    if (!entry || visited.has(entry)) return;
    visited.add(entry);
    if (isForwardRef(entry)) {
      visit(entry.forwardRef());
      return;
    }
    if (isDynamicModule(entry)) {
      entry.controllers?.forEach((controller) => controllers.add(controller));
      entry.imports?.forEach((imported) => visit(imported as ModuleEntry));
      visit(entry.module);
      return;
    }
    metadataList<Type>(MODULE_METADATA.CONTROLLERS, entry).forEach((controller) =>
      controllers.add(controller),
    );
    metadataList<ModuleEntry>(MODULE_METADATA.IMPORTS, entry).forEach(visit);
  };
  visit(root);
  return [...controllers];
}

const asPaths = (value: unknown): string[] =>
  Array.isArray(value) ? value : [typeof value === 'string' ? value : '/'];

const joinPath = (...segments: string[]): string =>
  '/' +
  segments
    .flatMap((segment) => segment.split('/'))
    .filter((segment) => segment.length > 0)
    .join('/');

function routesOf(controller: Type): Route[] {
  const classPublic = Reflect.getMetadata(IS_PUBLIC_KEY, controller) === true;
  const prototype = controller.prototype as Record<string, unknown>;
  return Object.getOwnPropertyNames(prototype).flatMap((name) => {
    const handler = prototype[name];
    if (typeof handler !== 'function' || !Reflect.hasMetadata(METHOD_METADATA, handler)) {
      return [];
    }
    const method = RequestMethod[Reflect.getMetadata(METHOD_METADATA, handler) as RequestMethod];
    const isPublic = classPublic || Reflect.getMetadata(IS_PUBLIC_KEY, handler) === true;
    return asPaths(Reflect.getMetadata(PATH_METADATA, controller)).flatMap((controllerPath) =>
      asPaths(Reflect.getMetadata(PATH_METADATA, handler)).map((handlerPath) => ({
        route: `${method} ${joinPath(GLOBAL_PREFIX, controllerPath, handlerPath)}`,
        isPublic,
      })),
    );
  });
}

describe('route auth matrix', () => {
  let routes: Route[];

  beforeAll(async () => {
    // AppModule validates the environment when it is imported.
    Object.assign(process.env, {
      VEIL_DATABASE_URL: 'postgresql://veil:veil@localhost:5432/veil',
      VEIL_JWT_SECRET: 'route-matrix-secret-0123456789abcdef',
      VEIL_S3_ENDPOINT: 'http://localhost:9000',
      VEIL_S3_REGION: 'us-east-1',
      VEIL_S3_ACCESS_KEY: 'minioadmin',
      VEIL_S3_SECRET_KEY: 'minioadmin',
      VEIL_S3_BUCKET: 'veil-encrypted',
    });
    const { AppModule } = await import('../../src/app.module');
    routes = collectControllers(AppModule).flatMap(routesOf);
  });

  it('discovers the mounted API surface', () => {
    const all = routes.map((entry) => entry.route);
    expect(all.length).toBeGreaterThan(40);
    expect(all).toEqual(expect.arrayContaining(['POST /v1/messages', 'GET /v1/health']));
  });

  // Subset, not equality: sibling work in this wave is removing @Public from
  // some of these routes in parallel.
  it('every @Public route is in the reviewed allowlist', () => {
    const unreviewed = routes
      .filter((entry) => entry.isPublic && !PUBLIC_ROUTES.has(entry.route))
      .map((entry) => entry.route);
    expect(unreviewed).toEqual([]);
  });

  it('no route offers recovery or backup', () => {
    const offending = routes
      .map((entry) => entry.route)
      .filter((route) => /recovery|backup/i.test(route));
    expect(offending).toEqual([]);
  });
});
