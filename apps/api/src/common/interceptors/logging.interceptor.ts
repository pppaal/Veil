import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Observable, tap } from 'rxjs';

import { httpStatusOf } from '../filters/exception-status';
import { AppLoggerService } from '../logger/app-logger.service';
import { ActorRefGenerator, routeTemplate, type RoutedRequest } from '../logger/request-redactor';
import { MetricsService } from '../../modules/metrics/metrics.service';

type LoggedRequest = RoutedRequest & {
  method?: string;
  headers: Record<string, string | string[] | undefined>;
  auth?: { userId: string };
  requestId?: string;
};

// Request logs are durable, so they carry only the route template, never the
// concrete path or query: a leaked log must not become a verified handle
// list. The actor appears only on 5xx lines, and then only as a daily-keyed
// pseudonym (see request-redactor.ts).
@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  constructor(
    private readonly logger: AppLoggerService,
    private readonly metrics: MetricsService,
    private readonly actorRefs: ActorRefGenerator,
  ) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<LoggedRequest>();
    const response = context.switchToHttp().getResponse<{
      setHeader(name: string, value: string): void;
      statusCode?: number;
    }>();
    const requestIdHeader = request.headers['x-request-id'];
    const incomingRequestId = Array.isArray(requestIdHeader) ? requestIdHeader[0] : requestIdHeader;
    request.requestId ??= incomingRequestId?.trim() ? incomingRequestId : randomUUID();
    response.setHeader('x-request-id', request.requestId);
    const method = request.method ?? 'UNKNOWN';
    const route = routeTemplate(request);
    const routeClass = this.metrics.classifyRoute(request);
    const startedAt = Date.now();
    const finish = (status: number): void => {
      const durationMs = Date.now() - startedAt;
      this.logger.info('request.completed', {
        method,
        route,
        status,
        durationMs,
        requestId: request.requestId,
        ...(status >= 500 && request.auth
          ? { actorRef: this.actorRefs.actorRef(request.auth.userId) }
          : {}),
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
        error: (error: unknown) => finish(httpStatusOf(error)),
      }),
    );
  }
}
