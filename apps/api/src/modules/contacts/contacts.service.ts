import { Injectable } from '@nestjs/common';

import { PrismaService } from '../../common/prisma.service';
import {
  badRequest,
  conflict,
  notFound,
} from '../../common/errors/api-error';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { AddContactDto } from './dto/add-contact.dto';

@Injectable()
export class ContactsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtimeGateway: RealtimeGateway,
  ) {}

  async listContacts(auth: { userId: string }) {
    const contacts = await this.prisma.userContact.findMany({
      where: { userId: auth.userId },
      include: {
        contactUser: {
          select: {
            id: true,
            handle: true,
            displayName: true,
            profile: {
              select: { avatarPath: true },
            },
          },
        },
      },
      orderBy: { createdAt: 'asc' },
    });

    return contacts.map((entry) => ({
      handle: entry.contactUser.handle,
      displayName: entry.contactUser.displayName,
      nickname: entry.nickname,
      avatarPath: entry.contactUser.profile?.avatarPath ?? null,
      addedAt: entry.createdAt.toISOString(),
    }));
  }

  async addContact(auth: { userId: string }, dto: AddContactDto) {
    const targetUser = await this.prisma.user.findUnique({
      where: { handle: dto.handle.toLowerCase() },
      select: { id: true, handle: true, displayName: true },
    });

    if (!targetUser) {
      throw notFound('contact_not_found', 'User not found');
    }

    if (targetUser.id === auth.userId) {
      throw badRequest('cannot_add_self', 'Cannot add yourself as a contact');
    }

    const existing = await this.prisma.userContact.findUnique({
      where: {
        userId_contactUserId: {
          userId: auth.userId,
          contactUserId: targetUser.id,
        },
      },
    });

    if (existing) {
      throw conflict('contact_already_exists', 'Contact already exists');
    }

    const contact = await this.prisma.userContact.create({
      data: {
        userId: auth.userId,
        contactUserId: targetUser.id,
        nickname: dto.nickname ?? null,
      },
    });

    return {
      handle: targetUser.handle,
      displayName: targetUser.displayName,
      nickname: contact.nickname,
      addedAt: contact.createdAt.toISOString(),
    };
  }

  async removeContact(auth: { userId: string }, handle: string) {
    const targetUser = await this.prisma.user.findUnique({
      where: { handle: handle.toLowerCase() },
      select: { id: true },
    });

    if (!targetUser) {
      throw notFound('contact_not_found', 'Contact not found');
    }

    const existing = await this.prisma.userContact.findUnique({
      where: {
        userId_contactUserId: {
          userId: auth.userId,
          contactUserId: targetUser.id,
        },
      },
    });

    if (!existing) {
      throw notFound('contact_not_found', 'Contact not found');
    }

    await this.prisma.userContact.delete({
      where: {
        userId_contactUserId: {
          userId: auth.userId,
          contactUserId: targetUser.id,
        },
      },
    });

    return { removed: true };
  }
}
