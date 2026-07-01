import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';

import { SafetyService } from '../../src/modules/safety/safety.service';

const USER = 'user-1';

// Minimal prisma surface; each test supplies only what its path touches.
function make(overrides: Record<string, unknown>) {
  return new SafetyService(overrides as never);
}

describe('SafetyService.block', () => {
  it('rejects blocking yourself', async () => {
    await expect(make({}).block(USER, USER)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects blocking a user that does not exist', async () => {
    const svc = make({ user: { findUnique: async () => null } });
    await expect(svc.block(USER, 'ghost')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('upserts a block for a real target', async () => {
    const svc = make({
      user: { findUnique: async () => ({ id: 'u2', handle: 'bob', displayName: 'Bob' }) },
      userBlock: { upsert: async () => ({ createdAt: new Date('2026-05-01T00:00:00.000Z') }) },
    });
    const res = await svc.block(USER, 'u2');
    expect(res.blocked).toMatchObject({ userId: 'u2', handle: 'bob' });
  });
});

describe('SafetyService.fileReport', () => {
  const dto = (over: Record<string, unknown> = {}) =>
    ({ reportedUserId: 'u2', reason: 'spam', ...over }) as never;

  it('rejects reporting yourself', async () => {
    await expect(make({}).fileReport(USER, dto({ reportedUserId: USER }))).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('rejects reporting a user that does not exist', async () => {
    const svc = make({ user: { findUnique: async () => null } });
    await expect(svc.fileReport(USER, dto())).rejects.toBeInstanceOf(NotFoundException);
  });

  it('requires conversation membership when a conversationId is given', async () => {
    const svc = make({
      user: { findUnique: async () => ({ id: 'u2' }) },
      conversationMember: { findUnique: async () => null },
    });
    await expect(svc.fileReport(USER, dto({ conversationId: 'c1' }))).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('files a report for a valid target', async () => {
    const svc = make({
      user: { findUnique: async () => ({ id: 'u2' }) },
      abuseReport: {
        create: async () => ({ id: 'r1', createdAt: new Date('2026-05-01T00:00:00.000Z') }),
      },
    });
    const res = await svc.fileReport(USER, dto());
    expect(res.reportId).toBe('r1');
  });
});

describe('SafetyService.setConversationMute', () => {
  it('requires conversation membership', async () => {
    const svc = make({ conversationMember: { findUnique: async () => null } });
    await expect(svc.setConversationMute(USER, 'c1', 60)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('deletes the mute (idempotently) when muted-for is null', async () => {
    let deleted = false;
    const svc = make({
      conversationMember: { findUnique: async () => ({ id: 'm1' }) },
      conversationMute: {
        delete: async () => {
          deleted = true;
          return {};
        },
      },
    });
    const res = await svc.setConversationMute(USER, 'c1', null);
    expect(res.mute).toBeNull();
    expect(deleted).toBe(true);
  });

  it('mutes indefinitely (mutedUntil null) when muted-for is undefined', async () => {
    let captured: { update: { mutedUntil: Date | null } } | null = null;
    const svc = make({
      conversationMember: { findUnique: async () => ({ id: 'm1' }) },
      conversationMute: {
        upsert: async (args: { update: { mutedUntil: Date | null } }) => {
          captured = args;
          return { conversationId: 'c1', mutedUntil: null };
        },
      },
    });
    const res = await svc.setConversationMute(USER, 'c1', undefined);
    expect(res.mute).toEqual({ conversationId: 'c1', mutedUntil: null });
    expect(captured!.update.mutedUntil).toBeNull();
  });

  it('mutes with a future expiry when muted-for is a positive number', async () => {
    const before = Date.now();
    const svc = make({
      conversationMember: { findUnique: async () => ({ id: 'm1' }) },
      conversationMute: {
        upsert: async (args: { update: { mutedUntil: Date } }) => ({
          conversationId: 'c1',
          mutedUntil: args.update.mutedUntil,
        }),
      },
    });
    const res = await svc.setConversationMute(USER, 'c1', 3600);
    const until = new Date(res.mute!.mutedUntil!).getTime();
    expect(until).toBeGreaterThan(before + 3500 * 1000);
    expect(until).toBeLessThan(before + 3700 * 1000);
  });
});

describe('SafetyService.isConversationMutedForUser', () => {
  const build = (mute: unknown) => make({ conversationMute: { findUnique: async () => mute } });

  it('is false when no mute row exists', async () => {
    expect(await build(null).isConversationMutedForUser(USER, 'c1')).toBe(false);
  });

  it('is true for an indefinite mute (mutedUntil null)', async () => {
    expect(await build({ mutedUntil: null }).isConversationMutedForUser(USER, 'c1')).toBe(true);
  });

  it('is true for a future expiry and false for a past one', async () => {
    expect(
      await build({ mutedUntil: new Date(Date.now() + 60_000) }).isConversationMutedForUser(
        USER,
        'c1',
      ),
    ).toBe(true);
    expect(
      await build({ mutedUntil: new Date(Date.now() - 60_000) }).isConversationMutedForUser(
        USER,
        'c1',
      ),
    ).toBe(false);
  });
});

describe('SafetyService.isBlockedEitherWay', () => {
  it('is true when a block exists in either direction, false otherwise', async () => {
    expect(
      await make({
        userBlock: { findFirst: async () => ({ blockerUserId: 'x' }) },
      }).isBlockedEitherWay('a', 'b'),
    ).toBe(true);
    expect(
      await make({ userBlock: { findFirst: async () => null } }).isBlockedEitherWay('a', 'b'),
    ).toBe(false);
  });
});
