import type { Prisma } from '@prisma/client';

type DeviceWriter = Pick<Prisma.TransactionClient, 'device'>;

/** Midnight UTC of the day that contains `at`. */
export const utcDayStart = (at: Date): Date =>
  new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth(), at.getUTCDate()));

// Device activity is kept to the UTC day: enough to tell a live device from a
// stale one, too coarse to rebuild when its owner was online. The writes are
// conditional, so a busy device costs one write a day instead of one per
// request, and a day's value is never rewritten.

export const recordDeviceSeen = async (
  prisma: DeviceWriter,
  deviceId: string,
  now = new Date(),
): Promise<void> => {
  const day = utcDayStart(now);
  await prisma.device.updateMany({
    where: { id: deviceId, lastSeenAt: { not: day } },
    data: { lastSeenAt: day },
  });
};

export const recordDeviceSynced = async (
  prisma: DeviceWriter,
  deviceId: string,
  now = new Date(),
): Promise<void> => {
  const day = utcDayStart(now);
  await prisma.device.updateMany({
    where: { id: deviceId, OR: [{ lastSyncAt: null }, { lastSyncAt: { not: day } }] },
    data: { lastSyncAt: day },
  });
};
