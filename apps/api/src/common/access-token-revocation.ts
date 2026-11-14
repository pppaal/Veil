import type { EphemeralStoreService } from './ephemeral-store.service';

export const jtiBlacklistKey = (jti: string): string => `auth:blacklist:${jti}`;
export const refreshFamilyKey = (familyId: string): string => `auth:refresh-family:${familyId}`;

/** The claims of an access token that revocation looks at. */
export interface RevocableAccessToken {
  jti?: unknown;
  // The refresh family (session) the token was issued under.
  sid?: unknown;
}

/**
 * Whether an access token was revoked before it expired: logout blacklisted
 * its id, or the session it was issued under is gone. Logout, refresh-token
 * reuse and account deletion revoke every refresh family of the device, so
 * every access token issued to the device dies with them, not just the one
 * that called logout. A token issued before tokens carried their family has
 * only the blacklist; it expires within the hour anyway.
 */
export const isAccessTokenRevoked = async (
  store: Pick<EphemeralStoreService, 'getJson'>,
  token: RevocableAccessToken,
): Promise<boolean> => {
  if (typeof token.jti === 'string' && (await store.getJson<unknown>(jtiBlacklistKey(token.jti)))) {
    return true;
  }
  return (
    typeof token.sid === 'string' && !(await store.getJson<unknown>(refreshFamilyKey(token.sid)))
  );
};
