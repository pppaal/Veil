# Why VEIL Has No Recovery

VEIL treats recoverability as a privacy tradeoff, not a default good.

If a service can restore your account without your existing device, then some alternate recovery authority exists. That authority becomes part of the attack surface. VEIL rejects that model for v1.

## Product consequences

- if the device is lost, access is lost
- if the active device is unavailable, transfer fails
- there is no password reset
- there is no recovery email flow
- there is no cloud message restore

## User-facing copy principles

- say it directly
- avoid softening the consequence
- make the tradeoff explicit before account creation

Required tone:

- `No backup. No recovery. No leaks.`
- `If you lose your device, your account and messages are gone.`
- `This is intentional.`
- `VEIL cannot restore your access.`
