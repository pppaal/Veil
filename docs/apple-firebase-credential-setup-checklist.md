# VEIL Apple And Firebase Credential Setup Checklist

Last updated: 2026-04-08

Use this checklist when preparing real APNs and FCM credentials for VEIL staging
or private-beta delivery.

This checklist exists to reduce mistakes. It does not authorize production
claims, and it does not replace the separate push privacy review.

Related docs:

- [push-privacy-review-checklist.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/push-privacy-review-checklist.md)
- [external-execution-master-checklist.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/external-execution-master-checklist.md)

## Goal

Prepare:

- APNs credentials for `io.veil.mobile`
- FCM credentials for the same shipping app identity
- secure env injection for the API

Do not:

- commit secrets to git
- mix debug and release identifiers
- enable push delivery before the privacy review is complete

## Before you start

Required access:

- Apple Developer account with key and capability access
- Firebase project creation access
- secure secret storage for staging and beta
- control over the API deployment environment

Required repo state:

- current branch green on `pnpm ci:verify`
- push provider path already present in code
- target environment file prepared but still missing real secrets

## Part 1. Apple APNs setup

### 1. Confirm the app identity

The expected shipping identity is:

- bundle identifier: `io.veil.mobile`

Verify:

- the Apple Developer App ID matches `io.veil.mobile`
- the iOS Xcode project bundle id matches `io.veil.mobile`

If these do not match, stop and fix the identity mismatch first.

### 2. Enable Push Notifications capability

In Apple Developer:

1. Open Certificates, IDs & Profiles
2. Open the App ID for `io.veil.mobile`
3. Confirm Push Notifications capability is enabled

Record:

- Apple Team ID
- Bundle ID

### 3. Create an APNs auth key

In Apple Developer:

1. Open Keys
2. Create a new key with APNs enabled
3. Download the `.p8` file immediately

Record:

- `VEIL_APNS_KEY_ID`
- `VEIL_APNS_TEAM_ID`
- `VEIL_APNS_BUNDLE_ID=io.veil.mobile`
- `VEIL_APNS_PRIVATE_KEY_PEM`

Security rules:

- store the `.p8` only in secure secret storage
- do not email it in plaintext
- do not commit it
- do not place it in shared drives without access control

### 4. Prepare staging env values

Expected env values:

- `VEIL_PUSH_PROVIDER=apns`
- `VEIL_PUSH_ENABLE_DELIVERY=false` initially
- `VEIL_APNS_BUNDLE_ID=io.veil.mobile`
- `VEIL_APNS_TEAM_ID=<team-id>`
- `VEIL_APNS_KEY_ID=<key-id>`
- `VEIL_APNS_PRIVATE_KEY_PEM=<single-line-or-secure-multiline-secret>`

Do not enable delivery yet.

## Part 2. Firebase FCM setup

### 1. Create or choose the Firebase project

Use a dedicated VEIL staging or beta project.

Record:

- Firebase project name
- `VEIL_FCM_PROJECT_ID`

Do not reuse consumer or unrelated internal projects.

### 2. Register Android and iOS apps

Inside Firebase:

- Android app id should match Android release identity
- iOS app id should match `io.veil.mobile`

Verify the app identities match the mobile project before proceeding.

### 3. Create a service account for HTTP v1 messaging

In Google Cloud / Firebase:

1. Create or select a service account
2. Grant only the messaging permissions needed
3. Download the JSON key into secure storage

Record:

- `VEIL_FCM_PROJECT_ID`
- `VEIL_FCM_SERVICE_ACCOUNT_JSON`

Security rules:

- never commit the JSON
- rotate if it is copied into an unsafe place
- treat it as a production-like secret

### 4. Prepare staging env values

Expected env values:

- `VEIL_PUSH_PROVIDER=fcm`
- `VEIL_PUSH_ENABLE_DELIVERY=false` initially
- `VEIL_FCM_PROJECT_ID=<firebase-project-id>`
- `VEIL_FCM_SERVICE_ACCOUNT_JSON=<secure-json-secret>`

Do not enable delivery yet.

## Part 3. Secret injection

Store the values in:

- deployment secret manager
- CI secret storage
- staging environment variables

Do not store them in:

- `.env.example`
- committed `.env` files
- README snippets
- issue comments

## Part 4. Machine validation

Run:

```bash
pnpm beta:push:readiness -- --env-file apps/api/.env --provider apns
pnpm beta:push:readiness -- --env-file apps/api/.env --provider fcm
```

Expected:

- both checks pass for the provider you prepared
- output artifact updates successfully

If the check fails:

- do not continue to privacy review
- fix the missing or malformed env values first

## Part 5. Hand-off to privacy review

Only after credentials are present:

1. keep `VEIL_PUSH_ENABLE_DELIVERY=false`
2. run the payload inspection and privacy review in
   [push-privacy-review-checklist.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/push-privacy-review-checklist.md)
3. capture evidence
4. get sign-off

Then, and only then:

- set `VEIL_PUSH_ENABLE_DELIVERY=true` in staging

## Exit criteria

This checklist is complete only when:

- APNs credentials exist and validate
- FCM credentials exist and validate
- secrets are injected securely
- push delivery is still disabled pending privacy review

At that point VEIL is ready for the next external step, not for production.
