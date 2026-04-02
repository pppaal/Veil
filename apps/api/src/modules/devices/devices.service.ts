import { Injectable } from '@nestjs/common';
import type { RevokeDeviceResponse } from '@veil/contracts';

import { forbidden, notFound } from '../../common/errors/api-error';
import { PrismaService } from '../../common/prisma.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';

@Injectable()
export class DevicesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
  ) {}

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
        await tx.user.update({
          where: { id: userId },
          data: { activeDeviceId: null },
        });
      }
    });

    this.realtimeGateway.disconnectDevice(dto.deviceId);

    return {
      deviceId: dto.deviceId,
      revokedAt: revokedAt.toISOString(),
    };
  }
}
