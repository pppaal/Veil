import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import type { Request, Response } from 'express';

import { AppLoggerService } from '../logger/app-logger.service';

@Catch()
export class ApiExceptionFilter implements ExceptionFilter {
  constructor(private readonly logger: AppLoggerService) {}

  catch(exception: unknown, host: ArgumentsHost): void {
    const context = host.switchToHttp();
    const response = context.getResponse<Response>();
    const request = context.getRequest<Request & { requestId?: string; auth?: { userId: string } }>();

    const status =
      exception instanceof HttpException
        ? exception.getStatus()
        : HttpStatus.INTERNAL_SERVER_ERROR;

    const body = this.toErrorBody(exception, status);

    if (status >= 500) {
      this.logger.error('request.failed', {
        method: request.method,
        url: request.url,
        requestId: request.requestId ?? null,
        actorUserId: request.auth?.userId ?? null,
        statusCode: status,
        code: body.code,
        error: exception instanceof Error ? exception : undefined,
      });
    } else {
      this.logger.warn('request.rejected', {
        method: request.method,
        url: request.url,
        requestId: request.requestId ?? null,
        actorUserId: request.auth?.userId ?? null,
        statusCode: status,
        code: body.code,
      });
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
      path: request.url,
    });
  }

  private toErrorBody(
    exception: unknown,
    status: number,
  ): { code: string; message: string } {
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
          : record.message ?? 'Request rejected';

        return {
          code: record.code ?? this.fallbackCode(status),
          message,
        };
      }
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
