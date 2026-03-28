import {
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import type {
  DeviceTransferApproveResponse,
  DeviceTransferCompleteResponse,
  DeviceTransferInitResponse,
} from '@veil/contracts';
import { createHash, randomUUID } from 'node:crypto';

import { AppConfigService } from '../../common/config/app-config.service';
import { EphemeralStoreService } from '../../common/ephemeral-store.service';
import { PrismaService } from '../../common/prisma.service';
import {
  DeviceTransferApproveDto,
  DeviceTransferCompleteDto,
  DeviceTransferInitDto,
} from './dto/device-transfer.dto';

interface PendingTransferApproval {
  newDeviceName: string;
  platform: 'ios' | 'android';
  publicIdentityKey: string;
  signedPrekeyBundle: string;
  authPublicKey: string;
}

const hashToken = (token: string): string =>
  createHash('sha256').update(token).digest('hex');

@Injectable()
export class DeviceTransferService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly ephemeralStore: EphemeralStoreService,
    private readonly config: AppConfigService,
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

    await this.ephemeralStore.setJson<PendingTransferApproval>(
      `transfer:approval:${dto.sessionId}`,
      {
        newDeviceName: dto.newDeviceName,
        platform: dto.platform,
        publicIdentityKey: dto.publicIdentityKey,
        signedPrekeyBundle: dto.signedPrekeyBundle,
        authPublicKey: dto.authPublicKey,
      },
      this.config.transferTokenTtlSeconds,
    );

    return {
      sessionId: dto.sessionId,
      approved: true,
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

    const pendingApproval = await this.ephemeralStore.getJson<PendingTransferApproval>(
      `transfer:approval:${dto.sessionId}`,
    );

    if (!pendingApproval) {
      throw new ForbiddenException('Old device approval is required before completion');
    }

    const completedAt = new Date();
    const result = await this.prisma.$transaction(async (tx) => {
      const newDevice = await tx.device.create({
        data: {
          userId: session.userId,
          deviceName: pendingApproval.newDeviceName,
          platform: pendingApproval.platform,
          publicIdentityKey: pendingApproval.publicIdentityKey,
          signedPrekeyBundle: pendingApproval.signedPrekeyBundle,
          authPublicKey: pendingApproval.authPublicKey,
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

    await this.ephemeralStore.delete(`transfer:approval:${dto.sessionId}`);

    return {
      sessionId: session.id,
      newDeviceId: result.id,
      revokedDeviceId: session.oldDeviceId,
      completedAt: completedAt.toISOString(),
    };
  }
}
