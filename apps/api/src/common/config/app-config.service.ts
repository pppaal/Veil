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

  get pushProvider(): EnvConfig['VEIL_PUSH_PROVIDER'] {
    return this.configService.get('VEIL_PUSH_PROVIDER', { infer: true });
  }

  get pushDeliveryEnabled(): boolean {
    return this.configService.get('VEIL_PUSH_ENABLE_DELIVERY', {
      infer: true,
    });
  }

  get apnsBundleId(): string | undefined {
    return this.configService.get('VEIL_APNS_BUNDLE_ID', { infer: true });
  }

  get apnsTeamId(): string | undefined {
    return this.configService.get('VEIL_APNS_TEAM_ID', { infer: true });
  }

  get apnsKeyId(): string | undefined {
    return this.configService.get('VEIL_APNS_KEY_ID', { infer: true });
  }

  get apnsPrivateKeyPem(): string | undefined {
    return this.configService.get('VEIL_APNS_PRIVATE_KEY_PEM', { infer: true });
  }

  get apnsUseSandbox(): boolean {
    return this.configService.get('VEIL_APNS_USE_SANDBOX', { infer: true });
  }

  get fcmProjectId(): string | undefined {
    return this.configService.get('VEIL_FCM_PROJECT_ID', { infer: true });
  }

  get fcmServiceAccountJson(): string | undefined {
    return this.configService.get('VEIL_FCM_SERVICE_ACCOUNT_JSON', { infer: true });
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

  get cryptoAuditAttested(): boolean {
    return this.configService.get('VEIL_AUDITED_CRYPTO_ATTESTED', { infer: true });
  }

  get metricsAuthToken(): string | undefined {
    return this.configService.get('VEIL_METRICS_AUTH_TOKEN', { infer: true });
  }

  get otelEndpoint(): string | undefined {
    return this.configService.get('VEIL_OTEL_EXPORTER_OTLP_ENDPOINT', { infer: true });
  }

  get otelServiceName(): string {
    return this.configService.get('VEIL_OTEL_SERVICE_NAME', { infer: true });
  }

  assertProductionReady(): void {
    if (!this.isProduction) return;
    const errors: string[] = [];

    if (!this.cryptoAuditAttested) {
      errors.push(
        'VEIL_AUDITED_CRYPTO_ATTESTED is not true. Set this only after the ' +
          'audited crypto adapter has replaced the mock boundary and external ' +
          'security review has covered the new crypto path. ' +
          'See docs/audited-crypto-adapter-execution.md.',
      );
    }

    // Wildcard CORS in production lets any origin call the API; in beta we
    // explicitly want a known set of frontends.
    if (this.allowedOrigins.includes('*')) {
      errors.push(
        'VEIL_ALLOWED_ORIGINS contains "*". Production must list explicit ' +
          'origins (https://veil-beta.example.com).',
      );
    }

    // The default JWT secret in dev compose / examples is a known-loose
    // value. Anything that smells like a placeholder is rejected.
    const jwt = this.jwtSecret;
    if (
      jwt.length < 32 ||
      /(replace[-_]?me|placeholder|demo|test[-_]?secret|example|change[-_]?me)/i.test(jwt)
    ) {
      errors.push(
        'VEIL_JWT_SECRET is a placeholder or shorter than 32 chars. ' +
          'Generate a real one with `openssl rand -base64 32`.',
      );
    }

    // The S3 public endpoint is what the browser hits for presigned PUTs;
    // localhost works for the local demo but is meaningless in production.
    const s3Public = this.s3PublicEndpoint;
    if (/localhost|127\.0\.0\.1|0\.0\.0\.0/.test(s3Public)) {
      errors.push(
        'VEIL_S3_PUBLIC_ENDPOINT points at localhost. Set it to a hostname ' +
          'browsers can resolve (e.g. https://s3.veil-beta.example.com).',
      );
    }

    // Swagger lists every route + DTO; useful in dev, not in production.
    if (this.swaggerEnabled) {
      errors.push('VEIL_ENABLE_SWAGGER must be false in production.');
    }

    // Push delivery without provider credentials silently no-ops; better to
    // refuse to boot than ship a misconfigured deployment.
    if (this.pushDeliveryEnabled) {
      const hasApns =
        this.apnsBundleId && this.apnsTeamId && this.apnsKeyId && this.apnsPrivateKeyPem;
      const hasFcm = this.fcmProjectId && this.fcmServiceAccountJson;
      if (!hasApns && !hasFcm) {
        errors.push('VEIL_PUSH_ENABLE_DELIVERY=true but no APNs or FCM credentials are set.');
      }
    }

    // The ephemeral store falls back to an in-memory Map when no Redis URL
    // is set. That's fine for local dev but breaks single-use refresh tokens
    // and JTI blacklists across multiple instances.
    if (!this.redisUrl) {
      errors.push(
        'VEIL_REDIS_URL is required in production. The in-memory ephemeral ' +
          'store cannot enforce single-use refresh tokens or the JTI blacklist ' +
          'across multiple processes/pods.',
      );
    }

    if (errors.length > 0) {
      throw new Error('VEIL production boot blocked:\n  - ' + errors.join('\n  - '));
    }
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
    // No-Origin requests are server-to-server, native clients (curl, mobile),
    // and same-origin loads — none of which are subject to browser CORS. We
    // always allow them and rely on the auth guard / rate limiter to do the
    // actual access control. (The earlier shape that rejected null Origin in
    // production broke every native/mobile client behind Cloudflare Tunnel.)
    if (!origin) {
      return true;
    }

    if (this.allowedOrigins.includes('*')) {
      // Wildcard is convenient for the local demo stack but is refused in
      // production by assertProductionReady; this branch only fires outside
      // production.
      return !this.isProduction;
    }

    return this.allowedOrigins.includes(origin);
  }
}
