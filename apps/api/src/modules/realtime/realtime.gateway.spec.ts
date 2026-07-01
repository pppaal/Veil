import { RealtimeGateway } from './realtime.gateway';

// shouldThrottleTyping is a private method that gates fan-out of
// typing.start/typing.stop to once per 500ms per (socket, conversation).
// Without it a fast typer fan-outs N events per keystroke.
describe('RealtimeGateway typing throttle', () => {
  let gw: RealtimeGateway;

  beforeEach(() => {
    // Constructor deps aren't exercised by the throttle method; null-cast
    // is fine for this isolated unit.
    gw = new RealtimeGateway(
      null as never,
      null as never,
      null as never,
      null as never,
      null as never,
    );
  });

  it('lets the first call through and throttles the next call inside 500ms', () => {
    const expose = gw as unknown as {
      shouldThrottleTyping: (socketId: string, conversationId: string) => boolean;
    };
    expect(expose.shouldThrottleTyping('s1', 'c1')).toBe(false);
    expect(expose.shouldThrottleTyping('s1', 'c1')).toBe(true);
  });

  it('throttles per (socket, conversation) so two conversations are independent', () => {
    const expose = gw as unknown as {
      shouldThrottleTyping: (socketId: string, conversationId: string) => boolean;
    };
    expect(expose.shouldThrottleTyping('s1', 'c1')).toBe(false);
    expect(expose.shouldThrottleTyping('s1', 'c2')).toBe(false);
    expect(expose.shouldThrottleTyping('s1', 'c1')).toBe(true);
    expect(expose.shouldThrottleTyping('s1', 'c2')).toBe(true);
  });

  it('lets the next call through after 500ms', async () => {
    const expose = gw as unknown as {
      shouldThrottleTyping: (socketId: string, conversationId: string) => boolean;
    };
    expect(expose.shouldThrottleTyping('s1', 'c1')).toBe(false);
    expect(expose.shouldThrottleTyping('s1', 'c1')).toBe(true);
    await new Promise((resolve) => setTimeout(resolve, 520));
    expect(expose.shouldThrottleTyping('s1', 'c1')).toBe(false);
  });
});

// The WS handshake must mirror the HTTP JWT guard's user-status check: a
// locked/revoked user holding a still-valid access token must not get a
// realtime channel.
describe('RealtimeGateway handshake user-status enforcement', () => {
  const buildClient = (disconnect: () => void) =>
    ({
      handshake: { headers: { origin: 'https://app.veil' }, auth: { token: 'tok' }, query: {} },
      disconnect,
    }) as never;

  const buildGateway = (userStatus: 'active' | 'locked' | 'revoked') => {
    const jwtService = {
      verifyAsync: async () => ({ sub: 'u1', deviceId: 'd1', handle: 'alice', jti: 'j1' }),
    } as never;
    const config = {
      isOriginAllowed: () => true,
      jwtSecret: 's',
      jwtAudience: 'a',
      jwtIssuer: 'i',
    } as never;
    const prisma = {
      device: {
        findUnique: async () => ({
          id: 'd1',
          userId: 'u1',
          isActive: true,
          revokedAt: null,
          user: { status: userStatus },
        }),
      },
    } as never;
    const ephemeralStore = { getJson: async () => null } as never;
    const metrics = {
      wsConnectionsActive: { inc: () => undefined, dec: () => undefined },
    } as never;
    return new RealtimeGateway(jwtService, config, prisma, ephemeralStore, metrics);
  };

  it.each(['locked', 'revoked'] as const)('disconnects a %s user mid-token', async (status) => {
    let disconnected = false;
    const gw = buildGateway(status);
    await gw.handleConnection(buildClient(() => (disconnected = true)));
    expect(disconnected).toBe(true);
    // The socket was never registered for fan-out.
    expect(gw.connectedDeviceIdsForUser('u1')).toEqual([]);
  });

  it('disconnectUser drops every live socket for a user', () => {
    const gw = buildGateway('active');
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
// call. The sender must be a member of the call's conversation; the server
// never inspects or stores the `data` payload.
describe('RealtimeGateway call.signal relay', () => {
  type Emitted = { userId: string; event: string; payload: unknown };

  const buildGateway = (members: Array<{ userId: string }> | null) => {
    const prisma = {
      callRecord: {
        findUnique: async () =>
          members === null ? null : { conversationId: 'conv-1', conversation: { members } },
      },
    } as never;
    const gw = new RealtimeGateway(
      null as never,
      null as never,
      prisma,
      null as never,
      null as never,
    );
    const emitted: Emitted[] = [];
    (
      gw as unknown as {
        emitToUser: (userId: string, event: string, payload: unknown) => void;
      }
    ).emitToUser = (userId, event, payload) => emitted.push({ userId, event, payload });
    return { gw, emitted };
  };

  const client = (userId: string | undefined, deviceId: string | undefined) =>
    ({ data: { userId, deviceId } }) as never;

  it('relays a signal from a member to the peer, never echoing back to the sender', async () => {
    const { gw, emitted } = buildGateway([{ userId: 'user-a' }, { userId: 'user-b' }]);

    await gw.handleCallSignal(client('user-a', 'device-a'), {
      callId: 'call-1',
      kind: 'offer',
      data: 'opaque-sdp',
    });

    expect(emitted).toEqual([
      {
        userId: 'user-b',
        event: 'call.signal',
        payload: {
          callId: 'call-1',
          kind: 'offer',
          data: 'opaque-sdp',
          fromUserId: 'user-a',
          fromDeviceId: 'device-a',
        },
      },
    ]);
  });

  it('drops a signal from a non-member', async () => {
    const { gw, emitted } = buildGateway([{ userId: 'user-a' }, { userId: 'user-b' }]);

    await gw.handleCallSignal(client('stranger', 'device-x'), {
      callId: 'call-1',
      kind: 'ice',
      data: 'opaque-ice',
    });

    expect(emitted).toEqual([]);
  });

  it('drops a signal when the call does not exist', async () => {
    const { gw, emitted } = buildGateway(null);

    await gw.handleCallSignal(client('user-a', 'device-a'), {
      callId: 'missing',
      kind: 'answer',
      data: 'opaque',
    });

    expect(emitted).toEqual([]);
  });

  it('drops a signal with an unknown kind without touching prisma', async () => {
    const { gw, emitted } = buildGateway([{ userId: 'user-a' }, { userId: 'user-b' }]);

    await gw.handleCallSignal(client('user-a', 'device-a'), {
      callId: 'call-1',
      kind: 'bogus' as never,
      data: 'opaque',
    });

    expect(emitted).toEqual([]);
  });
});
