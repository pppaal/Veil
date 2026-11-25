// What a hostile relay can list in place of the handle 'bob': each renders
// as 'bob', none equals it, and no honest server issues it
// (src/domain/handles.js).
export const BOB_LOOKALIKES = Object.freeze({
  'a zero-width space': 'bob​',
  'a Cyrillic o': 'bоb',
  'a right-to-left override': '‮bob',
  'a trailing space': 'bob ',
});
