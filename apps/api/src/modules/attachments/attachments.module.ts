import { Module } from '@nestjs/common';

import {
  ATTACHMENT_STORAGE_GATEWAY,
  S3AttachmentStorageGateway,
} from './attachment-storage.gateway';
import { AttachmentsController } from './attachments.controller';
import { AttachmentsService } from './attachments.service';

@Module({
  controllers: [AttachmentsController],
  providers: [
    AttachmentsService,
    {
      provide: ATTACHMENT_STORAGE_GATEWAY,
      useClass: S3AttachmentStorageGateway,
    },
  ],
  exports: [AttachmentsService],
})
export class AttachmentsModule {}
