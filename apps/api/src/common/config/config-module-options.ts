import type { ConfigModuleOptions } from '@nestjs/config';

import { envSchema } from './env.schema';

// How the API loads and validates its environment. The preflight that runs
// before migrations (src/preflight.ts) uses the same options, so it accepts
// and refuses exactly what the API would.
export const CONFIG_MODULE_OPTIONS: ConfigModuleOptions = {
  isGlobal: true,
  expandVariables: true,
  validate: (environment) => envSchema.parse(environment),
};
