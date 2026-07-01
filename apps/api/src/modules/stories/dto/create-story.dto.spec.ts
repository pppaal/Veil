import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';

import { CreateStoryDto } from './create-story.dto';

const make = (contentUrl: string, contentType = 'image') =>
  plainToInstance(CreateStoryDto, { contentType, contentUrl });
const urlErrors = async (contentUrl: string, contentType = 'image') =>
  (await validate(make(contentUrl, contentType))).filter((e) => e.property === 'contentUrl');

describe('CreateStoryDto.contentUrl', () => {
  it('accepts an https media URL and the text:// sentinel', async () => {
    expect(await urlErrors('https://cdn.veil.app/stories/abc.jpg')).toHaveLength(0);
    expect(await urlErrors('text://inline', 'text')).toHaveLength(0);
  });

  it('rejects dangerous schemes at the persistence boundary', async () => {
    expect((await urlErrors('javascript:alert(1)')).length).toBeGreaterThan(0);
    expect((await urlErrors('data:text/html;base64,AAAA')).length).toBeGreaterThan(0);
    expect((await urlErrors('file:///etc/passwd')).length).toBeGreaterThan(0);
  });

  it('rejects an over-length value (> 2048 chars)', async () => {
    const huge = 'https://cdn.veil.app/' + 'a'.repeat(2100);
    expect((await urlErrors(huge)).length).toBeGreaterThan(0);
  });
});
