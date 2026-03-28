import {
  ConflictException,
  Inject,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { UserStatus } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import type {
  AuthChallengeResponse,
  AuthVerifyResponse,
  RegisterResponse,
} from '@veil/contracts';
import { JwtService } from '@nestjs/jwt';

import { AppConfigService } from '../../common/config/app-config.service';
import { EphemeralStoreService } from '../../common/ephemeral-store.service';
import { PrismaService } from '../../common/prisma.service';
import { RegisterDto } from './dto/register.dto';
import { ChallengeDto, VerifyDto } from './dto/challenge.dto';
import { DEVICE_AUTH_VERIFIER, type DeviceAuthVerifier } from './device-auth-verifier';

interface StoredChallenge {
  challenge: string;
  deviceId: string;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly ephemeralStore: EphemeralStoreService,
    private readonly jwtService: JwtService,
    private readonly config: AppConfigService,
    @Inject(DEVICE_AUTH_VERIFIER)
    private readonly deviceAuthVerifier: DeviceAuthVerifier,
  ) {}

  async register(dto: RegisterDto): Promise<RegisterResponse> {
    const normalizedHandle = dto.handle.toLowerCase();
    const existing = await this.prisma.user.findUnique({
      where: { handle: normalizedHandle },
      select: { id: true },
    });

    if (existing) {
      throw new ConflictException('Handle is already taken');
    }

    const created = await this.prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          handle: normalizedHandle,
          displayName: dto.displayName,
          status: UserStatus.active,
        },
      });

      const device = await tx.device.create({
        data: {
          userId: user.id,
          deviceName: dto.deviceName,
          platform: dto.platform,
          publicIdentityKey: dto.publicIdentityKey,
          signedPrekeyBundle: dto.signedPrekeyBundle,
          authPublicKey: dto.authPublicKey,
          pushToken: dto.pushToken,
          isActive: true,
        },
      });

      await tx.user.update({
        where: { id: user.id },
        data: { activeDeviceId: device.id },
      });

      return { user, device };
    });

    return {
      userId: created.user.id,
      deviceId: created.device.id,
      handle: created.user.handle,
      status: created.user.status,
    };
  }

  async createChallenge(dto: ChallengeDto): Promise<AuthChallengeResponse> {
    const user = await this.prisma.user.findUnique({
      where: { handle: dto.handle.toLowerCase() },
      select: { id: true },
    });

    if (!user) {
      throw new NotFoundException('Handle not found');
    }

    const device = await this.prisma.device.findFirst({
      where: {
        id: dto.deviceId,
        userId: user.id,
        isActive: true,
        revokedAt: null,
      },
      select: { id: true },
    });

    if (!device) {
      throw new NotFoundException('Active device not found for handle');
    }

    const challengeId = randomUUID();
    const challenge = randomUUID();
    const expiresAt = new Date(Date.now() + this.config.authChallengeTtlSeconds * 1000);

    await this.ephemeralStore.setJson<StoredChallenge>(
      `auth:challenge:${challengeId}`,
      { challenge, deviceId: dto.deviceId },
      this.config.authChallengeTtlSeconds,
    );

    return {
      challengeId,
      challenge,
      expiresAt: expiresAt.toISOString(),
    };
  }

  async verify(dto: VerifyDto): Promise<AuthVerifyResponse> {
    const stored = await this.ephemeralStore.getJson<StoredChallenge>(
      `auth:challenge:${dto.challengeId}`,
    );

    if (!stored || stored.deviceId !== dto.deviceId) {
      throw new UnauthorizedException('Challenge expired or invalid');
    }

    const device = await this.prisma.device.findUnique({
      where: { id: dto.deviceId },
      include: { user: true },
    });

    if (
      !device ||
      !device.isActive ||
      device.revokedAt ||
      device.user.activeDeviceId !== device.id
    ) {
      throw new UnauthorizedException('Device is not active');
    }

    const isValid = await this.deviceAuthVerifier.verifyChallengeResponse({
      challenge: stored.challenge,
      proof: dto.signature,
      authPublicKey: device.authPublicKey,
      deviceId: device.id,
    });
    if (!isValid) {
      throw new UnauthorizedException('Invalid device signature');
    }

    await this.ephemeralStore.delete(`auth:challenge:${dto.challengeId}`);

    const expiresInSeconds = 60 * 60 * 12;
    const accessToken = await this.jwtService.signAsync(
      {
        sub: device.userId,
        deviceId: device.id,
        handle: device.user.handle,
      },
      {
        secret: this.config.jwtSecret,
        audience: this.config.jwtAudience,
        issuer: this.config.jwtIssuer,
        expiresIn: expiresInSeconds,
      },
    );

    await this.prisma.device.update({
      where: { id: device.id },
      data: { lastSeenAt: new Date() },
    });

    return {
      accessToken,
      deviceId: device.id,
      userId: device.userId,
      expiresAt: new Date(Date.now() + expiresInSeconds * 1000).toISOString(),
    };
  }
}
