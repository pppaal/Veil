import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import helmet from 'helmet';

import { AppModule } from './app.module';
import { AppConfigService } from './common/config/app-config.service';
import { corsOptions } from './common/config/cors-options';
import { ApiExceptionFilter } from './common/filters/api-exception.filter';
import { AppLoggerService } from './common/logger/app-logger.service';
import { ActorRefGenerator } from './common/logger/request-redactor';
import { mountWebAssets } from './web-assets';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    bufferLogs: true,
  });
  // Express's default JSON body limit is 100kb, but a message envelope can
  // legitimately carry up to ~128kb of ciphertext (inline voice / image
  // notes — see SendMessageDto.ciphertext MaxLength 131072). Without this
  // override those messages 413 at the body parser before DTO validation
  // ever runs. 512kb leaves headroom for the envelope JSON overhead while
  // staying bounded against payload-flood DoS (the messages route is also
  // throttled to 120/min).
  app.useBodyParser('json', { limit: '512kb' });
  const config = app.get(AppConfigService);
  config.assertProductionReady();
  app.use(
    helmet({
      contentSecurityPolicy: config.isProduction
        ? {
            directives: {
              defaultSrc: ["'none'"],
              frameAncestors: ["'none'"],
            },
          }
        : false,
      crossOriginEmbedderPolicy: config.isProduction,
      hsts: config.isProduction
        ? { maxAge: 63_072_000, includeSubDomains: true, preload: true }
        : false,
    }),
  );
  app.enableCors(corsOptions(config));
  // Only the X-Forwarded-For source needs Express to walk the proxy chain,
  // and then by exactly the configured number of hops; trusting it otherwise
  // would let any client pick its own req.ip.
  if (config.clientIpSource === 'x-forwarded-for') {
    app.set('trust proxy', config.trustedProxyHops);
  }
  app.enableShutdownHooks();

  mountWebAssets(app, config);

  app.setGlobalPrefix('v1');
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    }),
  );
  app.useGlobalFilters(
    new ApiExceptionFilter(app.get(AppLoggerService), app.get(ActorRefGenerator)),
  );

  if (config.swaggerEnabled) {
    const swaggerConfig = new DocumentBuilder()
      .setTitle('VEIL API')
      .setDescription('Privacy-first encrypted envelope relay API')
      .setVersion('1.0.0-private-beta')
      .addBearerAuth()
      .build();
    const swaggerDocument = SwaggerModule.createDocument(app, swaggerConfig);
    SwaggerModule.setup('docs', app, swaggerDocument);
  }

  await app.listen(config.port);
}

void bootstrap();
