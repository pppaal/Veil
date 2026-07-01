import { Injectable } from '@nestjs/common';
import type {
  ClaimOneTimePrekeyResponse,
  OneTimePrekeyUpload,
  UploadOneTimePrekeysResponse,
} from '@veil/contracts';

import { forbidden, notFound } from '../../common/errors/api-error';
import { PrismaService } from '../../common/prisma.service';

// How many times the atomic claim retries when it loses the race for a
// candidate prekey to a concurrent claimer before giving up and reporting the
// pool as depleted.
const CLAIM_MAX_ATTEMPTS = 5;

@Injectable()
export class PrekeysService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Store a batch of the calling device's public one-time prekeys. Duplicate
   * (device, keyId) pairs are skipped rather than erroring, so a client can
   * safely retry an upload. Returns how many were newly stored plus the
   * device's remaining unconsumed count.
   */
  async upload(
    userId: string,
    deviceId: string,
    prekeys: OneTimePrekeyUpload[],
  ): Promise<UploadOneTimePrekeysResponse> {
    await this.assertActiveDevice(userId, deviceId);

    const result = await this.prisma.oneTimePrekey.createMany({
      data: prekeys.map((prekey) => ({
        deviceId,
        keyId: prekey.keyId,
        publicKey: prekey.publicKey,
      })),
      skipDuplicates: true,
    });

    const available = await this.prisma.oneTimePrekey.count({
      where: { deviceId, consumedAt: null },
    });

    return { uploaded: result.count, available };
  }

  /** Remaining unconsumed prekeys for the calling device. */
  async count(userId: string, deviceId: string): Promise<{ available: number }> {
    await this.assertActiveDevice(userId, deviceId);
    const available = await this.prisma.oneTimePrekey.count({
      where: { deviceId, consumedAt: null },
    });
    return { available };
  }

  /**
   * Atomically claim one unused prekey for the handle's active device. The
   * claim marks the row consumed under a guard so two concurrent claimers can
   * never receive the same prekey. Returns prekey=null when the pool is empty,
   * letting the initiator fall back to signed-prekey-only X3DH.
   */
  async claim(handle: string): Promise<ClaimOneTimePrekeyResponse> {
    const deviceId = await this.resolveActiveDeviceId(handle);

    for (let attempt = 0; attempt < CLAIM_MAX_ATTEMPTS; attempt += 1) {
      const candidate = await this.prisma.oneTimePrekey.findFirst({
        where: { deviceId, consumedAt: null },
        orderBy: { keyId: 'asc' },
        select: { id: true, keyId: true, publicKey: true },
      });

      if (!candidate) {
        return { deviceId, prekey: null };
      }

      // The consumedAt: null guard is the race breaker: only the first claimer
      // to commit flips it, the loser's updateMany matches zero rows and retries
      // with the next candidate.
      const claimed = await this.prisma.oneTimePrekey.updateMany({
        where: { id: candidate.id, consumedAt: null },
        data: { consumedAt: new Date() },
      });

      if (claimed.count === 1) {
        return { deviceId, prekey: { keyId: candidate.keyId, publicKey: candidate.publicKey } };
      }
    }

    // Contended to exhaustion — treat as depleted; the initiator degrades
    // gracefully rather than failing the session.
    return { deviceId, prekey: null };
  }

  private async assertActiveDevice(userId: string, deviceId: string): Promise<void> {
    const device = await this.prisma.device.findUnique({
      where: { id: deviceId },
      select: { userId: true, isActive: true, revokedAt: true },
    });
    if (!device || device.userId !== userId) {
      throw notFound('device_not_found', 'Device not found');
    }
    if (!device.isActive || device.revokedAt) {
      throw forbidden('device_not_active', 'Device is not active');
    }
  }

  private async resolveActiveDeviceId(handle: string): Promise<string> {
    const user = await this.prisma.user.findUnique({
      where: { handle: handle.toLowerCase() },
      select: { id: true, activeDeviceId: true },
    });
    if (!user) {
      throw notFound('active_device_not_found', 'Active device bundle not found');
    }

    const trustedDevices = await this.prisma.device.findMany({
      where: { userId: user.id, isActive: true, revokedAt: null },
      orderBy: [{ trustedAt: 'desc' }, { lastSeenAt: 'desc' }],
      select: { id: true },
    });

    const resolved =
      trustedDevices.find((device) => device.id === user.activeDeviceId) ?? trustedDevices[0];
    if (!resolved) {
      throw notFound('active_device_not_found', 'Active device bundle not found');
    }
    return resolved.id;
  }
}
