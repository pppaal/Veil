import { Injectable } from '@nestjs/common';

import { PrismaService } from '../../common/prisma.service';

@Injectable()
export class AccountService {
  constructor(private readonly prisma: PrismaService) {}

  async deleteAccount(userId: string): Promise<{ deleted: true }> {
    await this.prisma.$transaction(async (tx) => {
      await tx.reaction.deleteMany({ where: { userId } });
      await tx.storyView.deleteMany({ where: { viewerUserId: userId } });
      await tx.story.deleteMany({ where: { userId } });
      await tx.messageReceipt.deleteMany({ where: { userId } });
      await tx.userContact.deleteMany({
        where: { OR: [{ userId }, { contactUserId: userId }] },
      });
      await tx.userProfile.deleteMany({ where: { userId } });
      await tx.conversationMember.deleteMany({ where: { userId } });
      await tx.deviceTransferSession.deleteMany({ where: { userId } });
      await tx.user.update({
        where: { id: userId },
        data: { activeDeviceId: null },
      });
      await tx.device.deleteMany({ where: { userId } });
      await tx.user.delete({ where: { id: userId } });
    });

    return { deleted: true };
  }
}
