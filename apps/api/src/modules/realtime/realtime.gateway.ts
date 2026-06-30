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

import { AppConfigService } from '../../common/config/app-config.service';
import { EphemeralStoreService } from '../../common/ephemeral-store.service';
import { PrismaService } from '../../common/prisma.service';

interface AccessTokenPayload {
  sub: string;
  deviceId: string;
  handle: string;
  jti?: string;
}

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
  private static readonly TYPING_MIN_INTERVAL_MS = 500;

  constructor(
    private readonly jwtService: JwtService,
    private readonly config: AppConfigService,
    private readonly prisma: PrismaService,
    private readonly ephemeralStore: EphemeralStoreService,
  ) {}

  async handleConnection(client: Socket): Promise<void> {
    const originHeader = client.handshake.headers.origin;
    const origin = typeof originHeader === 'string' ? originHeader : null;
    if (!this.config.isOriginAllowed(origin)) {
      client.disconnect(true);
      return;
    }

    const token =
      (typeof client.handshake.auth.token === 'string' && client.handshake.auth.token) ||
      (typeof client.handshake.query.token === 'string' && client.handshake.query.token) ||
      null;

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

      client.data.userId = payload.sub;
      client.data.deviceId = payload.deviceId;
      client.data.handle = payload.handle;

      const existing = this.socketsByUserId.get(payload.sub) ?? new Set<string>();
      existing.add(client.id);
      this.socketsByUserId.set(payload.sub, existing);

      const deviceSockets = this.socketsByDeviceId.get(payload.deviceId) ?? new Set<string>();
      deviceSockets.add(client.id);
      this.socketsByDeviceId.set(payload.deviceId, deviceSockets);

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
    const userId = client.data.userId as string | undefined;
    const deviceId = client.data.deviceId as string | undefined;
    if (!userId) {
      return;
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
  async handleTypingStart(client: Socket, payload: { conversationId: string }): Promise<void> {
    const userId = client.data.userId as string | undefined;
    const handle = client.data.handle as string | undefined;
    if (!userId || !handle || !payload?.conversationId) return;
    if (this.shouldThrottleTyping(client.id, payload.conversationId)) return;

    const members = await this.prisma.conversationMember.findMany({
      where: { conversationId: payload.conversationId },
      select: { userId: true },
    });

    for (const member of members) {
      if (member.userId !== userId) {
        this.emitToUser(member.userId, 'typing.start', {
          conversationId: payload.conversationId,
          userId,
          handle,
        });
      }
    }
  }

  @SubscribeMessage('typing.stop')
  async handleTypingStop(client: Socket, payload: { conversationId: string }): Promise<void> {
    const userId = client.data.userId as string | undefined;
    const handle = client.data.handle as string | undefined;
    if (!userId || !handle || !payload?.conversationId) return;
    if (this.shouldThrottleTyping(client.id, payload.conversationId)) return;

    const members = await this.prisma.conversationMember.findMany({
      where: { conversationId: payload.conversationId },
      select: { userId: true },
    });

    for (const member of members) {
      if (member.userId !== userId) {
        this.emitToUser(member.userId, 'typing.stop', {
          conversationId: payload.conversationId,
          userId,
          handle,
        });
      }
    }
  }

  /**
   * Relay a WebRTC signaling message (SDP offer/answer or ICE candidate)
   * between the two parties of a 1:1 call. The sender must be a member of the
   * call's conversation; otherwise the message is dropped silently.
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

    // Resolve the call's conversation members, mirroring how the typing
    // handlers authorize fan-out against conversation membership.
    const call = await this.prisma.callRecord.findUnique({
      where: { id: payload.callId },
      select: {
        conversationId: true,
        conversation: { select: { members: { select: { userId: true } } } },
      },
    });

    if (!call) return;

    const members = call.conversation.members;
    // Drop silently if the sender is not a member of the call's conversation.
    if (!members.some((m) => m.userId === userId)) return;

    for (const member of members) {
      if (member.userId !== userId) {
        this.emitToUser(member.userId, 'call.signal', {
          callId: payload.callId,
          kind: payload.kind,
          data: payload.data,
          fromUserId: userId,
          fromDeviceId: deviceId,
        });
      }
    }
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
