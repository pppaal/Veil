import { randomUUID } from 'node:crypto';

import { GATEWAY_OPTIONS } from '@nestjs/websockets/constants';

import { ConversationAccessService } from '../../common/conversation-access/conversation-access.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import { FakeSafetyService } from '../../../test/support/fake-services';
import {
  CALL_SIGNAL_MAX_DATA_LENGTH,
  MAX_INBOUND_FRAME_BYTES,
  RealtimeGateway,
} from './realtime.gateway';

type Emitted = { userId: string; event: string; payload: unknown };

// A gateway wired to the in-memory fakes with fan-out captured instead of
// sent over socket.io.
function buildGateway(
  overrides: {
    jwtService?: unknown;
    config?: unknown;
    prisma?: unknown;
    ephemeralStore?: unknown;
  } = {},
) {
  const prisma = new FakePrismaService();
  const safety = new FakeSafetyService();
  const gw = new RealtimeGateway(
    (overrides.jwtService ?? null) as never,
    (overrides.config ?? null) as never,
    (overrides.prisma ?? prisma) as never,
    (overrides.ephemeralStore ?? null) as never,
    { wsConnectionsActive: { inc: () => undefined, dec: () => undefined } } as never,
    new ConversationAccessService(prisma as never, safety as never),
  );
  const emitted: Emitted[] = [];
  (
    gw as unknown as { emitToUser: (userId: string, event: string, payload: unknown) => void }
  ).emitToUser = (userId, event, payload) => emitted.push({ userId, event, payload });
  return { gw, prisma, safety, emitted };
}

const socket = (data: { userId?: string; deviceId?: string; handle?: string }) =>
  ({ id: `socket-${randomUUID()}`, data }) as never;

// shouldThrottleTyping gates fan-out of typing.start/typing.stop to once per
// 500ms per (socket, conversation). Without it a fast typer fans out N
// events per keystroke.
describe('RealtimeGateway typing throttle', () => {
  type Exposed = { shouldThrottleTyping: (socketId: string, conversationId: string) => boolean };
  let gw: Exposed;

  beforeEach(() => {
    gw = buildGateway().gw as unknown as Exposed;
  });

  it('lets the first call through and throttles the next call inside 500ms', () => {
    expect(gw.shouldThrottleTyping('s1', 'c1')).toBe(false);
    expect(gw.shouldThrottleTyping('s1', 'c1')).toBe(true);
  });

  it('throttles per (socket, conversation) so two conversations are independent', () => {
    expect(gw.shouldThrottleTyping('s1', 'c1')).toBe(false);
    expect(gw.shouldThrottleTyping('s1', 'c2')).toBe(false);
    expect(gw.shouldThrottleTyping('s1', 'c1')).toBe(true);
    expect(gw.shouldThrottleTyping('s1', 'c2')).toBe(true);
  });

  it('lets the next call through after 500ms', async () => {
    expect(gw.shouldThrottleTyping('s1', 'c1')).toBe(false);
    expect(gw.shouldThrottleTyping('s1', 'c1')).toBe(true);
    await new Promise((resolve) => setTimeout(resolve, 520));
    expect(gw.shouldThrottleTyping('s1', 'c1')).toBe(false);
  });
});

describe('RealtimeGateway typing relay', () => {
  function directChat() {
    const fixture = buildGateway();
    const alice = fixture.prisma.seedUser('alice');
    const bob = fixture.prisma.seedUser('bob');
    const conversationId = fixture.prisma.seedConversation('direct', [alice.userId, bob.userId]);
    const typingFrom = (user: { userId: string; deviceId: string }, handle: string) =>
      socket({ userId: user.userId, deviceId: user.deviceId, handle });
    return { ...fixture, alice, bob, conversationId, typingFrom };
  }

  it('member relayed, not echoed', async () => {
    const { gw, prisma, emitted, alice, bob, typingFrom } = directChat();
    const carol = prisma.seedUser('carol');
    const groupId = prisma.seedConversation('group', [alice.userId, bob.userId, carol.userId]);

    await gw.handleTypingStart(typingFrom(alice, 'alice'), { conversationId: groupId });

    expect(emitted).toEqual([
      {
        userId: bob.userId,
        event: 'typing.start',
        payload: { conversationId: groupId, userId: alice.userId, handle: 'alice' },
      },
      {
        userId: carol.userId,
        event: 'typing.start',
        payload: { conversationId: groupId, userId: alice.userId, handle: 'alice' },
      },
    ]);
  });

  it('relays typing.stop through the same policy', async () => {
    const { gw, emitted, alice, bob, conversationId, typingFrom } = directChat();

    await gw.handleTypingStop(typingFrom(alice, 'alice'), { conversationId });

    expect(emitted.map((e) => [e.userId, e.event])).toEqual([[bob.userId, 'typing.stop']]);
  });

  it('non-member typing emits nothing', async () => {
    const { gw, prisma, emitted, conversationId, typingFrom } = directChat();
    const mallory = prisma.seedUser('mallory');

    await gw.handleTypingStart(typingFrom(mallory, 'mallory'), { conversationId });

    expect(emitted).toEqual([]);
  });

  it('blocked peer typing emits nothing', async () => {
    const { gw, safety, emitted, alice, bob, conversationId, typingFrom } = directChat();
    safety.setBlocked(bob.userId, alice.userId);

    await gw.handleTypingStart(typingFrom(alice, 'alice'), { conversationId });

    expect(emitted).toEqual([]);
  });

  it('channel subscriber typing emits nothing', async () => {
    const { gw, prisma, emitted, typingFrom } = directChat();
    const owner = prisma.seedUser('owner');
    const subscriber = prisma.seedUser('subscriber');
    const channelId = prisma.seedConversation('channel', [
      { userId: owner.userId, role: 'owner' },
      { userId: subscriber.userId, role: 'subscriber' },
    ]);

    await gw.handleTypingStart(typingFrom(subscriber, 'subscriber'), {
      conversationId: channelId,
    });

    expect(emitted).toEqual([]);
  });

  it('invalid UUID no prisma call', async () => {
    const { gw, prisma, emitted, alice, typingFrom } = directChat();
    const findUnique = jest.spyOn(prisma.conversationMember, 'findUnique');
    const findMany = jest.spyOn(prisma.conversationMember, 'findMany');

    for (const conversationId of ['conv-1', 42, undefined, { $ne: null }]) {
      await gw.handleTypingStart(typingFrom(alice, 'alice'), { conversationId });
    }

    expect(findUnique).not.toHaveBeenCalled();
    expect(findMany).not.toHaveBeenCalled();
    expect(emitted).toEqual([]);
  });

  it('records the typing throttle only for conversations the caller may type in', async () => {
    const { gw, alice, typingFrom } = directChat();
    const throttled = (
      gw as unknown as { typingRateLimitBySocket: Map<string, Map<string, number>> }
    ).typingRateLimitBySocket;
    const client = typingFrom(alice, 'alice') as { id: string };

    for (let i = 0; i < 10; i += 1) {
      await gw.handleTypingStart(client as never, { conversationId: randomUUID() });
    }

    expect(throttled.get(client.id)?.size ?? 0).toBe(0);
  });
});

// The WS handshake must mirror the HTTP JWT guard: a locked/revoked user
// holding a still-valid access token must not get a realtime channel, the
// token travels only in the handshake auth payload, and a socket does not
// outlive its token.
describe('RealtimeGateway handshake', () => {
  const buildClient = (
    handshake: { auth?: Record<string, unknown>; query?: Record<string, unknown> },
    disconnect: () => void,
  ) =>
    ({
      id: `socket-${randomUUID()}`,
      connected: true,
      data: {},
      handshake: { headers: { origin: 'https://app.veil' }, auth: {}, query: {}, ...handshake },
      disconnect,
    }) as never;

  const handshakeGateway = (
    userStatus: 'active' | 'locked' | 'revoked',
    expiresInSeconds = 3600,
  ) => {
    const verifyAsync = jest.fn(async () => ({
      sub: 'u1',
      deviceId: 'd1',
      handle: 'alice',
      jti: 'j1',
      exp: Math.floor(Date.now() / 1000) + expiresInSeconds,
    }));
    const { gw } = buildGateway({
      jwtService: { verifyAsync },
      config: { isOriginAllowed: () => true, jwtSecret: 's', jwtAudience: 'a', jwtIssuer: 'i' },
      prisma: {
        device: {
          findUnique: async () => ({
            id: 'd1',
            userId: 'u1',
            isActive: true,
            revokedAt: null,
            user: { status: userStatus },
          }),
        },
      },
      ephemeralStore: { getJson: async () => null },
    });
    return { gw, verifyAsync };
  };

  afterEach(() => {
    jest.useRealTimers();
  });

  it.each(['locked', 'revoked'] as const)('disconnects a %s user mid-token', async (status) => {
    let disconnected = false;
    const { gw } = handshakeGateway(status);
    await gw.handleConnection(buildClient({ auth: { token: 'tok' } }, () => (disconnected = true)));
    expect(disconnected).toBe(true);
    expect(gw.connectedDeviceIdsForUser('u1')).toEqual([]);
  });

  it('query-string token rejected', async () => {
    let disconnected = false;
    const { gw, verifyAsync } = handshakeGateway('active');

    await gw.handleConnection(
      buildClient({ query: { token: 'tok' } }, () => (disconnected = true)),
    );

    expect(disconnected).toBe(true);
    expect(verifyAsync).not.toHaveBeenCalled();
    expect(gw.hasConnectedUser('u1')).toBe(false);
  });

  it('socket disconnected at token exp', async () => {
    jest.useFakeTimers();
    const disconnect = jest.fn();
    const { gw } = handshakeGateway('active', 120);

    await gw.handleConnection(buildClient({ auth: { token: 'tok' } }, disconnect));
    expect(gw.hasConnectedUser('u1')).toBe(true);
    expect(disconnect).not.toHaveBeenCalled();

    jest.advanceTimersByTime(119_000);
    expect(disconnect).not.toHaveBeenCalled();
    jest.advanceTimersByTime(1_000);
    expect(disconnect).toHaveBeenCalledWith(true);
  });

  it('clears the expiry timer when the socket disconnects first', async () => {
    jest.useFakeTimers();
    const disconnect = jest.fn();
    const { gw } = handshakeGateway('active', 120);
    const client = buildClient({ auth: { token: 'tok' } }, disconnect);

    await gw.handleConnection(client);
    gw.handleDisconnect(client);

    expect(jest.getTimerCount()).toBe(0);
  });

  it('never registers a socket that disconnected during the handshake', async () => {
    jest.useFakeTimers();
    const { gw } = handshakeGateway('active', 120);
    const client = buildClient({ auth: { token: 'tok' } }, jest.fn()) as unknown as {
      connected: boolean;
    };

    const connecting = gw.handleConnection(client as never);
    client.connected = false;
    gw.handleDisconnect(client as never);
    await connecting;

    expect(gw.hasConnectedUser('u1')).toBe(false);
    expect(gw.connectedDeviceIdsForUser('u1')).toEqual([]);
    expect(jest.getTimerCount()).toBe(0);
  });

  it('disconnectUser drops every live socket for a user', () => {
    const { gw } = handshakeGateway('active');
    const disconnects: string[] = [];
    const sockets = new Map<string, { disconnect: () => void }>([
      ['s1', { disconnect: () => disconnects.push('s1') }],
      ['s2', { disconnect: () => disconnects.push('s2') }],
    ]);
    (gw as unknown as { server: unknown }).server = { sockets: { sockets } } as never;
    (gw as unknown as { socketsByUserId: Map<string, Set<string>> }).socketsByUserId.set(
      'u1',
      new Set(['s1', 's2']),
    );
    expect(gw.disconnectUser('u1')).toBe(2);
    expect(disconnects.sort()).toEqual(['s1', 's2']);
    expect(gw.disconnectUser('nobody')).toBe(0);
  });
});

// call.signal relays opaque WebRTC SDP/ICE blobs between the two parties of a
// call. The sender must be allowed to call in the call's conversation; the
// server never inspects or stores the `data` payload.
describe('RealtimeGateway call.signal relay', () => {
  function callFixture(overrides: Parameters<typeof buildGateway>[0] = {}) {
    const fixture = buildGateway(overrides);
    const alice = fixture.prisma.seedUser('alice');
    const bob = fixture.prisma.seedUser('bob');
    const conversationId = fixture.prisma.seedConversation('direct', [alice.userId, bob.userId]);
    const callId = randomUUID();
    fixture.prisma.callRecords.push({
      id: callId,
      conversationId,
      initiatorDeviceId: alice.deviceId,
      callType: 'voice',
      status: 'ringing',
      startedAt: new Date(),
      endedAt: null,
      duration: null,
    });
    return { ...fixture, alice, bob, callId };
  }

  it('relays a signal from a member to the peer, never echoing back to the sender', async () => {
    const { gw, emitted, alice, bob, callId } = callFixture();

    await gw.handleCallSignal(socket({ userId: alice.userId, deviceId: alice.deviceId }), {
      callId,
      kind: 'offer',
      data: 'opaque-sdp',
    });

    expect(emitted).toEqual([
      {
        userId: bob.userId,
        event: 'call.signal',
        payload: {
          callId,
          kind: 'offer',
          data: 'opaque-sdp',
          fromUserId: alice.userId,
          fromDeviceId: alice.deviceId,
        },
      },
    ]);
  });

  it('drops a signal from a non-member', async () => {
    const { gw, prisma, emitted, callId } = callFixture();
    const stranger = prisma.seedUser('stranger');

    await gw.handleCallSignal(socket({ userId: stranger.userId, deviceId: stranger.deviceId }), {
      callId,
      kind: 'ice',
      data: 'opaque-ice',
    });

    expect(emitted).toEqual([]);
  });

  it('drops a signal between a blocked pair', async () => {
    const { gw, safety, emitted, alice, bob, callId } = callFixture();
    safety.setBlocked(bob.userId, alice.userId);

    await gw.handleCallSignal(socket({ userId: alice.userId, deviceId: alice.deviceId }), {
      callId,
      kind: 'ice',
      data: 'opaque-ice',
    });

    expect(emitted).toEqual([]);
  });

  it('drops a signal when the call does not exist', async () => {
    const { gw, emitted, alice } = callFixture();

    await gw.handleCallSignal(socket({ userId: alice.userId, deviceId: alice.deviceId }), {
      callId: randomUUID(),
      kind: 'answer',
      data: 'opaque',
    });

    expect(emitted).toEqual([]);
  });

  it.each(['ended', 'declined', 'missed'])(
    'drops a signal for a call that is %s',
    async (status) => {
      const { gw, prisma, emitted, alice, callId } = callFixture();
      prisma.callRecords[0].status = status as never;

      await gw.handleCallSignal(socket({ userId: alice.userId, deviceId: alice.deviceId }), {
        callId,
        kind: 'ice',
        data: 'opaque-ice',
      });

      expect(emitted).toEqual([]);
    },
  );

  it('relays a signal for an active call', async () => {
    const { gw, prisma, emitted, alice, bob, callId } = callFixture();
    prisma.callRecords[0].status = 'active' as never;

    await gw.handleCallSignal(socket({ userId: alice.userId, deviceId: alice.deviceId }), {
      callId,
      kind: 'ice',
      data: 'opaque-ice',
    });

    expect(emitted.map((event) => event.userId)).toEqual([bob.userId]);
  });

  it('drops an oversized signal without touching prisma', async () => {
    const { gw, prisma, emitted, alice, callId } = callFixture();
    const findCall = jest.spyOn(prisma.callRecord, 'findUnique');

    await gw.handleCallSignal(socket({ userId: alice.userId, deviceId: alice.deviceId }), {
      callId,
      kind: 'offer',
      data: 'x'.repeat(CALL_SIGNAL_MAX_DATA_LENGTH + 1),
    });

    expect(findCall).not.toHaveBeenCalled();
    expect(emitted).toEqual([]);
  });

  it('limits each device to a burst of events, refilled over time', async () => {
    jest.useFakeTimers({ now: new Date('2026-11-12T10:00:00.000Z') });
    try {
      const { gw, prisma, emitted, alice, bob, callId } = callFixture();
      const findCall = jest.spyOn(prisma.callRecord, 'findUnique');
      const signal = (client: unknown) =>
        gw.handleCallSignal(client as never, { callId, kind: 'ice', data: 'opaque-ice' });
      // Two sockets of one device share the budget.
      const first = socket({ userId: alice.userId, deviceId: alice.deviceId });
      const second = socket({ userId: alice.userId, deviceId: alice.deviceId });

      for (let i = 0; i < 20; i += 1) await signal(first);
      for (let i = 0; i < 10; i += 1) await signal(second);
      expect(emitted).toHaveLength(30);
      expect(findCall).toHaveBeenCalledTimes(30);

      await signal(first);
      await gw.handleTypingStart(
        socket({ userId: alice.userId, deviceId: alice.deviceId, handle: 'alice' }),
        { conversationId: prisma.callRecords[0].conversationId },
      );
      expect(emitted).toHaveLength(30);
      expect(findCall).toHaveBeenCalledTimes(30);

      // Another device has its own budget.
      await gw.handleCallSignal(socket({ userId: bob.userId, deviceId: bob.deviceId }), {
        callId,
        kind: 'ice',
        data: 'opaque-ice',
      });
      expect(emitted).toHaveLength(31);

      jest.advanceTimersByTime(1000);
      for (let i = 0; i < 6; i += 1) await signal(first);
      expect(emitted).toHaveLength(36);
    } finally {
      jest.useRealTimers();
    }
  });

  it('drops a signal with an unknown kind without touching prisma', async () => {
    const { gw, prisma, emitted, alice, callId } = callFixture();
    const findCall = jest.spyOn(prisma.callRecord, 'findUnique');

    await gw.handleCallSignal(socket({ userId: alice.userId, deviceId: alice.deviceId }), {
      callId,
      kind: 'bogus' as never,
      data: 'opaque',
    });

    expect(findCall).not.toHaveBeenCalled();
    expect(emitted).toEqual([]);
  });

  // A gateway whose handshake signs Alice's device in, so a test can open and
  // close her sockets through handleConnection and handleDisconnect.
  function connectingCallFixture() {
    let claims = { sub: '', deviceId: '', handle: 'alice' };
    const fixture = callFixture({
      jwtService: {
        verifyAsync: async () => ({
          ...claims,
          jti: randomUUID(),
          exp: Math.floor(Date.now() / 1000) + 3600,
        }),
      },
      config: { isOriginAllowed: () => true, jwtSecret: 's', jwtAudience: 'a', jwtIssuer: 'i' },
      ephemeralStore: { getJson: async () => null },
    });
    claims = { sub: fixture.alice.userId, deviceId: fixture.alice.deviceId, handle: 'alice' };
    const connect = async () => {
      const client = {
        id: `socket-${randomUUID()}`,
        connected: true,
        data: {} as Record<string, unknown>,
        handshake: { headers: { origin: 'https://app.veil' }, auth: { token: 'tok' }, query: {} },
        disconnect: jest.fn(),
      };
      await fixture.gw.handleConnection(client as never);
      expect(client.data.deviceId).toBe(fixture.alice.deviceId);
      return client;
    };
    const signals = () => fixture.emitted.filter((event) => event.event === 'call.signal');
    const budgets = () =>
      (fixture.gw as unknown as { eventBudgetByDevice: Map<string, unknown> }).eventBudgetByDevice;
    return { ...fixture, connect, signals, budgets };
  }

  // A device that has spent its budget used to get a fresh burst of 30 as soon
  // as its last socket closed, so a connect, send 30, disconnect loop relayed
  // about 18 MB/s of call signals to the peer.
  it("keeps a device's spent budget when its only socket disconnects and it reconnects", async () => {
    jest.useFakeTimers({ now: new Date('2026-11-12T10:00:00.000Z') });
    try {
      const { gw, prisma, alice, callId, connect, signals } = connectingCallFixture();
      const findCall = jest.spyOn(prisma.callRecord, 'findUnique');
      const signal = (client: unknown) =>
        gw.handleCallSignal(client as never, { callId, kind: 'ice', data: 'opaque-ice' });

      const first = await connect();
      for (let i = 0; i < 30; i += 1) await signal(first);
      expect(signals()).toHaveLength(30);
      expect(findCall).toHaveBeenCalledTimes(30);

      gw.handleDisconnect(first as never);
      expect(gw.hasConnectedDevice(alice.deviceId)).toBe(false);

      for (let round = 0; round < 5; round += 1) {
        const again = await connect();
        await signal(again);
        await gw.handleTypingStart(again as never, {
          conversationId: prisma.callRecords[0].conversationId,
        });
        gw.handleDisconnect(again as never);
      }
      expect(signals()).toHaveLength(30);
      expect(findCall).toHaveBeenCalledTimes(30);

      // The bucket refills at 5 a second whether or not a socket is open.
      const reconnected = await connect();
      jest.advanceTimersByTime(1000);
      for (let i = 0; i < 6; i += 1) await signal(reconnected);
      expect(signals()).toHaveLength(35);
      expect(findCall).toHaveBeenCalledTimes(35);
    } finally {
      jest.useRealTimers();
    }
  });

  it('drops a budget once it has refilled, so disconnected devices do not pile up', async () => {
    jest.useFakeTimers({ now: new Date('2026-11-12T10:00:00.000Z') });
    try {
      const { gw, alice, callId, connect, budgets } = connectingCallFixture();
      const signalFrom = (deviceId: string) =>
        gw.handleCallSignal(socket({ userId: randomUUID(), deviceId }), {
          callId,
          kind: 'ice',
          data: 'opaque-ice',
        });

      // A budget that has refilled by the time the last socket closes goes at
      // once; one that has not stays until it has.
      const client = await connect();
      await gw.handleCallSignal(client as never, { callId, kind: 'ice', data: 'opaque-ice' });
      gw.handleDisconnect(client as never);
      expect(budgets().has(alice.deviceId)).toBe(true);
      const refilledClient = await connect();
      jest.advanceTimersByTime(200);
      gw.handleDisconnect(refilledClient as never);
      expect(budgets().has(alice.deviceId)).toBe(false);

      // Devices that sent an event and went away are swept once their
      // buckets have refilled.
      const gone = Array.from({ length: 50 }, () => randomUUID());
      for (const deviceId of gone) await signalFrom(deviceId);
      expect(budgets().size).toBe(50);
      jest.advanceTimersByTime(6_000);
      const last = randomUUID();
      await signalFrom(last);
      expect([...budgets().keys()]).toEqual([last]);
    } finally {
      jest.useRealTimers();
    }
  });

  // socket.io closes a connection whose frame is larger than this before any
  // handler runs. Without it the limit is 1 MB a frame.
  it('caps the inbound socket frame size in the gateway options', () => {
    const options = Reflect.getMetadata(GATEWAY_OPTIONS, RealtimeGateway) as {
      maxHttpBufferSize?: number;
    };
    expect(options.maxHttpBufferSize).toBe(MAX_INBOUND_FRAME_BYTES);
    expect(MAX_INBOUND_FRAME_BYTES).toBe(128 * 1024);
    expect(MAX_INBOUND_FRAME_BYTES).toBeGreaterThan(CALL_SIGNAL_MAX_DATA_LENGTH);
  });
});
