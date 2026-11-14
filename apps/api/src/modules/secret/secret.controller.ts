import {
  Body,
  Controller,
  Get,
  NotFoundException,
  Param,
  ParseUUIDPipe,
  Post,
  Req,
} from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';

import {
  clientAddress,
  clientNetwork,
  type ClientAddressRequest,
} from '../../common/client-address';
import { AppConfigService } from '../../common/config/app-config.service';
import { Public } from '../../common/guards/public.decorator';
import { CreateSecretDto } from './dto/create-secret.dto';
import { SecretService } from './secret.service';

interface CreateSecretResponse {
  id: string;
  expiresAt: string;
}

interface ReadSecretResponse {
  ciphertext: string;
}

// One-time secret links. Both routes are @Public on purpose: the recipient
// has no account — that is the feature. The server only ever sees opaque
// ciphertext; the decryption key lives in the link fragment.
@ApiTags('secret')
@Controller('s')
export class SecretController {
  constructor(
    private readonly secretService: SecretService,
    private readonly config: AppConfigService,
  ) {}

  // The per-minute limit is per address; the daily quota in SecretService is
  // per network (an IPv6 /64 counts once), from the same configured source.
  @Public()
  @Throttle({ default: { ttl: 60_000, limit: 20 } })
  @Post()
  async create(
    @Body() dto: CreateSecretDto,
    @Req() request: ClientAddressRequest,
  ): Promise<CreateSecretResponse> {
    const network = clientNetwork(clientAddress(request, this.config.clientIpSource));
    const created = await this.secretService.create(dto.ciphertext, dto.ttlSeconds, network);
    return { id: created.id, expiresAt: created.expiresAt.toISOString() };
  }

  @Public()
  @Get(':id')
  async read(@Param('id', ParseUUIDPipe) id: string): Promise<ReadSecretResponse> {
    const ciphertext = await this.secretService.burn(id);
    if (ciphertext === null) {
      throw new NotFoundException('This link has already been opened or has expired.');
    }
    return { ciphertext };
  }
}
