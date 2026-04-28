import { ConfigService } from '@nestjs/config';

import { AppConfigService } from '../../src/common/config/app-config.service';
import type { EnvConfig } from '../../src/common/config/env.schema';

// A "good prod" baseline that should pass assertProductionReady. Tests
// override individual keys to drive each gate's failure path.
const PROD_BASELINE: Record<string, unknown> = {
  VEIL_ENV: 'production',
  VEIL_AUDITED_CRYPTO_ATTESTED: true,
  VEIL_ALLOWED_ORIGINS: 'https://veil-beta.example.com',
  VEIL_JWT_SECRET: 'a-32+-character-real-production-secret-please',
  VEIL_S3_PUBLIC_ENDPOINT: 'https://s3.veil-beta.example.com',
  VEIL_S3_ENDPOINT: 'http://minio:9000',
  VEIL_ENABLE_SWAGGER: false,
  VEIL_PUSH_PROVIDER: 'none',
  VEIL_PUSH_ENABLE_DELIVERY: false,
  VEIL_REDIS_URL: 'redis://redis:6379',
};

function buildConfig(overrides: Partial<EnvConfig>): AppConfigService {
  const values: Record<string, unknown> = {
    VEIL_ENV: 'development',
    VEIL_AUDITED_CRYPTO_ATTESTED: false,
    ...overrides,
  };
  const configService = {
    get: (key: string) => values[key],
  } as unknown as ConfigService<EnvConfig, true>;
  return new AppConfigService(configService);
}

describe('AppConfigService.assertProductionReady', () => {
  it('passes in non-production regardless of attestation', () => {
    expect(() =>
      buildConfig({ VEIL_ENV: 'development' }).assertProductionReady(),
    ).not.toThrow();
    expect(() =>
      buildConfig({ VEIL_ENV: 'test' }).assertProductionReady(),
    ).not.toThrow();
  });

  it('throws in production when crypto audit is not attested', () => {
    const config = buildConfig({
      ...PROD_BASELINE,
      VEIL_AUDITED_CRYPTO_ATTESTED: false,
    } as unknown as Partial<EnvConfig>);

    expect(() => config.assertProductionReady()).toThrow(
      /VEIL_AUDITED_CRYPTO_ATTESTED/,
    );
  });

  it('passes in production when every gate is satisfied', () => {
    const config = buildConfig(PROD_BASELINE as unknown as Partial<EnvConfig>);
    expect(() => config.assertProductionReady()).not.toThrow();
  });

  it('rejects wildcard CORS origins in production', () => {
    const config = buildConfig({
      ...PROD_BASELINE,
      VEIL_ALLOWED_ORIGINS: '*',
    } as unknown as Partial<EnvConfig>);
    expect(() => config.assertProductionReady()).toThrow(/VEIL_ALLOWED_ORIGINS/);
  });

  it('rejects placeholder JWT secrets in production', () => {
    const config = buildConfig({
      ...PROD_BASELINE,
      VEIL_JWT_SECRET: 'replace-me',
    } as unknown as Partial<EnvConfig>);
    expect(() => config.assertProductionReady()).toThrow(/VEIL_JWT_SECRET/);
  });

  it('rejects localhost S3 public endpoints in production', () => {
    const config = buildConfig({
      ...PROD_BASELINE,
      VEIL_S3_PUBLIC_ENDPOINT: 'http://localhost:9000',
    } as unknown as Partial<EnvConfig>);
    expect(() => config.assertProductionReady()).toThrow(/VEIL_S3_PUBLIC_ENDPOINT/);
  });

  it('rejects swagger enabled in production', () => {
    const config = buildConfig({
      ...PROD_BASELINE,
      VEIL_ENABLE_SWAGGER: true,
    } as unknown as Partial<EnvConfig>);
    expect(() => config.assertProductionReady()).toThrow(/VEIL_ENABLE_SWAGGER/);
  });

  it('rejects push delivery enabled without provider credentials', () => {
    const config = buildConfig({
      ...PROD_BASELINE,
      VEIL_PUSH_ENABLE_DELIVERY: true,
    } as unknown as Partial<EnvConfig>);
    expect(() => config.assertProductionReady()).toThrow(/VEIL_PUSH_ENABLE_DELIVERY/);
  });

  it('rejects production boot without VEIL_REDIS_URL', () => {
    const noRedis = { ...PROD_BASELINE };
    delete (noRedis as Record<string, unknown>).VEIL_REDIS_URL;
    const config = buildConfig(noRedis as unknown as Partial<EnvConfig>);
    expect(() => config.assertProductionReady()).toThrow(/VEIL_REDIS_URL/);
  });
});

describe('AppConfigService.isOriginAllowed', () => {
  it('allows requests with no Origin header (curl, native, server-to-server)', () => {
    const config = buildConfig({
      VEIL_ENV: 'production',
      VEIL_ALLOWED_ORIGINS: 'https://veil-beta.example.com',
    } as unknown as Partial<EnvConfig>);
    expect(config.isOriginAllowed(undefined)).toBe(true);
    expect(config.isOriginAllowed(null)).toBe(true);
    expect(config.isOriginAllowed('')).toBe(true);
  });

  it('rejects browser-Origin requests not on the allowlist', () => {
    const config = buildConfig({
      VEIL_ENV: 'production',
      VEIL_ALLOWED_ORIGINS: 'https://veil-beta.example.com',
    } as unknown as Partial<EnvConfig>);
    expect(config.isOriginAllowed('https://evil.example.com')).toBe(false);
  });

  it('accepts wildcard origins outside production', () => {
    const config = buildConfig({
      VEIL_ENV: 'development',
      VEIL_ALLOWED_ORIGINS: '*',
    } as unknown as Partial<EnvConfig>);
    expect(config.isOriginAllowed('https://anything.example.com')).toBe(true);
  });

  it('refuses wildcard match in production even if configured', () => {
    const config = buildConfig({
      VEIL_ENV: 'production',
      VEIL_ALLOWED_ORIGINS: '*',
    } as unknown as Partial<EnvConfig>);
    expect(config.isOriginAllowed('https://anything.example.com')).toBe(false);
  });
});
