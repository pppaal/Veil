import { Param, ParseUUIDPipe } from '@nestjs/common';

import { apiError } from '../errors/api-error';

/**
 * Route parameter that must be a UUID. A malformed id is rejected with
 * 400 validation_failed before it reaches Prisma, where the uuid column cast
 * would otherwise surface it as a 500.
 */
export const UuidParam = (name: string): ParameterDecorator =>
  Param(
    name,
    new ParseUUIDPipe({
      exceptionFactory: () => apiError('validation_failed', `${name} must be a UUID`),
    }),
  );
