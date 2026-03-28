import { Controller, Get } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';

import { Public } from '../../common/guards/public.decorator';

@ApiTags('health')
@Controller('health')
export class HealthController {
  @Public()
  @Get()
  getHealth(): { status: 'ok'; service: 'veil-api' } {
    return {
      status: 'ok',
      service: 'veil-api',
    };
  }
}
