import { HttpException, HttpStatus } from '@nestjs/common';
import { Prisma } from '@prisma/client';

export interface MappedPrismaError {
  status: HttpStatus;
  code: string;
  message: string;
}

// Known Prisma request errors that describe a bad request rather than a
// server fault. Unmapped, a malformed id (P2023) or a dangling foreign key
// (P2003) surfaced as a 500 plus an error log. Messages are fixed strings:
// Prisma's own messages can echo column names and values.
const PRISMA_ERROR_RESPONSES: Readonly<Record<string, MappedPrismaError>> = {
  P2000: {
    status: HttpStatus.BAD_REQUEST,
    code: 'validation_failed',
    message: 'A value is too long for its field',
  },
  P2003: {
    status: HttpStatus.BAD_REQUEST,
    code: 'validation_failed',
    message: 'A referenced record does not exist',
  },
  P2023: {
    status: HttpStatus.BAD_REQUEST,
    code: 'validation_failed',
    message: 'An identifier is malformed',
  },
  P2002: {
    status: HttpStatus.CONFLICT,
    code: 'resource_conflict',
    message: 'The resource already exists',
  },
  P2025: {
    status: HttpStatus.NOT_FOUND,
    code: 'resource_not_found',
    message: 'The resource was not found',
  },
};

export function mapPrismaError(exception: unknown): MappedPrismaError | undefined {
  if (exception instanceof Prisma.PrismaClientKnownRequestError) {
    return PRISMA_ERROR_RESPONSES[exception.code];
  }
  return undefined;
}

// Single source of the status a thrown value produces, shared by the
// exception filter (the response) and the logging interceptor (logs and
// metrics), so both always agree.
export function httpStatusOf(exception: unknown): number {
  if (exception instanceof HttpException) {
    return exception.getStatus();
  }
  return mapPrismaError(exception)?.status ?? HttpStatus.INTERNAL_SERVER_ERROR;
}
