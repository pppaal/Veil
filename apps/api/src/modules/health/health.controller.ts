import { Controller, Get } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';

import { AppConfigService } from '../../common/config/app-config.service';
import { Public } from '../../common/guards/public.decorator';

@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(private readonly config: AppConfigService) {}

  @Public()
  @Get()
  getHealth(): { status: 'ok'; service: 'veil-api' } {
    return {
      status: 'ok',
      service: 'veil-api',
    };
  }

  @Public()
  @Get('ready')
  getReadiness(): {
    status: 'ok';
    service: 'veil-api';
    mode: string;
    checks: {
      allowedOriginsConfigured: boolean;
      pushProvider: string;
      pushDeliveryEnabled: boolean;
      s3PublicEndpointConfigured: boolean;
      productionBootBlocked: boolean;
    };
  } {
    return {
      status: 'ok',
      service: 'veil-api',
      mode: this.config.env,
      checks: {
        allowedOriginsConfigured: this.config.allowedOrigins.length > 0,
        pushProvider: this.config.pushProvider,
        pushDeliveryEnabled: this.config.pushDeliveryEnabled,
        s3PublicEndpointConfigured: this.config.s3PublicEndpoint.length > 0,
        productionBootBlocked: !this.config.isProduction,
      },
    };
  }
}
