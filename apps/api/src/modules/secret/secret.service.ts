import { Injectable } from '@nestjs/common';

import { PrismaService } from '../../common/prisma.service';
import { DEFAULT_TTL_SECONDS, MAX_TTL_SECONDS, MIN_TTL_SECONDS } from './dto/create-secret.dto';

export interface CreatedSecret {
  id: string;
  expiresAt: Date;
}

@Injectable()
export class SecretService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Store opaque client-side ciphertext and return its id + expiry. The
   * decryption key is never sent here; it stays in the link fragment.
   */
  async create(ciphertext: string, ttlSeconds?: number): Promise<CreatedSecret> {
    const ttl = Math.min(Math.max(ttlSeconds ?? DEFAULT_TTL_SECONDS, MIN_TTL_SECONDS), MAX_TTL_SECONDS);
    const expiresAt = new Date(Date.now() + ttl * 1000);
    const blob = await this.prisma.secretBlob.create({
      data: { ciphertext, expiresAt },
      select: { id: true, expiresAt: true },
    });
    return { id: blob.id, expiresAt: blob.expiresAt };
  }

  /**
   * Read-and-burn: atomically delete the row and return its ciphertext.
   * Returns null if the link was already opened, never existed, or expired.
   * Using delete (not find-then-delete) makes a concurrent double-open
   * resolve to a single winner — true one-time semantics.
   */
  async burn(id: string): Promise<string | null> {
    let blob: { ciphertext: string; expiresAt: Date };
    try {
      blob = await this.prisma.secretBlob.delete({
        where: { id },
        select: { ciphertext: true, expiresAt: true },
      });
    } catch {
      // P2025 (record not found) — already opened or never existed.
      return null;
    }
    if (blob.expiresAt.getTime() <= Date.now()) {
      // Expired but not yet swept; deleting it above already cleaned up.
      return null;
    }
    return blob.ciphertext;
  }
}
