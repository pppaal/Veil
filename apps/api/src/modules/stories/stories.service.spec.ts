import { BadRequestException, NotFoundException, ValidationPipe } from '@nestjs/common';

import { RelationshipService } from '../safety/relationship.service';
import { SafetyService } from '../safety/safety.service';
import { CreateStoryDto } from './dto/create-story.dto';
import { StoriesService } from './stories.service';
import { RetentionFakePrismaService } from '../../../test/support/fake-prisma-retention';
import { FakeRealtimeGateway } from '../../../test/support/fake-services';

async function setup() {
  const prisma = new RetentionFakePrismaService();
  const realtime = new FakeRealtimeGateway();
  const relationships = new RelationshipService(
    prisma as never,
    new SafetyService(prisma as never),
  );
  const service = new StoriesService(prisma as never, realtime as never, relationships);
  const authorId = await prisma.addUser('author');
  const viewerId = await prisma.addUser('viewer');

  const post = () =>
    service.createStory({ userId: authorId }, { contentType: 'text', caption: 'hello' });
  const visibleTo = async (userId: string) =>
    (await service.listStories({ userId })).map((story) => story.userId);

  return { prisma, realtime, service, authorId, viewerId, post, visibleTo };
}

const validateBody = (body: Record<string, unknown>) =>
  new ValidationPipe({ whitelist: true, transform: true, forbidNonWhitelisted: true }).transform(
    body,
    { type: 'body', metatype: CreateStoryDto },
  );

const expectStoryNotFound = async (promise: Promise<unknown>) => {
  const error = await promise.catch((caught: NotFoundException) => caught);
  expect(error).toBeInstanceOf(NotFoundException);
  expect((error as NotFoundException).getResponse()).toMatchObject({ code: 'story_not_found' });
};

describe('StoriesService audience', () => {
  it('one-way follower cannot list or view', async () => {
    const { prisma, service, authorId, viewerId, post, visibleTo } = await setup();
    prisma.addContact(viewerId, authorId);
    const story = await post();

    expect(await visibleTo(viewerId)).toEqual([]);
    await expectStoryNotFound(service.viewStory({ userId: viewerId }, story.id));
    expect(prisma.storyViews).toHaveLength(0);
  });

  it('mutual contact can', async () => {
    const { prisma, service, authorId, viewerId, post, visibleTo } = await setup();
    prisma.addMutualContacts(viewerId, authorId);
    const story = await post();

    expect(await visibleTo(viewerId)).toEqual([authorId]);
    await expect(service.viewStory({ userId: viewerId }, story.id)).resolves.toMatchObject({
      viewed: true,
    });
  });

  it('blocked mutual cannot', async () => {
    for (const viewerBlocks of [true, false]) {
      const { prisma, service, authorId, viewerId, post, visibleTo } = await setup();
      prisma.addMutualContacts(viewerId, authorId);
      if (viewerBlocks) {
        prisma.addBlock(viewerId, authorId);
      } else {
        prisma.addBlock(authorId, viewerId);
      }
      const story = await post();

      expect(await visibleTo(viewerId)).toEqual([]);
      await expectStoryNotFound(service.viewStory({ userId: viewerId }, story.id));
    }
  });

  it('authors always see their own stories', async () => {
    const { authorId, post, visibleTo } = await setup();
    await post();

    expect(await visibleTo(authorId)).toEqual([authorId]);
  });

  it('story.new only to mutual contacts', async () => {
    const { prisma, realtime, authorId, viewerId, post } = await setup();
    const followerId = await prisma.addUser('follower');
    const followedId = await prisma.addUser('followed');
    const blockedId = await prisma.addUser('blocked');
    prisma.addMutualContacts(viewerId, authorId);
    prisma.addContact(followerId, authorId);
    prisma.addContact(authorId, followedId);
    prisma.addMutualContacts(blockedId, authorId);
    prisma.addBlock(blockedId, authorId);

    await post();

    expect(
      realtime.emitted.filter((event) => event.event === 'story.new').map((event) => event.userId),
    ).toEqual([viewerId]);
  });
});

describe('StoriesService.createStory input', () => {
  it('301-char caption 400', async () => {
    await expect(
      validateBody({ contentType: 'text', caption: 'a'.repeat(301) }),
    ).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      validateBody({ contentType: 'text', caption: 'a'.repeat(300) }),
    ).resolves.toBeDefined();
  });

  it('image contentType rejected', async () => {
    await expect(
      validateBody({ contentType: 'image', contentUrl: 'https://cdn.example/pixel.gif' }),
    ).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      validateBody({ contentType: 'text', contentUrl: 'https://cdn.example/pixel.gif' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('missing contentUrl defaults to text://inline', async () => {
    const { prisma, service, authorId } = await setup();
    const dto = (await validateBody({ contentType: 'text', caption: 'hi' })) as CreateStoryDto;

    const story = await service.createStory({ userId: authorId }, dto);

    expect(story.contentUrl).toBe('text://inline');
    expect(prisma.stories[0].contentUrl).toBe('text://inline');
  });
});
