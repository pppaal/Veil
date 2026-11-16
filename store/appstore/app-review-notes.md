# App Review information for Veil

This document is for the App Store Review team. It explains what Veil is,
how to test it without a phone number or email, the encryption export-compliance
posture, and how data is handled. Please read sections (a) and (b) before
testing. Veil has no password, no phone number, no email and no account
recovery; that is the expected behavior, not a bug.

---

## (a) What the app does, and why there is no recovery

**Veil is an end-to-end encrypted messenger.** An account lives on the phone
that created it; it is not tied to a phone number or an email address.

Key behaviors a reviewer should expect:

- **No phone number, no email, no real name.** There is no password, email or
  SMS sign-up, and no OTP verification. On first launch the app shows a privacy
  notice and a short **Before you start** page, then the user creates an account
  on the phone (**Create account**) and picks a handle (**Choose a handle**). The
  app creates the account's keys on the phone and registers only the public keys
  and the handle.
- **End-to-end encryption.** Every message is encrypted on-device using a Double
  Ratchet over X25519 (key exchange), AES-256-GCM (symmetric encryption),
  Ed25519 (device signatures), and HKDF-SHA256 (key derivation). The server only
  ever passes on message ciphertext and never has access to message plaintext.
- **No account recovery.** The account and its message history live on the
  phone and the keys never leave it, so **there is no way to recover an account
  or restore chats if the phone is lost.** There is no password reset, no
  "forgot account" flow, no server-side backup of messages, and no administrator
  who can read or restore content. The only way to move an account to a new
  phone is **Move to a new phone** in the app, which needs both phones in the
  user's hands.

This means the reviewer will **not** encounter (and should not look for) a login
screen, "forgot password" link, or any way to view messages from a server admin
console. None of these exist.

---

## (b) How to test WITHOUT a phone number or email

No demo credentials are needed because **there are no credentials.** The flow:

1. **Install and launch the app.** Accept the privacy notice ("Agree and
   continue"), then read Before you start (no backup, no recovery) and tick its
   checkbox. On **Create account** an optional name can be entered; it stays on
   the phone. Continue to **Choose a handle** and pick any free handle (lowercase
   letters, digits and underscores, for example `reviewer_a`). The app then
   creates the account's keys on the phone (X25519/Ed25519 key pairs) and
   registers only the public keys and the handle. No phone number, email, SMS
   code, or password is requested.
2. **(Optional) Set the local app lock.** You may be offered a local PIN /
   biometric (Face ID) lock. This is an on-device lock only; it is not an account
   login and does not authenticate to any server.
3. **Test messaging with two installs.** Because messages are end-to-end
   encrypted and pass through the server, the realistic way to exercise it is
   with **two devices or two simulators** (Device A and Device B), each with its
   own account created as in step 1:
   - On Device A, tap **New chat** and enter Device B's handle. The chat offers
     a safety number the two devices can compare to confirm each other's keys.
   - Send a 1:1 message from A to B and confirm it is received and decrypted on B.
   - Optionally create a group (**New group**) and send a message in it to
     confirm the group path. This build sends text only: it has no attachments,
     voice messages or calls.
   - To report or block (guideline 1.2): on Device A, open the menu at the top
     right of the chat with B (**Report**, **Block**), or long-press one of B's
     messages (**Report**), or add B in **Contacts** (**Add contact** at the
     top right) and tap B there. A report sends B's account, the reason and
     which chat or message, not what it says. Blocked accounts are listed under
     **Settings > Privacy > Blocked accounts**. The same chat menu mutes the
     chat's notifications.
4. **Verify the "no recovery" behavior (optional).** Delete and reinstall the app
   on one device. The previous identity and message history will be gone, and the
   onboarding starts again for a brand-new account. This demonstrates the
   intended no-recovery model.

If only a single device is available, the app will still launch fully and create
an account; a second participant is simply required to observe message exchange,
exactly as with any messenger.

There is **no demo account, no demo phone number, and no test password** to
provide: each install creates its own account in a few seconds, on that
phone. Please contact us (below) if the review team
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

- **No CCATS / no ITSEncryptionExportComplianceCode is required:** a CCATS is
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
