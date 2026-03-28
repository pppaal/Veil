import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { Observable, tap } from 'rxjs';

import { AppLoggerService } from '../logger/app-logger.service';

@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  constructor(private readonly logger: AppLoggerService) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<Request & { auth?: { userId: string } }>();
    const method = request?.method ?? 'UNKNOWN';
    const url = request?.url ?? 'UNKNOWN';
    const startedAt = Date.now();

    return next.handle().pipe(
      tap({
        next: () =>
          this.logger.info('request.completed', {
            method,
            url,
            actorUserId: request?.auth?.userId ?? null,
            durationMs: Date.now() - startedAt,
          }),
      }),
    );
  }
}
