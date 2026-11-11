import { Injectable } from '@nestjs/common';

import { PrismaService } from '../../common/prisma.service';
import { SafetyService } from './safety.service';

/**
 * Who may see whose stories and profile. Adding a contact is one-way and
 * needs no consent, so it never grants visibility on its own: only a mutual
 * contact or a real shared conversation does, and a block in either direction
 * always wins.
 */
@Injectable()
export class RelationshipService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly safety: SafetyService,
  ) {}

  /** Mutual contacts of the user, minus anyone blocked in either direction. */
  async visibleContactIds(userId: string): Promise<string[]> {
    const [added, addedBy, blocks] = await Promise.all([
      this.prisma.userContact.findMany({ where: { userId }, select: { contactUserId: true } }),
      this.prisma.userContact.findMany({
        where: { contactUserId: userId },
        select: { userId: true },
      }),
      this.prisma.userBlock.findMany({
        where: { OR: [{ blockerUserId: userId }, { blockedUserId: userId }] },
        select: { blockerUserId: true, blockedUserId: true },
      }),
    ]);

    const addedBack = new Set(addedBy.map((row) => row.userId));
    const blocked = new Set(
      blocks.map((block) =>
        block.blockerUserId === userId ? block.blockedUserId : block.blockerUserId,
      ),
    );
    return added
      .map((row) => row.contactUserId)
      .filter((contactId) => addedBack.has(contactId) && !blocked.has(contactId));
  }

  async canSeeStoriesOf(viewerId: string, authorId: string): Promise<boolean> {
    if (viewerId === authorId) {
      return true;
    }
    return (
      (await this.areMutualContacts(viewerId, authorId)) &&
      !(await this.safety.isBlockedEitherWay(viewerId, authorId))
    );
  }

  async canSeeProfileOf(viewerId: string, targetId: string): Promise<boolean> {
    if (viewerId === targetId) {
      return true;
    }
    if (await this.safety.isBlockedEitherWay(viewerId, targetId)) {
      return false;
    }
    return (
      (await this.areMutualContacts(viewerId, targetId)) ||
      (await this.shareConversation(viewerId, targetId))
    );
  }

  private async areMutualContacts(userIdA: string, userIdB: string): Promise<boolean> {
    const [forward, backward] = await Promise.all([
      this.prisma.userContact.findUnique({
        where: { userId_contactUserId: { userId: userIdA, contactUserId: userIdB } },
        select: { id: true },
      }),
      this.prisma.userContact.findUnique({
        where: { userId_contactUserId: { userId: userIdB, contactUserId: userIdA } },
        select: { id: true },
      }),
    ]);
    return forward !== null && backward !== null;
  }

  // Channels are broadcast: subscribers share the conversation row but have
  // no relationship with each other, so only direct and group chats count.
  private async shareConversation(userIdA: string, userIdB: string): Promise<boolean> {
    const shared = await this.prisma.conversationMember.findFirst({
      where: {
        userId: userIdA,
        conversation: {
          type: { in: ['direct', 'group'] },
          members: { some: { userId: userIdB } },
        },
      },
      select: { id: true },
    });
    return shared !== null;
  }
}
