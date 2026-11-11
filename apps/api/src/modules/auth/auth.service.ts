import { Inject, Injectable, Optional } from '@nestjs/common';
import { Prisma, UserStatus } from '@prisma/client';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import type {
  AuthChallengeResponse,
  AuthRefreshResponse,
  AuthVerifyResponse,
  RegisterResponse,
} from '@veil/contracts';
import { JwtService } from '@nestjs/jwt';

import { AppConfigService } from '../../common/config/app-config.service';
import { conflict, notFound, unauthorized } from '../../common/errors/api-error';
import { EphemeralStoreService } from '../../common/ephemeral-store.service';
import { PrismaService } from '../../common/prisma.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { MetricsService } from '../metrics/metrics.service';
import { validatePushTokenOnRegistration } from '../push/push-endpoint.validator';
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
  familyId: string;
}

interface RefreshFamily {
  deviceId: string;
  tokenHash: string;
}

interface RotatedRefreshToken {
  familyId: string;
}

interface TokenPair {
  accessToken: string;
  refreshToken: string;
  expiresAt: string;
  refreshExpiresAt: string;
}

// Short access tokens limit the blast radius of token theft. Clients refresh
// using the long-lived refresh token, which is store-bound and revocable.
const ACCESS_TOKEN_TTL_SECONDS = 60 * 60;
const REFRESH_TOKEN_TTL_SECONDS = 60 * 60 * 24 * 30;

// Logins can legitimately overlap (a retry after a timeout, a second window),
// and a single per-device slot let anyone who knows a public deviceId cancel
// the owner's pending login just by requesting a new challenge. A small
// window removes that lockout while still bounding outstanding challenges.
const MAX_OUTSTANDING_CHALLENGES = 3;
// A device normally holds one refresh family; the least recently used ones
// are abandoned sessions and are revoked when the window overflows.
const MAX_REFRESH_FAMILIES_PER_DEVICE = 5;

const challengeKey = (challengeId: string): string => `auth:challenge:${challengeId}`;
const challengeIndexKey = (deviceId: string): string => `auth:challenge-index:${deviceId}`;
const refreshTokenKey = (tokenHash: string): string => `auth:refresh:${tokenHash}`;
const rotatedTokenKey = (tokenHash: string): string => `auth:rotated:${tokenHash}`;
const refreshFamilyKey = (familyId: string): string => `auth:refresh-family:${familyId}`;
const deviceFamiliesKey = (deviceId: string): string => `auth:refresh-families:${deviceId}`;
const jtiBlacklistKey = (jti: string): string => `auth:blacklist:${jti}`;

// Only the SHA-256 of a refresh token is ever stored, so a store dump yields
// no usable tokens.
const hashToken = (token: string): string => createHash('sha256').update(token).digest('hex');

// Moves (or appends) id to the newest end, so the oldest entries are the
// least recently used ones.
const appendKeepingNewest = (
  ids: readonly string[],
  id: string,
  limit: number,
): { kept: string[]; evicted: string[] } => {
  const all = [...ids.filter((existing) => existing !== id), id];
  return { kept: all.slice(-limit), evicted: all.slice(0, -limit) };
};

const isHandleConflict = (error: unknown): boolean => {
  if (!(error instanceof Prisma.PrismaClientKnownRequestError) || error.code !== 'P2002') {
    return false;
  }
  const target = error.meta?.target;
  return Array.isArray(target)
    ? target.includes('handle')
    : typeof target === 'string' && target.includes('handle');
};

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly ephemeralStore: EphemeralStoreService,
    private readonly jwtService: JwtService,
    private readonly config: AppConfigService,
    @Inject(DEVICE_AUTH_VERIFIER)
    private readonly deviceAuthVerifier: DeviceAuthVerifier,
    private readonly realtimeGateway: RealtimeGateway,
    // Optional so the many positional-construction unit tests don't need the
    // arg; NestJS still injects the @Global MetricsService in the real app.
    @Optional() private readonly metrics?: MetricsService,
  ) {}

  private countAuth(kind: 'register' | 'login' | 'refresh' | 'refresh_reuse' | 'logout'): void {
    try {
      this.metrics?.authEventsTotal.inc({ kind });
    } catch {
      // best-effort telemetry
    }
  }

  async register(dto: RegisterDto): Promise<RegisterResponse> {
    if (dto.pushToken) {
      validatePushTokenOnRegistration(dto.pushToken, this.config);
    }

    const normalizedHandle = dto.handle.toLowerCase();
    const existing = await this.prisma.user.findUnique({
      where: { handle: normalizedHandle },
      select: { id: true },
    });

    if (existing) {
      throw conflict('handle_taken', 'Handle is already taken');
    }

    const created = await this.prisma
      .$transaction(async (tx) => {
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
      })
      .catch((error: unknown) => {
        // Two registrations of one handle can both pass the lookup above; the
        // unique index decides, and the loser gets the same answer the lookup
        // would have given.
        throw isHandleConflict(error) ? conflict('handle_taken', 'Handle is already taken') : error;
      });

    this.countAuth('register');

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
    const ttlSeconds = this.config.authChallengeTtlSeconds;
    const expiresAt = new Date(Date.now() + ttlSeconds * 1000);

    await this.ephemeralStore.setJson<StoredChallenge>(
      challengeKey(challengeId),
      { challenge, deviceId: dto.deviceId },
      ttlSeconds,
    );
    await this.trackOutstandingChallenge(dto.deviceId, challengeId, ttlSeconds);

    return {
      challengeId,
      challenge,
      expiresAt: expiresAt.toISOString(),
    };
  }

  async verify(dto: VerifyDto): Promise<AuthVerifyResponse> {
    // Consumed on first presentation, success or failure, so a challenge can
    // never be retried with another signature.
    const stored = await this.ephemeralStore.takeJson<StoredChallenge>(
      challengeKey(dto.challengeId),
    );

    if (!stored || stored.deviceId !== dto.deviceId) {
      throw unauthorized('challenge_invalid', 'Challenge expired or invalid');
    }

    const device = await this.prisma.device.findUnique({
      where: { id: dto.deviceId },
      include: { user: true },
    });

    if (
      !device ||
      !device.isActive ||
      device.revokedAt ||
      device.user.status !== UserStatus.active
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

    const familyId = randomUUID();
    await this.recordRefreshFamily(device.id, await this.listRefreshFamilies(device.id), familyId);
    const tokens = await this.issueTokenPair(
      device.userId,
      device.id,
      device.user.handle,
      familyId,
    );

    await this.prisma.device.update({
      where: { id: device.id },
      data: { lastSeenAt: new Date() },
    });

    this.countAuth('login');

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
    // Atomic get-and-delete: of two concurrent refreshes with one token only
    // one can win; the loser lands on the rotation marker below.
    const stored = await this.ephemeralStore.takeJson<StoredRefreshToken>(
      refreshTokenKey(tokenHash),
    );

    if (!stored) {
      // A rotated token coming back means two parties hold the family: the
      // client and whoever copied a token. The server cannot tell which is
      // which, so the whole family dies and the device must prove possession
      // of its auth key again.
      const rotated = await this.ephemeralStore.getJson<RotatedRefreshToken>(
        rotatedTokenKey(tokenHash),
      );
      if (rotated) {
        await this.revokeRefreshFamily(rotated.familyId);
        this.countAuth('refresh_reuse');
      }
      throw unauthorized('refresh_token_invalid', 'Refresh token invalid');
    }

    await this.ephemeralStore.setJson<RotatedRefreshToken>(
      rotatedTokenKey(tokenHash),
      { familyId: stored.familyId },
      REFRESH_TOKEN_TTL_SECONDS,
    );

    // A token is only as alive as its family: logout or reuse detection may
    // have revoked the family after this token was issued.
    const family = await this.ephemeralStore.getJson<RefreshFamily>(
      refreshFamilyKey(stored.familyId),
    );
    if (family?.tokenHash !== tokenHash) {
      throw unauthorized('refresh_token_invalid', 'Refresh token invalid');
    }

    // Logout revokes exactly the families the device index lists, so a family
    // the index lost (to a concurrent read-modify-write) is refused here
    // instead of living on beyond logout's reach.
    const deviceFamilies = await this.listRefreshFamilies(stored.deviceId);
    if (!deviceFamilies.includes(stored.familyId)) {
      await this.revokeRefreshFamily(stored.familyId);
      throw unauthorized('refresh_token_invalid', 'Refresh token invalid');
    }

    const device = await this.prisma.device.findUnique({
      where: { id: stored.deviceId },
      include: { user: true },
    });

    if (
      !device ||
      device.userId !== stored.userId ||
      !device.isActive ||
      device.revokedAt ||
      device.user.status !== UserStatus.active
    ) {
      throw unauthorized('device_not_active', 'Device is not active');
    }

    // Every rotation renews the family, so it must renew the index entry too:
    // otherwise a device that only ever refreshes outlives its index and
    // logout finds nothing to revoke.
    await this.recordRefreshFamily(device.id, deviceFamilies, stored.familyId);
    const tokens = await this.issueTokenPair(
      device.userId,
      device.id,
      device.user.handle,
      stored.familyId,
    );

    await this.prisma.device.update({
      where: { id: device.id },
      data: { lastSeenAt: new Date() },
    });

    this.countAuth('refresh');

    return {
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: tokens.expiresAt,
      refreshExpiresAt: tokens.refreshExpiresAt,
    };
  }

  // Logout ends every session of the device, whether or not the client still
  // has, or sends, its refresh token.
  async logout(authContext: {
    userId: string;
    deviceId: string;
    jti?: string;
    exp?: number;
  }): Promise<{ ok: true }> {
    const familyIds =
      (await this.ephemeralStore.takeJson<string[]>(deviceFamiliesKey(authContext.deviceId))) ?? [];
    for (const familyId of familyIds) {
      await this.revokeRefreshFamily(familyId);
    }

    if (authContext.jti && authContext.exp) {
      const ttlSeconds = Math.max(1, authContext.exp - Math.floor(Date.now() / 1000));
      await this.ephemeralStore.setJson<{ userId: string; deviceId: string }>(
        jtiBlacklistKey(authContext.jti),
        { userId: authContext.userId, deviceId: authContext.deviceId },
        ttlSeconds,
      );
    }

    // Forcibly cut any active WS sockets bound to this device so the realtime
    // channel doesn't outlive the access token. The blacklist check above
    // also stops new sockets, but existing ones don't re-verify the JWT.
    this.realtimeGateway.disconnectDevice(authContext.deviceId);

    this.countAuth('logout');

    return { ok: true };
  }

  // The per-device index is read-modify-write, so concurrent requests can
  // drop an id from it; such a challenge just lives out its short TTL.
  private async trackOutstandingChallenge(
    deviceId: string,
    challengeId: string,
    ttlSeconds: number,
  ): Promise<void> {
    const outstanding =
      (await this.ephemeralStore.getJson<string[]>(challengeIndexKey(deviceId))) ?? [];
    const { kept, evicted } = appendKeepingNewest(
      outstanding,
      challengeId,
      MAX_OUTSTANDING_CHALLENGES,
    );
    for (const evictedId of evicted) {
      await this.ephemeralStore.delete(challengeKey(evictedId));
    }
    await this.ephemeralStore.setJson(challengeIndexKey(deviceId), kept, ttlSeconds);
  }

  private async listRefreshFamilies(deviceId: string): Promise<string[]> {
    return (await this.ephemeralStore.getJson<string[]>(deviceFamiliesKey(deviceId))) ?? [];
  }

  // Marks familyId as the device's most recently used family and gives the
  // index a full refresh TTL, so the index outlives every family it lists.
  // Families pushed out of the window are revoked.
  private async recordRefreshFamily(
    deviceId: string,
    families: readonly string[],
    familyId: string,
  ): Promise<void> {
    const { kept, evicted } = appendKeepingNewest(
      families,
      familyId,
      MAX_REFRESH_FAMILIES_PER_DEVICE,
    );
    for (const evictedId of evicted) {
      await this.revokeRefreshFamily(evictedId);
    }
    await this.ephemeralStore.setJson(deviceFamiliesKey(deviceId), kept, REFRESH_TOKEN_TTL_SECONDS);
  }

  private async revokeRefreshFamily(familyId: string): Promise<void> {
    const family = await this.ephemeralStore.takeJson<RefreshFamily>(refreshFamilyKey(familyId));
    if (family) {
      await this.ephemeralStore.delete(refreshTokenKey(family.tokenHash));
    }
  }

  private async issueTokenPair(
    userId: string,
    deviceId: string,
    handle: string,
    familyId: string,
  ): Promise<TokenPair> {
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
    const tokenHash = hashToken(refreshToken);
    await this.ephemeralStore.setJson<StoredRefreshToken>(
      refreshTokenKey(tokenHash),
      { userId, deviceId, familyId },
      REFRESH_TOKEN_TTL_SECONDS,
    );
    await this.ephemeralStore.setJson<RefreshFamily>(
      refreshFamilyKey(familyId),
      { deviceId, tokenHash },
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
