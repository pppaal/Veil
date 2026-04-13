import { Body, Controller, Delete, Get, Param, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { ContactsService } from './contacts.service';
import { AddContactDto } from './dto/add-contact.dto';

@ApiTags('contacts')
@ApiBearerAuth()
@Controller('contacts')
export class ContactsController {
  constructor(private readonly contactsService: ContactsService) {}

  @Get()
  listContacts(@Req() request: AuthenticatedRequest) {
    return this.contactsService.listContacts(request.auth);
  }

  @Post()
  addContact(
    @Req() request: AuthenticatedRequest,
    @Body() dto: AddContactDto,
  ) {
    return this.contactsService.addContact(request.auth, dto);
  }

  @Delete(':handle')
  removeContact(
    @Req() request: AuthenticatedRequest,
    @Param('handle') handle: string,
  ) {
    return this.contactsService.removeContact(request.auth, handle);
  }
}
