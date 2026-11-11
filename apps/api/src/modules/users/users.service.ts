import { Injectable } from '@nestjs/common';
import { ThrottlerException } from '@nestjs/throttler';
import type { KeyBundleResponse, UserProfileResponse } from '@veil/contracts';

import { notFound } from '../../common/errors/api-error';
import { pickActiveDevice } from '../../common/pick-active-device';
import { PrismaService } from '../../common/prisma.service';
import { DIRECTORY_BUDGETS, DirectoryBudget } from '../prekeys/directory-budget';

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly budget: DirectoryBudget,
  ) {}

  async getUserByHandle(handle: string): Promise<UserProfileResponse> {
    const user = await this.prisma.user.findUnique({
      where: { handle: handle.toLowerCase() },
      select: { id: true, handle: true, status: true },
    });

    if (!user) {
      throw notFound('handle_not_found', 'User not found');
    }

    return { id: user.id, handle: user.handle, status: user.status };
  }

  /**
   * Deprecated public directory lookup, kept until both clients move to the
   * authenticated GET /v1/keys/:handle. It discloses only what a session
   * initiator needs: no profile fields, device platforms or update times.
   * `clientTracker` buckets anonymous callers for the per-handle budget, which
   * is spent before the lookup so probing unknown handles costs the same.
   */
  async getKeyBundle(handle: string, clientTracker: string): Promise<KeyBundleResponse> {
    const normalizedHandle = handle.toLowerCase();
    if (
      !(await this.budget.tryConsume(
        DIRECTORY_BUDGETS.publicBundleLookups,
        clientTracker,
        normalizedHandle,
      ))
    ) {
      throw new ThrottlerException();
    }

    const user = await this.prisma.user.findUnique({
      where: { handle: normalizedHandle },
      select: { id: true, handle: true, status: true, activeDeviceId: true },
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
      select: { id: true, publicIdentityKey: true, signedPrekeyBundle: true, isActive: true },
    });

    const resolvedDevice = pickActiveDevice(trustedDevices, user.activeDeviceId);
    if (!resolvedDevice) {
      throw notFound('active_device_not_found', 'Active device bundle not found');
    }

    // Advisory per-device count of unconsumed one-time prekeys so an X3DH
    // initiator knows whether a claim will succeed before making it. Reading
    // the bundle never consumes anything — claiming needs an authenticated
    // requester (GET /v1/keys/:handle).
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

    const toBundle = (device: (typeof trustedDevices)[number]) => ({
      userId: user.id,
      deviceId: device.id,
      handle: user.handle,
      identityPublicKey: device.publicIdentityKey,
      signedPrekeyBundle: device.signedPrekeyBundle,
      isActive: device.isActive,
      oneTimePrekeyAvailable: availableByDeviceId.get(device.id) ?? 0,
    });

    return {
      user: {
        id: user.id,
        handle: user.handle,
        status: user.status,
        activeDeviceId: user.activeDeviceId,
      },
      bundle: toBundle(resolvedDevice),
      deviceBundles: trustedDevices.map(toBundle),
    };
  }
}
