// What a seized VEIL server reveals, checked in CI.
//
// Every stored field in apps/api/prisma/schema.prisma carries
//   /// @privacy(class=..., retention=..., visibleTo=...)
// This gate fails when a field is unannotated, when a field whose name says
// it holds user-written text is stored as anything but ciphertext (unless
// allowlisted below with a reason), or when a field has a timed retention
// that no RetentionService sweep enforces. It also renders the annotations
// as docs/server-data-inventory.md:
//   node scripts/schema-privacy-check.mjs           check the schema
//   node scripts/schema-privacy-check.mjs --check   ...and that the inventory is current
//   node scripts/schema-privacy-check.mjs --write   ...and regenerate the inventory
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const SCHEMA_PATH = 'apps/api/prisma/schema.prisma';
export const RETENTION_SERVICE_PATH = 'apps/api/src/modules/retention/retention.service.ts';
export const INVENTORY_PATH = 'docs/server-data-inventory.md';

export const PRIVACY_CLASSES = ['ciphertext', 'routing', 'operational', 'public', 'secret-hash'];
export const VISIBILITIES = ['self', 'members', 'server', 'public'];
const DURATION = /^(\d+)(s|m|h|d)$/;

// Words that mark a field as user-written content when they are its head
// noun, the last word of the name: displayName and statusMessage hold text,
// messageId and clientMessageId hold identifiers. A String or Json field
// named this way must be ciphertext.
export const PLAINTEXT_NAME_WORDS = [
  'body',
  'text',
  'caption',
  'bio',
  'status',
  'note',
  'nickname',
  'name',
  'emoji',
  'message',
  'title',
  'description',
  'url',
];

// Plaintext the server still stores on purpose, each with the reason. An
// entry that no longer matches a plaintext-named field fails the gate, so the
// list cannot outlive what it excuses.
export const PLAINTEXT_ALLOWLIST = {
  'GroupMeta.name': 'encrypted group metadata deferred',
  'GroupMeta.description': 'encrypted group metadata deferred',
  'ChannelMeta.name': 'encrypted group metadata deferred',
  'ChannelMeta.description': 'encrypted group metadata deferred',
  'Device.deviceName':
    "device label for the account's own device list, never shown to other users; encrypting it is deferred with encrypted profiles",
};

const TEXT_TYPES = new Set(['String', 'Json']);

const headNoun = (fieldName) =>
  fieldName
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .toLowerCase()
    .split(/[\s_]+/)
    .filter(Boolean)
    .at(-1);

const parseAnnotation = (text) => {
  const match = /@privacy\(([^)]*)\)/.exec(text);
  if (!match) return null;
  const pairs = match[1]
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => part.split('=').map((piece) => piece.trim()));
  return Object.fromEntries(pairs);
};

/**
 * Models with their stored fields and annotations. Relation fields (typed as
 * another model) store nothing and are skipped; every other field is a column.
 */
export function parseSchema(source) {
  const lines = source.split('\n');
  const blocks = [];
  let current = null;
  for (const [index, line] of lines.entries()) {
    const opened = /^(model|enum)\s+(\w+)\s*\{/.exec(line);
    if (opened) {
      current = { kind: opened[1], name: opened[2], start: index, lines: [] };
      continue;
    }
    if (current && /^\}/.test(line)) {
      blocks.push(current);
      current = null;
      continue;
    }
    current?.lines.push({ text: line, number: index + 1 });
  }

  const modelNames = new Set(
    blocks.filter((block) => block.kind === 'model').map((block) => block.name),
  );

  return blocks
    .filter((block) => block.kind === 'model')
    .map((block) => {
      let pendingComments = [];
      const fields = [];
      let table = block.name;
      for (const { text, number } of block.lines) {
        const trimmed = text.trim();
        if (trimmed.startsWith('//')) {
          pendingComments.push(trimmed);
          continue;
        }
        if (trimmed === '') {
          pendingComments = [];
          continue;
        }
        const mapped = /^@@map\(\s*"([^"]+)"\s*\)/.exec(trimmed);
        if (mapped) table = mapped[1];
        const field = /^(\w+)\s+(\w+)(\[\])?(\?)?/.exec(trimmed);
        if (!field || trimmed.startsWith('@@')) {
          pendingComments = [];
          continue;
        }
        const [, name, type] = field;
        const comments = pendingComments;
        pendingComments = [];
        if (modelNames.has(type)) continue;
        const annotationLine = comments.find(
          (comment) => comment.startsWith('///') && comment.includes('@privacy'),
        );
        fields.push({
          name,
          type,
          column: /@map\(\s*"([^"]+)"\s*\)/.exec(trimmed)?.[1] ?? name,
          annotation: annotationLine ? parseAnnotation(annotationLine) : null,
          line: number,
        });
      }
      return { name: block.name, table, fields };
    });
}

/** Models RetentionService sweeps, from its `// @retention-sweep <Model>` markers. */
export const sweptModels = (retentionSource) =>
  new Set([...retentionSource.matchAll(/\/\/\s*@retention-sweep\s+(\w+)/g)].map((m) => m[1]));

export function checkSchemaPrivacy({
  schemaSource,
  retentionSource,
  allowlist = PLAINTEXT_ALLOWLIST,
}) {
  const failures = [];
  const models = parseSchema(schemaSource);
  const swept = sweptModels(retentionSource);
  const allowlistUsed = new Set();
  const modelNames = new Set(models.map((model) => model.name));

  for (const model of models) {
    let timed = false;
    for (const field of model.fields) {
      const where = `${model.name}.${field.name} (schema.prisma:${field.line})`;
      if (!field.annotation) {
        failures.push(`${where}: unannotated field; add /// @privacy(class, retention, visibleTo)`);
        continue;
      }
      const { class: privacyClass, retention, visibleTo, ...unknown } = field.annotation;
      if (Object.keys(unknown).length > 0) {
        failures.push(`${where}: unknown @privacy keys ${Object.keys(unknown).join(', ')}`);
      }
      if (!PRIVACY_CLASSES.includes(privacyClass)) {
        failures.push(`${where}: class must be one of ${PRIVACY_CLASSES.join('|')}`);
      }
      if (!VISIBILITIES.includes(visibleTo)) {
        failures.push(`${where}: visibleTo must be one of ${VISIBILITIES.join('|')}`);
      }
      if (!retention || !(DURATION.test(retention) || ['account', 'forever'].includes(retention))) {
        failures.push(`${where}: retention must be <n>s|m|h|d, account or forever`);
      }
      if (retention && DURATION.test(retention)) {
        timed = true;
      }

      const key = `${model.name}.${field.name}`;
      const plaintextNamed = PLAINTEXT_NAME_WORDS.includes(headNoun(field.name));
      if (plaintextNamed && TEXT_TYPES.has(field.type) && privacyClass !== 'ciphertext') {
        if (allowlist[key]) {
          allowlistUsed.add(key);
        } else {
          failures.push(
            `${where}: plaintext-named ${field.type} field is not ciphertext; encrypt it or allowlist it with a reason`,
          );
        }
      }
    }
    if (timed && !swept.has(model.name)) {
      failures.push(
        `${model.name}: a field has a timed retention but RetentionService has no "// @retention-sweep ${model.name}" marker`,
      );
    }
  }

  for (const key of Object.keys(allowlist)) {
    if (!allowlistUsed.has(key)) {
      failures.push(`allowlist entry ${key} no longer matches a stored plaintext-named field`);
    }
  }
  for (const model of swept) {
    if (!modelNames.has(model)) {
      failures.push(`RetentionService marks a sweep for unknown model ${model}`);
    }
  }
  return { failures, models };
}

const CLASS_MEANING = {
  ciphertext: 'encrypted on the client; the server cannot read it',
  routing: 'identifiers the server needs to route, authorize and link rows',
  operational: 'timestamps, flags, counters and states the service runs on',
  public: 'meant to be seen by other users: handles, public keys, channel names',
  'secret-hash': 'a hash or keyed hash of a secret; the secret itself is not stored',
};

const VISIBILITY_MEANING = {
  self: 'returned only to the account it belongs to',
  members: 'returned to the members of the conversation, story audience or call',
  server: 'never returned by the API',
  public: 'returned to any signed-in user (and, for one-time secret links, to the link holder)',
};

const retentionText = (retention) => {
  const match = DURATION.exec(retention);
  if (!match) return retention === 'account' ? 'account lifetime' : 'forever';
  const units = { s: 'seconds', m: 'minutes', h: 'hours', d: 'days' };
  return `${match[1]} ${units[match[2]]}`;
};

export function renderInventory(models, allowlist = PLAINTEXT_ALLOWLIST) {
  const fields = models.flatMap((model) => model.fields.map((field) => ({ model, field })));
  const count = (predicate) => fields.filter(predicate).length;
  const out = [];
  out.push('# What a seized VEIL server reveals');
  out.push('');
  out.push(
    '<!-- Generated by `node scripts/schema-privacy-check.mjs --write` from the',
    '     @privacy annotations in apps/api/prisma/schema.prisma. Do not edit by',
    '     hand: CI fails when this file is out of date. -->',
  );
  out.push('');
  out.push(
    'This is every field the VEIL server stores in its database, what kind of',
    'data it is, how long it is kept and who the API shows it to. It is what',
    'someone who seizes or breaches the database gets. Message, story and',
    'one-time-link content is ciphertext the server cannot read; everything',
    'else below is metadata the server needs to deliver it. The production stack',
    'keeps no database dumps or snapshots. Deleting a row does not wipe it from',
    'the disk, though: Postgres leaves the bytes of deleted rows, burned one-time',
    'links among them, in write-ahead-log segments and in table and index pages',
    'until it happens to reuse that space, which follows no schedule and on a',
    'quiet server can take days. A seized database volume can therefore also',
    'hold rows that were deleted or swept before the seizure, and whoever has',
    'both the volume and a burned one-time link can still decrypt that link.',
    'The caveat is spelled out under "No database backups" in',
    '[metadata-retention.md](metadata-retention.md).',
  );
  out.push('');
  out.push(
    'Retention is counted from the event that starts the clock (a message reaching',
    'the server, a prekey being consumed, an account being deleted); the sweeps',
    'that enforce it are described in [metadata-retention.md](metadata-retention.md).',
    'Redis keys (rate-limit counters keyed by client address or device,',
    'key-directory budgets, auth challenges, refresh-token hashes with their user',
    'and device ids and a day-rounded expiry of up to 31 days, sealed group key',
    'distributions) and encrypted attachment blobs in object storage are not',
    'database fields and are covered there too.',
  );
  out.push('');
  out.push('## Classes');
  out.push('');
  out.push('| Class | Meaning | Fields |');
  out.push('| --- | --- | --- |');
  for (const privacyClass of PRIVACY_CLASSES) {
    out.push(
      `| \`${privacyClass}\` | ${CLASS_MEANING[privacyClass]} | ${count(({ field }) => field.annotation.class === privacyClass)} |`,
    );
  }
  out.push('');
  out.push('| Visible to | Meaning |');
  out.push('| --- | --- |');
  for (const visibility of VISIBILITIES) {
    out.push(`| \`${visibility}\` | ${VISIBILITY_MEANING[visibility]} |`);
  }
  out.push('');
  out.push('## Plaintext the server can read');
  out.push('');
  out.push(
    'Fields named like user-written text that are not ciphertext. Each one is',
    'allowlisted in `scripts/schema-privacy-check.mjs` with its reason; any other',
    'such field fails CI.',
  );
  out.push('');
  out.push('| Field | Reason |');
  out.push('| --- | --- |');
  for (const [key, reason] of Object.entries(allowlist)) {
    out.push(`| \`${key}\` | ${reason} |`);
  }
  out.push('');
  out.push('## Tables');
  for (const model of models) {
    out.push('');
    out.push(`### \`${model.table}\` (${model.name})`);
    out.push('');
    out.push('| Field | Column | Class | Retention | Visible to |');
    out.push('| --- | --- | --- | --- | --- |');
    for (const field of model.fields) {
      const { class: privacyClass, retention, visibleTo } = field.annotation;
      out.push(
        `| \`${field.name}\` | \`${field.column}\` | ${privacyClass} | ${retentionText(retention)} | ${visibleTo} |`,
      );
    }
  }
  out.push('');
  return out.join('\n');
}

const invokedDirectly = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;

if (invokedDirectly) {
  const root = fileURLToPath(new URL('..', import.meta.url));
  const read = (path) => readFileSync(`${root}${path}`, 'utf8');
  const { failures, models } = checkSchemaPrivacy({
    schemaSource: read(SCHEMA_PATH),
    retentionSource: read(RETENTION_SERVICE_PATH),
  });
  if (failures.length > 0) {
    console.error('Schema privacy check failed:');
    for (const failure of failures) console.error(`  ${failure}`);
    process.exit(1);
  }

  const inventory = renderInventory(models);
  if (process.argv.includes('--write')) {
    writeFileSync(`${root}${INVENTORY_PATH}`, inventory);
    console.log(`Wrote ${INVENTORY_PATH}.`);
  } else if (process.argv.includes('--check')) {
    let current = null;
    try {
      current = read(INVENTORY_PATH);
    } catch {
      // A missing inventory is reported as stale below.
    }
    if (current !== inventory) {
      console.error(
        `${INVENTORY_PATH} is stale; run node scripts/schema-privacy-check.mjs --write and commit it.`,
      );
      process.exit(1);
    }
  }
  const fieldCount = models.reduce((total, model) => total + model.fields.length, 0);
  console.log(`Schema privacy check passed (${fieldCount} fields in ${models.length} models).`);
}
