import { execFileSync, spawn, type ChildProcess } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// A private Redis server for tests of the commands the ephemeral store sends,
// which the in-memory fakes cannot check. It listens only on a Unix socket in
// its own temporary directory, keeps nothing on disk, and is deleted on stop.
// The binary comes from VEIL_TEST_REDIS_SERVER or `redis-server` on PATH.

export const findRedisServer = (): string | null => {
  const candidates = [process.env.VEIL_TEST_REDIS_SERVER, 'redis-server'].filter(
    (candidate): candidate is string => Boolean(candidate),
  );
  for (const candidate of candidates) {
    try {
      execFileSync(candidate, ['--version'], { stdio: 'pipe' });
      return candidate;
    } catch {
      // Not installed under that name.
    }
  }
  return null;
};

export class ThrowawayRedis {
  private constructor(
    private readonly dir: string,
    private readonly server: ChildProcess,
  ) {}

  /** The socket path; ioredis accepts it in place of a URL. */
  get socketPath(): string {
    return join(this.dir, 'redis.sock');
  }

  static async start(binary: string): Promise<ThrowawayRedis> {
    const dir = mkdtempSync(join(tmpdir(), 'veil-redis-'));
    const server = spawn(
      binary,
      [
        '--port',
        '0',
        '--unixsocket',
        join(dir, 'redis.sock'),
        '--save',
        '',
        '--appendonly',
        'no',
        '--dir',
        dir,
      ],
      { stdio: 'ignore' },
    );
    const redis = new ThrowawayRedis(dir, server);
    const deadline = Date.now() + 10_000;
    while (!existsSync(redis.socketPath)) {
      if (Date.now() > deadline || server.exitCode !== null) {
        redis.stop();
        throw new Error('redis-server did not start');
      }
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    return redis;
  }

  stop(): void {
    this.server.kill('SIGKILL');
    rmSync(this.dir, { recursive: true, force: true });
  }
}
