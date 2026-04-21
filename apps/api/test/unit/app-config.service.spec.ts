import { ConfigService } from '@nestjs/config';

import { AppConfigService } from '../../src/common/config/app-config.service';
import type { EnvConfig } from '../../src/common/config/env.schema';

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
      VEIL_ENV: 'production',
      VEIL_AUDITED_CRYPTO_ATTESTED: false,
    });

    expect(() => config.assertProductionReady()).toThrow(
      /VEIL_AUDITED_CRYPTO_ATTESTED/,
    );
  });

  it('passes in production when crypto audit is attested', () => {
    const config = buildConfig({
      VEIL_ENV: 'production',
      VEIL_AUDITED_CRYPTO_ATTESTED: true,
    });

    expect(() => config.assertProductionReady()).not.toThrow();
  });
});
