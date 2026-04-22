import { Injectable } from '@nestjs/common';
import type { ListDevicesResponse, RevokeDeviceResponse } from '@veil/contracts';

import { forbidden, notFound } from '../../common/errors/api-error';
import { PrismaService } from '../../common/prisma.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';

const STALE_DEVICE_WINDOW_MS = 1000 * 60 * 60 * 24 * 30;

@Injectable()
export class DevicesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
  ) {}

  async list(userId: string, currentDeviceId?: string): Promise<ListDevicesResponse> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { activeDeviceId: true },
    });

    const devices = await this.prisma.device.findMany({
      where: { userId },
      include: {
        joinedFromDevice: {
          select: {
            id: true,
            deviceName: true,
            platform: true,
          },
        },
      },
      orderBy: [
        { isActive: 'desc' },
        { lastSeenAt: 'desc' },
        { createdAt: 'desc' },
      ],
    });

    return {
      activeDeviceId: user?.activeDeviceId ?? null,
      items: devices.map((device) => {
        const lastTrustedActivityAt = this.resolveLastTrustedActivityAt(device);
        return {
          id: device.id,
          deviceName: device.deviceName,
          platform: device.platform,
          isActive: device.isActive,
          trustState: this.resolveTrustState(
            device,
            user?.activeDeviceId ?? null,
            currentDeviceId,
            lastTrustedActivityAt,
          ),
          revokedAt: device.revokedAt?.toISOString() ?? null,
          trustedAt: device.trustedAt.toISOString(),
          joinedFromDeviceId: device.joinedFromDeviceId ?? null,
          joinedFromDeviceName: device.joinedFromDevice?.deviceName ?? null,
          joinedFromPlatform: device.joinedFromDevice?.platform ?? null,
          createdAt: device.createdAt.toISOString(),
          lastSeenAt: device.lastSeenAt.toISOString(),
          lastSyncAt: device.lastSyncAt?.toISOString() ?? null,
          lastTrustedActivityAt: lastTrustedActivityAt.toISOString(),
        };
      }),
    };
  }

  async updatePushToken(
    userId: string,
    deviceId: string,
    pushToken: string,
  ): Promise<{ deviceId: string; updatedAt: string }> {
    const device = await this.prisma.device.findUnique({
      where: { id: deviceId },
      select: { id: true, userId: true, isActive: true, revokedAt: true },
    });

    if (!device || device.userId !== userId) {
      throw notFound('device_not_found', 'Device not found');
    }

    if (!device.isActive || device.revokedAt) {
      throw forbidden('device_not_active', 'Device is not active');
    }

    const now = new Date();
    await this.prisma.device.update({
      where: { id: deviceId },
      data: { pushToken, lastSeenAt: now },
    });

    return {
      deviceId,
      updatedAt: now.toISOString(),
    };
  }

  async clearPushToken(
    userId: string,
    deviceId: string,
  ): Promise<{ deviceId: string; clearedAt: string }> {
    const device = await this.prisma.device.findUnique({
      where: { id: deviceId },
      select: { id: true, userId: true },
    });

    if (!device || device.userId !== userId) {
      throw notFound('device_not_found', 'Device not found');
    }

    await this.prisma.device.update({
      where: { id: deviceId },
      data: { pushToken: null },
    });

    return {
      deviceId,
      clearedAt: new Date().toISOString(),
    };
  }

  async revoke(userId: string, dto: { deviceId: string }): Promise<RevokeDeviceResponse> {
    const device = await this.prisma.device.findUnique({
      where: { id: dto.deviceId },
    });

    if (!device) {
      throw notFound('device_not_found', 'Device not found');
    }

    if (device.userId !== userId) {
      throw forbidden('device_forbidden', 'Device does not belong to actor');
    }

    const revokedAt = new Date();
    await this.prisma.$transaction(async (tx) => {
      await tx.device.update({
        where: { id: dto.deviceId },
        data: {
          isActive: false,
          revokedAt,
          pushToken: null,
        },
      });

      const user = await tx.user.findUnique({
        where: { id: userId },
        select: { activeDeviceId: true },
      });

      if (user?.activeDeviceId === dto.deviceId) {
        const candidates = await tx.device.findMany({
          where: {
            userId,
            isActive: true,
            revokedAt: null,
          },
          orderBy: [
            { lastSeenAt: 'desc' },
            { trustedAt: 'desc' },
            { createdAt: 'desc' },
          ],
        });
        const replacement = candidates.find((candidate) => candidate.id !== dto.deviceId) ?? null;

        await tx.user.update({
          where: { id: userId },
          data: { activeDeviceId: replacement?.id ?? null },
        });
      }
    });

    this.realtimeGateway.disconnectDevice(dto.deviceId);

    return {
      deviceId: dto.deviceId,
      revokedAt: revokedAt.toISOString(),
    };
  }

  private resolveTrustState(
    device: {
      id: string;
      isActive: boolean;
      revokedAt: Date | null;
      lastSeenAt: Date;
      lastSyncAt?: Date | null;
    },
    preferredDeviceId: string | null,
    currentDeviceId?: string,
    lastTrustedActivityAt: Date = this.resolveLastTrustedActivityAt(device),
  ): 'current' | 'preferred' | 'trusted' | 'stale' | 'revoked' {
    if (device.revokedAt || !device.isActive) {
      return 'revoked';
    }
    if (currentDeviceId === device.id) {
      return 'current';
    }
    if (preferredDeviceId === device.id) {
      return 'preferred';
    }
    if (Date.now() - lastTrustedActivityAt.getTime() > STALE_DEVICE_WINDOW_MS) {
      return 'stale';
    }
    return 'trusted';
  }

  private resolveLastTrustedActivityAt(device: {
    lastSeenAt: Date;
    lastSyncAt?: Date | null;
  }): Date {
    if (!device.lastSyncAt) {
      return device.lastSeenAt;
    }
    return device.lastSyncAt.getTime() > device.lastSeenAt.getTime()
      ? device.lastSyncAt
      : device.lastSeenAt;
  }
}
