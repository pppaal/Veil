import { Module } from '@nestjs/common';

import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { DEVICE_AUTH_VERIFIER, Ed25519DeviceAuthVerifier } from './device-auth-verifier';

@Module({
  controllers: [AuthController],
  providers: [
    AuthService,
    Ed25519DeviceAuthVerifier,
    {
      provide: DEVICE_AUTH_VERIFIER,
      useExisting: Ed25519DeviceAuthVerifier,
    },
  ],
  exports: [AuthService, DEVICE_AUTH_VERIFIER],
})
export class AuthModule {}
