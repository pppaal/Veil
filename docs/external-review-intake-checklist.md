# VEIL External Review Intake Checklist

Last updated: 2026-04-11

Use this checklist when an external reviewer agrees to take the VEIL review.

Related docs:

- [external-security-review-request-template.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/external-security-review-request-template.md)
- [external-security-review-packet.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/external-security-review-packet.md)
- [external-review-remediation-tracker.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/external-review-remediation-tracker.md)

## Before sending the packet

Confirm:

- target commit SHA
- private beta posture statement
- mock crypto warning is explicit
- requested scope is written down

## Reviewer intake items

Collect and record:

- reviewer name
- firm or affiliation
- start date
- expected review window
- agreed scope
- exclusions
- communication channel

## Handoff packet checklist

Send:

- architecture overview
- threat model
- private beta audit
- final technical status
- release evidence artifacts
- review manifest
- remediation tracker template

## Scope confirmation

The reviewer should explicitly confirm whether they will review:

- auth and challenge/verify
- trusted-device graph and transfer
- revoke and invalidation
- local storage and app lock
- messaging relay assumptions
- attachment pipeline
- push metadata policy
- crypto abstraction boundary

## Immediately after acceptance

1. generate a fresh artifact bundle
2. record the commit SHA under review
3. open the remediation tracker
4. create a handoff note with the agreed scope

## When findings arrive

1. copy each finding into the tracker exactly once
2. assign severity
3. assign owner
4. decide patch vs process vs accepted risk
5. begin remediation
