import { Body, Controller, Delete, Get, Param, Patch, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { GroupsService } from './groups.service';
import { CreateGroupDto } from './dto/create-group.dto';
import { UpdateGroupDto } from './dto/update-group.dto';
import { ManageMemberDto } from './dto/manage-member.dto';

@ApiTags('groups')
@ApiBearerAuth()
@Controller('conversations/group')
export class GroupsController {
  constructor(private readonly groupsService: GroupsService) {}

  @Post()
  createGroup(
    @Req() request: AuthenticatedRequest,
    @Body() dto: CreateGroupDto,
  ) {
    return this.groupsService.createGroup(request.auth, dto);
  }

  @Get(':id')
  getGroup(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
  ) {
    return this.groupsService.getGroup(request.auth, id);
  }

  @Patch(':id')
  updateGroup(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
    @Body() dto: UpdateGroupDto,
  ) {
    return this.groupsService.updateGroup(request.auth, id, dto);
  }

  @Post(':id/members')
  addMember(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
    @Body() dto: ManageMemberDto,
  ) {
    return this.groupsService.addMember(request.auth, id, dto);
  }

  @Delete(':id/members/:handle')
  removeMember(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
    @Param('handle') handle: string,
  ) {
    return this.groupsService.removeMember(request.auth, id, handle);
  }

  @Post(':id/leave')
  leaveGroup(
    @Req() request: AuthenticatedRequest,
    @Param('id') id: string,
  ) {
    return this.groupsService.leaveGroup(request.auth, id);
  }
}
