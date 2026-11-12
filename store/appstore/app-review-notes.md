# Veil — App Review Information & Reviewer Guidance

This document is intended for the App Store Review team. It explains what Veil is,
how to test it without a phone number or email, the encryption export-compliance
posture, and how data is handled. Please read the "No recovery by design" and
"How to test without a phone number or email" sections before testing — Veil
intentionally has no password, no phone number, no email and no account
recovery, and that is the expected behavior, not a bug.

---

## (a) What the app does + "No recovery by design"

**Veil is a privacy-first, end-to-end encrypted messenger.** Its defining
property is that identity is **device-bound** rather than tied to a phone number,
email, or username.

Key behaviors a reviewer should expect:

- **No phone number, no email, no real name.** There is no password, email or
  SMS sign-up, and no OTP verification. On first launch the app shows a privacy
  notice and its product rules, then the user creates an account bound to the
  device (**Create Account**) and picks a handle (**Choose Handle**). The app
  generates the cryptographic identity locally on the device and registers only
  its public keys and the handle.
- **End-to-end encryption.** Every message is encrypted on-device using a Double
  Ratchet over X25519 (key exchange), AES-256-GCM (symmetric encryption),
  Ed25519 (device signatures), and HKDF-SHA256 (key derivation). The server only
  ever relays message ciphertext and never has access to message plaintext.
- **No recovery path — by design.** Because identity and message history are
  bound to the device and the keys never leave it, **there is no way to recover
  an account or restore conversations if the device is lost.** There is no
  password reset, no "forgot account" flow, no server-side backup of messages,
  and no administrator who can read or restore content. This is the core safety
  model of the app, not a defect. The only sanctioned way to move an identity to
  a new device is the in-app **encrypted device transfer** (possession-proof
  pairing between two devices the user controls).

This means the reviewer will **not** encounter (and should not look for) a login
screen, "forgot password" link, or any way to view messages from a server admin
console — none of these exist intentionally.

---

## (b) How to test WITHOUT a phone number or email

No demo credentials are needed because **there are no credentials.** The flow:

1. **Install and launch the app.** Accept the privacy notice ("Agree and
   continue") and read the product rules (no backup, no recovery). On **Create
   Account** an optional display name can be entered; continue to **Choose
   Handle** and pick any free handle (for example `reviewer.a`). The app then
   generates the device-bound identity locally (X25519/Ed25519 keypairs) and
   registers only its public keys and the handle. No phone number, email, SMS
   code, or password is requested.
2. **(Optional) Set the local app lock.** You may be offered a local PIN /
   biometric (Face ID) lock. This is an on-device lock only; it is not an account
   login and does not authenticate to any server.
3. **Test messaging with two installs.** Because Veil is end-to-end encrypted,
   server-relayed messaging, the realistic way to exercise it is with **two
   devices or two simulators** (Device A and Device B), each with its own
   account created as in step 1:
   - On Device A, start a new conversation with Device B's handle. The chat
     offers a safety number the two devices can compare to confirm each other's
     keys.
   - Send a 1:1 message from A to B and confirm it is received and decrypted on B.
   - Optionally create a group conversation and send an encrypted attachment to
     confirm group and media paths.
4. **Verify the "no recovery" behavior (optional).** Delete and reinstall the app
   on one device. The previous identity and message history will be gone, and the
   onboarding starts again for a brand-new account. This demonstrates the
   intended no-recovery model.

If only a single device is available, the app will still launch fully and create
an account; a second participant is simply required to observe message exchange,
exactly as with any messenger.

There is **no demo account, no demo phone number, and no test password** to
provide: each install creates its own account in a few seconds, bound to that
device. Please contact us (below) if the review team
would like a guided walkthrough or a paired second device/identity for testing.

---

## (c) Encryption export compliance

**ITSAppUsesNonExemptEncryption = YES (true).**

Veil implements its **own** end-to-end encryption (a Double Ratchet over X25519,
AES-256-GCM, Ed25519, and HKDF-SHA256). This goes beyond Apple's narrow
exemptions (OS-provided crypto, authentication-only, or HTTPS/TLS-only), so the
truthful answer to "does your app use non-exempt encryption" is **Yes**.

However, Veil uses **only standard, published cryptographic algorithms**, so it
qualifies for the U.S. **mass-market self-classification exemption** under
15 CFR 740.17(b)(1). Consequences:

- **No CCATS / no ITSEncryptionExportComplianceCode is required** — a CCATS is
  only needed for proprietary/non-standard algorithms, which Veil does not use.
  The `Info.plist` therefore does **not** carry an
  `ITSEncryptionExportComplianceCode` value.
- An **annual self-classification report** will be filed before distribution
  with U.S. BIS (crypt@bis.doc.gov) and the NSA ENC coordinator (enc@nsa.gov)
  under ECCN 5D992.c.
- A **French (ANSSI) encryption declaration** will be filed before distribution
  in France.

App Store Connect Export Compliance answers used for this submission:

1. "Is your app designed to use cryptography or does it contain or incorporate
   cryptography?" → **Yes.**
2. "Does your app qualify for any of the exemptions provided in Category 5,
   Part 2?" → **Yes.**
3. Exemption selected → the **standard-algorithms / mass-market
   self-classification** option (NOT the "only HTTPS / Apple OS" option, and NOT
   the proprietary-algorithm path).
4. Self-classification report filed with the U.S. government → answered truthfully
   per the BIS filing status above.

---

## (d) Data handling summary

Full details are in the accompanying **`app-privacy-answers.md`** (the source for
our App Privacy "nutrition label" answers). Summary:

- **No tracking.** Veil uses data for tracking: **No.** No advertising SDKs and no
  cross-app profiling.
- **No third-party analytics, no ads.**
- **Identifiers** (User ID, Device ID): collected, linked to the user, used solely
  for App Functionality, not for tracking.
- **User content** (message payloads): transited as **ciphertext only**. The
  server cannot decrypt it, so it is declared unlinked. Messages, media, and
  attachments are end-to-end encrypted.
- **Contacts:** the in-app contact list (which accounts the user added) is
  collected and linked to the user, for App Functionality only. The phone's
  address book is never read.
- **Other user content, linked:** group and channel names and descriptions and
  device labels (stored readable), and the metadata needed to deliver
  messages (conversation membership, message and receipt times, call
  records), all tied to the account.
- **Crash diagnostics:** not collected. The app ships no crash-reporting SDK
  (CI rejects adding one without a privacy review).
- **Not collected:** location, health/fitness, financial info, browsing
  history, search history, purchases, usage/analytics data, and sensitive info
  (see `app-privacy-answers.md` for the complete "Data Not Collected" list).
- Privacy policy: https://pppaal.github.io/Veil/

---

## (e) Contact for review questions

- **Email:** privacy@veil.app
- **Support:** https://veil.app/support

We will respond promptly to any questions from App Review, including arranging a
live walkthrough or a paired second device/identity for testing the encrypted
messaging flow described in section (b).
