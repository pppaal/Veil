import { Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import {
  InjectThrottlerOptions,
  InjectThrottlerStorage,
  ThrottlerGuard,
  type ThrottlerModuleOptions,
  type ThrottlerStorage,
} from '@nestjs/throttler';

import { clientAddress, type ClientAddressRequest } from '../client-address';
import { AppConfigService } from '../config/app-config.service';

interface TrackedRequest extends ClientAddressRequest {
  auth?: { deviceId?: unknown };
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
    return `ip:${clientAddress(req, this.config.clientIpSource) ?? 'unknown'}`;
  }
}
