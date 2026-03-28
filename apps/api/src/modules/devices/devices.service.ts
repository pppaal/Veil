import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import type { RevokeDeviceResponse } from '@veil/contracts';

import { PrismaService } from '../../common/prisma.service';

@Injectable()
export class DevicesService {
  constructor(private readonly prisma: PrismaService) {}

  async revoke(userId: string, dto: { deviceId: string }): Promise<RevokeDeviceResponse> {
    const device = await this.prisma.device.findUnique({
      where: { id: dto.deviceId },
    });

    if (!device) {
      throw new NotFoundException('Device not found');
    }

    if (device.userId !== userId) {
      throw new ForbiddenException('Device does not belong to actor');
    }

    const revokedAt = new Date();
    await this.prisma.$transaction(async (tx) => {
      await tx.device.update({
        where: { id: dto.deviceId },
        data: {
          isActive: false,
          revokedAt,
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

    return {
      deviceId: dto.deviceId,
      revokedAt: revokedAt.toISOString(),
    };
  }
}
