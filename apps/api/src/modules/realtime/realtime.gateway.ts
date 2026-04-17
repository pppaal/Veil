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
import { PrismaService } from '../../common/prisma.service';

interface AccessTokenPayload {
  sub: string;
  deviceId: string;
  handle: string;
}

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

  constructor(
    private readonly jwtService: JwtService,
    private readonly config: AppConfigService,
    private readonly prisma: PrismaService,
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

      const device = await this.prisma.device.findUnique({
        where: { id: payload.deviceId },
        include: { user: true },
      });

      if (
        !device ||
        device.userId !== payload.sub ||
        !device.isActive ||
        device.revokedAt
      ) {
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
  }

  emitToUser<K extends keyof RealtimeEventMap>(userId: string, event: K, payload: RealtimeEventMap[K]): void {
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

  @SubscribeMessage('typing.start')
  async handleTypingStart(client: Socket, payload: { conversationId: string }): Promise<void> {
    const userId = client.data.userId as string | undefined;
    const handle = client.data.handle as string | undefined;
    if (!userId || !handle || !payload?.conversationId) return;

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

  disconnectDevice(deviceId: string): void {
    const socketIds = this.socketsByDeviceId.get(deviceId);
    if (!socketIds) {
      return;
    }

    for (const socketId of socketIds) {
      const socket = this.server.sockets.sockets.get(socketId);
      socket?.disconnect(true);
    }
    this.socketsByDeviceId.delete(deviceId);
  }
}
