# App Store Privacy Questionnaire Answers (Veil)

Use these answers when filling out the App Store "App Privacy" section.
The Google Play counterpart, in Play's categories, is
`store/play/data-safety-answers.md`. These two files are the only source of the
store privacy labels: other documents point here, and
`scripts/store-label-check.mjs` fails CI when the two files disagree, when the
database stores something they do not declare, or when another document says a
declared type is not collected.

## Data Collection

**Do you or your third-party partners collect data from this app?**
Yes — only the minimum operational data described below. No data is used for tracking.

### Contact Info
- Collected: **No** (no name, email address, phone number or physical address)

### Contacts
- **Contacts**: collected. The in-app contact list records which accounts the
  user added, which is a social graph in Apple's definition. (The phone's
  address book is never read; the names the user gives contacts stay on the
  device.)
  - Linked to user: Yes
  - Used for: App Functionality
  - Tracking: No

### Identifiers
- **User ID**: collected
  - Linked to user: Yes
  - Used for: App Functionality
  - Tracking: No
- **Device ID**: collected (the server-generated id of each device and, when
  the app registers one, the device's push token, used only for wake-ups that
  carry no message content)
  - Linked to user: Yes
  - Used for: App Functionality
  - Tracking: No

### User Content
- **Other User Content** (encrypted message payloads): collected and transited
  - Linked to user: No (the server cannot decrypt the content)
  - Used for: App Functionality
  - Tracking: No
- Messages, media, photos, and audio are encrypted end-to-end. Apple's classification still requires declaring the transport of user content; we declare it as unlinked because the server cannot decrypt it.
- **Other User Content** (group and channel names and descriptions, device labels, and the metadata needed to deliver messages: who is in which conversation, message and receipt times, call records): collected
  - Linked to user: Yes. The names, descriptions and labels are stored in readable form, and all of it is tied to the account.
  - Used for: App Functionality
  - Tracking: No

### Diagnostics
- **Crash Data**: not collected (the app ships no crash-reporting SDK)
- **Performance Data**: not collected
- **Other Diagnostic Data**: not collected

### Data Not Collected
- Health & Fitness
- Financial Info
- Location
- Sensitive Info
- Browsing History
- Search History
- Purchases
- Usage Data (analytics)
- Surroundings
- Body Data

## Tracking
- Does the app use data for tracking? **No**.
- No third-party SDKs receive user data for advertising or cross-app profiling.
