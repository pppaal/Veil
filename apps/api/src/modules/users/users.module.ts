import { Module } from '@nestjs/common';

import { SafetyModule } from '../safety/safety.module';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';

@Module({
  imports: [SafetyModule],
  controllers: [UsersController],
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}
