import { Module } from '@nestjs/common';

import { RetiredHandlesService } from './retired-handles.service';

@Module({
  providers: [RetiredHandlesService],
  exports: [RetiredHandlesService],
})
export class HandlesModule {}
