import { Injectable } from '@nestjs/common';

import { apiError } from '../../common/errors/api-error';
import { PrismaService } from '../../common/prisma.service';
import {
  DEFAULT_TTL_SECONDS,
  MAX_STORED_SECRET_BYTES,
  MAX_STORED_SECRETS,
  MAX_TTL_SECONDS,
  MIN_TTL_SECONDS,
} from './dto/create-secret.dto';

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
    await this.assertWithinBudget(Buffer.byteLength(ciphertext, 'utf8'));
    const ttl = Math.min(
      Math.max(ttlSeconds ?? DEFAULT_TTL_SECONDS, MIN_TTL_SECONDS),
      MAX_TTL_SECONDS,
    );
    const expiresAt = new Date(Date.now() + ttl * 1000);
    const blob = await this.prisma.secretBlob.create({
      data: { ciphertext, expiresAt },
      select: { id: true, expiresAt: true },
    });
    return { id: blob.id, expiresAt: blob.expiresAt };
  }

  /**
   * Refuses a link that would take the stored links past the relay-wide
   * budget, counting rows the sweep has not yet removed: they still take
   * space. Concurrent creates can overshoot by what they add between them,
   * at most a few rows of MAX_CIPHERTEXT_LENGTH each.
   */
  private async assertWithinBudget(incomingBytes: number): Promise<void> {
    const [usage] = await this.prisma.$queryRaw<Array<{ blobs: bigint; bytes: bigint }>>`
      SELECT count(*) AS blobs, coalesce(sum(octet_length(ciphertext)), 0)::bigint AS bytes
        FROM secret_blobs`;
    if (
      Number(usage?.blobs ?? 0) >= MAX_STORED_SECRETS ||
      Number(usage?.bytes ?? 0) + incomingBytes > MAX_STORED_SECRET_BYTES
    ) {
      throw apiError('secret_storage_full', 'One-time links are at capacity; try again later');
    }
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
