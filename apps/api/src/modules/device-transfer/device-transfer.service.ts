import {
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import type {
  DeviceTransferApproveResponse,
  DeviceTransferClaimResponse,
  DeviceTransferCompleteResponse,
  DeviceTransferInitResponse,
} from '@veil/contracts';
import { createHash, randomUUID } from 'node:crypto';

import { AppConfigService } from '../../common/config/app-config.service';
import { EphemeralStoreService } from '../../common/ephemeral-store.service';
import { PrismaService } from '../../common/prisma.service';
import { DEVICE_AUTH_VERIFIER, type DeviceAuthVerifier } from '../auth/device-auth-verifier';
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
  ) {}

  async init(
    auth: { userId: string; deviceId: string },
    dto: DeviceTransferInitDto,
  ): Promise<DeviceTransferInitResponse> {
    if (auth.deviceId !== dto.oldDeviceId) {
      throw new ForbiddenException('Transfer must be initiated from the active old device');
    }

    const user = await this.prisma.user.findUnique({
      where: { id: auth.userId },
      select: { activeDeviceId: true },
    });

    if (!user || user.activeDeviceId !== dto.oldDeviceId) {
      throw new ForbiddenException('Old device is not the active bound device');
    }

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
      throw new NotFoundException('Transfer session not found');
    }

    if (session.completedAt || session.expiresAt.getTime() <= Date.now()) {
      throw new ForbiddenException('Transfer session is no longer active');
    }

    const pendingClaim = await this.ephemeralStore.getJson<PendingTransferClaim>(claimKey(dto.sessionId));
    if (!pendingClaim || pendingClaim.claimId !== dto.claimId) {
      throw new ForbiddenException('A matching new-device claim is required before approval');
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
      throw new NotFoundException('Transfer session not found');
    }

    if (session.completedAt || session.expiresAt.getTime() <= Date.now()) {
      throw new ForbiddenException('Transfer session is no longer active');
    }

    if (hashToken(dto.transferToken) !== session.tokenHash) {
      throw new UnauthorizedException('Transfer token invalid');
    }

    if (!session.oldDevice.isActive || session.oldDevice.revokedAt) {
      throw new ForbiddenException('Old device is unavailable; transfer cannot proceed');
    }

    if (session.user.activeDeviceId !== session.oldDeviceId) {
      throw new ForbiddenException('Old device is no longer active; transfer cannot proceed');
    }

    const validProof = await this.deviceAuthVerifier.verifyChallengeResponse({
      challenge: buildClaimChallenge(dto.sessionId, dto.transferToken),
      proof: dto.authProof,
      authPublicKey: dto.authPublicKey,
      deviceId: dto.sessionId,
    });

    if (!validProof) {
      throw new UnauthorizedException('New device claim proof is invalid');
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
      throw new NotFoundException('Transfer session not found');
    }

    if (session.completedAt) {
      throw new ForbiddenException('Transfer session already completed');
    }

    if (session.expiresAt.getTime() <= Date.now()) {
      throw new ForbiddenException('Transfer session expired');
    }

    if (hashToken(dto.transferToken) !== session.tokenHash) {
      throw new UnauthorizedException('Transfer token invalid');
    }

    if (!session.oldDevice.isActive || session.oldDevice.revokedAt) {
      throw new ForbiddenException('Old device is unavailable; transfer cannot proceed');
    }

    if (session.user.activeDeviceId !== session.oldDeviceId) {
      throw new ForbiddenException('Old device is no longer active; transfer cannot proceed');
    }

    const pendingClaim = await this.ephemeralStore.getJson<PendingTransferClaim>(claimKey(dto.sessionId));

    if (!pendingClaim || pendingClaim.claimId !== dto.claimId) {
      throw new ForbiddenException('A matching approved claim is required before completion');
    }

    if (!pendingClaim.approvedAt) {
      throw new ForbiddenException('Old device approval is required before completion');
    }

    const completedAt = new Date();
    const result = await this.prisma.$transaction(async (tx) => {
      const newDevice = await tx.device.create({
        data: {
          userId: session.userId,
          deviceName: pendingClaim.newDeviceName,
          platform: pendingClaim.platform,
          publicIdentityKey: pendingClaim.publicIdentityKey,
          signedPrekeyBundle: pendingClaim.signedPrekeyBundle,
          authPublicKey: pendingClaim.authPublicKey,
          isActive: true,
        },
      });

      await tx.device.update({
        where: { id: session.oldDeviceId },
        data: {
          isActive: false,
          revokedAt: completedAt,
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
    });

    await this.ephemeralStore.delete(claimKey(dto.sessionId));

    return {
      sessionId: session.id,
      claimId: dto.claimId,
      newDeviceId: result.id,
      revokedDeviceId: session.oldDeviceId,
      handle: session.user.handle,
      displayName: session.user.displayName,
      completedAt: completedAt.toISOString(),
    };
  }
}
