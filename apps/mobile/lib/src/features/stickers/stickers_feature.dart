/// The sticker and emoji picker stays off until what is picked reaches a
/// message: its sticker and GIF tabs are placeholders and picking an emoji
/// only shows a toast. While false, the picker has no route and nothing
/// opens it. Reactions have their own picker and are not affected.
const bool kStickerPickerEnabled = false;
