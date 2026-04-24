import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import type {
  BlockUserResponse,
  ConversationMuteSummary,
  FileAbuseReportResponse,
  ListBlockedUsersResponse,
  SetConversationMuteResponse,
  UnblockUserResponse,
} from '@veil/contracts';

import { PrismaService } from '../../common/prisma.service';
import type { FileAbuseReportDto } from './dto/file-report.dto';

@Injectable()
export class SafetyService {
  constructor(private readonly prisma: PrismaService) {}

  async listBlocked(currentUserId: string): Promise<ListBlockedUsersResponse> {
    const blocks = await this.prisma.userBlock.findMany({
      where: { blockerUserId: currentUserId },
      orderBy: { createdAt: 'desc' },
      include: {
        blocked: {
          select: { id: true, handle: true, displayName: true },
        },
      },
    });

    return {
      items: blocks.map((block) => ({
        userId: block.blocked.id,
        handle: block.blocked.handle,
        displayName: block.blocked.displayName,
        blockedAt: block.createdAt.toISOString(),
      })),
    };
  }

  async block(currentUserId: string, blockedUserId: string): Promise<BlockUserResponse> {
    if (blockedUserId === currentUserId) {
      throw new BadRequestException('Cannot block yourself');
    }

    const target = await this.prisma.user.findUnique({
      where: { id: blockedUserId },
      select: { id: true, handle: true, displayName: true },
    });

    if (!target) {
      throw new NotFoundException('User not found');
    }

    const block = await this.prisma.userBlock.upsert({
      where: {
        blockerUserId_blockedUserId: {
          blockerUserId: currentUserId,
          blockedUserId,
        },
      },
      update: {},
      create: {
        blockerUserId: currentUserId,
        blockedUserId,
      },
    });

    return {
      blocked: {
        userId: target.id,
        handle: target.handle,
        displayName: target.displayName,
        blockedAt: block.createdAt.toISOString(),
      },
    };
  }

  async unblock(currentUserId: string, blockedUserId: string): Promise<UnblockUserResponse> {
    await this.prisma.userBlock
      .delete({
        where: {
          blockerUserId_blockedUserId: {
            blockerUserId: currentUserId,
            blockedUserId,
          },
        },
      })
      .catch(() => {
        // Idempotent: treat "not blocked" as already-unblocked.
      });
    return { userId: blockedUserId, unblocked: true };
  }

  async isBlockedEitherWay(userIdA: string, userIdB: string): Promise<boolean> {
    const hit = await this.prisma.userBlock.findFirst({
      where: {
        OR: [
          { blockerUserId: userIdA, blockedUserId: userIdB },
          { blockerUserId: userIdB, blockedUserId: userIdA },
        ],
      },
      select: { blockerUserId: true },
    });
    return hit !== null;
  }

  async blockerIdsFor(blockedUserId: string): Promise<Set<string>> {
    const rows = await this.prisma.userBlock.findMany({
      where: { blockedUserId },
      select: { blockerUserId: true },
    });
    return new Set(rows.map((row) => row.blockerUserId));
  }

  async setConversationMute(
    currentUserId: string,
    conversationId: string,
    mutedForSeconds: number | null | undefined,
  ): Promise<SetConversationMuteResponse> {
    const membership = await this.prisma.conversationMember.findUnique({
      where: {
        conversationId_userId: { conversationId, userId: currentUserId },
      },
      select: { id: true },
    });
    if (!membership) {
      throw new ForbiddenException('Conversation membership required');
    }

    if (mutedForSeconds === null) {
      await this.prisma.conversationMute
        .delete({
          where: {
            userId_conversationId: { userId: currentUserId, conversationId },
          },
        })
        .catch(() => {
          // Idempotent.
        });
      return { mute: null };
    }

    const mutedUntil =
      mutedForSeconds === undefined
        ? null
        : new Date(Date.now() + mutedForSeconds * 1000);

    const mute = await this.prisma.conversationMute.upsert({
      where: {
        userId_conversationId: { userId: currentUserId, conversationId },
      },
      update: { mutedUntil },
      create: {
        userId: currentUserId,
        conversationId,
        mutedUntil,
      },
    });

    return {
      mute: {
        conversationId: mute.conversationId,
        mutedUntil: mute.mutedUntil?.toISOString() ?? null,
      },
    };
  }

  async listActiveMutes(userId: string): Promise<ConversationMuteSummary[]> {
    const now = new Date();
    const mutes = await this.prisma.conversationMute.findMany({
      where: {
        userId,
        OR: [{ mutedUntil: null }, { mutedUntil: { gt: now } }],
      },
      select: { conversationId: true, mutedUntil: true },
    });
    return mutes.map((mute) => ({
      conversationId: mute.conversationId,
      mutedUntil: mute.mutedUntil?.toISOString() ?? null,
    }));
  }

  async isConversationMutedForUser(userId: string, conversationId: string): Promise<boolean> {
    const mute = await this.prisma.conversationMute.findUnique({
      where: { userId_conversationId: { userId, conversationId } },
      select: { mutedUntil: true },
    });
    if (!mute) return false;
    if (mute.mutedUntil === null) return true;
    return mute.mutedUntil.getTime() > Date.now();
  }

  async fileReport(
    currentUserId: string,
    dto: FileAbuseReportDto,
  ): Promise<FileAbuseReportResponse> {
    if (dto.reportedUserId === currentUserId) {
      throw new BadRequestException('Cannot report yourself');
    }

    const target = await this.prisma.user.findUnique({
      where: { id: dto.reportedUserId },
      select: { id: true },
    });
    if (!target) {
      throw new NotFoundException('Reported user not found');
    }

    if (dto.conversationId) {
      const membership = await this.prisma.conversationMember.findUnique({
        where: {
          conversationId_userId: {
            conversationId: dto.conversationId,
            userId: currentUserId,
          },
        },
        select: { id: true },
      });
      if (!membership) {
        throw new ForbiddenException('Conversation membership required to report');
      }
    }

    const report = await this.prisma.abuseReport.create({
      data: {
        reporterUserId: currentUserId,
        reportedUserId: dto.reportedUserId,
        conversationId: dto.conversationId ?? null,
        messageId: dto.messageId ?? null,
        reason: dto.reason,
        note: dto.note ?? null,
      },
      select: { id: true, createdAt: true },
    });

    return {
      reportId: report.id,
      filedAt: report.createdAt.toISOString(),
    };
  }
}
