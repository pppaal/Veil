import { Module } from '@nestjs/common';
import { APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { ConfigModule } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';

import { CoreModule } from './common/core.module';
import { envSchema } from './common/config/env.schema';
import { AppConfigService } from './common/config/app-config.service';
import { JwtAuthGuard } from './common/guards/jwt-auth.guard';
import { LoggingInterceptor } from './common/interceptors/logging.interceptor';
import { AttachmentsModule } from './modules/attachments/attachments.module';
import { AuthModule } from './modules/auth/auth.module';
import { ChannelsModule } from './modules/channels/channels.module';
import { ConversationsModule } from './modules/conversations/conversations.module';
import { DeviceTransferModule } from './modules/device-transfer/device-transfer.module';
import { DevicesModule } from './modules/devices/devices.module';
import { GroupsModule } from './modules/groups/groups.module';
import { HealthModule } from './modules/health/health.module';
import { MessagesModule } from './modules/messages/messages.module';
import { PushModule } from './modules/push/push.module';
import { RealtimeModule } from './modules/realtime/realtime.module';
import { ContactsModule } from './modules/contacts/contacts.module';
import { ProfileModule } from './modules/profile/profile.module';
import { StoriesModule } from './modules/stories/stories.module';
import { UsersModule } from './modules/users/users.module';
import { AccountModule } from './modules/account/account.module';
import { CallsModule } from './modules/calls/calls.module';
import { SafetyModule } from './modules/safety/safety.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      expandVariables: true,
      validate: (environment) => envSchema.parse(environment),
    }),
    JwtModule.register({ global: true }),
    CoreModule,
    ThrottlerModule.forRoot([
      {
        ttl: 60_000,
        limit: 60,
      },
    ]),
    HealthModule,
    AuthModule,
    UsersModule,
    DevicesModule,
    ConversationsModule,
    GroupsModule,
    ChannelsModule,
    MessagesModule,
    AttachmentsModule,
    PushModule,
    RealtimeModule,
    DeviceTransferModule,
    ProfileModule,
    ContactsModule,
    StoriesModule,
    CallsModule,
    AccountModule,
    SafetyModule,
  ],
  providers: [
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
    {
      provide: APP_GUARD,
      useClass: JwtAuthGuard,
    },
    {
      provide: APP_INTERCEPTOR,
      useClass: LoggingInterceptor,
    },
  ],
})
export class AppModule {}
