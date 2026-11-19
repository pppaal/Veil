import { Body, Controller, Delete, Get, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { CreateStoryResponse, StorySummary } from '@veil/contracts';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { UuidParam } from '../../common/pipes/uuid-param.decorator';
import { StoriesService } from './stories.service';
import { CreateStoryDto } from './dto/create-story.dto';

@ApiTags('stories')
@ApiBearerAuth()
@Controller('stories')
export class StoriesController {
  constructor(private readonly storiesService: StoriesService) {}

  @Get()
  listStories(@Req() request: AuthenticatedRequest): Promise<StorySummary[]> {
    return this.storiesService.listStories(request.auth);
  }

  @Post()
  createStory(
    @Req() request: AuthenticatedRequest,
    @Body() dto: CreateStoryDto,
  ): Promise<CreateStoryResponse> {
    return this.storiesService.createStory(request.auth, dto);
  }

  @Post(':id/view')
  viewStory(@Req() request: AuthenticatedRequest, @UuidParam('id') id: string) {
    return this.storiesService.viewStory(request.auth, id);
  }

  @Delete(':id')
  deleteStory(@Req() request: AuthenticatedRequest, @UuidParam('id') id: string) {
    return this.storiesService.deleteStory(request.auth, id);
  }
}
