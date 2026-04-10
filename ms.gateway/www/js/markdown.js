/**
 * Markdown subset renderer for the blog post body.
 *
 * Supports only: h1-h6 (#), bold (**), italic (*) and images limited to the
 * local /media/:id endpoint. Everything else is treated as plain text. The
 * input is HTML-escaped *first*, so no raw HTML can slip through -- the
 * transforms below only re-introduce the specific tags we whitelist.
 *
 * Why hand-rolled instead of a markdown library? This is a demo repo with a
 * strict "no external JS dependencies" rule. The supported surface is tiny,
 * so a handful of regexes over escaped text is both safer and smaller than
 * pulling in a parser.
 *
 * The module exposes itself via window.renderMarkdown (browser) and via
 * module.exports (Node, used by test/js/renderMarkdown.test.js).
 */
(function () {
  // Pure-JS HTML escape, no DOM needed. Kept internal to this module so the
  // markdown renderer works identically in the browser and in Node tests.
  function mdEsc(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  // Inline transforms run on already-escaped text. Order matters: images first
  // (they contain parentheses that could confuse bold/italic), then bold (**)
  // before italic (*) because ** would otherwise be read as two * markers.
  function applyInline(text) {
    // ![alt](/media/42) -- only our own media endpoint is allowed; anything else
    // is left as plain escaped text. The alt text was already escaped.
    text = text.replace(
      /!\[([^\]]*)\]\(\/media\/(\d+)\)/g,
      function (_m, alt, id) {
        return '<img src="/media/' + id + '" alt="' + alt + '" class="md-img">';
      }
    );
    // **bold**
    text = text.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    // *italic*
    text = text.replace(/(^|[^*])\*([^*\n]+)\*(?!\*)/g, '$1<em>$2</em>');
    return text;
  }

  function renderMarkdown(src) {
    if (!src) return '';
    var escaped = mdEsc(src);
    var lines = escaped.split(/\r?\n/);
    var out = [];
    var paragraph = [];

    function flushParagraph() {
      if (paragraph.length === 0) return;
      var joined = paragraph.join(' ');
      out.push('<p>' + applyInline(joined) + '</p>');
      paragraph = [];
    }

    for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
      var line = lines[lineIdx];
      if (line.trim() === '') {
        flushParagraph();
        continue;
      }
      // # Heading, ## Heading, ... ###### Heading (1-6 hashes, then at least one space)
      var heading = line.match(/^(#{1,6})\s+(.*)$/);
      if (heading) {
        flushParagraph();
        var level = heading[1].length;
        out.push('<h' + level + '>' + applyInline(heading[2]) + '</h' + level + '>');
        continue;
      }
      paragraph.push(line);
    }
    flushParagraph();
    return out.join('\n');
  }

  // Browser: expose globally so app.js can call renderMarkdown(body) directly.
  if (typeof window !== 'undefined') {
    window.renderMarkdown = renderMarkdown;
  }
  // Node: expose for the test runner.
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      renderMarkdown: renderMarkdown,
      applyInline: applyInline,
      mdEsc: mdEsc
    };
  }
})();
