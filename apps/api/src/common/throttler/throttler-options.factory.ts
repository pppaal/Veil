import type { ThrottlerModuleOptions } from '@nestjs/throttler';
import Redis from 'ioredis';

import { AppConfigService } from '../config/app-config.service';
import { AppLoggerService } from '../logger/app-logger.service';
import { RedisThrottlerStorage } from './redis-throttler.storage';

const DEFAULT_THROTTLER = { ttl: 60_000, limit: 60 };

export function createThrottlerOptions(
  config: AppConfigService,
  logger: AppLoggerService,
): ThrottlerModuleOptions {
  if (!config.redisUrl) {
    return { throttlers: [DEFAULT_THROTTLER] };
  }

  const redis = new Redis(config.redisUrl, {
    maxRetriesPerRequest: 1,
    // A rate limiter must not add latency: while Redis is unreachable,
    // commands fail immediately and the storage fails open instead of queueing.
    enableOfflineQueue: false,
  });
  // Connection errors surface through the storage's fail-open warning; an
  // unhandled 'error' event would crash the process.
  redis.on('error', () => undefined);

  return {
    throttlers: [DEFAULT_THROTTLER],
    storage: new RedisThrottlerStorage(redis, logger),
  };
}
