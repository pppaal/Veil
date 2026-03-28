import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import type { EnvConfig } from './env.schema';

@Injectable()
export class AppConfigService {
  constructor(private readonly configService: ConfigService<EnvConfig, true>) {}

  get port(): number {
    return this.configService.get('VEIL_API_PORT', { infer: true });
  }

  get jwtSecret(): string {
    return this.configService.get('VEIL_JWT_SECRET', { infer: true });
  }

  get jwtAudience(): string {
    return this.configService.get('VEIL_JWT_AUDIENCE', { infer: true });
  }

  get jwtIssuer(): string {
    return this.configService.get('VEIL_JWT_ISSUER', { infer: true });
  }

  get mockAuthSharedSecret(): string {
    return this.configService.get('VEIL_MOCK_AUTH_SHARED_SECRET', { infer: true });
  }

  get redisUrl(): string | undefined {
    return this.configService.get('VEIL_REDIS_URL', { infer: true });
  }

  get transferTokenTtlSeconds(): number {
    return this.configService.get('VEIL_TRANSFER_TOKEN_TTL_SECONDS', { infer: true });
  }

  get authChallengeTtlSeconds(): number {
    return this.configService.get('VEIL_AUTH_CHALLENGE_TTL_SECONDS', { infer: true });
  }

  get s3Endpoint(): string {
    return this.configService.get('VEIL_S3_ENDPOINT', { infer: true });
  }

  get s3Bucket(): string {
    return this.configService.get('VEIL_S3_BUCKET', { infer: true });
  }
}
