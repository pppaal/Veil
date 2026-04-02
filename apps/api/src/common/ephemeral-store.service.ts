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
