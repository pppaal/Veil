import { CallsService } from '../../src/modules/calls/calls.service';

// These specs exercise the accept/decline state machine with plain in-memory
// fakes (no DB, no generated prisma client). The fake prisma only implements
// the narrow surface CallsService touches for these two methods.

type CallRow = {
  id: string;
  conversationId: string;
  status: string;
  startedAt: Date;
  endedAt: Date | null;
  duration: number | null;
  conversation: { members: Array<{ userId: string }> };
  initiatorDevice: { userId: string } | null;
};

type Emitted = { event: string; members: Array<{ userId: string }>; payload: unknown };

function createFixture(
  call: CallRow | null,
  opts: {
    conversation?: { type: string; members: Array<{ userId: string }> } | null;
    blocked?: boolean;
  } = {},
) {
  const emitted: Emitted[] = [];
  const created: Array<Record<string, unknown>> = [];

  const prisma = {
    callRecord: {
      findUnique: async () => call,
      update: async ({ data }: { data: Record<string, unknown> }) => {
        if (call) Object.assign(call, data);
        return call;
      },
      create: async ({ data }: { data: Record<string, unknown> }) => {
        const row = { id: 'new-call', ...data };
        created.push(row);
        return row;
      },
    },
    conversation: {
      findUnique: async () => opts.conversation ?? null,
    },
    user: {
      findUnique: async () => ({ handle: 'caller' }),
    },
  };

  const realtime = {
    emitConversationMembers: (
      members: Array<{ userId: string }>,
      event: string,
      payload: unknown,
    ) => {
      emitted.push({ event, members, payload });
    },
  };

  const safety = {
    isBlockedEitherWay: async () => opts.blocked ?? false,
  };

  const service = new CallsService(prisma as never, realtime as never, safety as never);
  return { service, emitted, created };
}

function ringingCall(): CallRow {
  return {
    id: 'call-1',
    conversationId: 'conv-1',
    status: 'ringing',
    startedAt: new Date(),
    endedAt: null,
    duration: null,
    conversation: { members: [{ userId: 'user-a' }, { userId: 'user-b' }] },
    // user-a initiated; user-b is the callee.
    initiatorDevice: { userId: 'user-a' },
  };
}

describe('CallsService initiateCall block enforcement', () => {
  const directConv = { type: 'direct', members: [{ userId: 'user-a' }, { userId: 'user-b' }] };
  const dto = { conversationId: 'conv-1', callType: 'voice' } as never;

  it('rings the peer when not blocked', async () => {
    const { service, emitted, created } = createFixture(null, {
      conversation: directConv,
      blocked: false,
    });

    await service.initiateCall({ userId: 'user-a', deviceId: 'dev-a' }, dto);

    expect(created).toHaveLength(1);
    expect(emitted).toHaveLength(1);
    expect(emitted[0].event).toBe('call.incoming');
    // Fan-out excludes the initiator.
    expect(emitted[0].members).toEqual([{ userId: 'user-b' }]);
  });

  it('refuses to ring a blocked peer and creates no call record', async () => {
    const { service, created, emitted } = createFixture(null, {
      conversation: directConv,
      blocked: true,
    });

    await expect(
      service.initiateCall({ userId: 'user-a', deviceId: 'dev-a' }, dto),
    ).rejects.toMatchObject({ response: { code: 'peer_unreachable' } });
    expect(created).toHaveLength(0);
    expect(emitted).toHaveLength(0);
  });

  it('rejects a non-member initiator', async () => {
    const { service } = createFixture(null, { conversation: directConv, blocked: false });
    await expect(
      service.initiateCall({ userId: 'stranger', deviceId: 'dev-x' }, dto),
    ).rejects.toMatchObject({ response: { code: 'conversation_membership_required' } });
  });

  it('does not apply the block gate to group calls (direct-only)', async () => {
    const groupConv = {
      type: 'group',
      members: [{ userId: 'user-a' }, { userId: 'user-b' }, { userId: 'user-c' }],
    };
    // blocked=true must be ignored for a group conversation.
    const { service, created } = createFixture(null, { conversation: groupConv, blocked: true });

    await service.initiateCall({ userId: 'user-a', deviceId: 'dev-a' }, dto);
    expect(created).toHaveLength(1);
  });
});

describe('CallsService accept/decline', () => {
  describe('acceptCall', () => {
    it('transitions ringing -> active and emits call.accepted', async () => {
      const call = ringingCall();
      const { service, emitted } = createFixture(call);

      const result = await service.acceptCall({ userId: 'user-b' }, 'call-1');

      expect(result.status).toBe('active');
      expect(call.status).toBe('active');
      expect(emitted).toHaveLength(1);
      expect(emitted[0].event).toBe('call.accepted');
      expect(emitted[0].payload).toEqual({ callId: 'call-1', conversationId: 'conv-1' });
    });

    it('rejects a non-member', async () => {
      const { service } = createFixture(ringingCall());
      await expect(service.acceptCall({ userId: 'stranger' }, 'call-1')).rejects.toMatchObject({
        response: { code: 'conversation_membership_required' },
      });
    });

    it('rejects the initiator accepting their own call', async () => {
      const { service } = createFixture(ringingCall());
      await expect(service.acceptCall({ userId: 'user-a' }, 'call-1')).rejects.toMatchObject({
        response: { code: 'call_initiator_forbidden' },
      });
    });

    it('rejects accepting a call that is not ringing', async () => {
      const call = ringingCall();
      call.status = 'active';
      const { service } = createFixture(call);
      await expect(service.acceptCall({ userId: 'user-b' }, 'call-1')).rejects.toMatchObject({
        response: { code: 'call_invalid_state' },
      });
    });

    it('rejects when the call is not found', async () => {
      const { service } = createFixture(null);
      await expect(service.acceptCall({ userId: 'user-b' }, 'missing')).rejects.toMatchObject({
        response: { code: 'call_not_found' },
      });
    });
  });

  describe('declineCall', () => {
    it('transitions ringing -> declined and emits call.declined', async () => {
      const call = ringingCall();
      const { service, emitted } = createFixture(call);

      const result = await service.declineCall({ userId: 'user-b' }, 'call-1');

      expect(result.status).toBe('declined');
      expect(call.status).toBe('declined');
      expect(call.endedAt).toBeInstanceOf(Date);
      expect(emitted).toHaveLength(1);
      expect(emitted[0].event).toBe('call.declined');
      expect(emitted[0].payload).toEqual({ callId: 'call-1', conversationId: 'conv-1' });
    });

    it('rejects a non-member', async () => {
      const { service } = createFixture(ringingCall());
      await expect(service.declineCall({ userId: 'stranger' }, 'call-1')).rejects.toMatchObject({
        response: { code: 'conversation_membership_required' },
      });
    });

    it('rejects declining a call that is not ringing', async () => {
      const call = ringingCall();
      call.status = 'ended';
      const { service } = createFixture(call);
      await expect(service.declineCall({ userId: 'user-b' }, 'call-1')).rejects.toMatchObject({
        response: { code: 'call_invalid_state' },
      });
    });

    it('rejects when the call is not found', async () => {
      const { service } = createFixture(null);
      await expect(service.declineCall({ userId: 'user-b' }, 'missing')).rejects.toMatchObject({
        response: { code: 'call_not_found' },
      });
    });
  });
});
