import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';

import { CreateStoryDto } from './create-story.dto';

const errorsFor = async (body: Record<string, unknown>, property: string) =>
  (await validate(plainToInstance(CreateStoryDto, { contentType: 'text', ...body }))).filter(
    (error) => error.property === property,
  );

describe('CreateStoryDto.contentUrl', () => {
  it('accepts the text:// sentinel or no value at all', async () => {
    expect(await errorsFor({ contentUrl: 'text://inline' }, 'contentUrl')).toHaveLength(0);
    expect(await errorsFor({}, 'contentUrl')).toHaveLength(0);
  });

  it('rejects free URLs, which would let a story carry a tracking pixel', async () => {
    for (const contentUrl of [
      'https://cdn.veil.app/stories/abc.jpg',
      'http://tracker.example/pixel.gif',
      'text://elsewhere',
    ]) {
      expect((await errorsFor({ contentUrl }, 'contentUrl')).length).toBeGreaterThan(0);
    }
  });

  it('rejects dangerous schemes at the persistence boundary', async () => {
    for (const contentUrl of [
      'javascript:alert(1)',
      'data:text/html;base64,AAAA',
      'file:///etc/passwd',
    ]) {
      expect((await errorsFor({ contentUrl }, 'contentUrl')).length).toBeGreaterThan(0);
    }
  });
});

describe('CreateStoryDto.contentType and caption', () => {
  it('accepts only text stories', async () => {
    expect(await errorsFor({}, 'contentType')).toHaveLength(0);
    for (const contentType of ['image', 'video', 'audio']) {
      expect((await errorsFor({ contentType }, 'contentType')).length).toBeGreaterThan(0);
    }
  });

  it('bounds the caption to the 300-character column', async () => {
    expect(await errorsFor({ caption: 'a'.repeat(300) }, 'caption')).toHaveLength(0);
    expect((await errorsFor({ caption: 'a'.repeat(301) }, 'caption')).length).toBeGreaterThan(0);
  });
});
