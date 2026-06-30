import { Body, Controller, Delete, Get, NotFoundException, Put, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';

import type { AuthenticatedRequest } from '../../common/guards/authenticated-request';
import { UpsertRecoveryBlobDto } from './dto/upsert-recovery-blob.dto';
import { RecoveryService } from './recovery.service';

interface RecoveryBlobResponse {
  ciphertext: string;
  format: string;
  updatedAt: string;
}

// Authenticated account-recovery backup. Every route is user-scoped to the
// caller — there is no way to address another user's backup. The server only
// ever sees the opaque passphrase-sealed envelope; it cannot decrypt it.
@ApiTags('recovery')
@ApiBearerAuth()
@Controller('recovery/backup')
export class RecoveryController {
  constructor(private readonly recoveryService: RecoveryService) {}

  // Tight throttle: a backup is written rarely (on key change / opt-in), and
  // bounding it stops the endpoint being abused as churn-y blob storage.
  @Throttle({ default: { ttl: 60_000, limit: 6 } })
  @Put()
  async upsert(
    @Req() request: AuthenticatedRequest,
    @Body() dto: UpsertRecoveryBlobDto,
  ): Promise<{ updatedAt: string }> {
    const { updatedAt } = await this.recoveryService.upsert(
      request.auth.userId,
      dto.ciphertext,
      dto.format,
    );
    return { updatedAt: updatedAt.toISOString() };
  }

  @Get()
  async get(@Req() request: AuthenticatedRequest): Promise<RecoveryBlobResponse> {
    const blob = await this.recoveryService.get(request.auth.userId);
    if (!blob) {
      throw new NotFoundException('No recovery backup stored for this account.');
    }
    return {
      ciphertext: blob.ciphertext,
      format: blob.format,
      updatedAt: blob.updatedAt.toISOString(),
    };
  }

  @Delete()
  async remove(@Req() request: AuthenticatedRequest): Promise<{ deleted: boolean }> {
    return this.recoveryService.remove(request.auth.userId);
  }
}
