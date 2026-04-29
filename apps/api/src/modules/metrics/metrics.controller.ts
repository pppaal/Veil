import { Controller, Get, Header, Headers, Res, UnauthorizedException } from '@nestjs/common';
import type { Response } from 'express';

import { AppConfigService } from '../../common/config/app-config.service';
import { Public } from '../../common/guards/public.decorator';
import { MetricsService } from './metrics.service';

// Bearer-token-gated /metrics endpoint. Returns 404 (not 401) when no
// token is configured so an unconfigured instance doesn't advertise
// that the seam exists.
@Controller('metrics')
export class MetricsController {
  constructor(
    private readonly metricsService: MetricsService,
    private readonly config: AppConfigService,
  ) {}

  @Public()
  @Get()
  @Header('Cache-Control', 'no-store')
  async scrape(
    @Headers('authorization') authHeader: string | undefined,
    @Res({ passthrough: false }) res: Response,
  ): Promise<void> {
    const token = this.config.metricsAuthToken;
    if (!token) {
      res.status(404).end();
      return;
    }
    const expected = `Bearer ${token}`;
    const ok = typeof authHeader === 'string' && timingSafeEquals(authHeader, expected);
    if (!ok) {
      throw new UnauthorizedException('metrics_unauthorized');
    }
    res.setHeader('Content-Type', this.metricsService.registry.contentType);
    res.send(await this.metricsService.registry.metrics());
  }
}

// Constant-time string compare so token brute-force can't time-attack.
// Both strings are short (token lengths) so allocation cost is fine.
function timingSafeEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
