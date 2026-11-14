import { Injectable } from '@nestjs/common';

import { PrismaService } from '../../common/prisma.service';

/**
 * Who a user may address a story to. Adding a contact is one-way and needs no
 * consent, so it never makes someone reachable on its own: only a mutual
 * contact does, and a block in either direction always wins.
 */
@Injectable()
export class RelationshipService {
  constructor(private readonly prisma: PrismaService) {}

  /** Mutual contacts of the user, minus anyone blocked in either direction. */
  async visibleContactIds(userId: string): Promise<string[]> {
    const [added, addedBy, blocked] = await Promise.all([
      this.prisma.userContact.findMany({ where: { userId }, select: { contactUserId: true } }),
      this.prisma.userContact.findMany({
        where: { contactUserId: userId },
        select: { userId: true },
      }),
      this.blockedEitherWay(userId),
    ]);

    const addedBack = new Set(addedBy.map((row) => row.userId));
    return added
      .map((row) => row.contactUserId)
      .filter((contactId) => addedBack.has(contactId) && !blocked.has(contactId));
  }

  /** Everyone the user blocked or was blocked by. */
  async blockedEitherWay(userId: string): Promise<Set<string>> {
    const blocks = await this.prisma.userBlock.findMany({
      where: { OR: [{ blockerUserId: userId }, { blockedUserId: userId }] },
      select: { blockerUserId: true, blockedUserId: true },
    });
    return new Set(
      blocks.map((block) =>
        block.blockerUserId === userId ? block.blockedUserId : block.blockerUserId,
      ),
    );
  }
}
