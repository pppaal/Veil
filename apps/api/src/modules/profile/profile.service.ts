import { Injectable } from '@nestjs/common';
import type { ProfileResponse } from '@veil/contracts';

import { apiError } from '../../common/errors/api-error';
import { PrismaService } from '../../common/prisma.service';

/**
 * A profile is the handle only. Display names, bio, status and avatars come
 * back once they can be stored end-to-end encrypted for the people the user
 * shares them with; until then the server keeps none of them.
 */
@Injectable()
export class ProfileService {
  constructor(private readonly prisma: PrismaService) {}

  async getProfile(auth: { userId: string }): Promise<ProfileResponse> {
    const user = await this.prisma.user.findUnique({
      where: { id: auth.userId },
      select: { id: true, handle: true },
    });
    if (!user) {
      throw apiError('profile_not_found', 'User not found');
    }
    return { userId: user.id, handle: user.handle };
  }
}
