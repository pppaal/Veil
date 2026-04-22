# App Store Privacy Questionnaire Answers (Veil)

Use these answers when filling out the App Store "App Privacy" section.

## Data Collection

**Do you or your third-party partners collect data from this app?**
Yes — only the minimum operational data described below. No data is used for tracking.

### Contact Info
- Collected: **No**

### Identifiers
- **User ID**: collected
  - Linked to user: Yes
  - Used for: App Functionality
  - Tracking: No
- **Device ID**: collected
  - Linked to user: Yes
  - Used for: App Functionality
  - Tracking: No

### User Content
- **Other User Content** (encrypted message payloads): collected and transited
  - Linked to user: No (server-side ciphertext has no plaintext identifier)
  - Used for: App Functionality
  - Tracking: No
- Messages, media, photos, audio, and customer support content are encrypted end-to-end. Apple's classification still requires declaring the transport of user content; we declare it as unlinked because the server cannot decrypt it.

### Diagnostics
- **Crash Data**: collected (opt-in via Sentry; disabled by default)
  - Linked to user: No
  - Used for: App Functionality
  - Tracking: No
- **Performance Data**: not collected
- **Other Diagnostic Data**: not collected

### Data Not Collected
- Health & Fitness
- Financial Info
- Location
- Sensitive Info
- Contacts
- Browsing History
- Search History
- Purchases
- Usage Data (analytics)
- Surroundings
- Body Data

## Tracking
- Does the app use data for tracking? **No**.
- No third-party SDKs receive user data for advertising or cross-app profiling.
