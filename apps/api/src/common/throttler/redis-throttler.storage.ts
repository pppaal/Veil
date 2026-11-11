import type { OnModuleDestroy } from '@nestjs/common';
import type { ThrottlerStorage } from '@nestjs/throttler';

type ThrottlerStorageRecord = Awaited<ReturnType<ThrottlerStorage['increment']>>;

// The subset of ioredis this storage needs, so tests can drive it with an
// in-memory fake instead of a live Redis.
export interface ThrottlerRedisTransaction {
  incr(key: string): ThrottlerRedisTransaction;
  pexpire(key: string, milliseconds: number, mode: 'NX'): ThrottlerRedisTransaction;
  pttl(key: string): ThrottlerRedisTransaction;
  exec(): Promise<Array<[Error | null, unknown]> | null>;
}

export interface ThrottlerRedisClient {
  multi(): ThrottlerRedisTransaction;
  set(key: string, value: string, mode: 'PX', milliseconds: number): Promise<unknown>;
  exists(key: string): Promise<number>;
  pttl(key: string): Promise<number>;
  quit(): Promise<unknown>;
}

export interface ThrottlerStorageLogger {
  warn(event: string, meta?: Record<string, unknown>): void;
}

const ALLOW: ThrottlerStorageRecord = {
  totalHits: 0,
  timeToExpire: 0,
  isBlocked: false,
  timeToBlockExpire: 0,
};

const toSeconds = (milliseconds: number): number => Math.max(0, Math.ceil(milliseconds / 1000));

// Fixed-window counter shared by every API instance. The in-memory default
// counts per process, so N replicas silently multiplied every limit by N.
//
// One MULTI per hit: INCR the window counter, start its expiry only on the
// first hit (PEXPIRE NX, Redis >= 7), and read the remaining window back.
// Exceeding the limit writes a separate block key so the block outlives the
// window when blockDuration > ttl, exactly like the built-in storage.
export class RedisThrottlerStorage implements ThrottlerStorage, OnModuleDestroy {
  private outageReported = false;

  constructor(
    private readonly redis: ThrottlerRedisClient,
    private readonly logger: ThrottlerStorageLogger,
  ) {}

  async increment(
    key: string,
    ttl: number,
    limit: number,
    blockDuration: number,
    throttlerName: string,
  ): Promise<ThrottlerStorageRecord> {
    try {
      const record = await this.count(
        `veil:thr:${throttlerName}:${key}`,
        ttl,
        limit,
        blockDuration,
      );
      this.outageReported = false;
      return record;
    } catch (error) {
      // Failing open keeps the relay available through a Redis outage; the
      // warning fires once per outage so it cannot flood the log.
      if (!this.outageReported) {
        this.outageReported = true;
        this.logger.warn('throttler.storage_unavailable', {
          error: error instanceof Error ? error.message : String(error),
        });
      }
      return ALLOW;
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.redis.quit();
  }

  private async count(
    hitsKey: string,
    ttl: number,
    limit: number,
    blockDuration: number,
  ): Promise<ThrottlerStorageRecord> {
    const blockKey = `${hitsKey}:blocked`;
    if ((await this.redis.exists(blockKey)) > 0) {
      const blockRemaining = await this.redis.pttl(blockKey);
      // While blocked the window cannot reopen before the block lifts, so the
      // block's remaining time doubles as the window's.
      return {
        totalHits: limit + 1,
        timeToExpire: toSeconds(blockRemaining),
        isBlocked: true,
        // The key may expire between EXISTS and PTTL; still report a block.
        timeToBlockExpire: Math.max(1, toSeconds(blockRemaining)),
      };
    }

    const replies = await this.redis
      .multi()
      .incr(hitsKey)
      .pexpire(hitsKey, ttl, 'NX')
      .pttl(hitsKey)
      .exec();
    const totalHits = Number(this.reply(replies, 0));
    const timeToExpire = toSeconds(Number(this.reply(replies, 2)));

    if (totalHits > limit) {
      await this.redis.set(blockKey, '1', 'PX', blockDuration);
      return {
        totalHits,
        timeToExpire,
        isBlocked: true,
        timeToBlockExpire: toSeconds(blockDuration),
      };
    }
    return { totalHits, timeToExpire, isBlocked: false, timeToBlockExpire: 0 };
  }

  private reply(replies: Array<[Error | null, unknown]> | null, index: number): unknown {
    if (!replies) {
      throw new Error('throttler transaction aborted');
    }
    const [error, value] = replies[index] ?? [new Error('throttler reply missing'), null];
    if (error) {
      throw error;
    }
    return value;
  }
}
