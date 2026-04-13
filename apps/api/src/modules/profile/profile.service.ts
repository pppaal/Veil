import { Injectable } from '@nestjs/common';

import { PrismaService } from '../../common/prisma.service';
import { notFound } from '../../common/errors/api-error';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { UpdateProfileDto } from './dto/update-profile.dto';

@Injectable()
export class ProfileService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
  ) {}

  async getProfile(auth: { userId: string }) {
    const user = await this.prisma.user.findUnique({
      where: { id: auth.userId },
      select: {
        id: true,
        handle: true,
        displayName: true,
        createdAt: true,
      },
    });

    if (!user) {
      throw notFound('profile_not_found', 'User not found');
    }

    const profile = await this.prisma.userProfile.upsert({
      where: { userId: auth.userId },
      update: {},
      create: { userId: auth.userId },
    });

    return {
      id: user.id,
      handle: user.handle,
      displayName: user.displayName,
      bio: profile.bio,
      statusMessage: profile.statusMessage,
      statusEmoji: profile.statusEmoji,
      avatarPath: profile.avatarPath,
      lastStatusAt: profile.lastStatusAt?.toISOString() ?? null,
      createdAt: user.createdAt.toISOString(),
    };
  }

  async updateProfile(auth: { userId: string }, dto: UpdateProfileDto) {
    const user = await this.prisma.user.findUnique({
      where: { id: auth.userId },
      select: { id: true },
    });

    if (!user) {
      throw notFound('profile_not_found', 'User not found');
    }

    if (dto.displayName !== undefined) {
      await this.prisma.user.update({
        where: { id: auth.userId },
        data: { displayName: dto.displayName },
      });
    }

    const currentProfile = await this.prisma.userProfile.findUnique({
      where: { userId: auth.userId },
    });

    const statusChanged =
      (dto.statusMessage !== undefined && dto.statusMessage !== currentProfile?.statusMessage) ||
      (dto.statusEmoji !== undefined && dto.statusEmoji !== currentProfile?.statusEmoji);

    const profile = await this.prisma.userProfile.upsert({
      where: { userId: auth.userId },
      update: {
        ...(dto.bio !== undefined ? { bio: dto.bio } : {}),
        ...(dto.statusMessage !== undefined ? { statusMessage: dto.statusMessage } : {}),
        ...(dto.statusEmoji !== undefined ? { statusEmoji: dto.statusEmoji } : {}),
        ...(statusChanged ? { lastStatusAt: new Date() } : {}),
      },
      create: {
        userId: auth.userId,
        bio: dto.bio ?? null,
        statusMessage: dto.statusMessage ?? null,
        statusEmoji: dto.statusEmoji ?? null,
        ...(statusChanged ? { lastStatusAt: new Date() } : {}),
      },
    });

    const updatedUser = await this.prisma.user.findUnique({
      where: { id: auth.userId },
      select: {
        id: true,
        handle: true,
        displayName: true,
        createdAt: true,
      },
    });

    return {
      id: updatedUser!.id,
      handle: updatedUser!.handle,
      displayName: updatedUser!.displayName,
      bio: profile.bio,
      statusMessage: profile.statusMessage,
      statusEmoji: profile.statusEmoji,
      avatarPath: profile.avatarPath,
      lastStatusAt: profile.lastStatusAt?.toISOString() ?? null,
      createdAt: updatedUser!.createdAt.toISOString(),
    };
  }

  async getPublicProfile(auth: { userId: string }, handle: string) {
    const user = await this.prisma.user.findUnique({
      where: { handle: handle.toLowerCase() },
      select: {
        id: true,
        handle: true,
        displayName: true,
      },
    });

    if (!user) {
      throw notFound('profile_not_found', 'User not found');
    }

    const profile = await this.prisma.userProfile.findUnique({
      where: { userId: user.id },
    });

    return {
      handle: user.handle,
      displayName: user.displayName,
      bio: profile?.bio ?? null,
      statusMessage: profile?.statusMessage ?? null,
      statusEmoji: profile?.statusEmoji ?? null,
      avatarPath: profile?.avatarPath ?? null,
    };
  }
}
