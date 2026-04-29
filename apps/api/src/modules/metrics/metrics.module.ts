import { Global, Module } from '@nestjs/common';

import { MetricsController } from './metrics.controller';
import { MetricsService } from './metrics.service';

// Global so any module can inject MetricsService without redeclaring
// imports. Counters live on the singleton; the registry survives the
// module lifecycle the same way prom-client's default registry does.
@Global()
@Module({
  controllers: [MetricsController],
  providers: [MetricsService],
  exports: [MetricsService],
})
export class MetricsModule {}
