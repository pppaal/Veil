import {
  Inject,
  Injectable,
} from '@nestjs/common';
import { UserStatus } from '@prisma/client';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import type {
  AuthChallengeResponse,
  AuthLogoutRequest,
  AuthRefreshResponse,
  AuthVerifyResponse,
  RegisterResponse,
} from '@veil/contracts';
import { JwtService } from '@nestjs/jwt';

import { AppConfigService } from '../../common/config/app-config.service';
import {
  conflict,
  notFound,
  unauthorized,
} from '../../common/errors/api-error';
import { EphemeralStoreService } from '../../common/ephemeral-store.service';
import { PrismaService } from '../../common/prisma.service';
import { RegisterDto } from './dto/register.dto';
import { ChallengeDto, VerifyDto } from './dto/challenge.dto';
import { DEVICE_AUTH_VERIFIER, type DeviceAuthVerifier } from './device-auth-verifier';

interface StoredChallenge {
  challenge: string;
  deviceId: string;
}

interface StoredRefreshToken {
  userId: string;
  deviceId: string;
  issuedAt: number;
}

const ACCESS_TOKEN_TTL_SECONDS = 60 * 60 * 12;
const REFRESH_TOKEN_TTL_SECONDS = 60 * 60 * 24 * 30;

const challengeKey = (challengeId: string): string => `auth:challenge:${challengeId}`;
const activeChallengeKey = (deviceId: string): string => `auth:challenge:device:${deviceId}`;
const refreshTokenKey = (tokenHash: string): string => `auth:refresh:${tokenHash}`;
const jtiBlacklistKey = (jti: string): string => `auth:blacklist:${jti}`;

const hashToken = (token: string): string =>
  createHash('sha256').update(token).digest('hex');

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
      throw conflict('handle_taken', 'Handle is already taken');
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
      throw notFound('handle_not_found', 'Handle not found');
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
      throw notFound('active_device_not_found', 'Active device not found for handle');
    }

    const challengeId = randomUUID();
    const challenge = randomUUID();
    const expiresAt = new Date(Date.now() + this.config.authChallengeTtlSeconds * 1000);

    const previousChallengeId = await this.ephemeralStore.getJson<string>(
      activeChallengeKey(dto.deviceId),
    );
    if (previousChallengeId) {
      await this.ephemeralStore.delete(challengeKey(previousChallengeId));
    }

    await this.ephemeralStore.setJson<StoredChallenge>(
      challengeKey(challengeId),
      { challenge, deviceId: dto.deviceId },
      this.config.authChallengeTtlSeconds,
    );
    await this.ephemeralStore.setJson<string>(
      activeChallengeKey(dto.deviceId),
      challengeId,
      this.config.authChallengeTtlSeconds,
    );

    return {
      challengeId,
      challenge,
      expiresAt: expiresAt.toISOString(),
    };
  }

  async verify(dto: VerifyDto): Promise<AuthVerifyResponse> {
    const stored = await this.ephemeralStore.getJson<StoredChallenge>(challengeKey(dto.challengeId));
    const activeChallengeId = await this.ephemeralStore.getJson<string>(
      activeChallengeKey(dto.deviceId),
    );

    if (
      !stored ||
      stored.deviceId !== dto.deviceId ||
      activeChallengeId !== dto.challengeId
    ) {
      throw unauthorized('challenge_invalid', 'Challenge expired or invalid');
    }

    await this.ephemeralStore.delete(challengeKey(dto.challengeId));
    await this.ephemeralStore.delete(activeChallengeKey(dto.deviceId));

    const device = await this.prisma.device.findUnique({
      where: { id: dto.deviceId },
      include: { user: true },
    });

    if (
      !device ||
      !device.isActive ||
      device.revokedAt
    ) {
      throw unauthorized('device_not_active', 'Device is not active');
    }

    const isValid = await this.deviceAuthVerifier.verifyChallengeResponse({
      challenge: stored.challenge,
      proof: dto.signature,
      authPublicKey: device.authPublicKey,
      deviceId: device.id,
    });
    if (!isValid) {
      throw unauthorized('invalid_device_signature', 'Invalid device signature');
    }

    const tokens = await this.issueTokenPair(device.userId, device.id, device.user.handle);

    await this.prisma.device.update({
      where: { id: device.id },
      data: { lastSeenAt: new Date() },
    });

    return {
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      deviceId: device.id,
      userId: device.userId,
      expiresAt: tokens.expiresAt,
      refreshExpiresAt: tokens.refreshExpiresAt,
    };
  }

  async refresh(refreshToken: string): Promise<AuthRefreshResponse> {
    if (!refreshToken) {
      throw unauthorized('refresh_token_invalid', 'Refresh token invalid');
    }

    const tokenHash = hashToken(refreshToken);
    const stored = await this.ephemeralStore.getJson<StoredRefreshToken>(
      refreshTokenKey(tokenHash),
    );

    if (!stored) {
      throw unauthorized('refresh_token_invalid', 'Refresh token invalid');
    }

    // Single-use refresh: revoke the presented token immediately to block replay.
    await this.ephemeralStore.delete(refreshTokenKey(tokenHash));

    const device = await this.prisma.device.findUnique({
      where: { id: stored.deviceId },
      include: { user: true },
    });

    if (
      !device ||
      device.userId !== stored.userId ||
      !device.isActive ||
      device.revokedAt
    ) {
      throw unauthorized('device_not_active', 'Device is not active');
    }

    const tokens = await this.issueTokenPair(device.userId, device.id, device.user.handle);

    await this.prisma.device.update({
      where: { id: device.id },
      data: { lastSeenAt: new Date() },
    });

    return {
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: tokens.expiresAt,
      refreshExpiresAt: tokens.refreshExpiresAt,
    };
  }

  async logout(
    authContext: { userId: string; deviceId: string; jti?: string; exp?: number },
    dto: AuthLogoutRequest,
  ): Promise<{ ok: true }> {
    if (dto.refreshToken) {
      const tokenHash = hashToken(dto.refreshToken);
      const stored = await this.ephemeralStore.getJson<StoredRefreshToken>(
        refreshTokenKey(tokenHash),
      );
      if (stored && stored.deviceId === authContext.deviceId) {
        await this.ephemeralStore.delete(refreshTokenKey(tokenHash));
      }
    }

    if (authContext.jti && authContext.exp) {
      const ttlSeconds = Math.max(1, authContext.exp - Math.floor(Date.now() / 1000));
      await this.ephemeralStore.setJson<{ userId: string; deviceId: string }>(
        jtiBlacklistKey(authContext.jti),
        { userId: authContext.userId, deviceId: authContext.deviceId },
        ttlSeconds,
      );
    }

    return { ok: true };
  }

  private async issueTokenPair(
    userId: string,
    deviceId: string,
    handle: string,
  ): Promise<{
    accessToken: string;
    refreshToken: string;
    expiresAt: string;
    refreshExpiresAt: string;
  }> {
    const jti = randomUUID();
    const accessToken = await this.jwtService.signAsync(
      {
        sub: userId,
        deviceId,
        handle,
        jti,
      },
      {
        secret: this.config.jwtSecret,
        audience: this.config.jwtAudience,
        issuer: this.config.jwtIssuer,
        expiresIn: ACCESS_TOKEN_TTL_SECONDS,
      },
    );

    const refreshToken = randomBytes(48).toString('base64url');
    await this.ephemeralStore.setJson<StoredRefreshToken>(
      refreshTokenKey(hashToken(refreshToken)),
      { userId, deviceId, issuedAt: Date.now() },
      REFRESH_TOKEN_TTL_SECONDS,
    );

    const now = Date.now();
    return {
      accessToken,
      refreshToken,
      expiresAt: new Date(now + ACCESS_TOKEN_TTL_SECONDS * 1000).toISOString(),
      refreshExpiresAt: new Date(now + REFRESH_TOKEN_TTL_SECONDS * 1000).toISOString(),
    };
  }
}
