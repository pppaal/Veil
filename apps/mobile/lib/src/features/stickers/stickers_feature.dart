/// The emoji picker stays off until the chat has a button that opens it
/// and puts what comes back into the message. The picker itself works: it
/// offers emoji by group and hands the picked one to whoever opened it. It
/// has no stickers and no GIFs; neither exists in this build. While false,
/// the picker has no route and nothing opens it. Reactions have their own
/// picker and are not affected.
const bool kStickerPickerEnabled = false;
