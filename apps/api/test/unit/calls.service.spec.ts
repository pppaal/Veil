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

function createFixture(call: CallRow | null) {
  const emitted: Emitted[] = [];

  const prisma = {
    callRecord: {
      findUnique: async () => call,
      update: async ({ data }: { data: Record<string, unknown> }) => {
        if (call) Object.assign(call, data);
        return call;
      },
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

  const service = new CallsService(prisma as never, realtime as never);
  return { service, emitted };
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
