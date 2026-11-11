import { Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import type { Server, Socket } from 'socket.io';
import type { RealtimeEventMap } from '@veil/contracts';
import { isUUID } from 'class-validator';

import { AppConfigService } from '../../common/config/app-config.service';
import { ConversationAccessService } from '../../common/conversation-access/conversation-access.service';
import { EphemeralStoreService } from '../../common/ephemeral-store.service';
import { PrismaService } from '../../common/prisma.service';
import { MetricsService } from '../metrics/metrics.service';

interface AccessTokenPayload {
  sub: string;
  deviceId: string;
  handle: string;
  jti?: string;
  exp?: number;
}

type TypingEvent = 'typing.start' | 'typing.stop';

const jtiBlacklistKey = (jti: string): string => `auth:blacklist:${jti}`;

@Injectable()
@WebSocketGateway({
  path: '/v1/realtime',
  cors: false,
})
export class RealtimeGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server!: Server;

  private readonly socketsByUserId = new Map<string, Set<string>>();
  private readonly socketsByDeviceId = new Map<string, Set<string>>();
  private readonly typingRateLimitBySocket = new Map<string, Map<string, number>>();
  private readonly tokenExpiryTimers = new Map<string, NodeJS.Timeout>();
  private static readonly TYPING_MIN_INTERVAL_MS = 500;

  constructor(
    private readonly jwtService: JwtService,
    private readonly config: AppConfigService,
    private readonly prisma: PrismaService,
    private readonly ephemeralStore: EphemeralStoreService,
    private readonly metrics: MetricsService,
    private readonly access: ConversationAccessService,
  ) {}

  async handleConnection(client: Socket): Promise<void> {
    const originHeader = client.handshake.headers.origin;
    const origin = typeof originHeader === 'string' ? originHeader : null;
    if (!this.config.isOriginAllowed(origin)) {
      client.disconnect(true);
      return;
    }

    // Only the handshake auth payload carries the token. A query-string
    // token ends up in proxy and access logs.
    const token =
      typeof client.handshake.auth?.token === 'string' && client.handshake.auth.token
        ? client.handshake.auth.token
        : null;

    if (!token) {
      client.disconnect(true);
      return;
    }

    try {
      const payload = await this.jwtService.verifyAsync<AccessTokenPayload>(token, {
        secret: this.config.jwtSecret,
        audience: this.config.jwtAudience,
        issuer: this.config.jwtIssuer,
      });

      // Reject sockets whose access token has been logged out. The same
      // blacklist key the HTTP guard checks; without this a logged-out
      // session keeps its WS channel alive until the socket disconnects.
      if (payload.jti) {
        const blacklisted = await this.ephemeralStore.getJson<unknown>(
          jtiBlacklistKey(payload.jti),
        );
        if (blacklisted) {
          client.disconnect(true);
          return;
        }
      }

      const device = await this.prisma.device.findUnique({
        where: { id: payload.deviceId },
        include: { user: true },
      });

      if (
        typeof payload.exp !== 'number' ||
        !device ||
        device.userId !== payload.sub ||
        !device.isActive ||
        device.revokedAt ||
        device.user.status !== 'active'
      ) {
        // Mirror the HTTP JWT guard: a locked/revoked user must not hold a
        // realtime channel even while a previously-issued access token is still
        // within its (<=1h) lifetime.
        client.disconnect(true);
        return;
      }

      // The client may have gone away while the checks above were awaited.
      // handleDisconnect has then already run, so registering now would
      // leave a dead socket, its gauge increment and its expiry timer behind.
      if (!client.connected) {
        return;
      }

      // A socket lives no longer than the token that opened it; the client
      // reconnects with a refreshed token.
      const expiryTimer = setTimeout(
        () => client.disconnect(true),
        Math.max(0, payload.exp * 1000 - Date.now()),
      );
      expiryTimer.unref();
      this.tokenExpiryTimers.set(client.id, expiryTimer);

      client.data.userId = payload.sub;
      client.data.deviceId = payload.deviceId;
      client.data.handle = payload.handle;

      const existing = this.socketsByUserId.get(payload.sub) ?? new Set<string>();
      existing.add(client.id);
      this.socketsByUserId.set(payload.sub, existing);

      const deviceSockets = this.socketsByDeviceId.get(payload.deviceId) ?? new Set<string>();
      deviceSockets.add(client.id);
      this.socketsByDeviceId.set(payload.deviceId, deviceSockets);

      // Operational gauge: one registered socket. Balanced by the dec in
      // handleDisconnect (which runs only for sockets that reached here, since
      // client.data.userId is set above). Guarded so telemetry can't drop a
      // connection.
      try {
        this.metrics.wsConnectionsActive.inc();
      } catch {
        // best-effort telemetry
      }

      this.emitToUser(payload.sub, 'presence.update', {
        userId: payload.sub,
        status: 'online',
        updatedAt: new Date().toISOString(),
      });
    } catch {
      client.disconnect(true);
    }
  }

  handleDisconnect(client: Socket): void {
    const expiryTimer = this.tokenExpiryTimers.get(client.id);
    if (expiryTimer) {
      clearTimeout(expiryTimer);
      this.tokenExpiryTimers.delete(client.id);
    }

    const userId = client.data.userId as string | undefined;
    const deviceId = client.data.deviceId as string | undefined;
    if (!userId) {
      return;
    }

    // Balances the inc in handleConnection: a userId is only ever set on a
    // socket that registered, so exactly the registered sockets decrement.
    try {
      this.metrics.wsConnectionsActive.dec();
    } catch {
      // best-effort telemetry
    }

    const sockets = this.socketsByUserId.get(userId);
    if (!sockets) {
      return;
    }

    sockets.delete(client.id);
    if (sockets.size === 0) {
      this.socketsByUserId.delete(userId);
      this.emitToUser(userId, 'presence.update', {
        userId,
        status: 'offline',
        updatedAt: new Date().toISOString(),
      });
    }

    if (deviceId) {
      const deviceSockets = this.socketsByDeviceId.get(deviceId);
      if (deviceSockets) {
        deviceSockets.delete(client.id);
        if (deviceSockets.size === 0) {
          this.socketsByDeviceId.delete(deviceId);
        }
      }
    }

    this.typingRateLimitBySocket.delete(client.id);
  }

  private shouldThrottleTyping(socketId: string, conversationId: string): boolean {
    const now = Date.now();
    let perConversation = this.typingRateLimitBySocket.get(socketId);
    if (!perConversation) {
      perConversation = new Map<string, number>();
      this.typingRateLimitBySocket.set(socketId, perConversation);
    }
    const last = perConversation.get(conversationId) ?? 0;
    if (now - last < RealtimeGateway.TYPING_MIN_INTERVAL_MS) {
      return true;
    }
    perConversation.set(conversationId, now);
    return false;
  }

  emitToUser<K extends keyof RealtimeEventMap>(
    userId: string,
    event: K,
    payload: RealtimeEventMap[K],
  ): void {
    const socketIds = this.socketsByUserId.get(userId);
    if (!socketIds) {
      return;
    }

    for (const socketId of socketIds) {
      this.server.to(socketId).emit(event, payload);
    }
  }

  emitToDevice<K extends keyof RealtimeEventMap>(
    deviceId: string,
    event: K,
    payload: RealtimeEventMap[K],
  ): void {
    const socketIds = this.socketsByDeviceId.get(deviceId);
    if (!socketIds) {
      return;
    }

    for (const socketId of socketIds) {
      this.server.to(socketId).emit(event, payload);
    }
  }

  emitConversationMembers<K extends keyof RealtimeEventMap>(
    members: Array<{ userId: string }>,
    event: K,
    payload: RealtimeEventMap[K],
  ): void {
    for (const member of members) {
      this.emitToUser(member.userId, event, payload);
    }
  }

  hasConnectedUser(userId: string): boolean {
    const sockets = this.socketsByUserId.get(userId);
    return (sockets?.size ?? 0) > 0;
  }

  hasConnectedDevice(deviceId: string): boolean {
    const sockets = this.socketsByDeviceId.get(deviceId);
    return (sockets?.size ?? 0) > 0;
  }

  connectedDeviceIdsForUser(userId: string): string[] {
    const userSockets = this.socketsByUserId.get(userId);
    if (!userSockets || userSockets.size === 0) {
      return [];
    }

    const connectedDeviceIds = new Set<string>();
    for (const socketId of userSockets) {
      const socket = this.server.sockets.sockets.get(socketId);
      const deviceId = socket?.data.deviceId as string | undefined;
      if (deviceId) {
        connectedDeviceIds.add(deviceId);
      }
    }

    return [...connectedDeviceIds];
  }

  /**
   * Force every socket bound to the given device to disconnect. Called from
   * the auth service when a device logs out, so the WS push channel doesn't
   * outlive the access token.
   */
  disconnectDevice(deviceId: string): number {
    const socketIds = this.socketsByDeviceId.get(deviceId);
    if (!socketIds || socketIds.size === 0) return 0;
    let count = 0;
    for (const socketId of [...socketIds]) {
      const socket = this.server.sockets.sockets.get(socketId);
      if (socket) {
        socket.disconnect(true);
        count++;
      }
    }
    return count;
  }

  /**
   * Drop every live socket for a user. Called when an account is revoked/locked
   * so existing realtime channels are cut immediately, not just refused on the
   * next reconnect. Pairs with the user-status check in handleConnection.
   */
  disconnectUser(userId: string): number {
    const socketIds = this.socketsByUserId.get(userId);
    if (!socketIds || socketIds.size === 0) return 0;
    let count = 0;
    for (const socketId of [...socketIds]) {
      const socket = this.server.sockets.sockets.get(socketId);
      if (socket) {
        socket.disconnect(true);
        count++;
      }
    }
    return count;
  }

  @SubscribeMessage('typing.start')
  handleTypingStart(client: Socket, payload: { conversationId?: unknown }): Promise<void> {
    return this.relayTyping(client, payload, 'typing.start');
  }

  @SubscribeMessage('typing.stop')
  handleTypingStop(client: Socket, payload: { conversationId?: unknown }): Promise<void> {
    return this.relayTyping(client, payload, 'typing.stop');
  }

  /**
   * Relays a typing indicator to the other members. Typing is best-effort, so
   * anything the policy refuses (non-member, a role without 'typing', a block
   * either way) is dropped silently rather than answered.
   */
  private async relayTyping(
    client: Socket,
    payload: { conversationId?: unknown },
    event: TypingEvent,
  ): Promise<void> {
    const userId = client.data.userId as string | undefined;
    const handle = client.data.handle as string | undefined;
    const conversationId = payload?.conversationId;
    if (!userId || !handle || typeof conversationId !== 'string' || !isUUID(conversationId)) {
      return;
    }
    if (this.shouldThrottleTyping(client.id, conversationId)) return;

    try {
      await this.access.requireAccess(userId, conversationId, 'typing');
    } catch {
      return;
    }

    const recipients = await this.prisma.conversationMember.findMany({
      where: { conversationId, userId: { not: userId } },
      select: { userId: true },
    });
    this.emitConversationMembers(recipients, event, { conversationId, userId, handle });
  }

  /**
   * Relay a WebRTC signaling message (SDP offer/answer or ICE candidate)
   * between the two parties of a 1:1 call. The sender must be allowed to call
   * in the call's conversation; otherwise the message is dropped silently.
   *
   * IMPORTANT: `payload.data` is an opaque E2E media-setup blob. The server
   * MUST NOT inspect, parse, persist, or otherwise interpret it — WebRTC media
   * is negotiated end-to-end (DTLS-SRTP). This handler only forwards the blob
   * to the other conversation members verbatim; nothing here is stored.
   */
  @SubscribeMessage('call.signal')
  async handleCallSignal(
    client: Socket,
    payload: { callId: string; kind: 'offer' | 'answer' | 'ice'; data: string },
  ): Promise<void> {
    const userId = client.data.userId as string | undefined;
    const deviceId = client.data.deviceId as string | undefined;
    if (
      !userId ||
      !deviceId ||
      !payload?.callId ||
      typeof payload.data !== 'string' ||
      (payload.kind !== 'offer' && payload.kind !== 'answer' && payload.kind !== 'ice')
    ) {
      return;
    }

    if (!isUUID(payload.callId)) return;
    const call = await this.prisma.callRecord.findUnique({
      where: { id: payload.callId },
      select: { conversationId: true },
    });
    if (!call) return;

    // Same policy as placing the call: a non-member or a blocked pair is
    // dropped silently.
    try {
      await this.access.requireAccess(userId, call.conversationId, 'call');
    } catch {
      return;
    }

    const recipients = await this.prisma.conversationMember.findMany({
      where: { conversationId: call.conversationId, userId: { not: userId } },
      select: { userId: true },
    });
    this.emitConversationMembers(recipients, 'call.signal', {
      callId: payload.callId,
      kind: payload.kind,
      data: payload.data,
      fromUserId: userId,
      fromDeviceId: deviceId,
    });
  }

  isUserOnline(userId: string): boolean {
    return this.hasConnectedUser(userId);
  }

  onlineStatusForUsers(userIds: string[]): Map<string, boolean> {
    const result = new Map<string, boolean>();
    for (const userId of userIds) {
      result.set(userId, this.hasConnectedUser(userId));
    }
    return result;
  }
}
