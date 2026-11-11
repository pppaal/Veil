import { ConfigService } from '@nestjs/config';

import {
  AppConfigService,
  DEV_RETIRED_HANDLE_PEPPER,
} from '../../src/common/config/app-config.service';
import { envSchema, type EnvConfig } from '../../src/common/config/env.schema';

// Raw environment strings, exactly as the process would see them, so every
// test goes through the same schema the app boots with.
const REQUIRED_ENV: Record<string, string> = {
  VEIL_DATABASE_URL: 'postgresql://veil:veil@localhost:5432/veil',
  VEIL_S3_ENDPOINT: 'http://minio:9000',
  VEIL_S3_REGION: 'us-east-1',
  VEIL_S3_ACCESS_KEY: 'access',
  VEIL_S3_SECRET_KEY: 'secret',
  VEIL_S3_BUCKET: 'veil-encrypted',
  VEIL_JWT_SECRET: 'a-32+-character-real-production-secret-please',
};

// A "good prod" baseline that passes assertProductionReady. Tests override
// individual keys to drive each gate's failure path.
const PROD_BASELINE: Record<string, string> = {
  ...REQUIRED_ENV,
  VEIL_ENV: 'production',
  VEIL_AUDITED_CRYPTO_ATTESTED: 'true',
  VEIL_AUDIT_REPORT_SHA256: 'ab'.repeat(32),
  VEIL_ALLOWED_ORIGINS: 'https://veil-beta.example.com',
  VEIL_S3_PUBLIC_ENDPOINT: 'https://s3.veil-beta.example.com',
  VEIL_ENABLE_SWAGGER: 'false',
  VEIL_PUSH_PROVIDER: 'none',
  VEIL_PUSH_ENABLE_DELIVERY: 'false',
  VEIL_REDIS_URL: 'redis://redis:6379',
  VEIL_RETIRED_HANDLE_PEPPER: 'a-real-production-pepper-from-openssl-rand',
};

const BOOLEAN_FLAGS = [
  'VEIL_ENABLE_SWAGGER',
  'VEIL_PUSH_ENABLE_DELIVERY',
  'VEIL_APNS_USE_SANDBOX',
  'VEIL_AUDITED_CRYPTO_ATTESTED',
] as const;

const parseEnv = (raw: Record<string, string | undefined>): EnvConfig => envSchema.parse(raw);

function configFrom(raw: Record<string, string | undefined>): AppConfigService {
  const parsed = parseEnv(raw) as Record<string, unknown>;
  const configService = {
    get: (key: string) => parsed[key],
  } as unknown as ConfigService<EnvConfig, true>;
  return new AppConfigService(configService);
}

const without = (raw: Record<string, string>, key: string): Record<string, string> => {
  const copy = { ...raw };
  delete copy[key];
  return copy;
};

describe('envSchema', () => {
  it('string false parses as false for every boolean flag', () => {
    for (const flag of BOOLEAN_FLAGS) {
      for (const spelling of ['false', 'FALSE', ' false ', '0', 'no']) {
        expect(parseEnv({ ...REQUIRED_ENV, [flag]: spelling })[flag]).toBe(false);
      }
      for (const spelling of ['true', 'True', '1', 'yes']) {
        expect(parseEnv({ ...REQUIRED_ENV, [flag]: spelling })[flag]).toBe(true);
      }
    }
  });

  it('banana fails boot', () => {
    for (const flag of BOOLEAN_FLAGS) {
      for (const value of ['banana', '', 'on', '2']) {
        const result = envSchema.safeParse({ ...REQUIRED_ENV, [flag]: value });
        expect(result.success).toBe(false);
        expect(result.error?.issues.map((issue) => issue.path.join('.'))).toContain(flag);
      }
    }
  });

  it('keeps the documented boolean defaults', () => {
    const parsed = parseEnv(REQUIRED_ENV);
    expect(parsed.VEIL_ENABLE_SWAGGER).toBe(false);
    expect(parsed.VEIL_PUSH_ENABLE_DELIVERY).toBe(false);
    expect(parsed.VEIL_APNS_USE_SANDBOX).toBe(true);
    expect(parsed.VEIL_AUDITED_CRYPTO_ATTESTED).toBe(false);
  });

  it('legacy VEIL_TRUST_PROXY fails boot', () => {
    for (const value of ['true', 'false', '']) {
      const result = envSchema.safeParse({ ...REQUIRED_ENV, VEIL_TRUST_PROXY: value });
      expect(result.success).toBe(false);
      expect(result.error?.issues).toContainEqual(
        expect.objectContaining({
          path: ['VEIL_TRUST_PROXY'],
          message: 'VEIL_TRUST_PROXY was removed; set VEIL_CLIENT_IP_SOURCE',
        }),
      );
    }
  });

  it('defaults the client IP source to the socket with one trusted hop', () => {
    const config = configFrom(REQUIRED_ENV);
    expect(config.clientIpSource).toBe('socket');
    expect(config.trustedProxyHops).toBe(1);
  });

  it('accepts only known client IP sources and positive hop counts', () => {
    const config = configFrom({
      ...REQUIRED_ENV,
      VEIL_CLIENT_IP_SOURCE: 'x-forwarded-for',
      VEIL_TRUSTED_PROXY_HOPS: '2',
    });
    expect(config.clientIpSource).toBe('x-forwarded-for');
    expect(config.trustedProxyHops).toBe(2);
    expect(
      envSchema.safeParse({ ...REQUIRED_ENV, VEIL_CLIENT_IP_SOURCE: 'true-client-ip' }).success,
    ).toBe(false);
    expect(envSchema.safeParse({ ...REQUIRED_ENV, VEIL_TRUSTED_PROXY_HOPS: '0' }).success).toBe(
      false,
    );
  });

  it('accepts only a lowercase hex SHA-256 for the audit report', () => {
    expect(
      envSchema.safeParse({ ...REQUIRED_ENV, VEIL_AUDIT_REPORT_SHA256: 'AB'.repeat(32) }).success,
    ).toBe(false);
    expect(
      envSchema.safeParse({ ...REQUIRED_ENV, VEIL_AUDIT_REPORT_SHA256: 'ab'.repeat(31) }).success,
    ).toBe(false);
  });
});

describe('AppConfigService.assertProductionReady', () => {
  it('passes in non-production regardless of attestation', () => {
    expect(() =>
      configFrom({ ...REQUIRED_ENV, VEIL_ENV: 'development' }).assertProductionReady(),
    ).not.toThrow();
    expect(() =>
      configFrom({ ...REQUIRED_ENV, VEIL_ENV: 'test' }).assertProductionReady(),
    ).not.toThrow();
  });

  it('passes in production when every gate is satisfied', () => {
    expect(() => configFrom(PROD_BASELINE).assertProductionReady()).not.toThrow();
  });

  it('production refuses attestation string false', () => {
    for (const spelling of ['false', 'FALSE', '0', 'no']) {
      const config = configFrom({ ...PROD_BASELINE, VEIL_AUDITED_CRYPTO_ATTESTED: spelling });
      expect(() => config.assertProductionReady()).toThrow(/VEIL_AUDITED_CRYPTO_ATTESTED/);
    }
    expect(() =>
      configFrom(without(PROD_BASELINE, 'VEIL_AUDITED_CRYPTO_ATTESTED')).assertProductionReady(),
    ).toThrow(/VEIL_AUDITED_CRYPTO_ATTESTED/);
  });

  it('production requires VEIL_AUDIT_REPORT_SHA256', () => {
    const config = configFrom(without(PROD_BASELINE, 'VEIL_AUDIT_REPORT_SHA256'));
    expect(() => config.assertProductionReady()).toThrow(/VEIL_AUDIT_REPORT_SHA256/);
    // Compose forwards an unset variable as an empty string.
    const forwardedEmpty = configFrom({ ...PROD_BASELINE, VEIL_AUDIT_REPORT_SHA256: '' });
    expect(() => forwardedEmpty.assertProductionReady()).toThrow(/VEIL_AUDIT_REPORT_SHA256/);
  });

  it('production requires VEIL_RETIRED_HANDLE_PEPPER', () => {
    for (const config of [
      configFrom(without(PROD_BASELINE, 'VEIL_RETIRED_HANDLE_PEPPER')),
      configFrom({ ...PROD_BASELINE, VEIL_RETIRED_HANDLE_PEPPER: '' }),
      configFrom({ ...PROD_BASELINE, VEIL_RETIRED_HANDLE_PEPPER: DEV_RETIRED_HANDLE_PEPPER }),
    ]) {
      expect(() => config.assertProductionReady()).toThrow(/VEIL_RETIRED_HANDLE_PEPPER/);
    }
    expect(
      envSchema.safeParse({ ...REQUIRED_ENV, VEIL_RETIRED_HANDLE_PEPPER: 'too-short' }).success,
    ).toBe(false);
  });

  it('falls back to the development pepper outside production', () => {
    expect(configFrom(REQUIRED_ENV).retiredHandlePepper).toBe(DEV_RETIRED_HANDLE_PEPPER);
  });

  it('caps message age at 30 days unless VEIL_MESSAGE_MAX_AGE_DAYS says otherwise', () => {
    expect(configFrom(REQUIRED_ENV).messageMaxAgeDays).toBe(30);
    expect(configFrom({ ...REQUIRED_ENV, VEIL_MESSAGE_MAX_AGE_DAYS: '0' }).messageMaxAgeDays).toBe(
      0,
    );
    expect(envSchema.safeParse({ ...REQUIRED_ENV, VEIL_MESSAGE_MAX_AGE_DAYS: '-1' }).success).toBe(
      false,
    );
  });

  it('production unifiedpush requires allowlist', () => {
    const unifiedPush = { ...PROD_BASELINE, VEIL_PUSH_PROVIDER: 'unifiedpush' };
    expect(() => configFrom(unifiedPush).assertProductionReady()).toThrow(
      /VEIL_UNIFIEDPUSH_ALLOWED_HOSTS/,
    );
    expect(() =>
      configFrom({ ...unifiedPush, VEIL_UNIFIEDPUSH_ALLOWED_HOSTS: ' , ' }).assertProductionReady(),
    ).toThrow(/VEIL_UNIFIEDPUSH_ALLOWED_HOSTS/);
    expect(() =>
      configFrom({
        ...unifiedPush,
        VEIL_UNIFIEDPUSH_ALLOWED_HOSTS: 'ntfy.sh',
      }).assertProductionReady(),
    ).not.toThrow();
  });

  it('rejects wildcard CORS origins in production', () => {
    const config = configFrom({ ...PROD_BASELINE, VEIL_ALLOWED_ORIGINS: '*' });
    expect(() => config.assertProductionReady()).toThrow(/VEIL_ALLOWED_ORIGINS/);
  });

  it('rejects placeholder JWT secrets in production', () => {
    const config = configFrom({
      ...PROD_BASELINE,
      VEIL_JWT_SECRET: 'replace-me-with-openssl-rand-base64-32-bytes',
    });
    expect(() => config.assertProductionReady()).toThrow(/VEIL_JWT_SECRET/);
  });

  it('rejects localhost S3 public endpoints in production', () => {
    const config = configFrom({
      ...PROD_BASELINE,
      VEIL_S3_PUBLIC_ENDPOINT: 'http://localhost:9000',
    });
    expect(() => config.assertProductionReady()).toThrow(/VEIL_S3_PUBLIC_ENDPOINT/);
  });

  it('rejects swagger enabled in production', () => {
    const config = configFrom({ ...PROD_BASELINE, VEIL_ENABLE_SWAGGER: 'true' });
    expect(() => config.assertProductionReady()).toThrow(/VEIL_ENABLE_SWAGGER/);
  });

  it('rejects push delivery enabled without provider credentials', () => {
    const config = configFrom({ ...PROD_BASELINE, VEIL_PUSH_ENABLE_DELIVERY: 'true' });
    expect(() => config.assertProductionReady()).toThrow(/VEIL_PUSH_ENABLE_DELIVERY/);
  });

  it('rejects production boot without VEIL_REDIS_URL', () => {
    const config = configFrom(without(PROD_BASELINE, 'VEIL_REDIS_URL'));
    expect(() => config.assertProductionReady()).toThrow(/VEIL_REDIS_URL/);
  });
});

describe('AppConfigService.isOriginAllowed', () => {
  const production = { ...REQUIRED_ENV, VEIL_ENV: 'production' };

  it('allows requests with no Origin header (curl, native, server-to-server)', () => {
    const config = configFrom({
      ...production,
      VEIL_ALLOWED_ORIGINS: 'https://veil-beta.example.com',
    });
    expect(config.isOriginAllowed(undefined)).toBe(true);
    expect(config.isOriginAllowed(null)).toBe(true);
    expect(config.isOriginAllowed('')).toBe(true);
  });

  it('rejects browser-Origin requests not on the allowlist', () => {
    const config = configFrom({
      ...production,
      VEIL_ALLOWED_ORIGINS: 'https://veil-beta.example.com',
    });
    expect(config.isOriginAllowed('https://evil.example.com')).toBe(false);
  });

  it('accepts wildcard origins outside production', () => {
    const config = configFrom({
      ...REQUIRED_ENV,
      VEIL_ENV: 'development',
      VEIL_ALLOWED_ORIGINS: '*',
    });
    expect(config.isOriginAllowed('https://anything.example.com')).toBe(true);
  });

  it('refuses wildcard match in production even if configured', () => {
    const config = configFrom({ ...production, VEIL_ALLOWED_ORIGINS: '*' });
    expect(config.isOriginAllowed('https://anything.example.com')).toBe(false);
  });
});
