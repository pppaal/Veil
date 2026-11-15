/// The groups of the emoji picker, in the order of its tabs.
enum EmojiGroup { smileys, gestures, symbols }

/// The emoji the picker offers, by group. They are plain Unicode text: no
/// pack, no image, nothing fetched. A sticker or a GIF is neither, and the
/// picker has none.
const emojiCatalog = <EmojiGroup, List<String>>{
  EmojiGroup.smileys: [
    '\u{1F600}', '\u{1F603}', '\u{1F604}', '\u{1F601}', '\u{1F606}', '\u{1F605}', '\u{1F602}', '\u{1F923}',
    '\u{1F60A}', '\u{1F607}', '\u{1F642}', '\u{1F643}', '\u{1F609}', '\u{1F60C}', '\u{1F60D}', '\u{1F970}',
    '\u{1F618}', '\u{1F617}', '\u{1F619}', '\u{1F61A}', '\u{1F60B}', '\u{1F61B}', '\u{1F61C}', '\u{1F92A}',
    '\u{1F61D}', '\u{1F911}', '\u{1F917}', '\u{1F92D}', '\u{1F92B}', '\u{1F914}', '\u{1F910}', '\u{1F928}',
    '\u{1F610}', '\u{1F611}', '\u{1F636}', '\u{1F60F}', '\u{1F612}', '\u{1F644}', '\u{1F62C}', '\u{1F925}',
    '\u{1F60E}', '\u{1F913}', '\u{1F9D0}', '\u{1F615}', '\u{1F61F}', '\u{1F641}', '\u{2639}\u{FE0F}', '\u{1F62E}',
    '\u{1F62F}', '\u{1F632}', '\u{1F633}', '\u{1F97A}', '\u{1F626}', '\u{1F627}', '\u{1F628}', '\u{1F630}',
    '\u{1F625}', '\u{1F622}', '\u{1F62D}', '\u{1F631}',
  ],
  EmojiGroup.gestures: [
    '\u{1F44D}', '\u{1F44E}', '\u{1F44F}', '\u{1F64C}', '\u{1F64F}', '\u{1F44B}', '\u{1F91D}', '\u{1F44C}',
    '\u{270C}\u{FE0F}', '\u{1F91E}', '\u{1F919}', '\u{1F450}', '\u{1F44A}', '\u{270A}', '\u{1F91B}', '\u{1F91C}',
  ],
  EmojiGroup.symbols: [
    '\u{2764}\u{FE0F}', '\u{1F9E1}', '\u{1F49B}', '\u{1F49A}', '\u{1F499}', '\u{1F49C}', '\u{1F5A4}', '\u{1F90D}',
    '\u{1F90E}', '\u{1F494}', '\u{1F525}', '\u{2B50}', '\u{1F31F}', '\u{1F4AB}', '\u{2728}', '\u{1F389}',
    '\u{1F4AF}', '\u{2705}',
  ],
};
