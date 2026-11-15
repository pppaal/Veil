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

- Before you start, before the account is created: "If you lose this phone,
  you lose this account and its messages. There is no backup and no way to
  recover it."
- The Security footer in Settings: "There is no backup, no password reset
  and no way for anyone, including us, to recover an account."
- Move to a new phone: "You need the old phone. If it is gone, the account
  is gone."
- The confirm dialogs of Sign out (signing out erases this phone's keys),
  Wipe this device, Revoke and Delete account.

It is not repeated on Create account, App lock, Chats, the Security rows or
the splash, and it is never a slogan.
