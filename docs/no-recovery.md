# Why VEIL Has No Recovery

VEIL treats recoverability as a privacy tradeoff, not a default good.

If a service can restore your account without your existing device, then some alternate recovery authority exists. That authority becomes part of the attack surface. VEIL rejects that model for v1.

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

The rule is enforced in CI, not just stated here:

- `scripts/policy-check.mjs` fails on any API route path containing
  `recovery` or `backup`, on any `modules/recovery` or `modules/backup`
  directory under `apps/api/src`, and on any password-reset flow. It runs a
  built-in self-test first, so a broken rule cannot pass silently.
- `apps/api/test/unit/route-auth-matrix.spec.ts` walks every mounted route
  and fails if one offers recovery or backup.

## User-facing copy principles

- say it directly
- avoid softening the consequence
- make the tradeoff explicit before account creation

Required tone:

- `No backup. No recovery. No leaks.`
- `If you lose your device, your account and messages are gone.`
- `This is intentional.`
- `VEIL cannot restore your access.`
