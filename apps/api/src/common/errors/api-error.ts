import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  HttpStatus,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';

export type VeilErrorCode =
  | 'unauthorized'
  | 'validation_failed'
  | 'handle_taken'
  | 'handle_not_found'
  | 'active_device_not_found'
  | 'device_not_found'
  | 'challenge_invalid'
  | 'device_not_active'
  | 'invalid_device_signature'
  | 'device_forbidden'
  | 'conversation_membership_required'
  | 'envelope_context_mismatch'
  | 'direct_peer_mismatch'
  | 'message_not_found'
  | 'attachment_not_found'
  | 'attachment_forbidden'
  | 'attachment_upload_invalid'
  | 'transfer_session_not_found'
  | 'transfer_session_inactive'
  | 'transfer_token_invalid'
  | 'transfer_claim_required'
  | 'transfer_claim_invalid'
  | 'transfer_approval_required'
  | 'transfer_completion_invalid'
  | 'internal_error'
  | 'profile_not_found'
  | 'cannot_add_self'
  | 'contact_already_exists'
  | 'contact_not_found'
  | 'story_not_found'
  | 'story_forbidden'
  | 'story_already_viewed'
  | 'refresh_token_invalid'
  | 'token_revoked'
  | 'peer_unreachable';

export class ApiError extends HttpException {
  constructor(
    readonly code: VeilErrorCode,
    status: HttpStatus,
    message: string,
  ) {
    super(
      {
        code,
        message,
      },
      status,
    );
  }
}

export const badRequest = (code: VeilErrorCode, message: string): BadRequestException =>
  new BadRequestException({ code, message });

export const unauthorized = (code: VeilErrorCode, message: string): UnauthorizedException =>
  new UnauthorizedException({ code, message });

export const forbidden = (code: VeilErrorCode, message: string): ForbiddenException =>
  new ForbiddenException({ code, message });

export const notFound = (code: VeilErrorCode, message: string): NotFoundException =>
  new NotFoundException({ code, message });

export const conflict = (code: VeilErrorCode, message: string): ConflictException =>
  new ConflictException({ code, message });

export const serviceUnavailable = (code: VeilErrorCode, message: string): HttpException =>
  new ApiError(code, HttpStatus.SERVICE_UNAVAILABLE, message);
