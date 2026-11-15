/// Stories stay off until this build can seal and open one: the relay takes
/// and gives a story only as an end-to-end encrypted envelope, and nothing
/// here makes or reads that envelope. The feed lists who has a story up and
/// when, with a notice that none can be opened or posted; the viewer says
/// it cannot open one. Neither marks a story as viewed. While false, neither
/// the feed nor any story route is reachable.
const bool kStoriesEnabled = false;
