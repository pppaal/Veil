import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import type { EnvConfig } from './env.schema';

@Injectable()
export class AppConfigService {
  constructor(private readonly configService: ConfigService<EnvConfig, true>) {}

  get env(): EnvConfig['VEIL_ENV'] {
    return this.configService.get('VEIL_ENV', { infer: true });
  }

  get isProduction(): boolean {
    return this.env === 'production';
  }

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

  get redisUrl(): string | undefined {
    return this.configService.get('VEIL_REDIS_URL', { infer: true });
  }

  get trustProxy(): boolean {
    return this.configService.get('VEIL_TRUST_PROXY', { infer: true });
  }

  get swaggerEnabled(): boolean {
    return this.configService.get('VEIL_ENABLE_SWAGGER', { infer: true });
  }

  get allowedOrigins(): string[] {
    const configured = this.configService.get('VEIL_ALLOWED_ORIGINS', { infer: true });
    if (configured?.trim()) {
      return configured
        .split(',')
        .map((value) => value.trim())
        .filter(Boolean);
    }

    if (this.env === 'development' || this.env === 'test') {
      return [
        'http://localhost:3000',
        'http://127.0.0.1:3000',
        'http://localhost:8080',
        'http://127.0.0.1:8080',
      ];
    }

    return [];
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

  get s3PublicEndpoint(): string {
    return this.configService.get('VEIL_S3_PUBLIC_ENDPOINT', { infer: true }) ?? this.s3Endpoint;
  }

  get s3Region(): string {
    return this.configService.get('VEIL_S3_REGION', { infer: true });
  }

  get s3AccessKey(): string {
    return this.configService.get('VEIL_S3_ACCESS_KEY', { infer: true });
  }

  get s3SecretKey(): string {
    return this.configService.get('VEIL_S3_SECRET_KEY', { infer: true });
  }

  get s3Bucket(): string {
    return this.configService.get('VEIL_S3_BUCKET', { infer: true });
  }

  get attachmentMaxBytes(): number {
    return this.configService.get('VEIL_ATTACHMENT_MAX_BYTES', { infer: true });
  }

  get attachmentAllowedMimeTypes(): string[] {
    const configured = this.configService.get('VEIL_ATTACHMENT_ALLOWED_MIME_TYPES', {
      infer: true,
    });
    return configured
      .split(',')
      .map((value) => value.trim().toLowerCase())
      .filter(Boolean);
  }

  isOriginAllowed(origin?: string | null): boolean {
    if (!origin) {
      return true;
    }

    return this.allowedOrigins.includes(origin);
  }

  assertReleaseSafety(): void {
    if (!this.isProduction) {
      return;
    }

    throw new Error(
      [
        'Production boot blocked.',
        'VEIL still uses the mock crypto boundary.',
        'Replace the crypto adapters before setting VEIL_ENV=production.',
      ].join(' '),
    );
  }
}
