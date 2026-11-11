import { randomUUID } from 'node:crypto';

import { ConversationAccessService } from '../../common/conversation-access/conversation-access.service';
import { FakePrismaService } from '../../../test/support/fake-prisma.service';
import { FakeSafetyService } from '../../../test/support/fake-services';
import { RealtimeGateway } from './realtime.gateway';

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
  function callFixture() {
    const fixture = buildGateway();
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
});
