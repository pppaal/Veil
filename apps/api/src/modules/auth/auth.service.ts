import { Inject, Injectable, Optional } from '@nestjs/common';
import { Prisma, UserStatus } from '@prisma/client';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import type {
  AuthChallengeResponse,
  AuthRefreshResponse,
  AuthVerifyResponse,
  DeviceStepUpProof,
  RegisterResponse,
} from '@veil/contracts';
import { JwtService } from '@nestjs/jwt';
import { isUUID } from 'class-validator';

import { jtiBlacklistKey, refreshFamilyKey } from '../../common/access-token-revocation';
import { AppConfigService } from '../../common/config/app-config.service';
import { recordDeviceSeen, utcDayStart } from '../../common/device-activity';
import { apiError, conflict, unauthorized } from '../../common/errors/api-error';
import { EphemeralStoreService } from '../../common/ephemeral-store.service';
import { PrismaService } from '../../common/prisma.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { RetiredHandlesService } from '../handles/retired-handles.service';
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

interface LegacyRotatedToken {
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
// Refresh state expires at a UTC midnight 31 days after the day it was last
// renewed, never at "now + 30 days": a relative TTL would keep the moment of
// every refresh in the key's expiry, an activity timeline finer than the UTC
// day device activity is kept to (common/device-activity.ts). A session lives
// at least 30 days.
const REFRESH_TOKEN_LIFETIME_DAYS = 31;
const DAY_MS = 24 * 60 * 60 * 1000;

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
// Only for tokens issued before they carried their family id; see refresh().
const legacyRotatedTokenKey = (tokenHash: string): string => `auth:rotated:${tokenHash}`;
const deviceFamiliesKey = (deviceId: string): string => `auth:refresh-families:${deviceId}`;

// Only the SHA-256 of a refresh token is ever stored, so a store dump yields
// no usable tokens.
const hashToken = (token: string): string => createHash('sha256').update(token).digest('hex');

// A refresh token is `<familyId>.<random>`. The family id lets refresh tell a
// superseded token of a live family (reuse) from garbage without keeping a
// marker per rotation. Clients treat the token as opaque.
const familyIdOf = (refreshToken: string): string | null => {
  const separator = refreshToken.indexOf('.');
  const familyId = separator > 0 ? refreshToken.slice(0, separator) : '';
  return isUUID(familyId) ? familyId : null;
};

const refreshExpiryFrom = (nowMs: number): number =>
  utcDayStart(new Date(nowMs)).getTime() + REFRESH_TOKEN_LIFETIME_DAYS * DAY_MS;

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
    private readonly retiredHandles: RetiredHandlesService,
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

    // Checked after the user lookup: account deletion frees the handle and
    // quarantines it in one transaction, so one of the two checks sees it.
    // A quarantined handle answers exactly like a taken one.
    if (existing || (await this.retiredHandles.isQuarantined(normalizedHandle))) {
      throw conflict('handle_taken', 'Handle is already taken');
    }

    // dto.displayName is accepted from older clients and dropped: the server
    // stores no profile text.
    const now = new Date();
    const created = await this.prisma
      .$transaction(async (tx) => {
        const user = await tx.user.create({
          data: {
            handle: normalizedHandle,
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
            lastSeenAt: utcDayStart(now),
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

  // An unknown handle answers exactly like a known one with a wrong device:
  // this public route must not tell which handles exist, or the rate limits
  // that keep directory lookups slow would not matter.
  async createChallenge(dto: ChallengeDto): Promise<AuthChallengeResponse> {
    const device = await this.prisma.device.findFirst({
      where: {
        id: dto.deviceId,
        isActive: true,
        revokedAt: null,
        user: { handle: dto.handle.toLowerCase() },
      },
      select: { id: true },
    });

    if (!device) {
      throw apiError('active_device_not_found', 'Active device not found for handle');
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
    const refreshExpiresAtMs = refreshExpiryFrom(Date.now());
    await this.recordRefreshFamily(
      device.id,
      await this.listRefreshFamilies(device.id),
      familyId,
      refreshExpiresAtMs,
    );
    const tokens = await this.issueTokenPair(
      device.userId,
      device.id,
      device.user.handle,
      familyId,
      refreshExpiresAtMs,
    );

    await recordDeviceSeen(this.prisma, device.id);

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
    const familyId = familyIdOf(refreshToken);
    // Atomic get-and-delete: of two concurrent refreshes with one token only
    // one can win; the loser is treated as a replay below.
    const stored = await this.ephemeralStore.takeJson<StoredRefreshToken>(
      refreshTokenKey(tokenHash),
    );

    if (!stored) {
      // A superseded token of a family that is still alive means two parties
      // hold the family: the client and whoever copied a token. The server
      // cannot tell which is which, so the whole family dies and the device
      // must prove possession of its auth key again.
      const reusedFamilyId = await this.liveFamilyOfSupersededToken(familyId, tokenHash);
      if (reusedFamilyId) {
        await this.revokeRefreshFamily(reusedFamilyId);
        this.countAuth('refresh_reuse');
      }
      throw unauthorized('refresh_token_invalid', 'Refresh token invalid');
    }

    if (!familyId) {
      // A token issued before tokens carried their family id. It still
      // rotates, into one that does: the mobile app has no way back in
      // without its refresh token. Its replay cannot be told from garbage, so
      // it alone leaves a marker, with the UTC-midnight expiry of the token
      // that replaces it. No pre-upgrade token outlives its 30-day TTL, so
      // this branch, and the markers, end 31 days after the upgrade.
      await this.ephemeralStore.setJsonUntil<LegacyRotatedToken>(
        legacyRotatedTokenKey(tokenHash),
        { familyId: stored.familyId },
        refreshExpiryFrom(Date.now()),
      );
    }

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
    const refreshExpiresAtMs = refreshExpiryFrom(Date.now());
    await this.recordRefreshFamily(device.id, deviceFamilies, stored.familyId, refreshExpiresAtMs);
    const tokens = await this.issueTokenPair(
      device.userId,
      device.id,
      device.user.handle,
      stored.familyId,
      refreshExpiresAtMs,
    );

    await recordDeviceSeen(this.prisma, device.id);

    this.countAuth('refresh');

    return {
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: tokens.expiresAt,
      refreshExpiresAt: tokens.refreshExpiresAt,
    };
  }

  // Logout ends every session of the device, whether or not the client still
  // has, or sends, its refresh token. Revoking the refresh families also
  // revokes every access token issued under them (isAccessTokenRevoked), on
  // this device's other sessions too, not only the token that called logout.
  async logout(authContext: {
    userId: string;
    deviceId: string;
    jti?: string;
    exp?: number;
  }): Promise<{ ok: true }> {
    await this.revokeDeviceRefreshFamilies(authContext.deviceId);

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

  /**
   * Checks that an irreversible request (account deletion, revoking the
   * calling or last device) comes from the device itself and not only from
   * someone holding its bearer token: a challenge issued for this device by
   * createChallenge, signed with its auth key over
   * `<purpose>:<challengeId>:<challenge>`. The purpose prefix keeps the
   * signature apart from a login proof, which signs the bare challenge, and
   * from every other purpose. The challenge is consumed on first
   * presentation, success or failure.
   *
   * Every relay requires the proof, whatever VEIL_ENV says: a development
   * relay that let unsigned requests through would hide a client that never
   * signs until it met a production one.
   */
  async verifyDeviceStepUp(
    deviceId: string,
    purpose: string,
    proof: DeviceStepUpProof | undefined,
  ): Promise<void> {
    if (!proof?.challengeId || !proof.signature) {
      throw unauthorized('challenge_invalid', 'A challenge signed by this device is required');
    }

    const stored = await this.ephemeralStore.takeJson<StoredChallenge>(
      challengeKey(proof.challengeId),
    );
    if (!stored || stored.deviceId !== deviceId) {
      throw unauthorized('challenge_invalid', 'Challenge expired or invalid');
    }

    const device = await this.prisma.device.findUnique({
      where: { id: deviceId },
      select: { authPublicKey: true, isActive: true, revokedAt: true },
    });
    if (!device || !device.isActive || device.revokedAt) {
      throw unauthorized('device_not_active', 'Device is not active');
    }

    const isValid = await this.deviceAuthVerifier.verifyChallengeResponse({
      challenge: `${purpose}:${proof.challengeId}:${stored.challenge}`,
      proof: proof.signature,
      authPublicKey: device.authPublicKey,
      deviceId,
    });
    if (!isValid) {
      throw unauthorized('invalid_device_signature', 'Invalid device signature');
    }
  }

  // The family a token that is no longer current belonged to, when that
  // family is still alive: its id is in the token itself, or, for a token
  // issued before that, in the marker its rotation left.
  private async liveFamilyOfSupersededToken(
    familyId: string | null,
    tokenHash: string,
  ): Promise<string | null> {
    if (familyId) {
      const family = await this.ephemeralStore.getJson<RefreshFamily>(refreshFamilyKey(familyId));
      return family ? familyId : null;
    }
    const marker = await this.ephemeralStore.getJson<LegacyRotatedToken>(
      legacyRotatedTokenKey(tokenHash),
    );
    return marker?.familyId ?? null;
  }

  // Removes everything the store keeps about a device's sessions: its refresh
  // families with their current tokens, the family index and its outstanding
  // login challenges. Account deletion calls it after revoking the device, so
  // no refresh can write the keys again; every step is a take or a delete, so
  // a retry is harmless. A family the index lost to a concurrent
  // read-modify-write is not reached; refresh() already refuses it, and it
  // expires on its own.
  async forgetDevice(deviceId: string): Promise<void> {
    await this.revokeDeviceRefreshFamilies(deviceId);
    const challengeIds =
      (await this.ephemeralStore.takeJson<string[]>(challengeIndexKey(deviceId))) ?? [];
    for (const challengeId of challengeIds) {
      await this.ephemeralStore.delete(challengeKey(challengeId));
    }
  }

  private async revokeDeviceRefreshFamilies(deviceId: string): Promise<void> {
    const familyIds =
      (await this.ephemeralStore.takeJson<string[]>(deviceFamiliesKey(deviceId))) ?? [];
    for (const familyId of familyIds) {
      await this.revokeRefreshFamily(familyId);
    }
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
  // index the same expiry as the family's new token, so the index outlives
  // every family it lists. Families pushed out of the window are revoked.
  private async recordRefreshFamily(
    deviceId: string,
    families: readonly string[],
    familyId: string,
    expiresAtMs: number,
  ): Promise<void> {
    const { kept, evicted } = appendKeepingNewest(
      families,
      familyId,
      MAX_REFRESH_FAMILIES_PER_DEVICE,
    );
    for (const evictedId of evicted) {
      await this.revokeRefreshFamily(evictedId);
    }
    await this.ephemeralStore.setJsonUntil(deviceFamiliesKey(deviceId), kept, expiresAtMs);
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
    refreshExpiresAtMs: number,
  ): Promise<TokenPair> {
    const jti = randomUUID();
    // sid names the refresh family, so the access token lives no longer than
    // its session: see isAccessTokenRevoked.
    const accessToken = await this.jwtService.signAsync(
      {
        sub: userId,
        deviceId,
        handle,
        jti,
        sid: familyId,
      },
      {
        secret: this.config.jwtSecret,
        audience: this.config.jwtAudience,
        issuer: this.config.jwtIssuer,
        expiresIn: ACCESS_TOKEN_TTL_SECONDS,
      },
    );

    const refreshToken = `${familyId}.${randomBytes(48).toString('base64url')}`;
    const tokenHash = hashToken(refreshToken);
    await this.ephemeralStore.setJsonUntil<StoredRefreshToken>(
      refreshTokenKey(tokenHash),
      { userId, deviceId, familyId },
      refreshExpiresAtMs,
    );
    await this.ephemeralStore.setJsonUntil<RefreshFamily>(
      refreshFamilyKey(familyId),
      { deviceId, tokenHash },
      refreshExpiresAtMs,
    );

    return {
      accessToken,
      refreshToken,
      expiresAt: new Date(Date.now() + ACCESS_TOKEN_TTL_SECONDS * 1000).toISOString(),
      refreshExpiresAt: new Date(refreshExpiresAtMs).toISOString(),
    };
  }
}
