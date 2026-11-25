import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus } from '@nestjs/common';
import type { Request, Response } from 'express';

import { AppLoggerService } from '../logger/app-logger.service';
import { ActorRefGenerator, routeTemplate } from '../logger/request-redactor';
import { httpStatusOf, mapPrismaError } from './exception-status';

type FilteredRequest = Request & { requestId?: string; auth?: { userId: string } };

@Catch()
export class ApiExceptionFilter implements ExceptionFilter {
  // The generator must be the app-wide instance the LoggingInterceptor uses,
  // or the two would derive actorRefs from different daily keys.
  constructor(
    private readonly logger: AppLoggerService,
    private readonly actorRefs: ActorRefGenerator,
  ) {}

  catch(exception: unknown, host: ArgumentsHost): void {
    const context = host.switchToHttp();
    const response = context.getResponse<Response>();
    const request = context.getRequest<FilteredRequest>();

    const status = httpStatusOf(exception);
    const body = this.toErrorBody(exception, status);
    const route = routeTemplate(request);
    const logMeta = {
      method: request.method,
      route,
      requestId: request.requestId ?? null,
      statusCode: status,
      code: body.code,
    };

    if (status >= 500) {
      this.logger.error('request.failed', {
        ...logMeta,
        actorRef: request.auth ? this.actorRefs.actorRef(request.auth.userId) : null,
        error: this.describeError(exception),
      });
    } else {
      this.logger.warn('request.rejected', logMeta);
    }

    if (request.requestId) {
      response.setHeader('x-request-id', request.requestId);
    }

    response.status(status).json({
      statusCode: status,
      error: HttpStatus[status] ?? 'Error',
      ...body,
      requestId: request.requestId ?? null,
      timestamp: new Date().toISOString(),
      path: route,
    });
  }

  // Prisma messages can embed query arguments (handles, ids), so only the
  // error class and code are logged for every Prisma client error.
  private describeError(exception: unknown): unknown {
    if (!(exception instanceof Error)) {
      return undefined;
    }
    if (exception.name.startsWith('PrismaClient')) {
      return { name: exception.name, code: (exception as { code?: unknown }).code ?? null };
    }
    return exception;
  }

  private toErrorBody(exception: unknown, status: number): { code: string; message: string } {
    if (exception instanceof HttpException) {
      const payload = exception.getResponse();
      if (typeof payload === 'string') {
        return {
          code: this.fallbackCode(status),
          message: payload,
        };
      }

      if (payload && typeof payload === 'object') {
        const record = payload as {
          code?: string;
          message?: string | string[];
        };
        const message = Array.isArray(record.message)
          ? record.message.join('; ')
          : (record.message ?? 'Request rejected');

        return {
          code: record.code ?? this.fallbackCode(status),
          message,
        };
      }
    }

    const prismaError = mapPrismaError(exception);
    if (prismaError) {
      return { code: prismaError.code, message: prismaError.message };
    }

    return {
      code: 'internal_error',
      message: 'Internal server error',
    };
  }

  private fallbackCode(status: number): string {
    if (status >= 500) {
      return 'internal_error';
    }
    if (status === HttpStatus.UNAUTHORIZED) {
      return 'unauthorized';
    }
    if (status === HttpStatus.FORBIDDEN) {
      return 'forbidden';
    }
    if (status === HttpStatus.NOT_FOUND) {
      return 'not_found';
    }
    if (status === HttpStatus.CONFLICT) {
      return 'conflict';
    }
    return 'validation_failed';
  }
}
