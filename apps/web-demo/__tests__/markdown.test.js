import { describe, it, expect } from 'vitest';
import { escapeHtml, renderMessageInline } from '../lib/markdown.js';

describe('escapeHtml', () => {
  it('escapes the standard HTML metacharacters', () => {
    expect(escapeHtml('<script>alert("x")</script>')).toBe(
      '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;',
    );
  });

  it('preserves non-ascii and emoji', () => {
    expect(escapeHtml('한국어 🔒 ok')).toBe('한국어 🔒 ok');
  });

  it('handles null / undefined / numbers without crashing', () => {
    expect(escapeHtml(null)).toBe('');
    expect(escapeHtml(undefined)).toBe('');
    expect(escapeHtml(42)).toBe('42');
  });
});

describe('renderMessageInline — markdown', () => {
  it('renders bold', () => {
    expect(renderMessageInline('hello *world*')).toBe('hello <strong>world</strong>');
  });

  it('renders italic with required leading boundary', () => {
    expect(renderMessageInline('hi _there_')).toBe('hi <em>there</em>');
  });

  it('does NOT mark snake_case identifiers as italic', () => {
    expect(renderMessageInline('use my_var here')).toBe('use my_var here');
  });

  it('renders inline code', () => {
    expect(renderMessageInline('run `pnpm test`')).toBe(
      'run <code>pnpm test</code>',
    );
  });

  it('handles bold + code together', () => {
    expect(renderMessageInline('`code` and *bold*')).toBe(
      '<code>code</code> and <strong>bold</strong>',
    );
  });
});

describe('renderMessageInline — URL auto-link', () => {
  it('linkifies http and https URLs', () => {
    expect(renderMessageInline('see https://example.com today')).toContain(
      '<a href="https://example.com" target="_blank" rel="noopener noreferrer">https://example.com</a>',
    );
  });

  it('does NOT linkify javascript: pseudo-URLs', () => {
    const out = renderMessageInline('click javascript:alert(1)');
    expect(out).not.toContain('href="javascript:');
  });

  it('does NOT linkify data: URIs', () => {
    const out = renderMessageInline('img data:image/png;base64,XXX');
    expect(out).not.toContain('href="data:');
  });
});

describe('renderMessageInline — mentions', () => {
  it('renders @mentions matching the server handle shape', () => {
    expect(renderMessageInline('hi @alice and @bob_42')).toContain(
      '<span class="mention">@alice</span>',
    );
    expect(renderMessageInline('hi @alice and @bob_42')).toContain(
      '<span class="mention">@bob_42</span>',
    );
  });

  it('does not chip handles shorter than 3 chars', () => {
    expect(renderMessageInline('@ab is too short')).not.toContain('class="mention"');
  });

  it('does not chip uppercase handles (server rejects them)', () => {
    expect(renderMessageInline('@Alice')).not.toContain('class="mention"');
  });
});

describe('renderMessageInline — defense in depth', () => {
  it('escapes HTML in the input before applying any markdown', () => {
    const out = renderMessageInline('<img src=x onerror=alert(1)>');
    expect(out).not.toContain('<img');
    expect(out).toContain('&lt;img');
  });

  it('treats bare ampersands inside markdown as text', () => {
    expect(renderMessageInline('A & B *bold*')).toBe(
      'A &amp; B <strong>bold</strong>',
    );
  });
});
