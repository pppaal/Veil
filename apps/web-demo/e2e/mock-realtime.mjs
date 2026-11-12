// The realtime gateway of the mock relay (mock-server.mjs): just enough of
// Socket.IO v4 over a WebSocket (engine.io protocol 4) for the demo's
// socket.io client, with no dependency beyond node:crypto. It mirrors
// RealtimeGateway in apps/api: the handshake auth payload carries the access
// token, a socket the token does not admit is connected and then cut ('io
// server disconnect'), presence goes to the user's own sockets only, and
// typing is relayed to the other members, throttled per socket and
// conversation.
//
// The gateway is off until a test turns it on, so the demo runs in polling
// mode by default, as the browser tests in e2e/browser/ expect.

import { createHash, randomBytes } from 'node:crypto';

const WEBSOCKET_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const REALTIME_PATH = '/v1/realtime/';
const PING_INTERVAL_MS = 25_000;
const PING_TIMEOUT_MS = 20_000;
const TYPING_MIN_INTERVAL_MS = 500;

const OPCODE = { continuation: 0x0, text: 0x1, close: 0x8, ping: 0x9, pong: 0xa };

function encodeFrame(payload, opcode = OPCODE.text) {
  const body = Buffer.from(payload);
  let header;
  if (body.length < 126) {
    header = Buffer.from([0x80 | opcode, body.length]);
  } else if (body.length < 0x10000) {
    header = Buffer.alloc(4);
    header.writeUInt16BE(body.length, 2);
    header[1] = 126;
  } else {
    header = Buffer.alloc(10);
    header.writeBigUInt64BE(BigInt(body.length), 2);
    header[1] = 127;
  }
  header[0] = 0x80 | opcode;
  return Buffer.concat([header, body]);
}

// Feeds raw socket bytes in, calls onText for every complete text message
// and onControl for close and ping frames. Client frames are always masked.
function createFrameReader({ onText, onControl }) {
  let buffer = Buffer.alloc(0);
  let fragments = [];
  return (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    while (buffer.length >= 2) {
      const fin = (buffer[0] & 0x80) !== 0;
      const opcode = buffer[0] & 0x0f;
      let length = buffer[1] & 0x7f;
      let offset = 2;
      if (length === 126) {
        if (buffer.length < 4) return;
        length = buffer.readUInt16BE(2);
        offset = 4;
      } else if (length === 127) {
        if (buffer.length < 10) return;
        length = Number(buffer.readBigUInt64BE(2));
        offset = 10;
      }
      const masked = (buffer[1] & 0x80) !== 0;
      const maskAt = offset;
      if (masked) offset += 4;
      if (buffer.length < offset + length) return;
      const payload = Buffer.from(buffer.subarray(offset, offset + length));
      if (masked) for (let i = 0; i < payload.length; i += 1) payload[i] ^= buffer[maskAt + (i % 4)];
      buffer = buffer.subarray(offset + length);
      if (opcode === OPCODE.text || opcode === OPCODE.continuation) {
        fragments.push(payload);
        if (fin) {
          onText(Buffer.concat(fragments).toString('utf8'));
          fragments = [];
        }
      } else {
        onControl(opcode, payload);
      }
    }
  };
}

// authenticate(token) -> { user, device } or null; isMember(userId,
// conversationId) -> boolean; membersOf(conversationId) -> userId[].
export function createRealtimeGateway({ authenticate, isMember, membersOf }) {
  let enabled = false;
  const sockets = new Set();

  function emitToUser(userId, event, payload) {
    for (const socket of sockets) if (socket.user?.id === userId) socket.emit(event, payload);
  }

  function relayTyping(socket, event, payload) {
    const conversationId = payload?.conversationId;
    if (typeof conversationId !== 'string' || !isMember(socket.user.id, conversationId)) return;
    const now = Date.now();
    if (now - (socket.typingAt.get(conversationId) ?? 0) < TYPING_MIN_INTERVAL_MS) return;
    socket.typingAt.set(conversationId, now);
    for (const userId of membersOf(conversationId)) {
      if (userId !== socket.user.id) {
        emitToUser(userId, event, { conversationId, userId: socket.user.id, handle: socket.user.handle });
      }
    }
  }

  function accept(req, raw) {
    const sid = randomBytes(10).toString('base64url');
    const socket = { user: null, device: null, typingAt: new Map(), closed: false };
    const write = (packet) => {
      if (!socket.closed && raw.writable) raw.write(encodeFrame(packet));
    };
    const ping = setInterval(() => write('2'), PING_INTERVAL_MS);
    socket.emit = (event, payload) => write(`42${JSON.stringify([event, payload])}`);
    socket.close = () => {
      if (socket.closed) return;
      write('41');
      socket.closed = true;
      clearInterval(ping);
      sockets.delete(socket);
      if (raw.writable) raw.end(encodeFrame(Buffer.alloc(0), OPCODE.close));
      if (socket.user && ![...sockets].some((other) => other.user?.id === socket.user.id)) {
        emitToUser(socket.user.id, 'presence.update', {
          userId: socket.user.id,
          status: 'offline',
          updatedAt: new Date().toISOString(),
        });
      }
    };

    function connect(auth) {
      const admitted = typeof auth?.token === 'string' ? authenticate(auth.token) : null;
      write(`40${JSON.stringify({ sid })}`);
      if (!admitted) {
        socket.close();
        return;
      }
      socket.user = admitted.user;
      socket.device = admitted.device;
      sockets.add(socket);
      emitToUser(socket.user.id, 'presence.update', {
        userId: socket.user.id,
        status: 'online',
        updatedAt: new Date().toISOString(),
      });
    }

    function onText(packet) {
      if (packet === '3') return;
      if (packet.startsWith('40')) {
        connect(packet.length > 2 ? JSON.parse(packet.slice(2)) : null);
      } else if (packet.startsWith('41')) {
        socket.close();
      } else if (packet.startsWith('42') && socket.user) {
        const [event, payload] = JSON.parse(packet.slice(2));
        if (event === 'typing.start' || event === 'typing.stop') relayTyping(socket, event, payload);
      }
    }

    const key = req.headers['sec-websocket-key'];
    const acceptKey = createHash('sha1').update(key + WEBSOCKET_GUID).digest('base64');
    raw.write(
      ['HTTP/1.1 101 Switching Protocols', 'Upgrade: websocket', 'Connection: Upgrade', `Sec-WebSocket-Accept: ${acceptKey}`, '', '']
        .join('\r\n'),
    );
    raw.on('data', createFrameReader({
      onText,
      onControl: (opcode, payload) => {
        if (opcode === OPCODE.ping && raw.writable) raw.write(encodeFrame(payload, OPCODE.pong));
        if (opcode === OPCODE.close) socket.close();
      },
    }));
    raw.on('close', () => socket.close());
    raw.on('error', () => socket.close());
    write(`0${JSON.stringify({ sid, upgrades: [], pingInterval: PING_INTERVAL_MS, pingTimeout: PING_TIMEOUT_MS, maxPayload: 1_000_000 })}`);
  }

  return {
    emitToUser,

    setEnabled(value) {
      enabled = value;
      if (!enabled) for (const socket of [...sockets]) socket.close();
    },

    // While the gateway is off, the upgrade is refused the way a relay
    // without one refuses it, and the client stays in polling mode.
    handleUpgrade(req, raw) {
      const url = new URL(req.url, 'http://relay');
      if (!enabled || url.pathname !== REALTIME_PATH || url.searchParams.get('transport') !== 'websocket') {
        raw.end('HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n');
        return;
      }
      accept(req, raw);
    },

    // As RealtimeGateway.disconnectDevice: a revoked device keeps no channel.
    disconnectDevice(deviceId) {
      for (const socket of [...sockets]) if (socket.device?.id === deviceId) socket.close();
    },
  };
}
