# VEIL Mobile Design System

## Tone

VEIL should feel cold, premium, restrained, and deliberate.

This is not a bright consumer chat app. The interface should communicate:

- local control
- severe privacy boundaries
- calm operational clarity
- premium messenger quality without visual noise

## Visual Rules

### Color

- Backgrounds stay near-black or charcoal.
- Surfaces layer upward in small tonal steps.
- Steel-blue and muted-cyan accents indicate focus, primary action, and live state.
- Warning and destructive colors remain subdued enough to fit the palette, but unmistakable.

### Typography

- Headlines are sharp, slightly compressed, and low-noise.
- Labels are uppercase or high-contrast where hierarchy matters.
- Supporting copy should stay precise and short.
- Body copy should avoid chatty phrasing.

### Spacing

- Dense where scanning matters.
- Roomy where consequence matters.
- Hero panels and destructive states get more air than routine list rows.

### Surfaces

- Use layered cards and bands instead of flat pages.
- Avoid playful pills, oversized avatars, or glossy gradients.
- Gradients are subtle and atmospheric, never neon.

## Component Intent

### `VeilButton`

- `primary`: decisive, forward-moving action
- `secondary`: controlled action without urgency
- `destructive`: high-risk lifecycle action
- `ghost`: low-emphasis inline action

### `VeilFieldBlock`

Field sections should always show:

- what the user is editing
- why it matters
- any relevant constraint or scope

### `VeilHeroPanel`

Use for:

- screen framing
- high-level consequences
- mode explanation

Do not use hero panels for routine form sections.

### `VeilInlineBanner`

Use banners for:

- failure
- blocked state
- privacy rule reminder
- temporary sync/runtime state

Do not use banners for decorative emphasis.

A banner's fill is a tint of the surface behind it, so its text is light on
the dark theme and dark on the light one; the tone colours (`info`, `good`,
`warn`, `danger`) have a darker variant for the light theme. The same holds
for `VeilStatusPill`, `VeilNoticeRow` and `VeilToast`.

### `VeilCopy`

Draws a sentence of the app's own copy with its Korean words kept whole
where it wraps (a line of Korean may otherwise break between any two
syllables), and reads it out as the plain text. The shared cards, banners,
hero and empty states draw their titles and bodies with it; a screen uses it
for a paragraph of its own.

Never for what a person wrote (a message, a name, a note): that goes into a
plain `Text`, as typed.

### `VeilGroup`, `VeilGroupRow`, `VeilGroupSwitchRow`

Rows that belong together, in one card with a hairline between them, under an
optional section label and over an optional footnote
(`shared/presentation/veil_grouped.dart`). A settings-like screen is a list of
groups, not a card per row: Settings, the profile and the one-time link use
them.

- A row that opens something ends in a chevron; a row that changes a setting
  carries its control (`VeilGroupSwitchRow` takes the tap anywhere on the row
  and reads as one switch).
- A `destructive` row draws its icon and title in the danger colour. Rows that
  cannot be undone form one group of their own, last on the screen, under a
  `VeilDestructiveNotice`.
- Section labels are written in capitals in English, like every
  `VeilSectionLabel`.

### `VeilMetricStrip`

Use for:

- compact runtime summaries
- device-graph counts
- chat and conversation overview state

Metric strips should stay short, factual, and scannable.

On a phone the tiles of a row share its width, three to a row at most and
never one alone on a row (four tiles are two and two). A tile's value takes
up to two lines there. Wider screens keep each tile at its own width.

### `VeilDestructiveNotice`

Use for:

- no-recovery reminders
- irreversible local wipe or revoke flows
- transfer failure consequences

Destructive notice blocks should feel calm and high-stakes, not melodramatic.

### `VeilComposer`

The composer should feel stable, deliberate, and operational.

- action always visible
- helper text short and policy-aware
- no playful send affordances

## Screen Guidance

### Onboarding

- Lead with consequence, not marketing.
- Keep no-recovery language blunt.

### Conversation List

- Optimize for scan speed and calm density.
- Search belongs to the device, not the server.
- Selected conversations should stand out through tone and border, not loud color.

### Chat Room

- Message bodies must be highly readable.
- Status should never overwhelm content.
- Sent-state clarity should use short, consistent badges such as `Queued`, `Uploading`, `Sent`, `Delivered`, and `Read`.
- Attachment and failure states must stay explicit.
- The header should keep relay, search, and disappearance context visible without crowding the composer.
- Local in-chat search should communicate that it is scanning cached device-local text, not the server.

### Reactions

- Long-press on a message bubble opens a reaction picker via modal bottom sheet.
- Reaction chips display grouped below the message bubble as `_ReactionChipsRow`.
- Each chip shows emoji + count. The current user's reactions are highlighted with accent color.
- Tapping an existing reaction from the current user removes it (toggle behavior).
- Reactions should feel restrained and functional, not playful.

### Contacts

- The list is the screen: search is its first row and scrolls away with it,
  adding a contact is an action of the bar, and what the relay keeps of the
  list is said under it and in the add sheet.
- Rows are filed under index letters: a Korean name under its first consonant
  (ㄱ, ㄴ, …), which lead the list in a Korean app.
- A contact's sheet offers "Start chat" (creates the direct conversation and
  opens the chat room), "Edit nickname" (the name this device shows; the relay
  never learns it) and "Remove contact". There is no profile view: a profile
  on the relay is the handle and nothing else.

### Group Chat

- Group conversations display all members in the header.
- Message send uses the group conversation's shared bundle (no per-peer key fetch).
- Group management actions (leave, remove member) should use destructive notice patterns for irreversible operations.

### Settings / Security / Transfer

- These screens are product philosophy surfaces.
- Make trust state, device state, and destructive actions unambiguous.
- Settings is grouped rows in this order: the account, appearance, privacy,
  security, devices, tools, and last, set apart under the no-recovery notice,
  what cannot be undone (log out, wipe, revoke this device, delete the
  account). Each of those four says what it erases and asks for a typed
  phrase; logging out erases this device's keys like the others.
- The devices of the account are a screen of their own, opened from the
  devices row, which counts them and flags a trusted device that has gone
  quiet on the row itself.

## Accessibility Notes

- Support larger text without clipped banners or broken button rows.
- Maintain readable contrast on every surface.
- Keep tap targets at or above 44px where interactive.
- Surface state changes with text, not color alone.
- Preserve semantics labels on major list and message items.

## Adaptive Layout

- Conversation list uses a wide breakpoint at 1120px logical width.
- Below the breakpoint, navigation pushes a separate chat room route.
- Above the breakpoint, the list and chat room render side-by-side in an 8:10 flex ratio.
- Wide layout should auto-select the first conversation if none is selected.
- Search results in wide layout switch the active conversation pane inline.
- Page storage preserves selected conversation, search query, and filter state across rebuilds.

## What To Avoid

- bright social-app color language
- cartoonish rounding
- overly playful microcopy
- neon cyberpunk styling
- consumer messenger cheerfulness
- visual resemblance to KakaoTalk
- direct visual imitation of Telegram
