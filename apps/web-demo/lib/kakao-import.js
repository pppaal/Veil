// Pure parser for KakaoTalk-exported chat .txt files. Korean-market
// killer feature: lets a user pull their existing 카톡 history into
// VEIL as a read-only archive without ever uploading the bytes to a
// server (entire flow is in-browser; the file never leaves the
// device).
//
// Format reference (KakaoTalk Android export, current as of 2026):
//
//   [홍길동] [2024. 3. 15. 오후 2:34] 안녕하세요
//   [김철수] [2024. 3. 15. 오후 2:35] 네 반갑습니다
//   2024년 3월 16일 토요일
//   [홍길동] [2024. 3. 16. 오전 10:00] 토요일이네요
//
// macOS / iOS exports use slightly different delimiters; we tolerate
// both. System lines (date dividers, "님이 들어왔습니다", etc) are
// preserved as 'system' kind so the UI can render them differently.

const MSG_RE_ANDROID =
  /^\[([^\]]+)\] \[([^\]]+)\] (.*)$/;
const MSG_RE_IOS_MAC =
  /^(\d{4}\. \d{1,2}\. \d{1,2}\. (?:오전|오후) \d{1,2}:\d{2}), ([^:]+) : (.*)$/;
const DATE_DIVIDER_RE =
  /^-+\s*(\d{4})년 (\d{1,2})월 (\d{1,2})일\s*(?:[가-힣]+요일)?\s*-+\s*$/;

function parseKakaoTimestamp(raw) {
  // "2024. 3. 15. 오후 2:34" → Date
  const m = raw.match(/^(\d{4})\.\s*(\d{1,2})\.\s*(\d{1,2})\.\s*(오전|오후)\s*(\d{1,2}):(\d{2})$/);
  if (!m) return null;
  const [, y, mo, d, ampm, h, mi] = m;
  let hour = Number(h);
  if (ampm === '오후' && hour < 12) hour += 12;
  if (ampm === '오전' && hour === 12) hour = 0;
  return new Date(Number(y), Number(mo) - 1, Number(d), hour, Number(mi));
}

export function parseKakaoExport(text) {
  if (typeof text !== 'string' || text.length === 0) {
    return { participants: [], messages: [], errors: ['empty input'] };
  }
  const lines = text.split(/\r?\n/);
  const messages = [];
  const errors = [];
  const participantSet = new Set();
  let pendingDate = null;
  let lastMsg = null;

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (line.trim() === '') continue;

    // Date divider line — reset the pending day. We don't emit a
    // synthetic message; the UI uses serverReceivedAt to draw its own
    // dividers.
    const div = line.match(DATE_DIVIDER_RE);
    if (div) { pendingDate = `${div[1]}-${div[2]}-${div[3]}`; continue; }

    // Android format: [name] [time] body
    const a = line.match(MSG_RE_ANDROID);
    if (a) {
      const [, name, ts, body] = a;
      const date = parseKakaoTimestamp(ts);
      if (!date) { errors.push(`unparsed ts on line ${i + 1}: ${ts}`); continue; }
      participantSet.add(name);
      lastMsg = {
        kind: 'msg',
        sender: name,
        sentAt: date.toISOString(),
        body,
      };
      messages.push(lastMsg);
      continue;
    }

    // iOS / macOS format: time, name : body
    const im = line.match(MSG_RE_IOS_MAC);
    if (im) {
      const [, ts, name, body] = im;
      const date = parseKakaoTimestamp(ts);
      if (!date) { errors.push(`unparsed ts on line ${i + 1}: ${ts}`); continue; }
      participantSet.add(name.trim());
      lastMsg = {
        kind: 'msg',
        sender: name.trim(),
        sentAt: date.toISOString(),
        body,
      };
      messages.push(lastMsg);
      continue;
    }

    // Continuation line for a multi-line message — KakaoTalk wraps
    // long messages onto subsequent lines without a [name][ts]
    // prefix. Append to the most recent message.
    if (lastMsg && lastMsg.kind === 'msg') {
      lastMsg.body = lastMsg.body + '\n' + line;
      continue;
    }

    // Header lines (KakaoTalk 대화 저장…), system messages without a
    // recognizable shape — record but don't error.
    messages.push({ kind: 'system', body: line });
    lastMsg = null;
  }

  return {
    participants: Array.from(participantSet),
    messages,
    errors,
    pendingDate,
  };
}
