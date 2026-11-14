import { Module } from '@nestjs/common';

import { RelationshipService } from './relationship.service';
import { SafetyController } from './safety.controller';
import { SafetyService } from './safety.service';

@Module({
  controllers: [SafetyController],
  providers: [SafetyService, RelationshipService],
  exports: [SafetyService, RelationshipService],
})
export class SafetyModule {}
