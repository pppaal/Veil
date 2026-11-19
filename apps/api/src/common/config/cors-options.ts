import type { CorsOptions } from '@nestjs/common/interfaces/external/cors-options.interface';

import { apiError } from '../errors/api-error';
import type { AppConfigService } from './app-config.service';

// Response headers a cross-origin browser client may read beyond the
// CORS-safelisted ones. Clients learn the server clock from `Date` and stamp
// signed prekeys with it (PUT /keys/signed-prekey only accepts a window
// around server time); `Date` is not safelisted, so without this a web client
// on another origin would never see it.
export const CORS_EXPOSED_HEADERS: readonly string[] = ['Date'];

// A request from an origin the relay does not serve is refused before any
// handler runs, with a 403 the exception filter logs as a rejection. A plain
// Error here became a 500 and an error-level log, so any web page a user
// visited could make their browser raise the relay's 5xx rate.
export const corsOptions = (config: Pick<AppConfigService, 'isOriginAllowed'>): CorsOptions => ({
  origin: (origin, callback) => {
    if (config.isOriginAllowed(origin)) {
      callback(null, true);
      return;
    }
    callback(apiError('origin_not_allowed', 'Origin not allowed'));
  },
  credentials: false,
  exposedHeaders: [...CORS_EXPOSED_HEADERS],
});
