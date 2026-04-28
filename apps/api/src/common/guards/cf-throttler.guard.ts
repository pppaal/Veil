import { Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';

// Behind Cloudflare Tunnel, every request appears to come from the same
// loopback address, so the default IP-based tracker collapses all traffic
// into one bucket. Use Cloudflare's cf-connecting-ip header when present,
// fall back to the JWT-bound device id for authed routes, and only use
// the socket address as a last resort.
@Injectable()
export class CfThrottlerGuard extends ThrottlerGuard {
  protected async getTracker(req: Record<string, any>): Promise<string> {
    const headers = (req?.headers ?? {}) as Record<string, string | string[] | undefined>;
    const cfHeader = headers['cf-connecting-ip'];
    const cf = Array.isArray(cfHeader) ? cfHeader[0] : cfHeader;
    if (typeof cf === 'string' && cf.trim().length > 0) {
      return `cf:${cf.trim()}`;
    }

    const deviceId = req?.auth?.deviceId;
    if (typeof deviceId === 'string' && deviceId.length > 0) {
      return `dev:${deviceId}`;
    }

    const xff = headers['x-forwarded-for'];
    const xffStr = Array.isArray(xff) ? xff[0] : xff;
    if (typeof xffStr === 'string' && xffStr.trim().length > 0) {
      return `xff:${xffStr.split(',')[0].trim()}`;
    }

    return `ip:${req?.ip ?? 'unknown'}`;
  }
}
