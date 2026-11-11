import { describe, expect, it } from 'vitest';

import { toFragment, toHtmlString, tokenize } from '../src/ui/markdown-dom.js';

// Minimal document double: records what toFragment builds so the test can
// inspect tags, attributes and text without a browser.
class FakeNode {
  constructor(nodeName, text = null) {
    this.nodeName = nodeName;
    this.text = text;
    this.attributes = new Map();
    this.childNodes = [];
  }

  setAttribute(name, value) { this.attributes.set(name, String(value)); }

  appendChild(child) {
    if (child.nodeName === '#fragment') this.childNodes.push(...child.childNodes);
    else this.childNodes.push(child);
    return child;
  }

  get textContent() {
    return this.text ?? this.childNodes.map((child) => child.textContent).join('');
  }
}

const fakeDocument = {
  createDocumentFragment: () => new FakeNode('#fragment'),
  createElement: (tag) => new FakeNode(tag.toUpperCase()),
  createTextNode: (text) => new FakeNode('#text', String(text)),
};

function elements(node, out = []) {
  for (const child of node.childNodes) {
    if (child.nodeName !== '#text') {
      out.push(child);
      elements(child, out);
    }
  }
  return out;
}

const render = (text) => toFragment(text, fakeDocument);
const anchors = (text) => elements(render(text)).filter((node) => node.nodeName === 'A');

const ALLOWED_TAGS = new Set(['A', 'CODE', 'PRE', 'STRONG', 'EM', 'SPAN']);
const ALLOWED_ATTRIBUTES = new Set(['href', 'rel', 'target', 'referrerpolicy', 'class', 'data-lang']);

function assertSafeTree(fragment) {
  for (const node of elements(fragment)) {
    expect(ALLOWED_TAGS.has(node.nodeName)).toBe(true);
    for (const name of node.attributes.keys()) expect(ALLOWED_ATTRIBUTES.has(name)).toBe(true);
    if (node.nodeName === 'SPAN') expect(node.attributes.get('class')).toBe('mention');
    if (node.nodeName === 'PRE') expect(node.attributes.get('class')).toBe('msg-codeblock');
    if (node.attributes.has('class') && !['SPAN', 'PRE'].includes(node.nodeName)) throw new Error(`class on ${node.nodeName}`);
    if (node.nodeName === 'A') {
      const href = new URL(node.attributes.get('href'));
      expect(['http:', 'https:']).toContain(href.protocol);
      expect(node.attributes.get('rel')).toBe('noopener noreferrer');
      expect(node.attributes.get('target')).toBe('_blank');
      expect(node.attributes.get('referrerpolicy')).toBe('no-referrer');
    } else {
      for (const name of ['href', 'rel', 'target', 'referrerpolicy']) expect(node.attributes.has(name)).toBe(false);
    }
  }
}

function assertSafeHtml(html) {
  for (const [, , tag, attributeText] of html.matchAll(/<(\/?)([a-zA-Z0-9-]+)([^>]*)>/g)) {
    expect(['a', 'code', 'pre', 'strong', 'em', 'span']).toContain(tag);
    for (const [, name] of attributeText.matchAll(/\s([a-zA-Z-]+)="/g)) expect(ALLOWED_ATTRIBUTES.has(name)).toBe(true);
  }
}

// Deterministic PRNG so a failing fuzz case reproduces.
function mulberry32(seed) {
  let a = seed;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const FUZZ_PIECES = [
  '*', '_', '`', '```', '```js\n', '\n', ' ', '@', '@alice', '@ab', '@bob_smith', 'https://', 'https://evil.example/?@alice',
  'http://a.example/*b*c', 'javascript:alert(1)', 'data:text/html,<b>x</b>', '<script>alert(1)</script>', '<img src=x onerror=alert(1)>',
  '"', "'", '\u0000', '\u0000FENCE0\u0000', '&amp;', '](', ')', '(', 'text', '한국어', '🔥', '\u202e', '" onmouseover="x', '<a href=',
  '>', '<', 'https://x.example/"onclick="y', 'HTTPS://UPPER.EXAMPLE', 'https://a.example/path_(x)', '*bold*', '_em_', '`code`',
];

describe('markdown-dom', () => {
  it('renders the supported constructs', () => {
    expect(toHtmlString('hello *world*')).toBe('hello <strong>world</strong>');
    expect(toHtmlString('hi _there_')).toBe('hi <em>there</em>');
    expect(toHtmlString('use my_var here')).toBe('use my_var here');
    expect(toHtmlString('run `pnpm test`')).toBe('run <code>pnpm test</code>');
    expect(toHtmlString('```ts\nconst a = 1;\n```')).toBe('<pre class="msg-codeblock" data-lang="ts"><code>const a = 1;</code></pre>');
    expect(toHtmlString('hey @alice!')).toBe('hey <span class="mention">@alice</span>!');
    expect(toHtmlString('see https://example.com.')).toBe(
      'see <a href="https://example.com/" target="_blank" rel="noopener noreferrer" referrerpolicy="no-referrer">https://example.com</a>.',
    );
    expect(toHtmlString('*see `a*b` ok*')).toBe('<strong>see <code>a*b</code> ok</strong>');
  });

  it('mention inside URL keeps one anchor with noreferrer', () => {
    const links = anchors('https://evil.example/?@alice');
    expect(links).toHaveLength(1);
    expect(links[0].attributes.get('href')).toBe('https://evil.example/?@alice');
    expect(links[0].attributes.get('rel')).toContain('noreferrer');
    expect(links[0].attributes.get('referrerpolicy')).toBe('no-referrer');
    expect(links[0].attributes.get('target')).toBe('_blank');
    expect(elements(render('https://evil.example/?@alice')).some((node) => node.nodeName === 'SPAN')).toBe(false);
    expect(toHtmlString('https://evil.example/?@alice')).toBe(
      '<a href="https://evil.example/?@alice" target="_blank" rel="noopener noreferrer" referrerpolicy="no-referrer">https://evil.example/?@alice</a>',
    );
  });

  it('NUL input never renders undefined', () => {
    for (const input of ['a \u0000FENCE0\u0000 b', '\u0000FENCE0\u0000', '```\nx\n``` \u0000FENCE1\u0000', '\u0000 FENCE0 \u0000']) {
      expect(toHtmlString(input)).not.toContain('undefined');
      expect(render(input).textContent).not.toContain('undefined');
    }
    expect(render('a \u0000FENCE0\u0000 b').textContent).toBe('a \u0000FENCE0\u0000 b');
  });

  it('asterisk inside URL keeps link', () => {
    const links = anchors('https://a.example/*b*c');
    expect(links).toHaveLength(1);
    expect(links[0].attributes.get('href')).toBe('https://a.example/*b*c');
    expect(links[0].textContent).toBe('https://a.example/*b*c');
    expect(elements(render('https://a.example/*b*c')).some((node) => node.nodeName === 'STRONG')).toBe(false);
  });

  it('never links non-http schemes', () => {
    for (const input of ['javascript:alert(1)', 'data:text/html,<b>', 'vbscript:x', 'file:///etc/passwd', 'xhttps://a.example']) {
      expect(anchors(input)).toHaveLength(0);
    }
  });

  it('builds text nodes only, so markup in messages stays text', () => {
    const fragment = render('<img src=x onerror=alert(1)> "quoted" *b*');
    assertSafeTree(fragment);
    expect(fragment.textContent).toBe('<img src=x onerror=alert(1)> "quoted" b');
    expect(toHtmlString('<script>alert("x")</script>')).toBe('&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;');
  });

  it('tokenizes fences before inline syntax', () => {
    expect(tokenize('```\n*not bold* @alice\n```')).toEqual([{ type: 'pre', lang: '', text: '*not bold* @alice' }]);
  });

  it('takes a language tag only from an opening line of its own', () => {
    expect(tokenize('```\n```')).toEqual([{ type: 'pre', lang: '', text: '' }]);
    expect(tokenize('```word```')).toEqual([{ type: 'pre', lang: '', text: 'word' }]);
    expect(tokenize('```js code```')).toEqual([{ type: 'pre', lang: '', text: 'js code' }]);
    expect(tokenize('```ts\nx\n```')).toEqual([{ type: 'pre', lang: 'ts', text: 'x' }]);
  });

  it('fuzz: 500 seeded inputs only produce allowed elements and attributes', () => {
    const random = mulberry32(0x5eed);
    for (let i = 0; i < 500; i += 1) {
      const length = 1 + Math.floor(random() * 30);
      let input = '';
      for (let j = 0; j < length; j += 1) input += FUZZ_PIECES[Math.floor(random() * FUZZ_PIECES.length)];
      assertSafeTree(render(input));
      const html = toHtmlString(input);
      assertSafeHtml(html);
      expect(html).not.toContain('undefined');
    }
  });
});
