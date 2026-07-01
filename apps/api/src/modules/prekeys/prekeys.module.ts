import { Module } from '@nestjs/common';

import { PrekeysController } from './prekeys.controller';
import { PrekeysService } from './prekeys.service';

@Module({
  controllers: [PrekeysController],
  providers: [PrekeysService],
  exports: [PrekeysService],
})
export class PrekeysModule {}
