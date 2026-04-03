import { Injectable, NotFoundException } from '@nestjs/common';
import type { KeyBundleResponse, UserProfileResponse } from '@veil/contracts';

import { PrismaService } from '../../common/prisma.service';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async getUserByHandle(handle: string): Promise<UserProfileResponse> {
    const user = await this.prisma.user.findUnique({
      where: { handle: handle.toLowerCase() },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    return {
      id: user.id,
      handle: user.handle,
      displayName: user.displayName,
      avatarPath: user.avatarPath,
      status: user.status,
      activeDeviceId: user.activeDeviceId,
    };
  }

  async getKeyBundle(handle: string): Promise<KeyBundleResponse> {
    const user = await this.prisma.user.findUnique({
      where: { handle: handle.toLowerCase() },
      select: {
        id: true,
        handle: true,
        displayName: true,
        avatarPath: true,
        status: true,
        activeDeviceId: true,
        updatedAt: true,
      },
    });

    if (!user) {
      throw new NotFoundException('Active device bundle not found');
    }

    const trustedDevices = await this.prisma.device.findMany({
      where: {
        userId: user.id,
        isActive: true,
        revokedAt: null,
      },
      orderBy: [
        { trustedAt: 'desc' },
        { lastSeenAt: 'desc' },
      ],
    });

    const resolvedDevice =
      trustedDevices.find((device) => device.id === user.activeDeviceId) ?? trustedDevices[0];

    if (!resolvedDevice || !resolvedDevice.isActive || resolvedDevice.revokedAt) {
      throw new NotFoundException('Active device bundle not found');
    }

    return {
      user: {
        id: user.id,
        handle: user.handle,
        displayName: user.displayName,
        avatarPath: user.avatarPath,
        status: user.status,
        activeDeviceId: user.activeDeviceId,
      },
      bundle: {
        userId: user.id,
        deviceId: resolvedDevice.id,
        handle: user.handle,
        identityPublicKey: resolvedDevice.publicIdentityKey,
        signedPrekeyBundle: resolvedDevice.signedPrekeyBundle,
        platform: resolvedDevice.platform,
        isActive: resolvedDevice.isActive,
        updatedAt: user.updatedAt.toISOString(),
      },
    };
  }
}
