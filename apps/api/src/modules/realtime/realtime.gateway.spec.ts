import { RealtimeGateway } from './realtime.gateway';

// shouldThrottleTyping is a private method that gates fan-out of
// typing.start/typing.stop to once per 500ms per (socket, conversation).
// Without it a fast typer fan-outs N events per keystroke.
describe('RealtimeGateway typing throttle', () => {
  let gw: RealtimeGateway;

  beforeEach(() => {
    // Constructor deps aren't exercised by the throttle method; null-cast
    // is fine for this isolated unit.
    gw = new RealtimeGateway(null as never, null as never, null as never, null as never);
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
    return new RealtimeGateway(jwtService, config, prisma, ephemeralStore);
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
