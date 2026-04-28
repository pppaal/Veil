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
