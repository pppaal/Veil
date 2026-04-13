# VEIL External Review Remediation Tracker

Last updated: 2026-04-07

Use this document after external review findings arrive.

This tracker is intentionally simple:

- one row per finding
- one owner
- one target fix decision
- one retest decision

Do not use this tracker to weaken VEIL philosophy.

## Status legend

- `open`: finding is accepted and still needs action
- `in_progress`: patch is being implemented
- `fixed`: patch landed and local verification passed
- `accepted_risk`: team accepted the risk for private beta
- `closed`: reviewer or internal security owner accepted the resolution

## Severity legend

- `critical`
- `high`
- `medium`
- `low`
- `informational`

## Finding tracker

| ID | Severity | Area | Summary | Owner | Status | Patch/Doc | Local verification | Retest needed | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXAMPLE-001 | high | auth | Example only. Replace with real finding. | unassigned | open | pending | pending | yes | Remove this row before use. |

## Area mapping

- `crypto`
- `auth`
- `device_trust`
- `messages`
- `attachments`
- `mobile_storage`
- `network`
- `push_privacy`
- `observability`
- `release_process`

## Required closure evidence

Every closed finding should link to:

- the patch commit or PR
- the updated doc or checklist if process changed
- the exact verification command or test
- the reviewer or internal approver who accepted the result

## Closure checklist

1. Record the finding exactly once.
2. Assign one owner.
3. Decide whether the finding is a patch, a doc/process change, or an accepted risk.
4. Land the patch or update the process.
5. Re-run the relevant verification.
6. Mark `fixed` only after verification passes.
7. Mark `closed` only after acceptance or retest.

## Related docs

- [external-security-review-packet.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/external-security-review-packet.md)
- [external-execution-master-checklist.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/external-execution-master-checklist.md)
- [final-technical-status.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/final-technical-status.md)
