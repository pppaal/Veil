import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  HttpStatus,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { ERROR_CATALOG, type VeilErrorCode } from '@veil/contracts';

export { ERROR_CATALOG };
export type { VeilErrorCode };

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

type ErrorBody = { code: VeilErrorCode; message: string };

// Statuses Nest already models with a dedicated exception class. Raising
// those classes keeps `instanceof ForbiddenException`-style checks working.
const NEST_EXCEPTION_BY_STATUS: Readonly<
  Partial<Record<number, new (body: ErrorBody) => HttpException>>
> = {
  [HttpStatus.BAD_REQUEST]: BadRequestException,
  [HttpStatus.UNAUTHORIZED]: UnauthorizedException,
  [HttpStatus.FORBIDDEN]: ForbiddenException,
  [HttpStatus.NOT_FOUND]: NotFoundException,
  [HttpStatus.CONFLICT]: ConflictException,
};

const defaultMessage = (code: VeilErrorCode): string => {
  const words = code.replace(/_/g, ' ');
  return words.charAt(0).toUpperCase() + words.slice(1);
};

/**
 * Builds the exception for an error code. The HTTP status always comes from
 * ERROR_CATALOG, so callers cannot pair a code with the wrong status.
 */
export const apiError = (code: VeilErrorCode, message = defaultMessage(code)): HttpException => {
  const status = ERROR_CATALOG[code];
  const NestException = NEST_EXCEPTION_BY_STATUS[status];
  return NestException ? new NestException({ code, message }) : new ApiError(code, status, message);
};

/** @deprecated Use apiError(code, message); the status comes from ERROR_CATALOG. */
export const badRequest = (code: VeilErrorCode, message: string): BadRequestException =>
  new BadRequestException({ code, message });

/** @deprecated Use apiError(code, message); the status comes from ERROR_CATALOG. */
export const unauthorized = (code: VeilErrorCode, message: string): UnauthorizedException =>
  new UnauthorizedException({ code, message });

/** @deprecated Use apiError(code, message); the status comes from ERROR_CATALOG. */
export const forbidden = (code: VeilErrorCode, message: string): ForbiddenException =>
  new ForbiddenException({ code, message });

/** @deprecated Use apiError(code, message); the status comes from ERROR_CATALOG. */
export const notFound = (code: VeilErrorCode, message: string): NotFoundException =>
  new NotFoundException({ code, message });

/** @deprecated Use apiError(code, message); the status comes from ERROR_CATALOG. */
export const conflict = (code: VeilErrorCode, message: string): ConflictException =>
  new ConflictException({ code, message });

/** @deprecated Use apiError(code, message); the status comes from ERROR_CATALOG. */
export const serviceUnavailable = (code: VeilErrorCode, message: string): HttpException =>
  new ApiError(code, HttpStatus.SERVICE_UNAVAILABLE, message);
