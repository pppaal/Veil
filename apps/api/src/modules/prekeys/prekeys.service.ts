import { Injectable } from '@nestjs/common';
import type { Prisma } from '@prisma/client';
import type {
  ClaimOneTimePrekeyResponse,
  OneTimePrekeyUpload,
  UploadOneTimePrekeysResponse,
} from '@veil/contracts';

import { forbidden, notFound } from '../../common/errors/api-error';
import type { AuthContext } from '../../common/guards/authenticated-request';
import { pickActiveDevice } from '../../common/pick-active-device';
import { PrismaService } from '../../common/prisma.service';
import { DIRECTORY_BUDGETS, DirectoryBudget } from './directory-budget';

// How many times the atomic claim retries when it loses the race for a
// candidate prekey to a concurrent claimer before giving up and reporting the
// pool as depleted.
const CLAIM_MAX_ATTEMPTS = 5;

export type DirectoryRequester = Pick<AuthContext, 'userId' | 'deviceId'>;

type PrekeyClaimClient = Pick<Prisma.TransactionClient, 'oneTimePrekey'>;

@Injectable()
export class PrekeysService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly budget: DirectoryBudget,
  ) {}

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
   * Legacy single-device claim for the handle's active device. It spends the
   * same budgets as GET /v1/keys, so neither route can drain a pool faster.
   */
  async claim(requester: DirectoryRequester, handle: string): Promise<ClaimOneTimePrekeyResponse> {
    const target = await this.resolveActiveDevice(handle);
    const claimed = await this.claimWithinBudget(requester, target.userId, [target.deviceId]);
    return { deviceId: target.deviceId, prekey: claimed.get(target.deviceId) ?? null };
  }

  /**
   * Claims one prekey per listed device of the target, in one transaction.
   * Devices missing from the result got nothing: the requester looked up its
   * own account, a budget is spent, or the pool is empty. A spent budget
   * consumes nothing, so draining degrades sessions to signed-prekey-only
   * X3DH instead of emptying the pool.
   */
  async claimWithinBudget(
    requester: DirectoryRequester,
    targetUserId: string,
    deviceIds: readonly string[],
  ): Promise<Map<string, OneTimePrekeyUpload>> {
    if (deviceIds.length === 0 || requester.userId === targetUserId) {
      return new Map();
    }

    const withinRequesterBudget = await this.budget.tryConsume(
      DIRECTORY_BUDGETS.prekeyClaimsPerRequester,
      requester.deviceId,
      targetUserId,
    );
    if (!withinRequesterBudget) {
      return new Map();
    }

    const claimable: string[] = [];
    for (const deviceId of deviceIds) {
      if (await this.budget.tryConsume(DIRECTORY_BUDGETS.prekeyClaimsPerTargetDevice, deviceId)) {
        claimable.push(deviceId);
      }
    }
    if (claimable.length === 0) {
      return new Map();
    }
    // Claim in id order, not listing order (which follows lastSeenAt), so two
    // concurrent lookups of the same account lock prekey rows in the same
    // order and cannot deadlock each other.
    claimable.sort();

    return this.prisma.$transaction(async (tx) => {
      const claimed = new Map<string, OneTimePrekeyUpload>();
      for (const deviceId of claimable) {
        const prekey = await this.claimForDevice(tx, deviceId);
        if (prekey) {
          claimed.set(deviceId, prekey);
        }
      }
      return claimed;
    });
  }

  /**
   * Atomically claim the device's lowest unused prekey. The claim marks the
   * row consumed under a guard so two concurrent claimers can never receive
   * the same prekey.
   */
  private async claimForDevice(
    client: PrekeyClaimClient,
    deviceId: string,
  ): Promise<OneTimePrekeyUpload | null> {
    for (let attempt = 0; attempt < CLAIM_MAX_ATTEMPTS; attempt += 1) {
      const candidate = await client.oneTimePrekey.findFirst({
        where: { deviceId, consumedAt: null },
        orderBy: { keyId: 'asc' },
        select: { id: true, keyId: true, publicKey: true },
      });

      if (!candidate) {
        return null;
      }

      // The consumedAt: null guard is the race breaker: only the first claimer
      // to commit flips it, the loser's updateMany matches zero rows and retries
      // with the next candidate.
      const claimed = await client.oneTimePrekey.updateMany({
        where: { id: candidate.id, consumedAt: null },
        data: { consumedAt: new Date() },
      });

      if (claimed.count === 1) {
        return { keyId: candidate.keyId, publicKey: candidate.publicKey };
      }
    }

    // Contended to exhaustion — treat as depleted; the initiator degrades
    // gracefully rather than failing the session.
    return null;
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

  private async resolveActiveDevice(handle: string): Promise<{ userId: string; deviceId: string }> {
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

    const resolved = pickActiveDevice(trustedDevices, user.activeDeviceId);
    if (!resolved) {
      throw notFound('active_device_not_found', 'Active device bundle not found');
    }
    return { userId: user.id, deviceId: resolved.id };
  }
}
