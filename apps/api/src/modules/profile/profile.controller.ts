import { Body, Controller, Get, Param, Patch, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { ProfileService } from './profile.service';
import { UpdateProfileDto } from './dto/update-profile.dto';

@ApiTags('profile')
@ApiBearerAuth()
@Controller('profile')
export class ProfileController {
  constructor(private readonly profileService: ProfileService) {}

  @Get()
  getProfile(@Req() request: AuthenticatedRequest) {
    return this.profileService.getProfile(request.auth);
  }

  @Patch()
  updateProfile(
    @Req() request: AuthenticatedRequest,
    @Body() dto: UpdateProfileDto,
  ) {
    return this.profileService.updateProfile(request.auth, dto);
  }

  @Get(':handle')
  getPublicProfile(
    @Req() request: AuthenticatedRequest,
    @Param('handle') handle: string,
  ) {
    return this.profileService.getPublicProfile(request.auth, handle);
  }
}
