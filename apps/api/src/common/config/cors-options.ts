import type { CorsOptions } from '@nestjs/common/interfaces/external/cors-options.interface';

import type { AppConfigService } from './app-config.service';

// Response headers a cross-origin browser client may read beyond the
// CORS-safelisted ones. Clients learn the server clock from `Date` and stamp
// signed prekeys with it (PUT /keys/signed-prekey only accepts a window
// around server time); `Date` is not safelisted, so without this a web client
// on another origin would never see it.
export const CORS_EXPOSED_HEADERS: readonly string[] = ['Date'];

export const corsOptions = (config: Pick<AppConfigService, 'isOriginAllowed'>): CorsOptions => ({
  origin: (origin, callback) => {
    if (config.isOriginAllowed(origin)) {
      callback(null, true);
      return;
    }
    callback(new Error('CORS origin rejected'));
  },
  credentials: false,
  exposedHeaders: [...CORS_EXPOSED_HEADERS],
});
