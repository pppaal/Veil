import { Injectable } from '@nestjs/common';
import type { KeyBundleResponse, UserProfileResponse } from '@veil/contracts';

import { notFound } from '../../common/errors/api-error';
import { pickActiveDevice } from '../../common/pick-active-device';
import { PrismaService } from '../../common/prisma.service';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async getUserByHandle(handle: string): Promise<UserProfileResponse> {
    const user = await this.prisma.user.findUnique({
      where: { handle: handle.toLowerCase() },
    });

    if (!user) {
      throw notFound('handle_not_found', 'User not found');
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
      throw notFound('active_device_not_found', 'Active device bundle not found');
    }

    const trustedDevices = await this.prisma.device.findMany({
      where: {
        userId: user.id,
        isActive: true,
        revokedAt: null,
      },
      orderBy: [{ trustedAt: 'desc' }, { lastSeenAt: 'desc' }],
    });

    const resolvedDevice = pickActiveDevice(trustedDevices, user.activeDeviceId);

    if (!resolvedDevice || !resolvedDevice.isActive || resolvedDevice.revokedAt) {
      throw notFound('active_device_not_found', 'Active device bundle not found');
    }

    // Advisory per-device count of unconsumed one-time prekeys so an X3DH
    // initiator knows whether a claim will succeed before making it. Reading
    // the bundle never consumes anything — claiming stays on
    // POST /v1/prekeys/claim/:handle.
    const unconsumed = await this.prisma.oneTimePrekey.groupBy({
      by: ['deviceId'],
      where: {
        deviceId: { in: trustedDevices.map((device) => device.id) },
        consumedAt: null,
      },
      _count: { _all: true },
    });
    const availableByDeviceId = new Map<string, number>(
      unconsumed.map((row) => [row.deviceId, row._count._all] as [string, number]),
    );

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
        oneTimePrekeyAvailable: availableByDeviceId.get(resolvedDevice.id) ?? 0,
      },
      deviceBundles: trustedDevices.map((device) => ({
        userId: user.id,
        deviceId: device.id,
        handle: user.handle,
        identityPublicKey: device.publicIdentityKey,
        signedPrekeyBundle: device.signedPrekeyBundle,
        platform: device.platform,
        isActive: device.isActive,
        updatedAt: user.updatedAt.toISOString(),
        oneTimePrekeyAvailable: availableByDeviceId.get(device.id) ?? 0,
      })),
    };
  }
}
