import { Injectable } from '@nestjs/common';
import type { UserProfileResponse } from '@veil/contracts';

import { notFound } from '../../common/errors/api-error';
import { PrismaService } from '../../common/prisma.service';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async getUserByHandle(handle: string): Promise<UserProfileResponse> {
    const user = await this.prisma.user.findUnique({
      where: { handle: handle.toLowerCase() },
      select: { id: true, handle: true, status: true },
    });

    if (!user) {
      throw notFound('handle_not_found', 'User not found');
    }

    return { id: user.id, handle: user.handle, status: user.status };
  }
}
