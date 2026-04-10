/**
 * Node tests for the Markdown subset renderer.
 *
 * Uses Node's built-in node:test module (available since Node 18) so there
 * are no external dependencies. Run with:
 *
 *   node --test test/js/renderMarkdown.test.js
 *
 * The module under test lives in ms.gateway/www/js/markdown.js and exposes
 * { renderMarkdown, applyInline, mdEsc } via CommonJS when loaded from Node.
 */
const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const { renderMarkdown, applyInline, mdEsc } = require(
  path.resolve(__dirname, '..', '..', 'ms.gateway', 'www', 'js', 'markdown.js')
);

// --- mdEsc: low-level HTML escape ---

test('mdEsc escapes all five HTML-significant characters', () => {
  assert.strictEqual(mdEsc('<script>alert("x&y")</script>'),
    '&lt;script&gt;alert(&quot;x&amp;y&quot;)&lt;/script&gt;');
});

test('mdEsc escapes single quotes', () => {
  assert.strictEqual(mdEsc("it's"), 'it&#39;s');
});

test('mdEsc returns empty string on empty input', () => {
  assert.strictEqual(mdEsc(''), '');
  assert.strictEqual(mdEsc(null), '');
  assert.strictEqual(mdEsc(undefined), '');
});

// --- renderMarkdown: escape-first guarantee ---

test('renderMarkdown escapes raw HTML in plain paragraphs', () => {
  const out = renderMarkdown('<script>alert(1)</script>');
  assert.ok(out.includes('&lt;script&gt;'), 'angle brackets must be escaped');
  assert.ok(!out.includes('<script>'), 'raw <script> must not survive');
});

test('renderMarkdown wraps a single line in a <p>', () => {
  assert.strictEqual(renderMarkdown('hello world'), '<p>hello world</p>');
});

test('renderMarkdown produces one paragraph per blank-line separated block', () => {
  const out = renderMarkdown('first line\n\nsecond line');
  assert.strictEqual(out, '<p>first line</p>\n<p>second line</p>');
});

test('renderMarkdown joins consecutive non-blank lines with a space', () => {
  const out = renderMarkdown('line one\nline two');
  assert.strictEqual(out, '<p>line one line two</p>');
});

test('renderMarkdown returns empty string on empty or null input', () => {
  assert.strictEqual(renderMarkdown(''), '');
  assert.strictEqual(renderMarkdown(null), '');
  assert.strictEqual(renderMarkdown(undefined), '');
});

// --- Headings h1 to h6 ---

test('renderMarkdown converts # through ###### to h1-h6', () => {
  for (let level = 1; level <= 6; level++) {
    const hashes = '#'.repeat(level);
    const out = renderMarkdown(`${hashes} Title ${level}`);
    assert.strictEqual(out, `<h${level}>Title ${level}</h${level}>`);
  }
});

test('renderMarkdown does not treat ####### as a heading (7 hashes is too many)', () => {
  const out = renderMarkdown('####### still a paragraph');
  assert.ok(out.startsWith('<p>'), 'seven hashes must fall through to paragraph');
  assert.ok(!out.includes('<h7>'));
});

test('renderMarkdown requires a space after the hashes', () => {
  const out = renderMarkdown('#NotAHeading');
  assert.ok(out.startsWith('<p>'), 'hash without space must not be a heading');
});

test('renderMarkdown escapes HTML inside heading text', () => {
  const out = renderMarkdown('# <b>bad</b>');
  assert.strictEqual(out, '<h1>&lt;b&gt;bad&lt;/b&gt;</h1>');
});

// --- Bold and italic ---

test('renderMarkdown renders **bold**', () => {
  assert.strictEqual(renderMarkdown('a **bold** word'),
    '<p>a <strong>bold</strong> word</p>');
});

test('renderMarkdown renders *italic*', () => {
  assert.strictEqual(renderMarkdown('a *slanted* word'),
    '<p>a <em>slanted</em> word</p>');
});

test('renderMarkdown handles bold and italic in the same paragraph', () => {
  const out = renderMarkdown('**strong** and *weak*');
  assert.ok(out.includes('<strong>strong</strong>'));
  assert.ok(out.includes('<em>weak</em>'));
});

test('renderMarkdown keeps single asterisks that are not inline markers', () => {
  // A stray '*' with no closing marker must not become <em>.
  const out = renderMarkdown('5 * 7 = 35');
  assert.ok(!out.includes('<em>'), 'standalone asterisk must not open an em tag');
});

// --- Image whitelisting ---

test('renderMarkdown converts ![alt](/media/42) to an <img>', () => {
  const out = renderMarkdown('![A caption](/media/42)');
  assert.ok(out.includes('<img src="/media/42"'));
  assert.ok(out.includes('alt="A caption"'));
  assert.ok(out.includes('class="md-img"'));
});

test('renderMarkdown rejects third-party image URLs', () => {
  // Only /media/NN is allowed. An http(s) URL must fall through as escaped text.
  const raw = '![x](https://evil.example/cookie.png)';
  const out = renderMarkdown(raw);
  assert.ok(!out.includes('<img'), 'external URL must not produce an <img>');
  assert.ok(out.includes('https://evil.example'),
    'the URL must appear as escaped text, not become src');
});

test('renderMarkdown rejects javascript: URLs in images', () => {
  const out = renderMarkdown('![x](javascript:alert(1))');
  assert.ok(!out.includes('<img'));
  assert.ok(!out.includes('javascript:alert(1)'.replace('(', '')),
    'javascript: URL must not land in an href or src');
});

test('renderMarkdown rejects /media/ without a numeric id', () => {
  const out = renderMarkdown('![x](/media/abc)');
  assert.ok(!out.includes('<img'), 'non-numeric id must not match the image regex');
});

test('renderMarkdown escapes HTML inside image alt text', () => {
  const out = renderMarkdown('![<b>bad</b>](/media/7)');
  // The alt text ran through mdEsc first, so the tag must be entity-escaped by
  // the time it lands in the alt attribute. The raw <b> must not appear.
  assert.ok(!out.includes('<b>bad</b>'));
  assert.ok(out.includes('alt="&lt;b&gt;bad&lt;/b&gt;"'));
});

// --- Combined / structural ---

test('renderMarkdown handles a full document with heading, paragraph and image', () => {
  const src = [
    '# Welcome',
    '',
    'This is a **demo** of the renderer.',
    '',
    '![cover](/media/1)',
    '',
    '## Details',
    '',
    'Some *italic* closing text.'
  ].join('\n');
  const out = renderMarkdown(src);
  assert.ok(out.includes('<h1>Welcome</h1>'));
  assert.ok(out.includes('<strong>demo</strong>'));
  assert.ok(out.includes('<img src="/media/1"'));
  assert.ok(out.includes('<h2>Details</h2>'));
  assert.ok(out.includes('<em>italic</em>'));
});

test('renderMarkdown never produces a tag outside the whitelist', () => {
  // Pick a nasty input that tries every angle of attack at once.
  const src = 'plain <iframe src=x> **<img src=x onerror=alert(1)>** end';
  const out = renderMarkdown(src);
  // The only allowed tags from this renderer are p, h1-h6, strong, em, img(md-img).
  // iframe and raw img must not appear as real tags.
  assert.ok(!/<iframe\b/i.test(out), 'iframe must not survive');
  assert.ok(!/<img(?!\s+src="\/media\/)/i.test(out),
    'any <img> in the output must be our whitelisted /media/ form');
});
