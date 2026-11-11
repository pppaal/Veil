// Fails when a mobile locale drifts from the English template: a missing
// key falls back silently at runtime, and a missing or renamed placeholder
// makes gen_l10n emit a method whose arguments never reach the text.
import { readFileSync, readdirSync } from 'node:fs';

const l10nDir = new URL('../apps/mobile/lib/src/l10n/', import.meta.url);
const templateFile = 'app_en.arb';

const readArb = (file) => JSON.parse(readFileSync(new URL(file, l10nDir), 'utf8'));

const messageKeys = (arb) => Object.keys(arb).filter((key) => !key.startsWith('@'));

const sameSet = (a, b) => a.size === b.size && [...a].every((value) => b.has(value));

const describe = (set) => (set.size === 0 ? '(none)' : [...set].sort().join(', '));

// ICU argument names used by a message, nested plural/select cases included.
// Without `use-escaping` in l10n.yaml every brace is ICU syntax.
const argumentNames = (message) => {
  const names = new Set();
  let i = 0;

  const fail = (reason) => {
    throw new Error(`${reason} at offset ${i} in ${JSON.stringify(message)}`);
  };
  const skipWhitespace = () => {
    while (/\s/.test(message[i] ?? '')) i += 1;
  };
  const expect = (char) => {
    skipWhitespace();
    if (message[i] !== char) fail(`expected '${char}'`);
    i += 1;
  };

  // Reads message text until an unmatched '}' (nested) or the end.
  const parseText = (nested) => {
    while (i < message.length) {
      if (message[i] === '{') {
        i += 1;
        parseArgument();
      } else if (message[i] === '}') {
        if (!nested) fail("unbalanced '}'");
        return;
      } else {
        i += 1;
      }
    }
    if (nested) fail('unterminated plural or select case');
  };

  const parseArgument = () => {
    skipWhitespace();
    const name = /^[A-Za-z_][A-Za-z0-9_]*/.exec(message.slice(i));
    if (!name) fail('expected an argument name');
    names.add(name[0]);
    i += name[0].length;
    skipWhitespace();
    if (message[i] === '}') {
      i += 1;
      return;
    }
    expect(',');
    skipWhitespace();
    const type = /^[a-z]+/.exec(message.slice(i));
    if (!type) fail('expected an argument type');
    i += type[0].length;
    if (!['plural', 'select', 'selectordinal'].includes(type[0])) {
      // number/date/time with an optional style: no nested messages.
      const close = message.indexOf('}', i);
      if (close === -1) fail('unterminated argument');
      i = close + 1;
      return;
    }
    expect(',');
    for (;;) {
      skipWhitespace();
      if (message[i] === '}') {
        i += 1;
        return;
      }
      const selector = /^[^\s{}]+/.exec(message.slice(i));
      if (!selector) fail('expected a case selector');
      i += selector[0].length;
      if (selector[0].startsWith('offset:')) continue;
      expect('{');
      parseText(true);
      i += 1;
    }
  };

  parseText(false);
  return names;
};

const declaredPlaceholders = (arb, key) => new Set(Object.keys(arb[`@${key}`]?.placeholders ?? {}));

const failures = [];
const template = readArb(templateFile);
const templateKeys = new Set(messageKeys(template));
const locales = readdirSync(l10nDir).filter(
  (file) => /^app_[A-Za-z_]+\.arb$/.test(file) && file !== templateFile,
);

if (locales.length === 0) {
  failures.push('no locale ARB files found next to the template');
}

for (const file of locales) {
  const locale = readArb(file);
  const localeKeys = new Set(messageKeys(locale));

  for (const key of templateKeys) {
    if (!localeKeys.has(key)) failures.push(`${file}: missing key ${key}`);
  }
  for (const key of localeKeys) {
    if (!templateKeys.has(key)) failures.push(`${file}: key ${key} is not in ${templateFile}`);
  }

  for (const key of templateKeys) {
    if (!localeKeys.has(key)) continue;
    try {
      const expected = argumentNames(template[key]);
      const actual = argumentNames(locale[key]);
      if (!sameSet(expected, actual)) {
        failures.push(
          `${file}: ${key} uses placeholders ${describe(actual)}, template uses ${describe(expected)}`,
        );
      }
    } catch (error) {
      failures.push(`${file}: ${key}: ${error.message}`);
    }
    // A locale may omit metadata (gen_l10n reads it from the template), but
    // metadata it does declare must name the same placeholders.
    if (locale[`@${key}`]?.placeholders) {
      const expected = declaredPlaceholders(template, key);
      const actual = declaredPlaceholders(locale, key);
      if (!sameSet(expected, actual)) {
        failures.push(
          `${file}: @${key} declares ${describe(actual)}, template declares ${describe(expected)}`,
        );
      }
    }
  }
}

if (failures.length > 0) {
  console.error('ARB parity check failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log(
  `ARB parity check passed: ${templateKeys.size} keys in ${templateFile} matched by ${locales.join(', ')}.`,
);
