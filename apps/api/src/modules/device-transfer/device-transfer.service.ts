import {
  Inject,
  Injectable,
} from '@nestjs/common';
import type {
  DeviceTransferApproveResponse,
  DeviceTransferClaimResponse,
  DeviceTransferCompleteResponse,
  DeviceTransferInitResponse,
} from '@veil/contracts';
import { createHash, randomUUID } from 'node:crypto';

import { Prisma } from '@prisma/client';

import { AppConfigService } from '../../common/config/app-config.service';
import {
  forbidden,
  notFound,
  unauthorized,
} from '../../common/errors/api-error';
import { EphemeralStoreService } from '../../common/ephemeral-store.service';
import { PrismaService } from '../../common/prisma.service';
import { DEVICE_AUTH_VERIFIER, type DeviceAuthVerifier } from '../auth/device-auth-verifier';
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

const claimFingerprint = (authPublicKey: string): string =>
  authPublicKey.length <= 12
    ? authPublicKey
    : `${authPublicKey.substring(0, 6)}...${authPublicKey.substring(authPublicKey.length - 4)}`;

const claimKey = (sessionId: string): string => `transfer:claim:${sessionId}`;

const hashToken = (token: string): string =>
  createHash('sha256').update(token).digest('hex');

@Injectable()
export class DeviceTransferService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly ephemeralStore: EphemeralStoreService,
    private readonly config: AppConfigService,
    @Inject(DEVICE_AUTH_VERIFIER)
    private readonly deviceAuthVerifier: DeviceAuthVerifier,
    private readonly realtimeGateway: RealtimeGateway,
  ) {}

  async init(
    auth: { userId: string; deviceId: string },
    dto: DeviceTransferInitDto,
  ): Promise<DeviceTransferInitResponse> {
    await this.cleanupExpiredSessions({
      userId: auth.userId,
      oldDeviceId: dto.oldDeviceId,
    });

    if (auth.deviceId !== dto.oldDeviceId) {
      throw forbidden(
        'device_forbidden',
        'Transfer must be initiated from the trusted old device',
      );
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

    if (!oldDevice || oldDevice.userId !== auth.userId || !oldDevice.isActive || oldDevice.revokedAt) {
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

    const pendingClaim = await this.ephemeralStore.getJson<PendingTransferClaim>(claimKey(dto.sessionId));
    if (!pendingClaim || pendingClaim.claimId !== dto.claimId) {
      throw forbidden('transfer_claim_required', 'A matching new-device claim is required before approval');
    }

    await this.ephemeralStore.setJson<PendingTransferClaim>(
      claimKey(dto.sessionId),
      {
        ...pendingClaim,
        approvedAt: new Date().toISOString(),
      },
      this.config.transferTokenTtlSeconds,
    );

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
      claimantFingerprint: claimFingerprint(dto.authPublicKey),
      claimProofVerifiedAt: new Date().toISOString(),
    };

    await this.ephemeralStore.setJson<PendingTransferClaim>(
      claimKey(dto.sessionId),
      pendingClaim,
      this.config.transferTokenTtlSeconds,
    );

    return {
      sessionId: dto.sessionId,
      claimId,
      claimantFingerprint: pendingClaim.claimantFingerprint,
      expiresAt: session.expiresAt.toISOString(),
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

    const pendingClaim = await this.ephemeralStore.getJson<PendingTransferClaim>(claimKey(dto.sessionId));

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
          throw forbidden(
            'transfer_session_inactive',
            'Transfer session already completed',
          );
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

    return {
      sessionId: session.id,
      claimId: dto.claimId,
      newDeviceId: result.id,
      revokedDeviceId: null,
      preferredDeviceId: result.id,
      handle: session.user.handle,
      displayName: session.user.displayName,
      completedAt: completedAt.toISOString(),
    };
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
