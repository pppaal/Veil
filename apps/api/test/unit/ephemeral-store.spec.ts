import Redis from 'ioredis';

import type { AppConfigService } from '../../src/common/config/app-config.service';
import { EphemeralStoreService } from '../../src/common/ephemeral-store.service';
import { ThrowawayRedis, findRedisServer } from '../support/throwaway-redis';

// incrementFieldsUntil backs the one-time-link quota: both counters move in
// one step, a negative amount undoes an add, and the key expires at the
// absolute time the caller gives (an expiry already past removes it). Checked
// on the in-memory fallback and, when redis-server is installed, on Redis.

const redisServer = findRedisServer();
if (!redisServer) {
  console.warn('ephemeral-store.spec: no redis-server found; the Redis cases are skipped');
}

interface Backend {
  store: EphemeralStoreService;
  /** The key's absolute expiry in ms, or null when the key is gone. */
  expiryOf(key: string): Promise<number | null>;
  close(): Promise<void>;
}

const inMemory = async (): Promise<Backend> => {
  const store = new EphemeralStoreService({ redisUrl: undefined } as AppConfigService);
  return {
    store,
    expiryOf: async (key) => {
      const entry = (
        store as unknown as { fallback: Map<string, { expiresAt: number }> }
      ).fallback.get(key);
      return entry?.expiresAt ?? null;
    },
    close: () => store.onModuleDestroy(),
  };
};

let redis: ThrowawayRedis | undefined;
const onRedis = async (): Promise<Backend> => {
  const store = new EphemeralStoreService({
    redisUrl: (redis as ThrowawayRedis).socketPath,
  } as AppConfigService);
  const inspector = new Redis((redis as ThrowawayRedis).socketPath);
  return {
    store,
    expiryOf: async (key) => {
      const expiry = Number(await inspector.call('PEXPIRETIME', key));
      return expiry < 0 ? null : expiry;
    },
    close: async () => {
      await inspector.quit();
      await store.onModuleDestroy();
    },
  };
};

const backends: Array<[string, () => Promise<Backend>]> = [['the in-memory fallback', inMemory]];
if (redisServer) {
  backends.push(['Redis', onRedis]);
}

describe.each(backends)('EphemeralStoreService.incrementFieldsUntil on %s', (_name, open) => {
  let backend: Backend;
  const key = 'secret:quota:test';

  beforeAll(async () => {
    if (open === onRedis && !redis) {
      redis = await ThrowawayRedis.start(redisServer as string);
    }
  });

  beforeEach(async () => {
    backend = await open();
    await backend.store.delete(key);
  });

  afterEach(async () => {
    await backend.close();
  });

  afterAll(() => {
    redis?.stop();
    redis = undefined;
  });

  it('adds to every field in one step and a negative amount undoes an add', async () => {
    const until = Date.now() + 60_000;
    const { store } = backend;

    await expect(store.incrementFieldsUntil(key, { links: 1, bytes: 10 }, until)).resolves.toEqual({
      links: 1,
      bytes: 10,
    });
    await expect(store.incrementFieldsUntil(key, { links: 1, bytes: 5 }, until)).resolves.toEqual({
      links: 2,
      bytes: 15,
    });
    await expect(store.incrementFieldsUntil(key, { links: -1, bytes: -5 }, until)).resolves.toEqual(
      { links: 1, bytes: 10 },
    );
  });

  it('expires the key at the absolute time given, whatever the time of the write', async () => {
    const until = Math.ceil(Date.now() / 1000) * 1000 + 3_600_000;

    await backend.store.incrementFieldsUntil(key, { links: 1 }, until);
    await expect(backend.expiryOf(key)).resolves.toBe(until);
    await backend.store.incrementFieldsUntil(key, { links: 1 }, until);
    await expect(backend.expiryOf(key)).resolves.toBe(until);
  });

  it('removes the key when the expiry given has already passed', async () => {
    const future = Date.now() + 60_000;
    await backend.store.incrementFieldsUntil(key, { links: 3 }, future);

    await expect(
      backend.store.incrementFieldsUntil(key, { links: -1 }, Date.now() - 1),
    ).resolves.toEqual({ links: 2 });
    await expect(backend.expiryOf(key)).resolves.toBeNull();
    await expect(backend.store.incrementFieldsUntil(key, { links: 0 }, future)).resolves.toEqual({
      links: 0,
    });
  });
});
