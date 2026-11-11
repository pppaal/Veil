import {
  RedisThrottlerStorage,
  type ThrottlerRedisClient,
  type ThrottlerRedisTransaction,
} from '../../src/common/throttler/redis-throttler.storage';

// In-memory stand-in for the Redis commands the storage uses, with a
// controllable clock so window and block expiry are deterministic.
class FakeRedis implements ThrottlerRedisClient {
  now = 1_000_000;
  failing = false;
  quitCalled = false;
  readonly entries = new Map<string, { value: string; expiresAt: number | null }>();

  multi(): ThrottlerRedisTransaction {
    const operations: Array<() => unknown> = [];
    const transaction: ThrottlerRedisTransaction = {
      incr: (key) => {
        operations.push(() => this.incr(key));
        return transaction;
      },
      pexpire: (key, milliseconds) => {
        operations.push(() => this.pexpireNx(key, milliseconds));
        return transaction;
      },
      pttl: (key) => {
        operations.push(() => this.pttlSync(key));
        return transaction;
      },
      exec: async () => {
        this.assertReachable();
        return operations.map((operation) => [null, operation()] as [null, unknown]);
      },
    };
    return transaction;
  }

  async set(key: string, value: string, _mode: 'PX', milliseconds: number): Promise<'OK'> {
    this.assertReachable();
    this.entries.set(key, { value, expiresAt: this.now + milliseconds });
    return 'OK';
  }

  async del(key: string): Promise<number> {
    this.assertReachable();
    return this.entries.delete(key) ? 1 : 0;
  }

  async exists(key: string): Promise<number> {
    this.assertReachable();
    return this.live(key) ? 1 : 0;
  }

  async pttl(key: string): Promise<number> {
    this.assertReachable();
    return this.pttlSync(key);
  }

  async quit(): Promise<'OK'> {
    this.quitCalled = true;
    return 'OK';
  }

  private assertReachable(): void {
    if (this.failing) {
      throw new Error('connect ECONNREFUSED');
    }
  }

  private live(key: string) {
    const entry = this.entries.get(key);
    if (entry && entry.expiresAt !== null && entry.expiresAt <= this.now) {
      this.entries.delete(key);
      return undefined;
    }
    return entry;
  }

  private incr(key: string): number {
    const entry = this.live(key);
    const next = Number(entry?.value ?? 0) + 1;
    this.entries.set(key, { value: String(next), expiresAt: entry?.expiresAt ?? null });
    return next;
  }

  private pexpireNx(key: string, milliseconds: number): number {
    const entry = this.live(key);
    if (!entry || entry.expiresAt !== null) {
      return 0;
    }
    entry.expiresAt = this.now + milliseconds;
    return 1;
  }

  private pttlSync(key: string): number {
    const entry = this.live(key);
    if (!entry) return -2;
    if (entry.expiresAt === null) return -1;
    return entry.expiresAt - this.now;
  }
}

const recordingLogger = () => {
  const warnings: string[] = [];
  return { warnings, logger: { warn: (event: string) => warnings.push(event) } };
};

describe('RedisThrottlerStorage', () => {
  it('counts hits within ttl', async () => {
    const redis = new FakeRedis();
    const storage = new RedisThrottlerStorage(redis, recordingLogger().logger);

    const first = await storage.increment('tracker', 60_000, 3, 60_000, 'default');
    redis.now += 20_000;
    const second = await storage.increment('tracker', 60_000, 3, 60_000, 'default');

    expect(first).toEqual({
      totalHits: 1,
      timeToExpire: 60,
      isBlocked: false,
      timeToBlockExpire: 0,
    });
    expect(second).toEqual({
      totalHits: 2,
      timeToExpire: 40,
      isBlocked: false,
      timeToBlockExpire: 0,
    });
    expect(redis.entries.has('veil:thr:default:tracker')).toBe(true);

    // Another throttler or tracker never shares the counter.
    await expect(storage.increment('tracker', 60_000, 3, 60_000, 'burst')).resolves.toMatchObject({
      totalHits: 1,
    });
    await expect(storage.increment('other', 60_000, 3, 60_000, 'default')).resolves.toMatchObject({
      totalHits: 1,
    });

    redis.now += 40_000;
    await expect(storage.increment('tracker', 60_000, 3, 60_000, 'default')).resolves.toMatchObject(
      {
        totalHits: 1,
        timeToExpire: 60,
      },
    );
  });

  it('blocks after limit and reports timeToBlockExpire', async () => {
    const redis = new FakeRedis();
    const storage = new RedisThrottlerStorage(redis, recordingLogger().logger);

    await storage.increment('tracker', 10_000, 2, 30_000, 'default');
    await storage.increment('tracker', 10_000, 2, 30_000, 'default');
    const exceeded = await storage.increment('tracker', 10_000, 2, 30_000, 'default');
    expect(exceeded).toMatchObject({ totalHits: 3, isBlocked: true, timeToBlockExpire: 30 });

    // The block outlives the 10 s window.
    redis.now += 12_000;
    await expect(storage.increment('tracker', 10_000, 2, 30_000, 'default')).resolves.toMatchObject(
      {
        isBlocked: true,
        timeToBlockExpire: 18,
      },
    );

    redis.now += 18_000;
    await expect(storage.increment('tracker', 10_000, 2, 30_000, 'default')).resolves.toEqual({
      totalHits: 1,
      timeToExpire: 10,
      isBlocked: false,
      timeToBlockExpire: 0,
    });
  });

  it('a block shorter than the window lifts onto a fresh window', async () => {
    const redis = new FakeRedis();
    const storage = new RedisThrottlerStorage(redis, recordingLogger().logger);

    for (let i = 0; i < 3; i += 1) {
      await storage.increment('tracker', 60_000, 2, 5_000, 'default');
    }
    redis.now += 5_000;

    await expect(storage.increment('tracker', 60_000, 2, 5_000, 'default')).resolves.toEqual({
      totalHits: 1,
      timeToExpire: 60,
      isBlocked: false,
      timeToBlockExpire: 0,
    });
  });

  it('fails open and warns once per outage', async () => {
    const redis = new FakeRedis();
    const { logger, warnings } = recordingLogger();
    const storage = new RedisThrottlerStorage(redis, logger);

    redis.failing = true;
    for (let i = 0; i < 3; i += 1) {
      await expect(storage.increment('tracker', 1_000, 1, 1_000, 'default')).resolves.toMatchObject(
        {
          isBlocked: false,
        },
      );
    }
    expect(warnings).toEqual(['throttler.storage_unavailable']);

    redis.failing = false;
    await storage.increment('tracker', 1_000, 1, 1_000, 'default');
    redis.failing = true;
    await storage.increment('tracker', 1_000, 1, 1_000, 'default');
    expect(warnings).toHaveLength(2);
  });

  it('closes the Redis connection on shutdown', async () => {
    const redis = new FakeRedis();
    await new RedisThrottlerStorage(redis, recordingLogger().logger).onModuleDestroy();
    expect(redis.quitCalled).toBe(true);
  });
});
