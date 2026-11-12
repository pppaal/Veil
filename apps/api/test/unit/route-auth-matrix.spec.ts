import { RequestMethod, type DynamicModule, type Type } from '@nestjs/common';
import { METHOD_METADATA, MODULE_METADATA, PATH_METADATA } from '@nestjs/common/constants';

import { IS_PUBLIC_KEY } from '../../src/common/guards/public.decorator';

// Exactly the routes reachable without a bearer token. Adding one widens the
// unauthenticated attack surface (enumeration, abuse, metadata leaks), so a
// new entry here needs a security review, not just a passing test. Nothing
// about a user or their keys is on this list.
const PUBLIC_ROUTES: readonly string[] = [
  'GET /v1/health',
  'GET /v1/metrics',
  'POST /v1/auth/register',
  'POST /v1/auth/challenge',
  'POST /v1/auth/verify',
  'POST /v1/auth/refresh',
  'POST /v1/device-transfer/claim',
  'POST /v1/device-transfer/complete',
  'POST /v1/s',
  'GET /v1/s/:id',
];

const GLOBAL_PREFIX = 'v1';

interface Route {
  route: string;
  isPublic: boolean;
}

type ModuleEntry =
  | Type
  | DynamicModule
  | Promise<DynamicModule>
  | { forwardRef: () => ModuleEntry }
  | undefined;

const isForwardRef = (entry: object): entry is { forwardRef: () => ModuleEntry } =>
  'forwardRef' in entry && typeof entry.forwardRef === 'function';

const isDynamicModule = (entry: object): entry is DynamicModule => 'module' in entry;

const metadataList = <T>(key: string, target: object): T[] =>
  (Reflect.getMetadata(key, target) as T[] | undefined) ?? [];

// Walks the module graph from module metadata alone, without instantiating
// anything, so the matrix covers exactly what Nest would mount. Async dynamic
// modules (ConfigModule.forRoot returns a Promise) are awaited, not skipped.
async function collectControllers(root: Type): Promise<Type[]> {
  const visited = new Set<unknown>();
  const controllers = new Set<Type>();
  const visit = async (pending: ModuleEntry): Promise<void> => {
    const entry = await pending;
    if (!entry || visited.has(entry)) return;
    visited.add(entry);
    if (isForwardRef(entry)) {
      await visit(entry.forwardRef());
      return;
    }
    if (isDynamicModule(entry)) {
      entry.controllers?.forEach((controller) => controllers.add(controller));
      for (const imported of entry.imports ?? []) {
        await visit(imported as ModuleEntry);
      }
      await visit(entry.module);
      return;
    }
    metadataList<Type>(MODULE_METADATA.CONTROLLERS, entry).forEach((controller) =>
      controllers.add(controller),
    );
    for (const imported of metadataList<ModuleEntry>(MODULE_METADATA.IMPORTS, entry)) {
      await visit(imported);
    }
  };
  await visit(root);
  return [...controllers];
}

// Nest mounts handlers inherited from base controller classes too.
const methodNames = (prototype: object): string[] => {
  const names = new Set<string>();
  for (
    let current: object | null = prototype;
    current && current !== Object.prototype;
    current = Object.getPrototypeOf(current) as object | null
  ) {
    Object.getOwnPropertyNames(current).forEach((name) => names.add(name));
  }
  names.delete('constructor');
  return [...names];
};

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
  return methodNames(prototype).flatMap((name) => {
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
    routes = (await collectControllers(AppModule)).flatMap(routesOf);
  });

  it('discovers the mounted API surface', () => {
    const all = routes.map((entry) => entry.route);
    expect(all.length).toBeGreaterThan(40);
    expect(all).toEqual(expect.arrayContaining(['POST /v1/messages', 'GET /v1/health']));
  });

  // Equality, not a subset: a stale entry would let a route quietly turn
  // public again without anyone reviewing it.
  it('route-auth-matrix equals final PUBLIC_ROUTES', () => {
    const publicRoutes = routes.filter((entry) => entry.isPublic).map((entry) => entry.route);
    expect([...publicRoutes].sort()).toEqual([...PUBLIC_ROUTES].sort());
  });

  it('serves no key material or profile without a bearer token', () => {
    const all = routes.map((entry) => entry.route);
    expect(all).not.toContain('GET /v1/users/:handle/key-bundle');
    for (const keyRoute of ['GET /v1/keys/:handle', 'GET /v1/keys/group/:conversationId']) {
      expect(all).toContain(keyRoute);
      expect(routes.find((entry) => entry.route === keyRoute)?.isPublic).toBe(false);
    }
  });

  it('no route offers recovery or backup', () => {
    const offending = routes
      .map((entry) => entry.route)
      .filter((route) => /recovery|backup/i.test(route));
    expect(offending).toEqual([]);
  });
});
