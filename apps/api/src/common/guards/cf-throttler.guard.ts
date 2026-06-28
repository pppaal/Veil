import { Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';

// Throttle tracker. Priority:
//  1. The authenticated device id — bound to a verified JWT, so it cannot be
//     spoofed and gives per-device limits on authed routes.
//  2. Cloudflare's `cf-connecting-ip` — but ONLY when the operator has
//     asserted a trusted edge via VEIL_TRUST_PROXY. Behind Cloudflare Tunnel
//     the socket address is loopback, so the real client ip arrives here.
//  3. The socket address (`req.ip`). With `trust proxy` enabled in main.ts,
//     Express already resolves this from X-Forwarded-For safely.
//
// Client-supplied forwarding headers are IGNORED unless VEIL_TRUST_PROXY is
// set. Previously `cf-connecting-ip` was trusted first and unconditionally, so
// any client could land in a fresh throttle bucket per request by spoofing the
// header — defeating every limit, including the unauthenticated /auth,
// registration, and handle-enumeration limits.
@Injectable()
export class CfThrottlerGuard extends ThrottlerGuard {
  protected async getTracker(req: Record<string, any>): Promise<string> {
    const deviceId = req?.auth?.deviceId;
    if (typeof deviceId === 'string' && deviceId.length > 0) {
      return `dev:${deviceId}`;
    }

    if (process.env.VEIL_TRUST_PROXY === 'true') {
      const headers = (req?.headers ?? {}) as Record<string, string | string[] | undefined>;
      const cfHeader = headers['cf-connecting-ip'];
      const cf = Array.isArray(cfHeader) ? cfHeader[0] : cfHeader;
      if (typeof cf === 'string' && cf.trim().length > 0) {
        return `cf:${cf.trim()}`;
      }
    }

    return `ip:${req?.ip ?? 'unknown'}`;
  }
}
