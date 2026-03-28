import { Body, Controller, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type {
  AuthChallengeResponse,
  AuthVerifyResponse,
  RegisterResponse,
} from '@veil/contracts';

import { Public } from '../../common/guards/public.decorator';
import { AuthService } from './auth.service';
import { ChallengeDto, VerifyDto } from './dto/challenge.dto';
import { RegisterDto } from './dto/register.dto';

@ApiTags('auth')
@ApiBearerAuth()
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Public()
  @Post('register')
  register(@Body() dto: RegisterDto): Promise<RegisterResponse> {
    return this.authService.register(dto);
  }

  @Public()
  @Post('challenge')
  createChallenge(@Body() dto: ChallengeDto): Promise<AuthChallengeResponse> {
    return this.authService.createChallenge(dto);
  }

  @Public()
  @Post('verify')
  verify(@Body() dto: VerifyDto): Promise<AuthVerifyResponse> {
    return this.authService.verify(dto);
  }
}
