import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Observable, tap } from 'rxjs';

import { AppLoggerService } from '../logger/app-logger.service';
import { MetricsService } from '../../modules/metrics/metrics.service';

// Logs are durable, so it is dangerous to ship per-request URLs that include
// social handles — if logs leak we hand attackers a verified handle list.
// Redact the handle segment of /users/:handle and any UUID-looking segment.
function redactUrl(url: string): string {
  const [path, query] = url.split('?', 2);
  const segments = path.split('/');
  const redacted = segments.map((seg, i) => {
    if (segments[1] === 'users' && i === 2 && seg.length > 0) return '*';
    if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(seg)) return '*';
    return seg;
  });
  return query ? `${redacted.join('/')}?*` : redacted.join('/');
}

@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  constructor(
    private readonly logger: AppLoggerService,
    private readonly metrics: MetricsService,
  ) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<
      Request & { auth?: { userId: string }; requestId?: string }
    >();
    const response = context.switchToHttp().getResponse<{
      setHeader(name: string, value: string): void;
      statusCode?: number;
    }>();
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
    const rawUrl = request?.url ?? 'UNKNOWN';
    const url = redactUrl(rawUrl);
    const routeClass = this.metrics.classifyRoute(rawUrl);
    const startedAt = Date.now();
    const finish = (status: number): void => {
      const durationMs = Date.now() - startedAt;
      this.logger.info('request.completed', {
        method,
        url,
        requestId: request.requestId,
        actorUserId: request?.auth?.userId ?? null,
        durationMs,
      });
      this.metrics.httpRequestsTotal
        .labels({
          method,
          route_class: routeClass,
          status_class: this.metrics.classifyStatus(status),
        })
        .inc();
      this.metrics.httpRequestDurationSeconds
        .labels({ method, route_class: routeClass })
        .observe(durationMs / 1000);
    };

    return next.handle().pipe(
      tap({
        next: () => finish(response.statusCode ?? 200),
        error: (err) => {
          const status = typeof err?.status === 'number' ? err.status : 500;
          finish(status);
        },
      }),
    );
  }
}
