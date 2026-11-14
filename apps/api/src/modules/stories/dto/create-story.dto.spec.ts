import { BadRequestException, ValidationPipe } from '@nestjs/common';
import { randomUUID } from 'node:crypto';

import { CreateStoryDto } from './create-story.dto';

const validateBody = (body: Record<string, unknown>) =>
  new ValidationPipe({ whitelist: true, transform: true, forbidNonWhitelisted: true }).transform(
    body,
    { type: 'body', metatype: CreateStoryDto },
  );

const validStory = (overrides: Record<string, unknown> = {}) => ({
  ciphertext: 'sealed-story',
  envelopeVersion: 'veil-envelope-v2',
  audienceUserIds: [randomUUID()],
  ...overrides,
});

describe('CreateStoryDto', () => {
  it('accepts a sealed envelope addressed to an explicit audience', async () => {
    await expect(validateBody(validStory())).resolves.toBeInstanceOf(CreateStoryDto);
  });

  it('bounds the ciphertext to 65536 characters', async () => {
    await expect(
      validateBody(validStory({ ciphertext: 'a'.repeat(65536) })),
    ).resolves.toBeDefined();
    for (const ciphertext of ['', 'a'.repeat(65537)]) {
      await expect(validateBody(validStory({ ciphertext }))).rejects.toBeInstanceOf(
        BadRequestException,
      );
    }
  });

  it('requires 1 to 500 unique audience user ids', async () => {
    const id = randomUUID();
    const tooMany = Array.from({ length: 501 }, () => randomUUID());
    for (const audienceUserIds of [[], [id, id], tooMany, ['not-a-uuid']]) {
      await expect(validateBody(validStory({ audienceUserIds }))).rejects.toBeInstanceOf(
        BadRequestException,
      );
    }
    await expect(
      validateBody(validStory({ audienceUserIds: tooMany.slice(0, 500) })),
    ).resolves.toBeDefined();
  });

  it('accepts only known envelope versions', async () => {
    await expect(validateBody(validStory({ envelopeVersion: 'rot13-v1' }))).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('rejects the plaintext fields stories used to carry', async () => {
    for (const plaintext of [
      { contentType: 'text' },
      { caption: 'hello' },
      { contentUrl: 'text://inline' },
    ]) {
      await expect(validateBody(validStory(plaintext))).rejects.toBeInstanceOf(BadRequestException);
    }
  });
});
