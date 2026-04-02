import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Observable, tap } from 'rxjs';

import { AppLoggerService } from '../logger/app-logger.service';

@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  constructor(private readonly logger: AppLoggerService) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<
      Request & { auth?: { userId: string }; requestId?: string }
    >();
    const response = context.switchToHttp().getResponse<{ setHeader(name: string, value: string): void }>();
    const headers = request.headers as unknown as Record<string, string | string[] | undefined>;
    const requestIdHeader = headers['x-request-id'];
    const incomingRequestId =
      typeof requestIdHeader === 'string'
        ? requestIdHeader
        : Array.isArray(requestIdHeader)
          ? requestIdHeader[0]
          : undefined;
    request.requestId ??=
      (incomingRequestId && incomingRequestId.trim().length > 0 ? incomingRequestId : undefined) ||
      randomUUID();
    response.setHeader('x-request-id', request.requestId);
    const method = request?.method ?? 'UNKNOWN';
    const url = request?.url ?? 'UNKNOWN';
    const startedAt = Date.now();

    return next.handle().pipe(
      tap({
        next: () =>
          this.logger.info('request.completed', {
            method,
            url,
            requestId: request.requestId,
            actorUserId: request?.auth?.userId ?? null,
            durationMs: Date.now() - startedAt,
          }),
      }),
    );
  }
}
