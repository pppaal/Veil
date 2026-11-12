import { Injectable } from '@nestjs/common';
import type { UserProfileResponse } from '@veil/contracts';

import { notFound } from '../../common/errors/api-error';
import { PrismaService } from '../../common/prisma.service';
import { SafetyService } from '../safety/safety.service';

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly safety: SafetyService,
  ) {}

  // A block in either direction answers exactly like an unknown handle, as
  // createDirect and addMember do, so the lookup does not tell a blocked user
  // that they were blocked.
  async getUserByHandle(requesterUserId: string, handle: string): Promise<UserProfileResponse> {
    const user = await this.prisma.user.findUnique({
      where: { handle: handle.toLowerCase() },
      select: { id: true, handle: true, status: true },
    });

    if (!user || (await this.safety.isBlockedEitherWay(requesterUserId, user.id))) {
      throw notFound('handle_not_found', 'User not found');
    }

    return { id: user.id, handle: user.handle, status: user.status };
  }
}
