# Why Veil has no recovery

Veil treats recoverability as a privacy cost, not a default good.

If a service can restore your account without your existing device, then some alternate recovery authority exists. That authority becomes part of the attack surface. Veil does not have one.

## Product consequences

- if the device is lost, access is lost
- if the active device is unavailable, transfer fails
- there is no password reset
- there is no recovery email flow
- there is no cloud message restore
- there is no server-held key backup, sealed or not

## How the server enforces it

A passphrase-sealed key backup was briefly prototyped (see
[recovery-backup-design.md](recovery-backup-design.md)) and removed: even an
envelope the server cannot open turns the passphrase into an alternate
recovery authority, and the server into an offline brute-force target.

CI enforces the rule:

- `scripts/policy-check.mjs` fails on any API route path containing
  `recovery` or `backup`, on any `modules/recovery` or `modules/backup`
  directory under `apps/api/src`, on any password-reset flow, on any
  recovery or backup model or table in `apps/api/prisma/schema.prisma`, on
  any recovery or backup type in `packages/contracts/src`, and on an
  `apps/mobile/lib/src/core/backup` directory. It runs a built-in self-test
  first, so a broken rule cannot pass silently.
- `apps/api/test/unit/route-auth-matrix.spec.ts` walks every mounted route
  and fails if one offers recovery or backup.

## How the app says it

Say it directly, once, where the decision is made, and do not soften the
consequence. The app states it in a few fixed places only
([mobile-design-system.md](mobile-design-system.md), section 9), in these
words:

- Before you start, before the account is created: "Your account lives on
  this phone." / "If you lose the phone, your account and messages are gone
  for good." / "To move to a new phone later, you'll need this one.", with
  the checkbox "I understand a lost account can't be recovered".
- The confirm dialog of Sign out: "This signs this phone out and erases Veil
  from it. You lose the account for good."
- The confirm dialog of Delete account: "This deletes your account, messages
  and contacts from this phone and the server, and the groups you created,
  for everyone in them. It can't be undone." (The server deletes every group
  the account owns, AccountService.deleteAccount, and neither app offers to
  hand a group over first.)
- App lock setup, for the PIN: "If you forget your PIN, there's no way to
  reset it."

Both Settings dialogs ask the user to type their own handle first. It is not
repeated in Settings itself, on Choose a handle, Chats, the transfer screens
or the splash, and it is never a slogan.
