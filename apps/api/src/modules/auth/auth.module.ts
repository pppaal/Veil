import { Module } from '@nestjs/common';

import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { DEVICE_AUTH_VERIFIER, MockDeviceAuthVerifier } from './device-auth-verifier';

@Module({
  controllers: [AuthController],
  providers: [
    AuthService,
    MockDeviceAuthVerifier,
    {
      provide: DEVICE_AUTH_VERIFIER,
      useExisting: MockDeviceAuthVerifier,
    },
  ],
  exports: [AuthService],
})
export class AuthModule {}
