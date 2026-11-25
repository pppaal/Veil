import type { Prisma } from '@prisma/client';

type RevocationWriter = Pick<
  Prisma.TransactionClient,
  'device' | 'oneTimePrekey' | 'deviceConversationState'
>;

// What a revoked device's label becomes. The original label is text the user
// wrote; the device list only needs to show that a device was removed.
export const REVOKED_DEVICE_NAME = 'Removed device';

/**
 * Revokes a device inside the caller's transaction. Besides cutting its
 * access, it drops what a revoked device no longer needs: its label, push
 * token, unclaimed one-time prekeys and per-conversation sync cursors. The row
 * itself stays while messages, attachments or call records still point at it;
 * RetentionService deletes it once nothing does.
 */
export const revokeDevice = async (
  tx: RevocationWriter,
  deviceId: string,
  revokedAt: Date,
): Promise<void> => {
  await tx.device.update({
    where: { id: deviceId },
    data: { isActive: false, revokedAt, pushToken: null, deviceName: REVOKED_DEVICE_NAME },
  });
  await tx.oneTimePrekey.deleteMany({ where: { deviceId } });
  await tx.deviceConversationState.deleteMany({ where: { deviceId } });
};
