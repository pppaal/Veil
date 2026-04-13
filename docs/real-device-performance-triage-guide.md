# VEIL Real-Device Performance Triage Guide

Last updated: 2026-04-11

Use this guide after real-device results are captured.

Related docs:

- [real-device-performance-execution.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/real-device-performance-execution.md)
- [real-device-performance-results-template.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/real-device-performance-results-template.md)

## Purpose

Convert raw real-device observations into actionable engineering work.

This guide is intentionally simple: classify first, optimize second.

## Severity rubric

### Blocker

Use `blocker` when:

- long-history chat becomes visibly unstable
- search or jump-to-context fails repeatedly
- reconnect/resume loses or duplicates state
- attachment retry/cancel becomes confusing or stuck

### Major

Use `major` when:

- p95 scroll is visibly janky on baseline hardware
- conversation open or search latency feels slow enough to notice
- wide layout or larger text breaks important interaction flow

### Moderate

Use `moderate` when:

- the flow works but feels heavier than expected
- small layout jitter or visual delay is present
- retry/reconnect is understandable but not polished

### Minor

Use `minor` when:

- polish is missing but clarity remains good
- the issue is cosmetic or low-frequency

## Triage buckets

Every issue should go into exactly one bucket:

- `rendering`
- `state_sync`
- `io_or_cache`
- `search`
- `history_paging`
- `attachments`
- `adaptive_layout`
- `accessibility_copy`

## Suggested fixes by bucket

### rendering

Look for:

- repeated rebuilds
- large repaint regions
- expensive row composition

### state_sync

Look for:

- duplicate refresh
- unnecessary notify cycles
- over-eager reconnect work

### io_or_cache

Look for:

- repeated decryption
- repeated cache lookup
- local search index growth

### search

Look for:

- stale-result races
- expensive query recomputation
- result list over-rendering

### history_paging

Look for:

- duplicate page work
- unstable cursor merge
- poor scroll anchor behavior

### attachments

Look for:

- retry state confusion
- heavy temp-file lifecycle
- download-resolution latency

## Required outputs after triage

For every issue:

- severity
- bucket
- device
- scenario
- likely root cause
- first fix proposal

## Recommended response speed

- blocker: patch before next beta candidate
- major: patch or explicitly defer with rationale
- moderate: bundle into the next polish pass
- minor: backlog only if higher-value work is clear
