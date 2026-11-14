import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Reflector } from '@nestjs/core';

import type { AuthenticatedRequest } from './authenticated-request';
import { IS_PUBLIC_KEY } from './public.decorator';
import { isAccessTokenRevoked } from '../access-token-revocation';
import { AppConfigService } from '../config/app-config.service';
import { recordDeviceSeen, utcDayStart } from '../device-activity';
import { EphemeralStoreService } from '../ephemeral-store.service';
import { unauthorized } from '../errors/api-error';
import { PrismaService } from '../prisma.service';

interface AccessTokenPayload {
  sub: string;
  deviceId: string;
  handle: string;
  jti?: string;
  exp?: number;
  sid?: string;
}

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly jwtService: JwtService,
    private readonly config: AppConfigService,
    private readonly prisma: PrismaService,
    private readonly ephemeralStore: EphemeralStoreService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (context.getType<'http' | 'ws' | 'rpc'>() !== 'http') {
      return true;
    }

    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);

    if (isPublic) {
      return true;
    }

    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const header = request.headers.authorization;
    const token = header?.startsWith('Bearer ') ? header.slice('Bearer '.length) : null;

    if (!token) {
      throw unauthorized('unauthorized', 'Missing bearer token');
    }

    const { payload, device } = await this.authenticate(token);

    // Runs after authentication and outside its catch: a failed bookkeeping
    // write is a server error, not a reason to send the client back through
    // sign-in. Checked against the loaded row first, so a device already seen
    // today costs no write at all.
    const now = new Date();
    if (device.lastSeenAt.getTime() !== utcDayStart(now).getTime()) {
      await recordDeviceSeen(this.prisma, device.id, now);
    }

    request.auth = {
      userId: payload.sub,
      deviceId: payload.deviceId,
      handle: payload.handle,
      jti: payload.jti,
      exp: payload.exp,
    };
    return true;
  }

  private async authenticate(token: string) {
    try {
      const payload = await this.jwtService.verifyAsync<AccessTokenPayload>(token, {
        secret: this.config.jwtSecret,
        audience: this.config.jwtAudience,
        issuer: this.config.jwtIssuer,
      });

      if (await isAccessTokenRevoked(this.ephemeralStore, payload)) {
        throw unauthorized('token_revoked', 'Access token has been revoked');
      }

      const device = await this.prisma.device.findUnique({
        where: { id: payload.deviceId },
        include: { user: true },
      });

      if (
        !device ||
        device.userId !== payload.sub ||
        !device.isActive ||
        device.revokedAt ||
        device.user.status !== 'active'
      ) {
        throw unauthorized('device_not_active', 'Device is not active');
      }

      return { payload, device };
    } catch (error) {
      if (error instanceof UnauthorizedException) {
        throw error;
      }
      throw unauthorized('unauthorized', 'Invalid access token');
    }
  }
}
