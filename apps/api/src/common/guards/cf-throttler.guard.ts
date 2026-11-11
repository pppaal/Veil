import { isIP } from 'node:net';

import { Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import {
  InjectThrottlerOptions,
  InjectThrottlerStorage,
  ThrottlerGuard,
  type ThrottlerModuleOptions,
  type ThrottlerStorage,
} from '@nestjs/throttler';

import { AppConfigService } from '../config/app-config.service';

interface TrackedRequest {
  auth?: { deviceId?: unknown };
  headers?: Record<string, string | string[] | undefined>;
  ip?: string;
  socket?: { remoteAddress?: string };
}

// Throttle tracker. Runs after JwtAuthGuard (see app.module.ts), so:
//  1. Authenticated requests are keyed by the device id bound to a verified
//     JWT — unspoofable, and two devices behind one NAT get separate buckets.
//  2. Everything else is keyed by client address, read only from the single
//     source the operator configured in VEIL_CLIENT_IP_SOURCE. A forwarding
//     header the configured edge does not overwrite is attacker-controlled, so
//     no other header is ever consulted.
@Injectable()
export class CfThrottlerGuard extends ThrottlerGuard {
  constructor(
    @InjectThrottlerOptions() options: ThrottlerModuleOptions,
    @InjectThrottlerStorage() storageService: ThrottlerStorage,
    reflector: Reflector,
    private readonly config: AppConfigService,
  ) {
    super(options, storageService, reflector);
  }

  protected async getTracker(req: TrackedRequest): Promise<string> {
    const deviceId = req.auth?.deviceId;
    if (typeof deviceId === 'string' && deviceId.length > 0) {
      return `dev:${deviceId}`;
    }
    return `ip:${this.clientAddress(req) ?? 'unknown'}`;
  }

  private clientAddress(req: TrackedRequest): string | undefined {
    switch (this.config.clientIpSource) {
      case 'cf-connecting-ip': {
        // Duplicate headers arrive comma-joined and fail isIP, so a client
        // cannot smuggle a second value past a proxy that appends.
        const header = req.headers?.['cf-connecting-ip'];
        const candidate = typeof header === 'string' ? header.trim() : '';
        return isIP(candidate) ? candidate : req.socket?.remoteAddress;
      }
      case 'x-forwarded-for':
        // Express resolves req.ip from X-Forwarded-For using exactly
        // VEIL_TRUSTED_PROXY_HOPS trusted hops (main.ts sets `trust proxy`).
        return req.ip;
      case 'socket':
      default:
        return req.socket?.remoteAddress;
    }
  }
}
