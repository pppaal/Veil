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

### `VeilMetricStrip`

Use for:

- compact runtime summaries
- device-graph counts
- chat and conversation overview state

Metric strips should stay short, factual, and scannable.

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
- Attachment and failure states must stay explicit.
- The header should keep relay, search, and disappearance context visible without crowding the composer.

### Settings / Security / Transfer

- These screens are product philosophy surfaces.
- Make trust state, device state, and destructive actions unambiguous.

## Accessibility Notes

- Support larger text without clipped banners or broken button rows.
- Maintain readable contrast on every surface.
- Keep tap targets at or above 44px where interactive.
- Surface state changes with text, not color alone.
- Preserve semantics labels on major list and message items.

## What To Avoid

- bright social-app color language
- cartoonish rounding
- overly playful microcopy
- neon cyberpunk styling
- consumer messenger cheerfulness
- visual resemblance to KakaoTalk
- direct visual imitation of Telegram
