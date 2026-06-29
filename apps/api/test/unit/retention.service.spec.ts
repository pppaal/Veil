import { RetentionService } from '../../src/modules/retention/retention.service';

type DeleteArgs = { where: Record<string, unknown> };

const makeService = (retentionDays: number) => {
  const deleteCalls: DeleteArgs[] = [];
  let deleteResult = { count: 0 };
  const prisma = {
    callRecord: {
      deleteMany: (args: DeleteArgs) => {
        deleteCalls.push(args);
        return Promise.resolve(deleteResult);
      },
    },
  } as never;
  const config = { callRecordRetentionDays: retentionDays } as never;
  const logs: Array<[string, Record<string, unknown>]> = [];
  const logger = {
    info: (e: string, m: Record<string, unknown>) => logs.push([e, m]),
    warn: (e: string, m: Record<string, unknown>) => logs.push([e, m]),
    error() {},
  } as never;

  const service = new RetentionService(prisma, config, logger);
  return {
    service,
    deleteCalls,
    logs,
    setDeleteResult: (count: number) => {
      deleteResult = { count };
    },
  };
};

describe('RetentionService', () => {
  it('prunes only terminal call records older than the retention cutoff', async () => {
    const { service, deleteCalls } = makeService(30);
    const before = Date.now();

    await service.sweep();

    expect(deleteCalls).toHaveLength(1);
    const where = deleteCalls[0].where as {
      startedAt: { lt: Date };
      status: { in: string[] };
    };
    // In-flight calls (ringing/active) must be excluded.
    expect(where.status.in).toEqual(['ended', 'missed', 'declined']);
    expect(where.status.in).not.toContain('ringing');
    expect(where.status.in).not.toContain('active');

    // Cutoff is ~30 days ago.
    const cutoffMs = where.startedAt.lt.getTime();
    const expected = before - 30 * 24 * 60 * 60 * 1000;
    expect(Math.abs(cutoffMs - expected)).toBeLessThan(5_000);
  });

  it('does nothing when retention is disabled (0 days)', async () => {
    const { service, deleteCalls } = makeService(0);
    await service.sweep();
    expect(deleteCalls).toHaveLength(0);
  });

  it('logs a count-only line when records are pruned (no conversation/device ids)', async () => {
    const { service, logs, setDeleteResult } = makeService(30);
    setDeleteResult(4);

    await service.sweep();

    const pruned = logs.find(([event]) => event === 'retention.call_records_pruned');
    expect(pruned).toBeDefined();
    expect(pruned![1]).toEqual({ count: 4, retentionDays: 30 });
    // The log must not leak the metadata being deleted.
    expect(JSON.stringify(pruned![1])).not.toMatch(/conversation|device|user/i);
  });

  it('swallows sweep failures so the timer never throws', async () => {
    const prisma = {
      callRecord: {
        deleteMany: () => Promise.reject(new Error('db down')),
      },
    } as never;
    const config = { callRecordRetentionDays: 30 } as never;
    const warns: Array<[string, Record<string, unknown>]> = [];
    const logger = {
      info() {},
      warn: (e: string, m: Record<string, unknown>) => warns.push([e, m]),
      error() {},
    } as never;
    const service = new RetentionService(prisma, config, logger);

    await expect(service.sweep()).resolves.toBeUndefined();
    expect(warns[0][0]).toBe('retention.call_records_sweep_failed');
  });
});
