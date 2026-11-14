import { Injectable } from '@nestjs/common';
import type { Prisma } from '@prisma/client';
import type {
  ClaimOneTimePrekeyResponse,
  OneTimePrekeyUpload,
  UploadOneTimePrekeysResponse,
} from '@veil/contracts';

import { apiError, notFound } from '../../common/errors/api-error';
import type { AuthContext } from '../../common/guards/authenticated-request';
import { pickActiveDevice } from '../../common/pick-active-device';
import { PrismaService } from '../../common/prisma.service';
import { SafetyService } from '../safety/safety.service';
import { DIRECTORY_BUDGETS, DirectoryBudget } from './directory-budget';
import { MAX_UNCONSUMED_PREKEYS_PER_DEVICE } from './dto/upload-prekeys.dto';

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
    private readonly safety: SafetyService,
  ) {}

  /**
   * Store a batch of the calling device's public one-time prekeys. Duplicate
   * (device, keyId) pairs are skipped rather than erroring, so a client can
   * safely retry an upload. Returns how many were newly stored plus the
   * device's remaining unconsumed count. A batch that would leave the device
   * holding more than MAX_UNCONSUMED_PREKEYS_PER_DEVICE unused prekeys is
   * refused whole; keys it repeats do not count, so a retry of a stored
   * batch still succeeds.
   */
  async upload(
    userId: string,
    deviceId: string,
    prekeys: OneTimePrekeyUpload[],
  ): Promise<UploadOneTimePrekeysResponse> {
    await this.assertActiveDevice(userId, deviceId);

    return this.prisma.$transaction(async (tx) => {
      // One upload per device at a time, so concurrent uploads cannot each
      // pass the cap below on a count that misses the other's rows.
      await tx.$queryRaw`SELECT 1 FROM devices WHERE id = ${deviceId}::uuid FOR UPDATE`;

      const result = await tx.oneTimePrekey.createMany({
        data: prekeys.map((prekey) => ({
          deviceId,
          keyId: prekey.keyId,
          publicKey: prekey.publicKey,
        })),
        skipDuplicates: true,
      });

      const available = await tx.oneTimePrekey.count({
        where: { deviceId, consumedAt: null },
      });
      if (available > MAX_UNCONSUMED_PREKEYS_PER_DEVICE) {
        // Thrown inside the transaction, so nothing of the batch is stored.
        throw apiError(
          'validation_failed',
          `A device may hold at most ${MAX_UNCONSUMED_PREKEYS_PER_DEVICE} unused one-time prekeys`,
        );
      }

      return { uploaded: result.count, available };
    });
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
    const target = await this.resolveActiveDevice(requester.userId, handle);
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
      throw apiError('device_not_active', 'Device is not active');
    }
  }

  // A block in either direction answers like an unknown handle.
  private async resolveActiveDevice(
    requesterUserId: string,
    handle: string,
  ): Promise<{ userId: string; deviceId: string }> {
    const user = await this.prisma.user.findUnique({
      where: { handle: handle.toLowerCase() },
      select: { id: true, activeDeviceId: true },
    });
    if (!user || (await this.safety.isBlockedEitherWay(requesterUserId, user.id))) {
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
