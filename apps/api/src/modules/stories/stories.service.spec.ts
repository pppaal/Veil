import { NotFoundException } from '@nestjs/common';

import { RelationshipService } from '../safety/relationship.service';
import { StoriesService } from './stories.service';
import { RetentionFakePrismaService } from '../../../test/support/fake-prisma-retention';
import { FakeRealtimeGateway } from '../../../test/support/fake-services';

async function setup(options: { isProduction?: boolean } = {}) {
  const prisma = new RetentionFakePrismaService();
  const realtime = new FakeRealtimeGateway();
  const service = new StoriesService(
    prisma as never,
    realtime as never,
    new RelationshipService(prisma as never),
    { isProduction: options.isProduction ?? false } as never,
  );
  const authorId = await prisma.addUser('author');
  const viewerId = await prisma.addUser('viewer');

  const post = (audienceUserIds: string[], envelopeVersion = 'veil-envelope-v2') =>
    service.createStory(
      { userId: authorId },
      { ciphertext: 'sealed-story', envelopeVersion, audienceUserIds },
    );
  const visibleTo = async (userId: string) =>
    (await service.listStories({ userId })).map((story) => story.userId);

  return { prisma, realtime, service, authorId, viewerId, post, visibleTo };
}

const expectStoryNotFound = async (promise: Promise<unknown>) => {
  const error = await promise.catch((caught: NotFoundException) => caught);
  expect(error).toBeInstanceOf(NotFoundException);
  expect((error as NotFoundException).getResponse()).toMatchObject({ code: 'story_not_found' });
};

describe('StoriesService audience', () => {
  it('story audience with non-mutual user 400', async () => {
    const { prisma, authorId, viewerId, post } = await setup();
    const followerId = await prisma.addUser('follower');
    const blockedId = await prisma.addUser('blocked');
    prisma.addMutualContacts(viewerId, authorId);
    prisma.addContact(followerId, authorId);
    prisma.addMutualContacts(blockedId, authorId);
    prisma.addBlock(authorId, blockedId);

    for (const audience of [[viewerId, followerId], [blockedId], [authorId]]) {
      await expect(post(audience)).rejects.toMatchObject({
        status: 400,
        response: { code: 'story_audience_invalid' },
      });
    }
    expect(prisma.stories).toEqual([]);
    expect(prisma.storyAudiences).toEqual([]);
  });

  it('story listed only to audience', async () => {
    const { prisma, service, authorId, viewerId, post, visibleTo } = await setup();
    const leftOutId = await prisma.addUser('left-out');
    prisma.addMutualContacts(viewerId, authorId);
    prisma.addMutualContacts(leftOutId, authorId);

    const story = await post([viewerId]);

    expect(story.audienceSize).toBe(1);
    expect(await visibleTo(viewerId)).toEqual([authorId]);
    expect(await visibleTo(leftOutId)).toEqual([]);
    await expectStoryNotFound(service.viewStory({ userId: leftOutId }, story.id));
    await expect(service.viewStory({ userId: viewerId }, story.id)).resolves.toMatchObject({
      viewed: true,
    });

    const [asViewer] = await service.listStories({ userId: viewerId });
    expect(asViewer).toMatchObject({
      id: story.id,
      handle: 'author',
      ciphertext: 'sealed-story',
      envelopeVersion: 'veil-envelope-v2',
      viewedByMe: true,
      viewCount: null,
    });
    const [asAuthor] = await service.listStories({ userId: authorId });
    expect(asAuthor).toMatchObject({ id: story.id, viewCount: 1 });
  });

  it('a later contact change does not widen the audience', async () => {
    const { prisma, authorId, viewerId, post, visibleTo } = await setup();
    const lateId = await prisma.addUser('late');
    prisma.addMutualContacts(viewerId, authorId);
    await post([viewerId]);

    prisma.addMutualContacts(lateId, authorId);

    expect(await visibleTo(lateId)).toEqual([]);
  });

  it('a block after posting hides the story', async () => {
    for (const viewerBlocks of [true, false]) {
      const { prisma, service, authorId, viewerId, post, visibleTo } = await setup();
      prisma.addMutualContacts(viewerId, authorId);
      const story = await post([viewerId]);

      if (viewerBlocks) {
        prisma.addBlock(viewerId, authorId);
      } else {
        prisma.addBlock(authorId, viewerId);
      }

      expect(await visibleTo(viewerId)).toEqual([]);
      await expectStoryNotFound(service.viewStory({ userId: viewerId }, story.id));
    }
  });

  it('authors always see their own stories', async () => {
    const { prisma, authorId, viewerId, post, visibleTo } = await setup();
    prisma.addMutualContacts(viewerId, authorId);
    await post([viewerId]);

    expect(await visibleTo(authorId)).toEqual([authorId]);
  });

  it('story.new only to the audience, without plaintext metadata', async () => {
    const { prisma, realtime, authorId, viewerId, post } = await setup();
    const leftOutId = await prisma.addUser('left-out');
    prisma.addMutualContacts(viewerId, authorId);
    prisma.addMutualContacts(leftOutId, authorId);

    const story = await post([viewerId]);

    const announcements = realtime.emitted.filter((event) => event.event === 'story.new');
    expect(announcements.map((event) => event.userId)).toEqual([viewerId]);
    expect(announcements[0]!.payload).toEqual({
      storyId: story.id,
      userId: authorId,
      handle: 'author',
      envelopeVersion: 'veil-envelope-v2',
      createdAt: story.createdAt,
      expiresAt: story.expiresAt,
    });
  });

  it('deleting someone else’s story answers like a missing one', async () => {
    const { prisma, service, authorId, viewerId, post } = await setup();
    prisma.addMutualContacts(viewerId, authorId);
    const story = await post([viewerId]);

    await expectStoryNotFound(service.deleteStory({ userId: viewerId }, story.id));
    expect(prisma.stories).toHaveLength(1);

    await expect(service.deleteStory({ userId: authorId }, story.id)).resolves.toEqual({
      deleted: true,
    });
    expect(prisma.stories).toHaveLength(0);
  });

  it('a production relay refuses development envelopes', async () => {
    const { prisma, authorId, viewerId, post } = await setup({ isProduction: true });
    prisma.addMutualContacts(viewerId, authorId);

    await expect(post([viewerId], 'veil-envelope-v1-dev')).rejects.toMatchObject({
      status: 400,
      response: { code: 'envelope_version_forbidden' },
    });
  });
});
