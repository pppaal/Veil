import { Injectable } from '@nestjs/common';

import { PrismaService } from '../../common/prisma.service';
import { forbidden, notFound } from '../../common/errors/api-error';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { CreateStoryDto } from './dto/create-story.dto';

const STORY_TTL_MS = 24 * 60 * 60 * 1000;

@Injectable()
export class StoriesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
  ) {}

  async listStories(auth: { userId: string }) {
    const now = new Date();

    const contacts = await this.prisma.userContact.findMany({
      where: { userId: auth.userId },
      select: { contactUserId: true },
    });

    const contactIds = contacts.map((c) => c.contactUserId);
    const userIds = [auth.userId, ...contactIds];

    const stories = await this.prisma.story.findMany({
      where: {
        userId: { in: userIds },
        expiresAt: { gt: now },
      },
      orderBy: { createdAt: 'desc' },
      include: {
        user: {
          select: {
            id: true,
            handle: true,
            displayName: true,
          },
        },
        views: {
          where: { viewerUserId: auth.userId },
          select: { id: true },
        },
        _count: {
          select: { views: true },
        },
      },
    });

    return stories.map((story) => ({
      id: story.id,
      userId: story.userId,
      handle: story.user.handle,
      displayName: story.user.displayName,
      contentType: story.contentType,
      contentUrl: story.contentUrl,
      caption: story.caption,
      viewCount: story._count.views,
      viewedByMe: story.views.length > 0,
      createdAt: story.createdAt.toISOString(),
      expiresAt: story.expiresAt.toISOString(),
    }));
  }

  async createStory(auth: { userId: string }, dto: CreateStoryDto) {
    const now = new Date();
    const expiresAt = new Date(now.getTime() + STORY_TTL_MS);

    const story = await this.prisma.story.create({
      data: {
        userId: auth.userId,
        contentType: dto.contentType,
        contentUrl: dto.contentUrl,
        caption: dto.caption ?? null,
        expiresAt,
      },
    });

    const contacts = await this.prisma.userContact.findMany({
      where: { contactUserId: auth.userId },
      select: { userId: true },
    });

    const user = await this.prisma.user.findUnique({
      where: { id: auth.userId },
      select: { handle: true, displayName: true },
    });

    const payload = {
      storyId: story.id,
      userId: auth.userId,
      handle: user?.handle ?? '',
      displayName: user?.displayName ?? null,
      contentType: story.contentType,
      createdAt: story.createdAt.toISOString(),
      expiresAt: story.expiresAt.toISOString(),
    };

    for (const contact of contacts) {
      this.realtimeGateway.emitToUser(contact.userId, 'story.new' as any, payload);
    }

    return {
      id: story.id,
      contentType: story.contentType,
      contentUrl: story.contentUrl,
      caption: story.caption,
      createdAt: story.createdAt.toISOString(),
      expiresAt: story.expiresAt.toISOString(),
    };
  }

  async viewStory(auth: { userId: string }, storyId: string) {
    const now = new Date();

    const story = await this.prisma.story.findUnique({
      where: { id: storyId },
    });

    if (!story || story.expiresAt <= now) {
      throw notFound('story_not_found', 'Story not found or expired');
    }

    const existingView = await this.prisma.storyView.findUnique({
      where: {
        storyId_viewerUserId: {
          storyId,
          viewerUserId: auth.userId,
        },
      },
    });

    if (existingView) {
      return { viewed: true, viewedAt: existingView.viewedAt.toISOString() };
    }

    const view = await this.prisma.storyView.create({
      data: {
        storyId,
        viewerUserId: auth.userId,
      },
    });

    return { viewed: true, viewedAt: view.viewedAt.toISOString() };
  }

  async deleteStory(auth: { userId: string }, storyId: string) {
    const story = await this.prisma.story.findUnique({
      where: { id: storyId },
    });

    if (!story) {
      throw notFound('story_not_found', 'Story not found');
    }

    if (story.userId !== auth.userId) {
      throw forbidden('story_forbidden', 'Cannot delete another user\'s story');
    }

    await this.prisma.story.delete({
      where: { id: storyId },
    });

    return { deleted: true };
  }
}
