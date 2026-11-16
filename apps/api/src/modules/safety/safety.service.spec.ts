import { SafetyService } from './safety.service';

// Minimal mocks. The real SafetyService uses prisma.userBlock.findFirst /
// findMany and prisma.conversationMute.findFirst / findMany, plus
// prisma.abuseReport.create. We hand-roll just the methods each test needs
// because the project's FakePrismaService doesn't model UserBlock yet.
function makePrismaMock(blocks: Array<{ blocker: string; blocked: string }>) {
  return {
    userBlock: {
      findFirst: jest.fn(({ where }) => {
        const or = where?.OR as Array<{ blockerUserId: string; blockedUserId: string }>;
        for (const clause of or ?? []) {
          const hit = blocks.find(
            (b) => b.blocker === clause.blockerUserId && b.blocked === clause.blockedUserId,
          );
          if (hit) return Promise.resolve({ blockerUserId: hit.blocker });
        }
        return Promise.resolve(null);
      }),
    },
  } as never;
}

describe('SafetyService.isBlockedEitherWay', () => {
  const ALICE = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  const BOB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

  it('returns false when no block exists', async () => {
    const svc = new SafetyService(makePrismaMock([]));
    expect(await svc.isBlockedEitherWay(ALICE, BOB)).toBe(false);
  });

  it('returns true when Alice blocked Bob', async () => {
    const svc = new SafetyService(makePrismaMock([{ blocker: ALICE, blocked: BOB }]));
    expect(await svc.isBlockedEitherWay(ALICE, BOB)).toBe(true);
  });

  it('returns true when Bob blocked Alice (symmetric check)', async () => {
    // The asymmetric naming is the whole point of "either way" — direction
    // shouldn't leak which user pulled the trigger.
    const svc = new SafetyService(makePrismaMock([{ blocker: BOB, blocked: ALICE }]));
    expect(await svc.isBlockedEitherWay(ALICE, BOB)).toBe(true);
  });
});

// What MessagesService asks before it wakes a recipient's devices.
describe('SafetyService.isConversationMutedForUser', () => {
  const BOB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  const CONVERSATION = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  const withMute = (mute: { mutedUntil: Date | null } | null) =>
    new SafetyService({
      conversationMute: { findUnique: jest.fn(() => Promise.resolve(mute)) },
    } as never);

  it('is false with no mute, true with no end or an end ahead, false once it ended', async () => {
    expect(await withMute(null).isConversationMutedForUser(BOB, CONVERSATION)).toBe(false);
    expect(await withMute({ mutedUntil: null }).isConversationMutedForUser(BOB, CONVERSATION)).toBe(
      true,
    );
    expect(
      await withMute({ mutedUntil: new Date(Date.now() + 60_000) }).isConversationMutedForUser(
        BOB,
        CONVERSATION,
      ),
    ).toBe(true);
    expect(
      await withMute({ mutedUntil: new Date(Date.now() - 1_000) }).isConversationMutedForUser(
        BOB,
        CONVERSATION,
      ),
    ).toBe(false);
  });
});
