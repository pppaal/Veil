import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';

import { ERROR_CATALOG, apiError, type VeilErrorCode } from './api-error';

const codes = Object.keys(ERROR_CATALOG) as VeilErrorCode[];

describe('ERROR_CATALOG', () => {
  it('each code has exactly one status and catalog contains resource_conflict and resource_not_found', () => {
    expect(new Set(codes).size).toBe(codes.length);
    for (const code of codes) {
      const status = ERROR_CATALOG[code];
      expect(Number.isInteger(status)).toBe(true);
      expect(status >= 400 && status <= 599).toBe(true);
    }
    expect(ERROR_CATALOG.resource_conflict).toBe(409);
    expect(ERROR_CATALOG.resource_not_found).toBe(404);
  });

  it('is frozen', () => {
    expect(Object.isFrozen(ERROR_CATALOG)).toBe(true);
  });

  it.each([
    ['conversation_role_required', 403],
    ['owner_immutable', 409],
    ['group_not_found', 404],
    ['channel_not_found', 404],
    ['edit_window_expired', 403],
    ['reply_target_invalid', 400],
    ['envelope_version_mismatch', 400],
    ['envelope_version_forbidden', 400],
    ['group_member_limit', 409],
    ['sender_keys_irreversible', 400],
    ['call_not_allowed', 403],
    ['group_epoch_stale', 409],
    ['attachment_id_conflict', 409],
    ['signed_prekey_timestamp_out_of_window', 400],
  ] as const)('maps %s to %i', (code, status) => {
    expect(ERROR_CATALOG[code]).toBe(status);
  });
});

describe('apiError', () => {
  it.each(codes)('raises %s with its catalog status', (code) => {
    const error = apiError(code);

    expect(error).toBeInstanceOf(HttpException);
    expect(error.getStatus()).toBe(ERROR_CATALOG[code]);
    expect(error.getResponse()).toMatchObject({ code });
  });

  it('uses the Nest exception class for the status so instanceof checks keep working', () => {
    expect(apiError('validation_failed')).toBeInstanceOf(BadRequestException);
    expect(apiError('unauthorized')).toBeInstanceOf(UnauthorizedException);
    expect(apiError('conversation_membership_required')).toBeInstanceOf(ForbiddenException);
    expect(apiError('group_not_found')).toBeInstanceOf(NotFoundException);
    expect(apiError('owner_immutable')).toBeInstanceOf(ConflictException);
  });

  it('derives a readable default message from the code', () => {
    expect(apiError('conversation_membership_required').getResponse()).toEqual({
      code: 'conversation_membership_required',
      message: 'Conversation membership required',
    });
    expect(apiError('call_not_found', 'Call record not found').getResponse()).toEqual({
      code: 'call_not_found',
      message: 'Call record not found',
    });
  });
});
