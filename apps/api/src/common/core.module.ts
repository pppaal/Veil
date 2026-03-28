import { Global, Module } from '@nestjs/common';

import { AppConfigService } from './config/app-config.service';
import { EphemeralStoreService } from './ephemeral-store.service';
import { AppLoggerService } from './logger/app-logger.service';
import { PrismaService } from './prisma.service';

@Global()
@Module({
  providers: [AppConfigService, PrismaService, EphemeralStoreService, AppLoggerService],
  exports: [AppConfigService, PrismaService, EphemeralStoreService, AppLoggerService],
})
export class CoreModule {}
