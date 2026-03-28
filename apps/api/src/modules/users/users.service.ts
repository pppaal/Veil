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
      include: {
        activeDevice: true,
      },
    });

    if (!user || !user.activeDevice) {
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
        deviceId: user.activeDevice.id,
        handle: user.handle,
        identityPublicKey: user.activeDevice.publicIdentityKey,
        signedPrekeyBundle: user.activeDevice.signedPrekeyBundle,
        platform: user.activeDevice.platform,
        isActive: user.activeDevice.isActive,
        updatedAt: user.updatedAt.toISOString(),
      },
    };
  }
}
