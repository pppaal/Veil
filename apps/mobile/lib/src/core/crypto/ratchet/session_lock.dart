import '../../util/keyed_async_lock.dart';

export '../../util/keyed_async_lock.dart';

/// Per-conversation serial lock. Every operation that reads and then
/// replaces a conversation's ratchet state runs inside it, so an encrypt can
/// never interleave with a decrypt (or a second encrypt) and reuse a counter.
typedef SessionLock = KeyedAsyncLock<String>;
