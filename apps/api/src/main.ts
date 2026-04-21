import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import helmet from 'helmet';

import { AppModule } from './app.module';
import { AppConfigService } from './common/config/app-config.service';
import { ApiExceptionFilter } from './common/filters/api-exception.filter';
import { AppLoggerService } from './common/logger/app-logger.service';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    bufferLogs: true,
  });
  const config = app.get(AppConfigService);
  config.assertProductionReady();
  const corsOrigin = (
    origin: string | undefined,
    callback: (error: Error | null, allow?: boolean) => void,
  ): void => {
    if (config.isOriginAllowed(origin)) {
      callback(null, true);
      return;
    }

    callback(new Error('CORS origin rejected'));
  };

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
  app.enableCors({
    origin: corsOrigin,
    credentials: false,
  });
  if (config.trustProxy) {
    app.set('trust proxy', 1);
  }
  app.enableShutdownHooks();

  app.setGlobalPrefix('v1');
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    }),
  );
  app.useGlobalFilters(new ApiExceptionFilter(app.get(AppLoggerService)));

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
