import { Injectable } from '@nestjs/common';
import type { ContactSummary } from '@veil/contracts';

import { PrismaService } from '../../common/prisma.service';
import { badRequest, conflict, notFound } from '../../common/errors/api-error';
import { AddContactDto } from './dto/add-contact.dto';

// The server keeps only who added whom. What users call their contacts stays
// on their devices.
@Injectable()
export class ContactsService {
  constructor(private readonly prisma: PrismaService) {}

  async listContacts(auth: { userId: string }): Promise<ContactSummary[]> {
    const contacts = await this.prisma.userContact.findMany({
      where: { userId: auth.userId },
      include: { contactUser: { select: { handle: true } } },
      orderBy: { createdAt: 'asc' },
    });

    return contacts.map((entry) => ({
      handle: entry.contactUser.handle,
      addedAt: entry.createdAt.toISOString(),
    }));
  }

  async addContact(auth: { userId: string }, dto: AddContactDto): Promise<ContactSummary> {
    const targetUser = await this.prisma.user.findUnique({
      where: { handle: dto.handle.toLowerCase() },
      select: { id: true, handle: true },
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
      data: { userId: auth.userId, contactUserId: targetUser.id },
    });

    return { handle: targetUser.handle, addedAt: contact.createdAt.toISOString() };
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
