import Redis from 'ioredis';

import { RedisThrottlerStorage } from './redis-throttler.storage';
import { createThrottlerOptions } from './throttler-options.factory';

jest.mock('ioredis');

const logger = { warn: jest.fn() } as never;
const configWith = (redisUrl: string | undefined) => ({ redisUrl }) as never;

describe('createThrottlerOptions', () => {
  beforeEach(() => {
    jest.mocked(Redis).mockClear();
  });

  it('counts in process memory without VEIL_REDIS_URL', () => {
    expect(createThrottlerOptions(configWith(undefined), logger)).toEqual({
      throttlers: [{ ttl: 60_000, limit: 60 }],
    });
    expect(Redis).not.toHaveBeenCalled();
  });

  it('shares counters through Redis when VEIL_REDIS_URL is set', () => {
    const options = createThrottlerOptions(configWith('redis://redis:6379'), logger);

    expect(options).toMatchObject({ throttlers: [{ ttl: 60_000, limit: 60 }] });
    expect((options as { storage?: unknown }).storage).toBeInstanceOf(RedisThrottlerStorage);
    // Commands must fail fast during an outage so the storage can fail open
    // instead of queueing requests behind a dead connection.
    expect(Redis).toHaveBeenCalledWith(
      'redis://redis:6379',
      expect.objectContaining({ enableOfflineQueue: false }),
    );
  });
});
