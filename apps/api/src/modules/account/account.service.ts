import { Injectable } from '@nestjs/common';

import { PrismaService } from '../../common/prisma.service';

// Right-to-erasure cascade for a full account wipe. Order matters — several
// FKs in schema.prisma are `onDelete: Restrict` (Message.senderDevice,
// Attachment.uploaderDevice, CallRecord.initiatorDevice, DeviceTransferSession.oldDevice,
// GroupMeta.createdBy, ChannelMeta.createdBy), so we must remove those rows
// before deleting the devices or the user they point at. Product intent:
// when a user deletes their account, their outbound messages and any
// conversations they created go too — this is a privacy-first messenger and
// sender→user linkage is still identifying metadata even when content is E2E
// encrypted.
@Injectable()
export class AccountService {
  constructor(private readonly prisma: PrismaService) {}

  async deleteAccount(userId: string): Promise<{ deleted: true }> {
    await this.prisma.$transaction(async (tx) => {
      const deviceIds = (
        await tx.device.findMany({ where: { userId }, select: { id: true } })
      ).map((d) => d.id);

      // Conversations the user created (group/channel owner) cascade-delete
      // everything inside them: members, messages, receipts, reactions,
      // groupMeta/channelMeta, callRecords. Scoped by the metadata tables
      // since creation ownership doesn't live on Conversation directly.
      const ownedGroupConvIds = (
        await tx.groupMeta.findMany({
          where: { createdByUserId: userId },
          select: { conversationId: true },
        })
      ).map((m) => m.conversationId);
      const ownedChannelConvIds = (
        await tx.channelMeta.findMany({
          where: { createdByUserId: userId },
          select: { conversationId: true },
        })
      ).map((m) => m.conversationId);
      const ownedConversationIds = [...ownedGroupConvIds, ...ownedChannelConvIds];
      if (ownedConversationIds.length > 0) {
        await tx.conversation.deleteMany({
          where: { id: { in: ownedConversationIds } },
        });
      }

      // Rows that cascade off User directly — safe to remove in any order
      // before the final user.delete.
      await tx.reaction.deleteMany({ where: { userId } });
      await tx.storyView.deleteMany({ where: { viewerUserId: userId } });
      await tx.story.deleteMany({ where: { userId } });
      await tx.messageReceipt.deleteMany({ where: { userId } });
      await tx.userContact.deleteMany({
        where: { OR: [{ userId }, { contactUserId: userId }] },
      });
      await tx.userProfile.deleteMany({ where: { userId } });
      await tx.conversationMember.deleteMany({ where: { userId } });

      // Rows that Restrict on Device deletion — must be removed before
      // device.deleteMany or Postgres will reject the FK.
      if (deviceIds.length > 0) {
        await tx.callRecord.deleteMany({
          where: { initiatorDeviceId: { in: deviceIds } },
        });
        await tx.deviceTransferSession.deleteMany({
          where: {
            OR: [{ userId }, { oldDeviceId: { in: deviceIds } }],
          },
        });
        await tx.message.deleteMany({
          where: { senderDeviceId: { in: deviceIds } },
        });
        await tx.attachment.deleteMany({
          where: { uploaderDeviceId: { in: deviceIds } },
        });
      } else {
        await tx.deviceTransferSession.deleteMany({ where: { userId } });
      }

      // Clear the self-referential FK before deleting the devices row.
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
