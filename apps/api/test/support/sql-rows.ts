// INSERT statements for tests that seed a ThrowawayPostgres database directly,
// with fixed ids so expectations can name the rows.

export const id = (n: number): string =>
  `00000000-0000-4000-8000-${n.toString(16).padStart(12, '0')}`;

// The format ConversationsService.createDirect writes.
export const directKey = (a: string, b: string): string => [a, b].sort().join('|');

export const users = (...entries: Array<[string, string, string?]>): string =>
  entries
    .map(
      ([userId, handle, status = 'active']) =>
        `INSERT INTO users (id, handle, status, updated_at) VALUES ('${userId}', '${handle}', '${status}', now());`,
    )
    .join('\n');

export const device = (deviceId: string, userId: string): string =>
  `INSERT INTO devices (id, user_id, platform, device_name, public_identity_key, signed_prekey_bundle, auth_public_key)
   VALUES ('${deviceId}', '${userId}', 'ios', 'phone', 'ik', 'spk', 'auth');`;

export const conversation = (
  conversationId: string,
  type: 'direct' | 'group',
  members: string[],
): string =>
  [
    `INSERT INTO conversations (id, type, direct_key) VALUES ('${conversationId}', '${type}', ${
      type === 'direct' ? `'${directKey(members[0], members[1])}'` : 'NULL'
    });`,
    ...members.map(
      (userId) =>
        `INSERT INTO conversation_members (id, conversation_id, user_id)
         VALUES (gen_random_uuid(), '${conversationId}', '${userId}');`,
    ),
  ].join('\n');
