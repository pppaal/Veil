import { Inject, Injectable } from '@nestjs/common';
import { ThrottlerException } from '@nestjs/throttler';
import { Prisma } from '@prisma/client';
import type {
  GroupMemberKeysResponse,
  KeyClaimMode,
  KeysResponse,
  OneTimePrekeyUpload,
  RotateSignedPrekeyResponse,
} from '@veil/contracts';
import { isUUID } from 'class-validator';

import { isActionAllowed } from '../../common/conversation-access/conversation-policy';
import { apiError, badRequest, forbidden, notFound } from '../../common/errors/api-error';
import { pickActiveDevice } from '../../common/pick-active-device';
import { PrismaService } from '../../common/prisma.service';
import { SafetyService } from '../safety/safety.service';
import { DIRECTORY_BUDGETS, DirectoryBudget } from './directory-budget';
import { PrekeysService, type DirectoryRequester } from './prekeys.service';
import { decodeSignedPrekeyBundleV2, verifySignedPrekeyBundleV2 } from './signed-prekey-bundle';

export const KEYS_CLOCK = Symbol('KEYS_CLOCK');
export type Clock = () => number;

// A signed prekey must be fresh when it is published: a replayed old bundle
// or a pre-generated future one is rejected. Clients stamp spkTs from their
// clock corrected by the HTTP Date header and may re-send an unpublished
// bundle while it is under 30 minutes old, so the window reaches an hour back
// and allows 10 minutes ahead for what correction leaves of the skew.
const SIGNED_PREKEY_MAX_AGE_MS = 60 * 60 * 1000;
const SIGNED_PREKEY_MAX_LEAD_MS = 10 * 60 * 1000;

// The devices the directory serves for a user: trusted and not revoked, most
// recently trusted first (pickActiveDevice relies on this order).
const DIRECTORY_DEVICES = {
  where: { isActive: true, revokedAt: null },
  orderBy: [{ trustedAt: 'desc' }, { lastSeenAt: 'desc' }],
} satisfies Prisma.DeviceFindManyArgs;

interface DirectoryDevice {
  id: string;
  publicIdentityKey: string;
  signedPrekeyBundle: string;
}

const directoryEntry = (
  user: { id: string; handle: string },
  devices: readonly DirectoryDevice[],
  activeDeviceId: string,
  claimed: ReadonlyMap<string, OneTimePrekeyUpload>,
): KeysResponse => ({
  user: { id: user.id, handle: user.handle, activeDeviceId },
  devices: devices.map((device) => ({
    deviceId: device.id,
    identityPublicKey: device.publicIdentityKey,
    signedPrekeyBundle: device.signedPrekeyBundle,
    isActive: device.id === activeDeviceId,
    oneTimePrekey: claimed.get(device.id) ?? null,
  })),
});

const groupNotFound = () => apiError('group_not_found', 'Group not found');

function claimTargets(mode: KeyClaimMode, deviceIds: string[], activeDeviceId: string): string[] {
  switch (mode) {
    case 'all':
      return deviceIds;
    case 'active':
      return [activeDeviceId];
    case 'none':
      return [];
  }
}

@Injectable()
export class KeysService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly prekeys: PrekeysService,
    private readonly budget: DirectoryBudget,
    @Inject(KEYS_CLOCK) private readonly clock: Clock,
    private readonly safety: SafetyService,
  ) {}

  /**
   * Key material for every trusted device of the handle, with one-time
   * prekeys claimed for the devices the mode selects.
   */
  async getKeys(
    requester: DirectoryRequester,
    handle: string,
    mode: KeyClaimMode,
  ): Promise<KeysResponse> {
    const user = await this.prisma.user.findUnique({
      where: { handle: handle.toLowerCase() },
      select: { id: true, handle: true, activeDeviceId: true },
    });
    // A block in either direction answers like an unknown handle (as
    // createDirect does) and claims no prekey.
    if (!user || (await this.safety.isBlockedEitherWay(requester.userId, user.id))) {
      throw notFound('handle_not_found', 'User not found');
    }

    const devices = await this.prisma.device.findMany({
      where: { userId: user.id, ...DIRECTORY_DEVICES.where },
      orderBy: DIRECTORY_DEVICES.orderBy,
      select: { id: true, publicIdentityKey: true, signedPrekeyBundle: true },
    });
    const activeDevice = pickActiveDevice(devices, user.activeDeviceId);
    if (!activeDevice) {
      throw notFound('active_device_not_found', 'Active device bundle not found');
    }

    const claimed = await this.prekeys.claimWithinBudget(
      requester,
      user.id,
      claimTargets(
        mode,
        devices.map((device) => device.id),
        activeDevice.id,
      ),
    );

    return directoryEntry(user, devices, activeDevice.id, claimed);
  }

  /**
   * The directory entry of every other current member of a group the caller
   * belongs to, so a Sender Keys distribution round costs one request instead
   * of one GET /keys/:handle per member. Devices are chosen as in getKeys;
   * nothing is claimed and no directory budget is spent, so oneTimePrekey is
   * always null. Members and epoch come from one snapshot: a membership change
   * bumps the epoch in the same transaction, so the list is exactly that
   * epoch's membership. Anything but a current member of a group gets
   * group_not_found, which does not tell whether the id exists.
   */
  async getGroupMemberKeys(
    requester: DirectoryRequester,
    conversationId: string,
  ): Promise<GroupMemberKeysResponse> {
    if (!isUUID(conversationId)) {
      throw groupNotFound();
    }
    return this.prisma.$transaction(
      async (tx) => {
        const membership = await tx.conversationMember.findUnique({
          where: { conversationId_userId: { conversationId, userId: requester.userId } },
          select: { role: true, conversation: { select: { type: true, currentEpoch: true } } },
        });
        if (
          membership?.conversation.type !== 'group' ||
          !isActionAllowed('group', membership.role, 'readMembers')
        ) {
          throw groupNotFound();
        }

        const others = await tx.conversationMember.findMany({
          where: { conversationId, userId: { not: requester.userId } },
          orderBy: { joinedAt: 'asc' },
          select: { user: { select: { id: true, handle: true, activeDeviceId: true } } },
        });
        const devices = await tx.device.findMany({
          where: { userId: { in: others.map(({ user }) => user.id) }, ...DIRECTORY_DEVICES.where },
          orderBy: DIRECTORY_DEVICES.orderBy,
          select: { id: true, userId: true, publicIdentityKey: true, signedPrekeyBundle: true },
        });

        const members = others.flatMap(({ user }) => {
          const userDevices = devices.filter((device) => device.userId === user.id);
          const activeDevice = pickActiveDevice(userDevices, user.activeDeviceId);
          return activeDevice
            ? [directoryEntry(user, userDevices, activeDevice.id, new Map())]
            : [];
        });
        return { conversationId, epoch: membership.conversation.currentEpoch, members };
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead },
    );
  }

  /**
   * Publishes a new signed prekey for the calling device. The bundle must be
   * signed by the device's identity key; once a device publishes v2, its X25519
   * identity key is pinned and spkId must strictly increase. A legacy v1
   * bundle may be upgraded to v2 exactly once.
   */
  async rotateSignedPrekey(
    requester: DirectoryRequester,
    signedPrekeyBundle: string,
  ): Promise<RotateSignedPrekeyResponse> {
    if (
      !(await this.budget.tryConsume(DIRECTORY_BUDGETS.signedPrekeyRotations, requester.deviceId))
    ) {
      throw new ThrottlerException();
    }

    const device = await this.prisma.device.findUnique({
      where: { id: requester.deviceId },
      select: {
        userId: true,
        isActive: true,
        revokedAt: true,
        publicIdentityKey: true,
        signedPrekeyBundle: true,
      },
    });
    if (!device || device.userId !== requester.userId) {
      throw notFound('device_not_found', 'Device not found');
    }
    if (!device.isActive || device.revokedAt) {
      throw forbidden('device_not_active', 'Device is not active');
    }

    const next = decodeSignedPrekeyBundleV2(signedPrekeyBundle);
    if (!next) {
      throw badRequest('validation_failed', 'Signed prekey bundle must be a canonical v2 bundle');
    }
    if (!verifySignedPrekeyBundleV2(next, device.publicIdentityKey)) {
      throw badRequest(
        'invalid_device_signature',
        'Signed prekey bundle is not signed by the device identity key',
      );
    }
    const now = this.clock();
    if (
      next.spkTs < now - SIGNED_PREKEY_MAX_AGE_MS ||
      next.spkTs > now + SIGNED_PREKEY_MAX_LEAD_MS
    ) {
      throw apiError(
        'signed_prekey_timestamp_out_of_window',
        'Signed prekey timestamp must be within the last hour and at most 10 minutes ahead of server time',
      );
    }

    const current = decodeSignedPrekeyBundleV2(device.signedPrekeyBundle);
    if (current && !next.ikx.equals(current.ikx)) {
      throw badRequest('validation_failed', 'The X25519 identity key cannot change');
    }
    if (current && next.spkId <= current.spkId) {
      throw badRequest('validation_failed', 'spkId must increase with every rotation');
    }

    // Compare-and-swap on the bundle we validated against, so two concurrent
    // rotations cannot both pass the checks and leave the older one stored.
    const { count } = await this.prisma.device.updateMany({
      where: { id: requester.deviceId, signedPrekeyBundle: device.signedPrekeyBundle },
      data: { signedPrekeyBundle },
    });
    if (count !== 1) {
      throw badRequest('validation_failed', 'Signed prekey changed concurrently; retry');
    }

    return { deviceId: requester.deviceId, spkId: next.spkId };
  }
}
