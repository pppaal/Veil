import { Injectable, OnModuleDestroy } from '@nestjs/common';
import Redis from 'ioredis';

import { AppConfigService } from './config/app-config.service';

@Injectable()
export class EphemeralStoreService implements OnModuleDestroy {
  private readonly fallback = new Map<string, { value: string; expiresAt: number }>();
  private readonly redis?: Redis;

  constructor(config: AppConfigService) {
    if (config.redisUrl) {
      this.redis = new Redis(config.redisUrl, {
        maxRetriesPerRequest: 1,
        lazyConnect: false,
      });
      this.redis.on('error', () => {
        // Intentionally silent. The service falls back to in-memory storage in local development.
      });
    }
  }

  async setJson<T>(key: string, value: T, ttlSeconds: number): Promise<void> {
    this.purgeExpiredFallbackEntries();
    const serialized = JSON.stringify(value);
    if (this.redis) {
      await this.redis.set(key, serialized, 'EX', ttlSeconds);
      return;
    }

    this.fallback.set(key, {
      value: serialized,
      expiresAt: Date.now() + ttlSeconds * 1000,
    });
  }

  /**
   * Like setJson, but the key expires at an absolute time (SET .. PXAT,
   * Redis >= 6.2, already required for GETDEL). Used where a relative TTL
   * would record the moment of the write in the key's expiry.
   */
  async setJsonUntil<T>(key: string, value: T, expiresAtMs: number): Promise<void> {
    this.purgeExpiredFallbackEntries();
    const serialized = JSON.stringify(value);
    if (this.redis) {
      await this.redis.set(key, serialized, 'PXAT', expiresAtMs);
      return;
    }

    this.fallback.set(key, { value: serialized, expiresAt: expiresAtMs });
  }

  async getJson<T>(key: string): Promise<T | null> {
    this.purgeExpiredFallbackEntries();
    if (this.redis) {
      const value = await this.redis.get(key);
      return value ? (JSON.parse(value) as T) : null;
    }

    const entry = this.fallback.get(key);
    if (!entry) {
      return null;
    }
    if (entry.expiresAt <= Date.now()) {
      this.fallback.delete(key);
      return null;
    }
    return JSON.parse(entry.value) as T;
  }

  async delete(key: string): Promise<void> {
    this.purgeExpiredFallbackEntries();
    if (this.redis) {
      await this.redis.del(key);
      return;
    }
    this.fallback.delete(key);
  }

  /**
   * Atomic get-and-delete. Returns the parsed value if the key existed (and
   * also removes it in the same hop); returns null if the key was already
   * gone — concurrent callers with the same key get exactly one non-null
   * result. Used by refresh-token rotation to defeat replay races.
   */
  async takeJson<T>(key: string): Promise<T | null> {
    this.purgeExpiredFallbackEntries();
    if (this.redis) {
      // GETDEL is atomic in Redis ≥ 6.2.
      const raw = await this.redis.getdel(key);
      return raw ? (JSON.parse(raw) as T) : null;
    }
    const entry = this.fallback.get(key);
    if (!entry || entry.expiresAt <= Date.now()) {
      this.fallback.delete(key);
      return null;
    }
    this.fallback.delete(key);
    return JSON.parse(entry.value) as T;
  }

  /**
   * Atomic counter for fixed-window budgets. The window starts at the first
   * increment and is never extended by later ones, so a caller hammering the
   * key cannot keep its own window open forever.
   */
  async incrementWithTtl(key: string, ttlSeconds: number): Promise<number> {
    this.purgeExpiredFallbackEntries();
    if (this.redis) {
      // The key is created together with its expiry (SET NX EX) and INCR keeps
      // that TTL, so no failure between two commands can leave a counter that
      // never expires and locks its subject out for good.
      const results = await this.redis
        .multi()
        .set(key, '0', 'EX', ttlSeconds, 'NX')
        .incr(key)
        .exec();
      const [[createError] = [], [incrementError, count] = []] = results ?? [];
      if (createError || incrementError || typeof count !== 'number') {
        throw createError ?? incrementError ?? new Error('Redis INCR returned no count');
      }
      return count;
    }

    const entry = this.fallback.get(key);
    const next = entry ? Number(entry.value) + 1 : 1;
    this.fallback.set(key, {
      value: String(next),
      expiresAt: entry?.expiresAt ?? Date.now() + ttlSeconds * 1000,
    });
    return next;
  }

  /**
   * Writes the value only when the key is absent (SET NX EX). Returns false
   * when another writer got there first, so concurrent callers race to a
   * single winner instead of silently overwriting each other.
   */
  async setJsonIfAbsent<T>(key: string, value: T, ttlSeconds: number): Promise<boolean> {
    this.purgeExpiredFallbackEntries();
    const serialized = JSON.stringify(value);
    if (this.redis) {
      return (await this.redis.set(key, serialized, 'EX', ttlSeconds, 'NX')) === 'OK';
    }

    if (this.fallback.has(key)) {
      return false;
    }
    this.fallback.set(key, {
      value: serialized,
      expiresAt: Date.now() + ttlSeconds * 1000,
    });
    return true;
  }

  private purgeExpiredFallbackEntries(): void {
    if (this.redis || this.fallback.size === 0) {
      return;
    }

    const now = Date.now();
    for (const [key, entry] of this.fallback.entries()) {
      if (entry.expiresAt <= now) {
        this.fallback.delete(key);
      }
    }
  }

  async onModuleDestroy(): Promise<void> {
    if (this.redis) {
      await this.redis.quit();
    }
  }
}
