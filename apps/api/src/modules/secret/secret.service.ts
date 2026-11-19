import { createHash } from 'node:crypto';

import { Injectable } from '@nestjs/common';

import { utcDayStart } from '../../common/device-activity';
import { EphemeralStoreService } from '../../common/ephemeral-store.service';
import { apiError } from '../../common/errors/api-error';
import { PrismaService } from '../../common/prisma.service';
import {
  DEFAULT_TTL_SECONDS,
  MAX_SECRET_BYTES_PER_CLIENT_DAY,
  MAX_SECRETS_PER_CLIENT_DAY,
  MAX_STORED_SECRET_BYTES,
  MAX_STORED_SECRETS,
  MAX_TTL_SECONDS,
  MIN_TTL_SECONDS,
} from './dto/create-secret.dto';

export interface CreatedSecret {
  id: string;
  expiresAt: Date;
}

interface StoredUsage {
  blobs: number;
  bytes: number;
}

const DAY_MS = 24 * 60 * 60 * 1000;
// How long the last scan of secret_blobs may refuse a link without a new
// scan. It is never trusted to accept one. Once the budget is full every
// create would otherwise scan the table again just to refuse; this keeps that
// to one scan per instance per window, at the cost of refusing for up to this
// long after links free space.
const SCAN_REUSE_MS = 5_000;

@Injectable()
export class SecretService {
  private lastScan?: StoredUsage & { atMs: number };

  constructor(
    private readonly prisma: PrismaService,
    private readonly store: EphemeralStoreService,
  ) {}

  /**
   * Store opaque client-side ciphertext and return its id + expiry. The
   * decryption key is never sent here; it stays in the link fragment.
   * `clientNetwork` is the caller's network (see clientNetwork()), whose daily
   * quota is spent first, so one client is refused on its own quota before it
   * can use up the relay-wide budget that every client shares.
   */
  async create(
    ciphertext: string,
    ttlSeconds: number | undefined,
    clientNetwork: string,
  ): Promise<CreatedSecret> {
    const bytes = Buffer.byteLength(ciphertext, 'utf8');
    const refund = await this.spendClientQuota(clientNetwork, bytes);
    try {
      await this.assertWithinBudget(bytes);
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
    } catch (error) {
      // Nothing was stored, so the quota is given back; a failed refund only
      // costs the client part of today's quota and must not hide the error.
      await refund().catch(() => undefined);
      throw error;
    }
  }

  /**
   * Spends one link and its bytes from the network's quota for the current UTC
   * day and returns how to give them back. The add comes first and is undone
   * when it went over, so concurrent creates can never be admitted past the
   * quota together (a race can only refuse one that would have fitted).
   * The key holds a digest of the day and the network, never the address, and
   * expires at the end of that day, so its expiry records no request time.
   */
  private async spendClientQuota(
    clientNetwork: string,
    bytes: number,
  ): Promise<() => Promise<void>> {
    const day = utcDayStart(new Date(Date.now()));
    const expiresAtMs = day.getTime() + DAY_MS;
    const digest = createHash('sha256')
      .update(`${day.toISOString()}\u0000${clientNetwork}`)
      .digest('base64url');
    const key = `secret:quota:${digest}`;

    const used = await this.store.incrementFieldsUntil(key, { links: 1, bytes }, expiresAtMs);
    const refund = async (): Promise<void> => {
      await this.store.incrementFieldsUntil(key, { links: -1, bytes: -bytes }, expiresAtMs);
    };
    if (used.links > MAX_SECRETS_PER_CLIENT_DAY || used.bytes > MAX_SECRET_BYTES_PER_CLIENT_DAY) {
      await refund();
      throw apiError(
        'secret_quota_exceeded',
        'This network has used its one-time links for today; the quota renews at 00:00 UTC',
      );
    }
    return refund;
  }

  /**
   * Refuses a link that would take the stored links past the relay-wide
   * budget, counting rows the sweep has not yet removed: they still take
   * space. Concurrent creates can overshoot by what they add between them,
   * at most a few rows of MAX_CIPHERTEXT_LENGTH each.
   */
  private async assertWithinBudget(incomingBytes: number): Promise<void> {
    const recent = this.lastScan;
    if (
      recent &&
      Date.now() - recent.atMs < SCAN_REUSE_MS &&
      SecretService.exceedsBudget(recent, incomingBytes)
    ) {
      throw SecretService.storageFull();
    }

    const [row] = await this.prisma.$queryRaw<Array<{ blobs: bigint; bytes: bigint }>>`
      SELECT count(*) AS blobs, coalesce(sum(octet_length(ciphertext)), 0)::bigint AS bytes
        FROM secret_blobs`;
    const usage = { blobs: Number(row?.blobs ?? 0), bytes: Number(row?.bytes ?? 0) };
    this.lastScan = { ...usage, atMs: Date.now() };
    if (SecretService.exceedsBudget(usage, incomingBytes)) {
      throw SecretService.storageFull();
    }
  }

  private static exceedsBudget(usage: StoredUsage, incomingBytes: number): boolean {
    return (
      usage.blobs >= MAX_STORED_SECRETS || usage.bytes + incomingBytes > MAX_STORED_SECRET_BYTES
    );
  }

  private static storageFull() {
    return apiError('secret_storage_full', 'One-time links are at capacity; try again later');
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
