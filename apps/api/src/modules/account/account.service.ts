import { Injectable, Logger } from '@nestjs/common';

import { PrismaService } from '../../common/prisma.service';

// Right-to-erasure cascade for a full account wipe. Order matters — several
// FKs in schema.prisma are `onDelete: Restrict` (Message.senderDevice,
// Attachment.uploaderDevice, CallRecord.initiatorDevice,
// DeviceTransferSession.oldDevice, GroupMeta.createdBy, ChannelMeta.createdBy),
// so we must remove those rows before deleting the devices or the user they
// point at. Product intent: when a user deletes their account, their outbound
// messages and any conversations they created go too — this is a
// privacy-first messenger and sender→user linkage is still identifying
// metadata even when content is E2E encrypted.
//
// Earlier implementation wrapped the entire cascade in a single transaction.
// For an account with hundreds of thousands of messages that produced lock
// storms and could blow past statement_timeout. We now revoke auth in a small
// initial transaction, run the bulky deletes outside any transaction (so
// Postgres can release locks between batches and so a partial failure can be
// resumed), and only put the small final user/device cleanup back inside a
// transaction.
@Injectable()
export class AccountService {
  private readonly logger = new Logger(AccountService.name);

  constructor(private readonly prisma: PrismaService) {}

  async deleteAccount(userId: string): Promise<{ deleted: true }> {
    // Phase 1 (small tx): immediately revoke auth so any in-flight tokens
    // can't be reused and no new sessions can come in mid-cascade.
    await this.prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: userId },
        data: { status: 'revoked', activeDeviceId: null },
      });
      await tx.device.updateMany({
        where: { userId },
        data: { isActive: false },
      });
    });

    const deviceIds = (
      await this.prisma.device.findMany({ where: { userId }, select: { id: true } })
    ).map((d) => d.id);

    const ownedGroupConvIds = (
      await this.prisma.groupMeta.findMany({
        where: { createdByUserId: userId },
        select: { conversationId: true },
      })
    ).map((m) => m.conversationId);
    const ownedChannelConvIds = (
      await this.prisma.channelMeta.findMany({
        where: { createdByUserId: userId },
        select: { conversationId: true },
      })
    ).map((m) => m.conversationId);
    const ownedConversationIds = [...ownedGroupConvIds, ...ownedChannelConvIds];

    // Phase 2 (no enclosing tx): each deleteMany is its own statement,
    // committed independently. Postgres releases the row locks between
    // statements so concurrent reads on unrelated rows aren't blocked.
    // The order respects the Restrict FKs.
    for (const deviceId of deviceIds) {
      await this.runDelete('messages', () =>
        this.prisma.message.deleteMany({ where: { senderDeviceId: deviceId } }),
      );
      await this.runDelete('attachments', () =>
        this.prisma.attachment.deleteMany({ where: { uploaderDeviceId: deviceId } }),
      );
      await this.runDelete('callRecords', () =>
        this.prisma.callRecord.deleteMany({ where: { initiatorDeviceId: deviceId } }),
      );
    }

    await this.runDelete('messageReceipts', () =>
      this.prisma.messageReceipt.deleteMany({ where: { userId } }),
    );
    await this.runDelete('reactions', () =>
      this.prisma.reaction.deleteMany({ where: { userId } }),
    );
    await this.runDelete('storyViews', () =>
      this.prisma.storyView.deleteMany({ where: { viewerUserId: userId } }),
    );
    await this.runDelete('stories', () =>
      this.prisma.story.deleteMany({ where: { userId } }),
    );
    await this.runDelete('userContacts', () =>
      this.prisma.userContact.deleteMany({
        where: { OR: [{ userId }, { contactUserId: userId }] },
      }),
    );
    await this.runDelete('conversationMembers', () =>
      this.prisma.conversationMember.deleteMany({ where: { userId } }),
    );

    if (ownedConversationIds.length > 0) {
      // Cascade-delete is bounded by the number of group/channel
      // conversations the user owns — typically small.
      await this.runDelete('ownedConversations', () =>
        this.prisma.conversation.deleteMany({
          where: { id: { in: ownedConversationIds } },
        }),
      );
    }

    // Phase 3 (small tx): finish the metadata + the user/device rows
    // themselves. By now everything restricting them is gone.
    await this.prisma.$transaction(async (tx) => {
      if (deviceIds.length > 0) {
        await tx.deviceTransferSession.deleteMany({
          where: {
            OR: [{ userId }, { oldDeviceId: { in: deviceIds } }],
          },
        });
      } else {
        await tx.deviceTransferSession.deleteMany({ where: { userId } });
      }
      await tx.userProfile.deleteMany({ where: { userId } });
      await tx.user.update({
        where: { id: userId },
        data: { activeDeviceId: null },
      });
      await tx.device.deleteMany({ where: { userId } });
      await tx.user.delete({ where: { id: userId } });
    });

    return { deleted: true };
  }

  private async runDelete(
    label: string,
    run: () => Promise<{ count: number }>,
  ): Promise<number> {
    try {
      const { count } = await run();
      if (count > 0) {
        this.logger.debug(`deleteAccount: ${label} removed ${count} rows`);
      }
      return count;
    } catch (e) {
      this.logger.warn(`deleteAccount: ${label} failed: ${(e as Error).message}`);
      throw e;
    }
  }
}
