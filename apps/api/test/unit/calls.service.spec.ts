import { randomUUID } from 'node:crypto';

import { ConversationAccessService } from '../../src/common/conversation-access/conversation-access.service';
import { CallsService } from '../../src/modules/calls/calls.service';
import { FakePrismaService } from '../support/fake-prisma.service';
import { FakeRealtimeGateway, FakeSafetyService } from '../support/fake-services';

type CallStatus = 'ringing' | 'active' | 'ended' | 'missed' | 'declined';

// user-a and user-b share a direct conversation; user-a placed the call.
function createFixture() {
  const prisma = new FakePrismaService();
  const realtime = new FakeRealtimeGateway();
  const safety = new FakeSafetyService();
  const service = new CallsService(
    prisma as never,
    realtime as never,
    new ConversationAccessService(prisma as never, safety as never),
  );
  const caller = prisma.seedUser('caller');
  const callee = prisma.seedUser('callee');
  const conversationId = prisma.seedConversation('direct', [caller.userId, callee.userId]);

  const seedCall = (status: CallStatus = 'ringing', startedAt = new Date()) => {
    const callId = randomUUID();
    prisma.callRecords.push({
      id: callId,
      conversationId,
      initiatorDeviceId: caller.deviceId,
      callType: 'voice',
      status,
      startedAt,
      endedAt: status === 'ringing' || status === 'active' ? null : new Date(),
      duration: status === 'ended' ? 42 : null,
    });
    return callId;
  };

  return { prisma, realtime, safety, service, caller, callee, conversationId, seedCall };
}

describe('CallsService initiateCall', () => {
  it('rings the peer when not blocked', async () => {
    const { service, prisma, realtime, caller, callee, conversationId } = createFixture();

    const result = await service.initiateCall(caller, { conversationId, callType: 'voice' });

    expect(result.status).toBe('ringing');
    expect(prisma.callRecords).toHaveLength(1);
    // Fan-out excludes the initiator.
    expect(realtime.emitted.map((e) => [e.userId, e.event])).toEqual([
      [callee.userId, 'call.incoming'],
    ]);
  });

  it('refuses to ring a blocked peer and creates no call record', async () => {
    const { service, prisma, realtime, safety, caller, callee, conversationId } = createFixture();
    safety.setBlocked(callee.userId, caller.userId);

    await expect(
      service.initiateCall(caller, { conversationId, callType: 'voice' }),
    ).rejects.toMatchObject({ status: 403, response: { code: 'peer_unreachable' } });
    expect(prisma.callRecords).toHaveLength(0);
    expect(realtime.emitted).toHaveLength(0);
  });

  it('rejects a non-member initiator', async () => {
    const { service, prisma, conversationId } = createFixture();
    const stranger = prisma.seedUser('stranger');

    await expect(
      service.initiateCall(stranger, { conversationId, callType: 'voice' }),
    ).rejects.toMatchObject({
      status: 403,
      response: { code: 'conversation_membership_required' },
    });
  });

  it('group initiate 403 call_not_allowed', async () => {
    const { service, prisma, realtime, caller, callee } = createFixture();
    const third = prisma.seedUser('third');
    const groupId = prisma.seedConversation('group', [caller.userId, callee.userId, third.userId]);

    await expect(
      service.initiateCall(caller, { conversationId: groupId, callType: 'video' }),
    ).rejects.toMatchObject({ status: 403, response: { code: 'call_not_allowed' } });
    expect(prisma.callRecords).toHaveLength(0);
    expect(realtime.emitted).toHaveLength(0);
  });

  it('refuses channel calls that would ring every subscriber', async () => {
    const { service, prisma, caller, callee } = createFixture();
    const channelId = prisma.seedConversation('channel', [
      { userId: caller.userId, role: 'owner' },
      { userId: callee.userId, role: 'subscriber' },
    ]);

    await expect(
      service.initiateCall(caller, { conversationId: channelId, callType: 'voice' }),
    ).rejects.toMatchObject({ status: 403, response: { code: 'call_not_allowed' } });
  });
});

describe('CallsService accept/decline', () => {
  describe('acceptCall', () => {
    it('transitions ringing -> active and emits call.accepted', async () => {
      const { service, prisma, realtime, callee, conversationId, seedCall } = createFixture();
      const callId = seedCall();

      const result = await service.acceptCall(callee, callId);

      expect(result).toEqual({ callId, status: 'active' });
      expect(prisma.callRecords[0]?.status).toBe('active');
      expect(realtime.emitted.map((e) => e.event)).toEqual(['call.accepted', 'call.accepted']);
      expect(realtime.emitted[0]?.payload).toEqual({ callId, conversationId });
    });

    it('rejects a non-member', async () => {
      const { service, prisma, seedCall } = createFixture();
      const stranger = prisma.seedUser('stranger');

      await expect(service.acceptCall(stranger, seedCall())).rejects.toMatchObject({
        status: 403,
        response: { code: 'conversation_membership_required' },
      });
    });

    it('rejects the initiator accepting their own call', async () => {
      const { service, caller, seedCall } = createFixture();

      await expect(service.acceptCall(caller, seedCall())).rejects.toMatchObject({
        status: 403,
        response: { code: 'call_initiator_forbidden' },
      });
    });

    it('rejects accepting a call that is not ringing', async () => {
      const { service, callee, seedCall } = createFixture();

      await expect(service.acceptCall(callee, seedCall('active'))).rejects.toMatchObject({
        status: 409,
        response: { code: 'call_invalid_state' },
      });
    });

    it('rejects when the call is not found', async () => {
      const { service, callee } = createFixture();

      await expect(service.acceptCall(callee, randomUUID())).rejects.toMatchObject({
        status: 404,
        response: { code: 'call_not_found' },
      });
    });
  });

  describe('declineCall', () => {
    it('transitions ringing -> declined and emits call.declined', async () => {
      const { service, prisma, realtime, callee, conversationId, seedCall } = createFixture();
      const callId = seedCall();

      const result = await service.declineCall(callee, callId);

      expect(result).toEqual({ callId, status: 'declined' });
      expect(prisma.callRecords[0]?.status).toBe('declined');
      expect(prisma.callRecords[0]?.endedAt).toBeInstanceOf(Date);
      expect(realtime.emitted[0]).toMatchObject({
        event: 'call.declined',
        payload: { callId, conversationId },
      });
    });

    it('rejects a non-member', async () => {
      const { service, prisma, seedCall } = createFixture();
      const stranger = prisma.seedUser('stranger');

      await expect(service.declineCall(stranger, seedCall())).rejects.toMatchObject({
        status: 403,
        response: { code: 'conversation_membership_required' },
      });
    });

    it('rejects declining a call that is not ringing', async () => {
      const { service, callee, seedCall } = createFixture();

      await expect(service.declineCall(callee, seedCall('ended'))).rejects.toMatchObject({
        status: 409,
        response: { code: 'call_invalid_state' },
      });
    });

    it('rejects when the call is not found', async () => {
      const { service, callee } = createFixture();

      await expect(service.declineCall(callee, randomUUID())).rejects.toMatchObject({
        status: 404,
        response: { code: 'call_not_found' },
      });
    });
  });
});

describe('CallsService endCall', () => {
  it('ends an active call with its duration', async () => {
    const { service, prisma, realtime, callee, seedCall } = createFixture();
    const callId = seedCall('active', new Date(Date.now() - 90_000));

    const result = await service.endCall(callee, callId);

    expect(result.status).toBe('ended');
    expect(result.duration).toBeGreaterThanOrEqual(90);
    expect(prisma.callRecords[0]).toMatchObject({ status: 'ended', duration: result.duration });
    expect(realtime.emitted[0]?.event).toBe('call.ended');
  });

  it('lets the caller hang up while still ringing', async () => {
    const { service, caller, seedCall } = createFixture();

    await expect(service.endCall(caller, seedCall('ringing'))).resolves.toMatchObject({
      status: 'ended',
    });
  });

  it('endCall unknown 404 call_not_found', async () => {
    const { service, callee } = createFixture();

    await expect(service.endCall(callee, randomUUID())).rejects.toMatchObject({
      status: 404,
      response: { code: 'call_not_found' },
    });
  });

  it('endCall on declined 409', async () => {
    const { service, prisma, realtime, callee, seedCall } = createFixture();
    const callId = seedCall('declined');

    await expect(service.endCall(callee, callId)).rejects.toMatchObject({
      status: 409,
      response: { code: 'call_invalid_state' },
    });
    expect(prisma.callRecords[0]).toMatchObject({ status: 'declined', duration: null });
    expect(realtime.emitted).toHaveLength(0);
  });

  it.each(['missed', 'ended'] as const)(
    'never recomputes the duration of a %s call',
    async (status) => {
      const { service, prisma, callee, seedCall } = createFixture();
      const callId = seedCall(status, new Date(Date.now() - 3_600_000));
      const durationBefore = prisma.callRecords[0]?.duration;

      await expect(service.endCall(callee, callId)).rejects.toMatchObject({
        status: 409,
        response: { code: 'call_invalid_state' },
      });
      expect(prisma.callRecords[0]?.duration).toBe(durationBefore);
    },
  );

  it('lets a blocked pair still hang up', async () => {
    const { service, safety, caller, callee, seedCall } = createFixture();
    const callId = seedCall('active');
    safety.setBlocked(callee.userId, caller.userId);

    await expect(service.endCall(callee, callId)).resolves.toMatchObject({ status: 'ended' });
  });
});
