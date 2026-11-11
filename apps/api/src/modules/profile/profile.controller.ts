import { Controller, Get, Patch, Put, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { ProfileResponse } from '@veil/contracts';

import { apiError } from '../../common/errors/api-error';
import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { ProfileService } from './profile.service';

const PROFILE_TEXT_PENDING = 'Profiles return once they can be stored end-to-end encrypted';

@ApiTags('profile')
@ApiBearerAuth()
@Controller('profile')
export class ProfileController {
  constructor(private readonly profileService: ProfileService) {}

  @Get()
  getProfile(@Req() request: AuthenticatedRequest): Promise<ProfileResponse> {
    return this.profileService.getProfile(request.auth);
  }

  // Profile text would be plaintext on the server, so writing or reading
  // someone's profile is gone until encrypted profiles ship.
  @Patch()
  updateProfile(): never {
    throw apiError('profile_e2e_pending', PROFILE_TEXT_PENDING);
  }

  @Put()
  replaceProfile(): never {
    throw apiError('profile_e2e_pending', PROFILE_TEXT_PENDING);
  }

  @Get(':handle')
  getPublicProfile(): never {
    throw apiError('profile_e2e_pending', PROFILE_TEXT_PENDING);
  }
}
