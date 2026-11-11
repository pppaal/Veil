import { Inject, Injectable, Optional } from '@nestjs/common';
import type {
  DeviceTransferApproveResponse,
  DeviceTransferClaimResponse,
  DeviceTransferCompleteResponse,
  DeviceTransferInitResponse,
  DeviceTransferSessionStatusResponse,
  DeviceTransferStatus,
} from '@veil/contracts';
import { createHash, randomUUID } from 'node:crypto';

import { Prisma } from '@prisma/client';

import { AppConfigService } from '../../common/config/app-config.service';
import { conflict, forbidden, notFound, unauthorized } from '../../common/errors/api-error';
import { EphemeralStoreService } from '../../common/ephemeral-store.service';
import { PrismaService } from '../../common/prisma.service';
import { DEVICE_AUTH_VERIFIER, type DeviceAuthVerifier } from '../auth/device-auth-verifier';
import { MetricsService } from '../metrics/metrics.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import {
  DeviceTransferApproveDto,
  DeviceTransferClaimDto,
  DeviceTransferCompleteDto,
  DeviceTransferInitDto,
} from './dto/device-transfer.dto';

interface PendingTransferClaim {
  claimId: string;
  newDeviceName: string;
  platform: 'ios' | 'android' | 'windows' | 'macos' | 'linux';
  publicIdentityKey: string;
  signedPrekeyBundle: string;
  authPublicKey: string;
  claimantFingerprint: string;
  approvedAt?: string;
  claimProofVerifiedAt: string;
}

const buildClaimChallenge = (sessionId: string, transferToken: string): string =>
  `transfer-claim:${sessionId}:${transferToken}`;

// 'invalidated' is not yet part of the shared DeviceTransferStatus contract.
export type TransferSessionStatus = DeviceTransferStatus | 'invalidated';
export type TransferSessionStatusResponse = Omit<DeviceTransferSessionStatusResponse, 'status'> & {
  status: TransferSessionStatus;
};

// Full SHA-256 over both keys the new device will be trusted with, in 16
// groups of 4 so the two screens can be compared group by group. A truncated
// fingerprint is cheap to collide. The auth key has already been verified as
// a 32-byte Ed25519 key, so the concatenation is unambiguous.
const claimFingerprint = (authPublicKey: string, publicIdentityKey: string): string =>
  createHash('sha256')
    .update(Buffer.from(authPublicKey, 'base64url'))
    .update(Buffer.from(publicIdentityKey, 'base64url'))
    .digest('hex')
    .replace(/(.{4})(?!$)/g, '$1 ');

const claimKey = (sessionId: string): string => `transfer:claim:${sessionId}`;

const hashToken = (token: string): string => createHash('sha256').update(token).digest('hex');

// A session killed by a competing claim keeps this in place of its token
// hash: the token can never match again, and the state stays durable (unlike
// an ephemeral marker) so the old device is never told 'completed' — which
// would make it log itself out — for a transfer that did not happen.
const INVALIDATED_TOKEN_HASH = 'invalidated';

@Injectable()
export class DeviceTransferService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly ephemeralStore: EphemeralStoreService,
    private readonly config: AppConfigService,
    @Inject(DEVICE_AUTH_VERIFIER)
    private readonly deviceAuthVerifier: DeviceAuthVerifier,
    private readonly realtimeGateway: RealtimeGateway,
    // Optional so positional-construction unit tests don't need the arg;
    // NestJS injects the @Global MetricsService in the real app.
    @Optional() private readonly metrics?: MetricsService,
  ) {}

  private countTransfer(stage: 'init' | 'claim' | 'approve' | 'complete'): void {
    try {
      this.metrics?.transferEventsTotal.inc({ stage });
    } catch {
      // best-effort telemetry
    }
  }

  async init(
    auth: { userId: string; deviceId: string },
    dto: DeviceTransferInitDto,
  ): Promise<DeviceTransferInitResponse> {
    await this.cleanupExpiredSessions({
      userId: auth.userId,
      oldDeviceId: dto.oldDeviceId,
    });

    if (auth.deviceId !== dto.oldDeviceId) {
      throw forbidden('device_forbidden', 'Transfer must be initiated from the trusted old device');
    }

    const oldDevice = await this.prisma.device.findUnique({
      where: { id: dto.oldDeviceId },
      select: {
        id: true,
        userId: true,
        isActive: true,
        revokedAt: true,
      },
    });

    if (
      !oldDevice ||
      oldDevice.userId !== auth.userId ||
      !oldDevice.isActive ||
      oldDevice.revokedAt
    ) {
      throw forbidden('device_forbidden', 'Old device is not part of the trusted device graph');
    }

    await this.invalidateExistingSessions(auth.userId, dto.oldDeviceId);

    const transferToken = randomUUID();
    const expiresAt = new Date(Date.now() + this.config.transferTokenTtlSeconds * 1000);

    const session = await this.prisma.deviceTransferSession.create({
      data: {
        userId: auth.userId,
        oldDeviceId: dto.oldDeviceId,
        tokenHash: hashToken(transferToken),
        expiresAt,
      },
    });

    this.countTransfer('init');

    return {
      sessionId: session.id,
      transferToken,
      expiresAt: expiresAt.toISOString(),
    };
  }

  async approve(
    auth: { userId: string; deviceId: string },
    dto: DeviceTransferApproveDto,
  ): Promise<DeviceTransferApproveResponse> {
    const session = await this.prisma.deviceTransferSession.findUnique({
      where: { id: dto.sessionId },
    });

    if (!session || session.userId !== auth.userId || session.oldDeviceId !== auth.deviceId) {
      throw notFound('transfer_session_not_found', 'Transfer session not found');
    }

    if (await this.closeIfInactive(session.id, session.completedAt, session.expiresAt)) {
      throw forbidden('transfer_session_inactive', 'Transfer session is no longer active');
    }

    const pendingClaim = await this.ephemeralStore.getJson<PendingTransferClaim>(
      claimKey(dto.sessionId),
    );
    if (!pendingClaim || pendingClaim.claimId !== dto.claimId) {
      throw forbidden(
        'transfer_claim_required',
        'A matching new-device claim is required before approval',
      );
    }

    await this.ephemeralStore.setJson<PendingTransferClaim>(
      claimKey(dto.sessionId),
      {
        ...pendingClaim,
        approvedAt: new Date().toISOString(),
      },
      this.config.transferTokenTtlSeconds,
    );

    this.countTransfer('approve');

    return {
      sessionId: dto.sessionId,
      claimId: dto.claimId,
      approved: true,
    };
  }

  async claim(dto: DeviceTransferClaimDto): Promise<DeviceTransferClaimResponse> {
    const session = await this.prisma.deviceTransferSession.findUnique({
      where: { id: dto.sessionId },
      include: {
        oldDevice: true,
        user: true,
      },
    });

    if (!session) {
      throw notFound('transfer_session_not_found', 'Transfer session not found');
    }

    if (await this.closeIfInactive(session.id, session.completedAt, session.expiresAt)) {
      throw forbidden('transfer_session_inactive', 'Transfer session is no longer active');
    }

    if (hashToken(dto.transferToken) !== session.tokenHash) {
      throw unauthorized('transfer_token_invalid', 'Transfer token invalid');
    }

    if (!session.oldDevice.isActive || session.oldDevice.revokedAt) {
      throw forbidden(
        'transfer_session_inactive',
        'Old trusted device is unavailable; transfer cannot proceed',
      );
    }

    const validProof = await this.deviceAuthVerifier.verifyChallengeResponse({
      challenge: buildClaimChallenge(dto.sessionId, dto.transferToken),
      proof: dto.authProof,
      authPublicKey: dto.authPublicKey,
      deviceId: dto.sessionId,
    });

    if (!validProof) {
      throw unauthorized('transfer_claim_invalid', 'New device claim proof is invalid');
    }

    const claimId = randomUUID();
    const pendingClaim: PendingTransferClaim = {
      claimId,
      newDeviceName: dto.newDeviceName,
      platform: dto.platform,
      publicIdentityKey: dto.publicIdentityKey,
      signedPrekeyBundle: dto.signedPrekeyBundle,
      authPublicKey: dto.authPublicKey,
      claimantFingerprint: claimFingerprint(dto.authPublicKey, dto.publicIdentityKey),
      claimProofVerifiedAt: new Date().toISOString(),
    };

    // First claim wins. Anyone who saw the QR code holds a valid token, so a
    // second valid claim means the code leaked: kill the whole session rather
    // than let a later claim replace the one the user is about to approve.
    const isFirstClaim = await this.ephemeralStore.setJsonIfAbsent<PendingTransferClaim>(
      claimKey(dto.sessionId),
      pendingClaim,
      this.config.transferTokenTtlSeconds,
    );
    if (!isFirstClaim) {
      await this.invalidateSession(dto.sessionId);
      throw conflict(
        'transfer_claim_invalid',
        'Transfer session was claimed twice and has been invalidated; start a new transfer',
      );
    }

    this.countTransfer('claim');

    return {
      sessionId: dto.sessionId,
      claimId,
      claimantFingerprint: pendingClaim.claimantFingerprint,
      expiresAt: session.expiresAt.toISOString(),
    };
  }

  // Polling endpoint for the old device. New-device polling rides on
  // /complete instead — same auth proof every retry, server rejects with
  // transfer_approval_required until the old device has approved.
  async getSessionStatus(args: {
    sessionId: string;
    auth: { userId: string; deviceId: string };
  }): Promise<TransferSessionStatusResponse> {
    const session = await this.prisma.deviceTransferSession.findUnique({
      where: { id: args.sessionId },
    });

    if (!session) {
      throw notFound('transfer_session_not_found', 'Transfer session not found');
    }

    if (session.userId !== args.auth.userId || session.oldDeviceId !== args.auth.deviceId) {
      throw notFound('transfer_session_not_found', 'Transfer session not found');
    }

    // A claim racing the invalidation can be rewritten after it, so an
    // invalidated session never shows one.
    const invalidated = session.tokenHash === INVALIDATED_TOKEN_HASH;
    const pendingClaim = invalidated
      ? null
      : await this.ephemeralStore.getJson<PendingTransferClaim>(claimKey(args.sessionId));

    let status: TransferSessionStatus;
    if (invalidated) {
      status = 'invalidated';
    } else if (session.completedAt) {
      status = 'completed';
    } else if (session.expiresAt.getTime() <= Date.now()) {
      status = 'expired';
    } else if (pendingClaim?.approvedAt) {
      status = 'approved';
    } else if (pendingClaim) {
      status = 'claimed';
    } else {
      status = 'pending';
    }

    return {
      sessionId: session.id,
      status,
      expiresAt: session.expiresAt.toISOString(),
      completedAt: session.completedAt && !invalidated ? session.completedAt.toISOString() : null,
      pendingClaim: pendingClaim
        ? {
            claimId: pendingClaim.claimId,
            claimantFingerprint: pendingClaim.claimantFingerprint,
            newDeviceName: pendingClaim.newDeviceName,
            platform: pendingClaim.platform,
            approvedAt: pendingClaim.approvedAt ?? null,
          }
        : null,
    };
  }

  async complete(dto: DeviceTransferCompleteDto): Promise<DeviceTransferCompleteResponse> {
    const session = await this.prisma.deviceTransferSession.findUnique({
      where: { id: dto.sessionId },
      include: {
        user: true,
        oldDevice: true,
      },
    });

    if (!session) {
      throw notFound('transfer_session_not_found', 'Transfer session not found');
    }

    if (await this.closeIfInactive(session.id, session.completedAt, session.expiresAt)) {
      throw forbidden('transfer_session_inactive', 'Transfer session already completed');
    }

    if (hashToken(dto.transferToken) !== session.tokenHash) {
      throw unauthorized('transfer_token_invalid', 'Transfer token invalid');
    }

    // Preliminary check on the cached read — the authoritative check happens
    // inside the serializable transaction below. We keep this one as an early
    // 403 so most failures still short-circuit before we spend ECDSA verify
    // and a tx round-trip.
    if (!session.oldDevice.isActive || session.oldDevice.revokedAt) {
      throw forbidden(
        'transfer_session_inactive',
        'Old trusted device is unavailable; transfer cannot proceed',
      );
    }

    const pendingClaim = await this.ephemeralStore.getJson<PendingTransferClaim>(
      claimKey(dto.sessionId),
    );

    if (!pendingClaim || pendingClaim.claimId !== dto.claimId) {
      throw forbidden(
        'transfer_claim_required',
        'A matching approved claim is required before completion',
      );
    }

    if (!pendingClaim.approvedAt) {
      throw forbidden(
        'transfer_approval_required',
        'Old device approval is required before completion',
      );
    }

    const validCompletionProof = await this.deviceAuthVerifier.verifyChallengeResponse({
      challenge: `transfer-complete:${dto.sessionId}:${dto.claimId}:${dto.transferToken}`,
      proof: dto.authProof,
      authPublicKey: pendingClaim.authPublicKey,
      deviceId: dto.claimId,
    });
    if (!validCompletionProof) {
      throw unauthorized('transfer_completion_invalid', 'New device completion proof is invalid');
    }

    const completedAt = new Date();
    const result = await this.prisma.$transaction(
      async (tx) => {
        // Re-read the old device inside the serializable tx. The cached read
        // from earlier could be stale: between that read and now, a concurrent
        // revoke could have fired. Without this re-check an attacker with
        // stolen transfer credentials could race-win against a revocation
        // that should have blocked them. Serializable isolation plus an
        // in-tx re-read closes that window.
        const freshOldDevice = await tx.device.findUnique({
          where: { id: session.oldDeviceId },
          select: { isActive: true, revokedAt: true },
        });
        if (!freshOldDevice || !freshOldDevice.isActive || freshOldDevice.revokedAt) {
          throw forbidden(
            'transfer_session_inactive',
            'Old trusted device is unavailable; transfer cannot proceed',
          );
        }

        // Also re-verify the transfer session has not been completed by a
        // concurrent call — without this, two simultaneous completes could
        // both succeed and create two "new" devices.
        const freshSession = await tx.deviceTransferSession.findUnique({
          where: { id: session.id },
          select: { completedAt: true },
        });
        if (freshSession?.completedAt) {
          throw forbidden('transfer_session_inactive', 'Transfer session already completed');
        }

        const newDevice = await tx.device.create({
          data: {
            userId: session.userId,
            deviceName: pendingClaim.newDeviceName,
            platform: pendingClaim.platform,
            publicIdentityKey: pendingClaim.publicIdentityKey,
            signedPrekeyBundle: pendingClaim.signedPrekeyBundle,
            authPublicKey: pendingClaim.authPublicKey,
            isActive: true,
            trustedAt: completedAt,
            joinedFromDeviceId: session.oldDeviceId,
          },
        });

        // Transfer means "moving to a new device", not "adding a parallel
        // device", so the old device must be revoked atomically with the
        // new one being created. Without this, the old device's access
        // token keeps working until natural expiry — bad if the user is
        // transferring because the old device was lost or compromised.
        await tx.device.update({
          where: { id: session.oldDeviceId },
          data: {
            isActive: false,
            revokedAt: completedAt,
            pushToken: null,
          },
        });

        await tx.user.update({
          where: { id: session.userId },
          data: { activeDeviceId: newDevice.id },
        });

        await tx.deviceTransferSession.update({
          where: { id: session.id },
          data: { completedAt },
        });

        return newDevice;
      },
      {
        isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
      },
    );

    await this.ephemeralStore.delete(claimKey(dto.sessionId));

    // The JwtAuthGuard now rejects any future request from the old device
    // because device.isActive is false, but a socket that connected before
    // revoke would otherwise stay open and keep delivering envelopes to a
    // device the user just told us they don't trust anymore. Cut it.
    this.realtimeGateway.disconnectDevice(session.oldDeviceId);

    this.countTransfer('complete');

    return {
      sessionId: session.id,
      claimId: dto.claimId,
      newDeviceId: result.id,
      revokedDeviceId: session.oldDeviceId,
      preferredDeviceId: result.id,
      handle: session.user.handle,
      displayName: session.user.displayName,
      completedAt: completedAt.toISOString(),
    };
  }

  private async invalidateSession(sessionId: string): Promise<void> {
    // Only an open session: a completed transfer must keep reporting completed.
    await this.prisma.deviceTransferSession.updateMany({
      where: { id: sessionId, completedAt: null },
      data: { tokenHash: INVALIDATED_TOKEN_HASH, completedAt: new Date() },
    });
    await this.ephemeralStore.delete(claimKey(sessionId));
  }

  private async invalidateExistingSessions(userId: string, oldDeviceId: string): Promise<void> {
    const openSessions = await this.prisma.deviceTransferSession.findMany({
      where: {
        userId,
        oldDeviceId,
        completedAt: null,
      },
      select: { id: true, expiresAt: true },
    });

    for (const session of openSessions) {
      await this.ephemeralStore.delete(claimKey(session.id));
    }

    if (openSessions.length > 0) {
      await this.prisma.deviceTransferSession.updateMany({
        where: {
          userId,
          oldDeviceId,
          completedAt: null,
        },
        data: {
          completedAt: new Date(),
        },
      });
    }
  }

  private async cleanupExpiredSessions(args: {
    userId: string;
    oldDeviceId?: string;
  }): Promise<void> {
    const now = new Date();
    const expired = await this.prisma.deviceTransferSession.findMany({
      where: {
        userId: args.userId,
        ...(args.oldDeviceId ? { oldDeviceId: args.oldDeviceId } : {}),
        completedAt: null,
        expiresAt: {
          lt: now,
        },
      },
      select: { id: true },
    });

    if (expired.length === 0) {
      return;
    }

    for (const session of expired) {
      await this.ephemeralStore.delete(claimKey(session.id));
    }

    await this.prisma.deviceTransferSession.updateMany({
      where: {
        id: {
          in: expired.map((session) => session.id),
        },
      },
      data: {
        completedAt: now,
      },
    });
  }

  private async closeIfInactive(
    sessionId: string,
    completedAt: Date | null,
    expiresAt: Date,
  ): Promise<boolean> {
    if (completedAt) {
      await this.ephemeralStore.delete(claimKey(sessionId));
      return true;
    }

    if (expiresAt.getTime() > Date.now()) {
      return false;
    }

    await this.ephemeralStore.delete(claimKey(sessionId));
    await this.prisma.deviceTransferSession.update({
      where: { id: sessionId },
      data: { completedAt: new Date() },
    });
    return true;
  }
}
