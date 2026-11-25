import { ConfigModule } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';

import { AppConfigService } from './common/config/app-config.service';
import { CONFIG_MODULE_OPTIONS } from './common/config/config-module-options';

// docker-entrypoint.sh runs this before `prisma migrate deploy`. It loads the
// environment exactly as the API does and runs the production boot gate,
// without connecting to anything, so a deploy the API would refuse to boot
// stops before a migration (some delete data for good) touches the database.
class PreflightModule {}

export async function preflight(): Promise<void> {
  const context = await NestFactory.createApplicationContext(
    {
      module: PreflightModule,
      imports: [ConfigModule.forRoot(CONFIG_MODULE_OPTIONS)],
      providers: [AppConfigService],
    },
    { logger: false, abortOnError: false },
  );
  try {
    context.get(AppConfigService).assertProductionReady();
  } finally {
    await context.close();
  }
}

if (require.main === module) {
  preflight().catch((error: unknown) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exit(1);
  });
}
