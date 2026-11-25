import type { Prisma } from '@prisma/client';

import type { PrismaService } from '../../common/prisma.service';
import type { AttachmentStorageGateway } from '../attachments/attachment-storage.gateway';

// An attachment nothing visible points at any more: no message, or only
// delete-for-everyone tombstones that no longer show it.
export const UNREFERENCED_ATTACHMENT: Prisma.AttachmentWhereInput = {
  messages: { none: { deletedAt: null } },
};

export interface StoredAttachment {
  id: string;
  storageKey: string;
}

// The deletes are independent, so a few run at once: enough that a remote
// bucket's round trips do not dominate a batch, few enough not to flood it.
const BLOB_DELETE_CONCURRENCY = 10;

/**
 * Deletes attachment blobs and then their rows for one retention tick. It
 * runs only after the batch that selected the attachments has committed, so
 * object-storage latency never holds the retention lock or any row lock.
 *
 * Blob before row: a row whose blob delete failed is kept, so the orphan
 * sweep retries it on a later tick instead of leaving ciphertext in storage
 * with nothing pointing at it. When every delete in a group fails, storage is
 * treated as unavailable for the rest of the tick, so an outage costs one
 * round of timeouts rather than one per blob.
 */
export class AttachmentReleaser {
  deletedBlobs = 0;
  storageUnavailable = false;
  /** The first error of the group that marked storage unavailable. */
  storageError: unknown = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: AttachmentStorageGateway,
  ) {}

  /** Returns how many attachment rows were removed. */
  async release(attachments: readonly StoredAttachment[]): Promise<number> {
    const gone = await this.deleteBlobs(attachments);
    if (gone.length === 0) {
      return 0;
    }

    // A single statement commits atomically on its own, and needs no lock:
    // deleting an already-deleted row is a no-op. The re-check keeps the row
    // if a new message started referencing the attachment after the batch
    // selected it. Only the uploader can do that, and its blob is already
    // gone, so that one message's attachment fails to download: a narrow race
    // the previous prune had as well.
    const { count } = await this.prisma.attachment.deleteMany({
      where: { id: { in: gone }, ...UNREFERENCED_ATTACHMENT },
    });
    return count;
  }

  private async deleteBlobs(attachments: readonly StoredAttachment[]): Promise<string[]> {
    const gone: string[] = [];
    for (
      let start = 0;
      start < attachments.length && !this.storageUnavailable;
      start += BLOB_DELETE_CONCURRENCY
    ) {
      const group = attachments.slice(start, start + BLOB_DELETE_CONCURRENCY);
      const results = await Promise.allSettled(
        group.map((attachment) => this.storage.deleteObject(attachment.storageKey)),
      );
      results.forEach((result, index) => {
        if (result.status === 'fulfilled') {
          gone.push(group[index].id);
        }
      });
      const failures = results.filter(
        (result): result is PromiseRejectedResult => result.status === 'rejected',
      );
      if (failures.length === group.length) {
        this.storageUnavailable = true;
        this.storageError = failures[0].reason;
      }
    }
    this.deletedBlobs += gone.length;
    return gone;
  }
}
