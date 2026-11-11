import { Module } from '@nestjs/common';

import { DirectoryBudget } from './directory-budget';
import { KeysController } from './keys.controller';
import { KEYS_CLOCK, KeysService } from './keys.service';
import { PrekeysController } from './prekeys.controller';
import { PrekeysService } from './prekeys.service';

@Module({
  controllers: [PrekeysController, KeysController],
  providers: [
    PrekeysService,
    KeysService,
    DirectoryBudget,
    { provide: KEYS_CLOCK, useValue: () => Date.now() },
  ],
  exports: [PrekeysService, DirectoryBudget],
})
export class PrekeysModule {}
