import { Injectable } from '@nestjs/common';

import { PrismaService } from '../../common/prisma.service';

export interface StoredRecoveryBlob {
  ciphertext: string;
  format: string;
  updatedAt: Date;
}

@Injectable()
export class RecoveryService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Store (or replace) the caller's passphrase-sealed recovery backup. The
   * server only ever holds the opaque envelope — it has neither the passphrase
   * nor the derived key, so it cannot decrypt this. One row per user; a new
   * upload supersedes the previous backup.
   */
  async upsert(userId: string, ciphertext: string, format?: string): Promise<{ updatedAt: Date }> {
    const fmt = format ?? 'veilbak:v1';
    const blob = await this.prisma.recoveryBlob.upsert({
      where: { userId },
      update: { ciphertext, format: fmt },
      create: { userId, ciphertext, format: fmt },
      select: { updatedAt: true },
    });
    return { updatedAt: blob.updatedAt };
  }

  /**
   * Return the caller's stored backup, or null if they have none. Authenticated
   * read only — the lost-device retrieval path is a separate, still-open design
   * decision (see docs/recovery-backup-design.md).
   */
  async get(userId: string): Promise<StoredRecoveryBlob | null> {
    const blob = await this.prisma.recoveryBlob.findUnique({
      where: { userId },
      select: { ciphertext: true, format: true, updatedAt: true },
    });
    return blob;
  }

  /**
   * Delete the caller's backup. Idempotent — removing a non-existent backup is
   * a no-op, not an error.
   */
  async remove(userId: string): Promise<{ deleted: boolean }> {
    const result = await this.prisma.recoveryBlob.deleteMany({ where: { userId } });
    return { deleted: result.count > 0 };
  }
}
