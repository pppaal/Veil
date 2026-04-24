import { ApiProperty } from '@nestjs/swagger';
import { IsEnum, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

import type { AbuseReportReason, FileAbuseReportRequest } from '@veil/contracts';

const REPORT_REASONS: AbuseReportReason[] = [
  'spam',
  'harassment',
  'impersonation',
  'csam',
  'violence',
  'scam',
  'other',
];

export class FileAbuseReportDto implements FileAbuseReportRequest {
  @ApiProperty({ format: 'uuid' })
  @IsUUID()
  reportedUserId!: string;

  @ApiProperty({ format: 'uuid', required: false, nullable: true })
  @IsOptional()
  @IsUUID()
  conversationId?: string | null;

  @ApiProperty({ format: 'uuid', required: false, nullable: true })
  @IsOptional()
  @IsUUID()
  messageId?: string | null;

  @ApiProperty({ enum: REPORT_REASONS })
  @IsEnum(REPORT_REASONS as readonly string[] as string[])
  reason!: AbuseReportReason;

  @ApiProperty({ required: false, nullable: true, maxLength: 1000 })
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  note?: string | null;
}
