import { Inject, Injectable } from '@nestjs/common';
import { ThrottlerException } from '@nestjs/throttler';
import type { KeyClaimMode, KeysResponse, RotateSignedPrekeyResponse } from '@veil/contracts';

import { badRequest, forbidden, notFound } from '../../common/errors/api-error';
import { pickActiveDevice } from '../../common/pick-active-device';
import { PrismaService } from '../../common/prisma.service';
import { DIRECTORY_BUDGETS, DirectoryBudget } from './directory-budget';
import { PrekeysService, type DirectoryRequester } from './prekeys.service';
import { decodeSignedPrekeyBundleV2, verifySignedPrekeyBundleV2 } from './signed-prekey-bundle';

export const KEYS_CLOCK = Symbol('KEYS_CLOCK');
export type Clock = () => number;

// A signed prekey must be fresh when it is published: a replayed old bundle
// or a pre-generated future one is rejected.
const MAX_SIGNED_PREKEY_CLOCK_SKEW_MS = 10 * 60 * 1000;

function claimTargets(mode: KeyClaimMode, deviceIds: string[], activeDeviceId: string): string[] {
  switch (mode) {
    case 'all':
      return deviceIds;
    case 'active':
      return [activeDeviceId];
    case 'none':
      return [];
  }
}

@Injectable()
export class KeysService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly prekeys: PrekeysService,
    private readonly budget: DirectoryBudget,
    @Inject(KEYS_CLOCK) private readonly clock: Clock,
  ) {}

  /**
   * Key material for every trusted device of the handle, with one-time
   * prekeys claimed for the devices the mode selects.
   */
  async getKeys(
    requester: DirectoryRequester,
    handle: string,
    mode: KeyClaimMode,
  ): Promise<KeysResponse> {
    const user = await this.prisma.user.findUnique({
      where: { handle: handle.toLowerCase() },
      select: { id: true, handle: true, activeDeviceId: true },
    });
    if (!user) {
      throw notFound('handle_not_found', 'User not found');
    }

    const devices = await this.prisma.device.findMany({
      where: { userId: user.id, isActive: true, revokedAt: null },
      orderBy: [{ trustedAt: 'desc' }, { lastSeenAt: 'desc' }],
      select: { id: true, publicIdentityKey: true, signedPrekeyBundle: true },
    });
    const activeDevice = pickActiveDevice(devices, user.activeDeviceId);
    if (!activeDevice) {
      throw notFound('active_device_not_found', 'Active device bundle not found');
    }

    const claimed = await this.prekeys.claimWithinBudget(
      requester,
      user.id,
      claimTargets(
        mode,
        devices.map((device) => device.id),
        activeDevice.id,
      ),
    );

    return {
      user: { id: user.id, handle: user.handle, activeDeviceId: activeDevice.id },
      devices: devices.map((device) => ({
        deviceId: device.id,
        identityPublicKey: device.publicIdentityKey,
        signedPrekeyBundle: device.signedPrekeyBundle,
        isActive: device.id === activeDevice.id,
        oneTimePrekey: claimed.get(device.id) ?? null,
      })),
    };
  }

  /**
   * Publishes a new signed prekey for the calling device. The bundle must be
   * signed by the device's identity key; once a device publishes v2, its X25519
   * identity key is pinned and spkId must strictly increase. A legacy v1
   * bundle may be upgraded to v2 exactly once.
   */
  async rotateSignedPrekey(
    requester: DirectoryRequester,
    signedPrekeyBundle: string,
  ): Promise<RotateSignedPrekeyResponse> {
    if (
      !(await this.budget.tryConsume(DIRECTORY_BUDGETS.signedPrekeyRotations, requester.deviceId))
    ) {
      throw new ThrottlerException();
    }

    const device = await this.prisma.device.findUnique({
      where: { id: requester.deviceId },
      select: {
        userId: true,
        isActive: true,
        revokedAt: true,
        publicIdentityKey: true,
        signedPrekeyBundle: true,
      },
    });
    if (!device || device.userId !== requester.userId) {
      throw notFound('device_not_found', 'Device not found');
    }
    if (!device.isActive || device.revokedAt) {
      throw forbidden('device_not_active', 'Device is not active');
    }

    const next = decodeSignedPrekeyBundleV2(signedPrekeyBundle);
    if (!next) {
      throw badRequest('validation_failed', 'Signed prekey bundle must be a canonical v2 bundle');
    }
    if (!verifySignedPrekeyBundleV2(next, device.publicIdentityKey)) {
      throw badRequest(
        'invalid_device_signature',
        'Signed prekey bundle is not signed by the device identity key',
      );
    }
    if (Math.abs(next.spkTs - this.clock()) > MAX_SIGNED_PREKEY_CLOCK_SKEW_MS) {
      throw badRequest(
        'validation_failed',
        'Signed prekey timestamp is outside the accepted window',
      );
    }

    const current = decodeSignedPrekeyBundleV2(device.signedPrekeyBundle);
    if (current && !next.ikx.equals(current.ikx)) {
      throw badRequest('validation_failed', 'The X25519 identity key cannot change');
    }
    if (current && next.spkId <= current.spkId) {
      throw badRequest('validation_failed', 'spkId must increase with every rotation');
    }

    // Compare-and-swap on the bundle we validated against, so two concurrent
    // rotations cannot both pass the checks and leave the older one stored.
    const { count } = await this.prisma.device.updateMany({
      where: { id: requester.deviceId, signedPrekeyBundle: device.signedPrekeyBundle },
      data: { signedPrekeyBundle },
    });
    if (count !== 1) {
      throw badRequest('validation_failed', 'Signed prekey changed concurrently; retry');
    }

    return { deviceId: requester.deviceId, spkId: next.spkId };
  }
}
