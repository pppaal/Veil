/**
 * Shared selection rule for "which device represents this user right now":
 * prefer the user's declared active device when it is present in the trusted
 * list, otherwise fall back to the head of the list. Callers pass devices
 * already filtered to isActive && !revoked and ordered
 * [trustedAt desc, lastSeenAt desc], so the fallback is the most recently
 * trusted device.
 */
export const pickActiveDevice = <T extends { id: string }>(
  trustedDevices: readonly T[],
  activeDeviceId: string | null | undefined,
): T | undefined =>
  trustedDevices.find((device) => device.id === activeDeviceId) ?? trustedDevices[0];
