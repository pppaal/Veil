import { Injectable } from '@nestjs/common';
import type { CreateStoryResponse, StorySummary } from '@veil/contracts';
import { PRODUCTION_FORBIDDEN_ENVELOPE_VERSIONS } from '@veil/shared';

import { AppConfigService } from '../../common/config/app-config.service';
import { apiError } from '../../common/errors/api-error';
import { PrismaService } from '../../common/prisma.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { RelationshipService } from '../safety/relationship.service';
import { CreateStoryDto } from './dto/create-story.dto';

const STORY_TTL_MS = 24 * 60 * 60 * 1000;

type Viewer = { userId: string };

/**
 * Stories are end-to-end encrypted envelopes addressed to an explicit
 * audience the author picks. Who may list or view a story is decided by that
 * audience alone, never recomputed from the contact graph; a block in either
 * direction still hides it. Outside its audience a story answers exactly like
 * a missing one, so story ids cannot be probed.
 */
@Injectable()
export class StoriesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
    private readonly relationships: RelationshipService,
    private readonly config: AppConfigService,
  ) {}

  async listStories(viewer: Viewer): Promise<StorySummary[]> {
    const [stories, blocked] = await Promise.all([
      this.prisma.story.findMany({
        where: { expiresAt: { gt: new Date() }, ...this.visibleTo(viewer) },
        orderBy: { createdAt: 'desc' },
        include: {
          user: { select: { handle: true } },
          views: { where: { viewerUserId: viewer.userId }, select: { id: true } },
          _count: { select: { views: true } },
        },
      }),
      this.relationships.blockedEitherWay(viewer.userId),
    ]);

    return stories
      .filter((story) => !blocked.has(story.userId))
      .map((story) => ({
        id: story.id,
        userId: story.userId,
        handle: story.user.handle,
        ciphertext: story.ciphertext,
        envelopeVersion: story.envelopeVersion,
        viewedByMe: story.views.length > 0,
        viewCount: story.userId === viewer.userId ? story._count.views : null,
        createdAt: story.createdAt.toISOString(),
        expiresAt: story.expiresAt.toISOString(),
      }));
  }

  async createStory(author: Viewer, dto: CreateStoryDto): Promise<CreateStoryResponse> {
    if (
      this.config.isProduction &&
      PRODUCTION_FORBIDDEN_ENVELOPE_VERSIONS.includes(dto.envelopeVersion)
    ) {
      throw apiError(
        'envelope_version_forbidden',
        'Development envelope formats are not accepted by this relay',
      );
    }
    const reachable = new Set(await this.relationships.visibleContactIds(author.userId));
    if (!dto.audienceUserIds.every((userId) => reachable.has(userId))) {
      throw apiError(
        'story_audience_invalid',
        'Every audience member must be a mutual contact neither side has blocked',
      );
    }

    const now = new Date();
    const story = await this.prisma.story.create({
      data: {
        userId: author.userId,
        ciphertext: dto.ciphertext,
        envelopeVersion: dto.envelopeVersion,
        expiresAt: new Date(now.getTime() + STORY_TTL_MS),
        audience: { create: dto.audienceUserIds.map((userId) => ({ userId })) },
      },
      include: { user: { select: { handle: true } } },
    });

    const announcement = {
      storyId: story.id,
      userId: author.userId,
      handle: story.user.handle,
      envelopeVersion: story.envelopeVersion,
      createdAt: story.createdAt.toISOString(),
      expiresAt: story.expiresAt.toISOString(),
    };
    for (const userId of dto.audienceUserIds) {
      this.realtimeGateway.emitToUser(userId, 'story.new', announcement);
    }

    return {
      id: story.id,
      envelopeVersion: story.envelopeVersion,
      audienceSize: dto.audienceUserIds.length,
      createdAt: story.createdAt.toISOString(),
      expiresAt: story.expiresAt.toISOString(),
    };
  }

  async viewStory(viewer: Viewer, storyId: string) {
    const story = await this.findVisible(viewer, storyId);
    if (story.userId !== viewer.userId) {
      const blocked = await this.relationships.blockedEitherWay(viewer.userId);
      if (blocked.has(story.userId)) {
        throw apiError('story_not_found', 'Story not found or expired');
      }
    }

    const existingView = await this.prisma.storyView.findUnique({
      where: { storyId_viewerUserId: { storyId, viewerUserId: viewer.userId } },
    });
    if (existingView) {
      return { viewed: true, viewedAt: existingView.viewedAt.toISOString() };
    }

    const view = await this.prisma.storyView.create({
      data: { storyId, viewerUserId: viewer.userId },
    });
    return { viewed: true, viewedAt: view.viewedAt.toISOString() };
  }

  // Someone else's story answers like a missing one, so DELETE cannot be used
  // to probe which story ids exist.
  async deleteStory(author: Viewer, storyId: string) {
    const { count } = await this.prisma.story.deleteMany({
      where: { id: storyId, userId: author.userId },
    });
    if (count === 0) {
      throw apiError('story_not_found', 'Story not found');
    }
    return { deleted: true };
  }

  private async findVisible(viewer: Viewer, storyId: string) {
    const story = await this.prisma.story.findFirst({
      where: { id: storyId, expiresAt: { gt: new Date() }, ...this.visibleTo(viewer) },
      select: { id: true, userId: true },
    });
    if (!story) {
      throw apiError('story_not_found', 'Story not found or expired');
    }
    return story;
  }

  private visibleTo(viewer: Viewer) {
    return {
      OR: [{ userId: viewer.userId }, { audience: { some: { userId: viewer.userId } } }],
    };
  }
}
