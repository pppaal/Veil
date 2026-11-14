# Google Play Data Safety Answers (Veil)

Use these answers when filling out the Play Console **Data safety** form. They
are the Play counterpart of `store/appstore/app-privacy-answers.md`: the two
files declare the same data, each in its own store's categories. Other
documents point here instead of repeating the table, and
`scripts/store-label-check.mjs` fails CI when the two files disagree, when the
database stores something they do not declare, or when another document says
a declared type is not collected.

Any change to what the server stores is a change to this file and to the
Play Console form, made together.

## Overview questions

- Does your app collect or share any of the required user data types? **Yes**
- Is all of the user data collected by your app encrypted in transit? **Yes**
  (TLS for every request; message payloads are also encrypted on the device
  before they leave it)
- Do you provide a way for users to request that their data is deleted?
  **Yes** (Settings → Delete account deletes the account and the server's data
  about it)

## Data types

No data is shared with third parties, so **Shared** is No for every row.
Every collected type is processed for **App functionality** only: never
advertising, analytics, personalisation or tracking.

| Data type | Collected | Shared | Optional | Purpose | What the server keeps |
| --- | --- | --- | --- | --- | --- |
| Name | No | — | — | — | No real name is asked for. The handle is a username, declared under User IDs. |
| Email address | No | — | — | — | Never asked for. |
| User IDs | Yes | No | No | App functionality | The handle and the server-generated account id. |
| Address | No | — | — | — | |
| Phone number | No | — | — | — | Never asked for. |
| Race and ethnicity | No | — | — | — | |
| Political or religious beliefs | No | — | — | — | |
| Sexual orientation | No | — | — | — | |
| Other info | No | — | — | — | |
| User payment info | No | — | — | — | |
| Purchase history | No | — | — | — | |
| Credit score | No | — | — | — | |
| Other financial info | No | — | — | — | |
| Health info | No | — | — | — | |
| Fitness info | No | — | — | — | |
| Emails | No | — | — | — | |
| SMS or MMS | No | — | — | — | |
| Other in-app messages | Yes | No | No | App functionality | Message payloads, held only as ciphertext the server cannot decrypt, and when each was sent, delivered and read. |
| Photos | Yes | No | Yes | App functionality | Photo attachments, held only as ciphertext the server cannot decrypt, until they expire. |
| Videos | Yes | No | Yes | App functionality | Video attachments, held only as ciphertext the server cannot decrypt, until they expire. |
| Voice or sound recordings | Yes | No | Yes | App functionality | Voice messages, held only as ciphertext the server cannot decrypt, until they expire. |
| Music files | No | — | — | — | |
| Other audio files | No | — | — | — | |
| Files and docs | Yes | No | Yes | App functionality | File attachments, held only as ciphertext the server cannot decrypt, until they expire. |
| Calendar events | No | — | — | — | |
| Contacts | Yes | No | No | App functionality | The in-app contact list (which accounts the user added), who is in which conversation, and call records (the conversation, the device that started the call, voice or video, status, start and end times, duration). Play's Contacts type covers social-graph information and call history. The phone's address book is never read, and the names the user gives contacts stay on the device. |
| App interactions | No | — | — | — | The app ships no analytics SDK. |
| In-app search history | No | — | — | — | Search runs on the device. |
| Installed apps | No | — | — | — | |
| Other user-generated content | Yes | No | No | App functionality | Group and channel names and descriptions and the label of each device, which the server stores readable. |
| Other actions | No | — | — | — | |
| Web browsing history | No | — | — | — | |
| Crash logs | No | — | — | — | The crash log stays on the device; the app ships no crash-reporting SDK. |
| Diagnostics | No | — | — | — | |
| Other app performance data | No | — | — | — | |
| Device or other IDs | Yes | No | No | App functionality | The server-generated id of each device and, when the app registers one, the device's push token, which the server uses only to send wake-ups that carry no message content. |
| Approximate location | No | — | — | — | |
| Precise location | No | — | — | — | |

The rows for messages, photos, videos, voice recordings and files declare
content the server holds only as ciphertext. They match the App Store answers,
which declare the encrypted payloads as user content that is not linked to the
user.
