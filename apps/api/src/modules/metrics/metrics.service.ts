import { Injectable, OnModuleInit } from '@nestjs/common';
import { Counter, Gauge, Histogram, Registry, collectDefaultMetrics } from 'prom-client';

// Centralized Prometheus registry. Counters that touch user identity
// (handle, deviceId, conversationId) are intentionally NOT included —
// even bucketed labels can leak metadata over time. Only operational
// signals: throughput, latency, queue depth, error class.
@Injectable()
export class MetricsService implements OnModuleInit {
  readonly registry = new Registry();

  readonly httpRequestsTotal = new Counter({
    name: 'veil_http_requests_total',
    help: 'HTTP requests handled, labelled by method/route-class/status-class',
    labelNames: ['method', 'route_class', 'status_class'],
    registers: [this.registry],
  });

  readonly httpRequestDurationSeconds = new Histogram({
    name: 'veil_http_request_duration_seconds',
    help: 'HTTP request duration in seconds',
    labelNames: ['method', 'route_class'],
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5],
    registers: [this.registry],
  });

  readonly wsConnectionsActive = new Gauge({
    name: 'veil_ws_connections_active',
    help: 'Active websocket connections',
    registers: [this.registry],
  });

  readonly messagesSentTotal = new Counter({
    name: 'veil_messages_sent_total',
    help: 'Messages accepted by /messages, labelled by message type',
    labelNames: ['message_type'],
    registers: [this.registry],
  });

  readonly authEventsTotal = new Counter({
    name: 'veil_auth_events_total',
    help: 'Authentication lifecycle events',
    labelNames: ['kind'],
    registers: [this.registry],
  });

  readonly transferEventsTotal = new Counter({
    name: 'veil_transfer_events_total',
    help: 'Device-transfer lifecycle events',
    labelNames: ['stage'],
    registers: [this.registry],
  });

  readonly attachmentsBytesTotal = new Counter({
    name: 'veil_attachments_bytes_total',
    help: 'Cumulative bytes accepted for attachment uploads',
    registers: [this.registry],
  });

  onModuleInit(): void {
    collectDefaultMetrics({ register: this.registry, prefix: 'veil_' });
  }

  // Coarse route classification keeps the cardinality bounded — a label
  // per UUID-shaped path segment would explode the index. Mirrors the
  // logging-interceptor redaction rules.
  classifyRoute(url: string): string {
    const path = url.split('?', 1)[0];
    return path
      .split('/')
      .map((seg, i) => {
        if (i === 0) return seg;
        if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(seg))
          return ':id';
        if (i === 2 && path.split('/')[1] === 'users') return ':handle';
        return seg;
      })
      .join('/');
  }

  classifyStatus(status: number): string {
    if (status >= 500) return '5xx';
    if (status >= 400) return '4xx';
    if (status >= 300) return '3xx';
    if (status >= 200) return '2xx';
    return 'other';
  }
}
