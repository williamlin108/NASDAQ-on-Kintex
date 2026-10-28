#!/usr/bin/env python3
"""Generate docs/user-guide.html from docs/user-guide.md.

user-guide.md is the source; edit it, then run:
    python3 -I docs/build-user-guide.py
Needs python3-markdown (apt). The output is one self-contained HTML file (no network).
"""
import datetime, html, os, re, sys

try:
    import markdown
except ImportError:
    sys.exit("python3-markdown missing: sudo apt-get install python3-markdown")

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "user-guide.md")
OUT = os.path.join(HERE, "user-guide.html")

# A keyboard shortcut like Ctrl+Shift+B, Alt+←, Ctrl+` or F5
KEY = r"(?:Ctrl|Shift|Alt)(?:\+(?:Ctrl|Shift|Alt))*\+(?:F\d{1,2}|Space|[A-Z]|\\?`|←|→)|F\d{1,2}"


def convert_markdown(text):
    """Convert the guide's markdown to HTML and return (html, toc tokens)."""
    md = markdown.Markdown(extensions=["tables", "fenced_code", "sane_lists", "toc"],
                           extension_configs={"toc": {"toc_depth": "2-3"}})
    body = md.convert(text)
    # A literal | in a table cell is written \| in markdown; GitHub drops the backslash
    # but python-markdown keeps it inside <code>, so drop it here too.
    body = re.sub(r"<code>(.*?)</code>", lambda m: "<code>" + m.group(1).replace("\\|", "|") + "</code>", body)
    return body, md.toc_tokens


def take_title(body):
    """Remove the first <h1> from body and return (title text, remaining body)."""
    m = re.search(r"<h1[^>]*>(.*?)</h1>\s*", body)
    if not m:
        return "User guide", body
    return re.sub("<[^>]+>", "", m.group(1)), body[:m.start()] + body[m.end():]


def kbd(combo):
    """Render a key combo like Ctrl+Shift+B as <kbd> keys."""
    keys = combo.replace("\\`", "`").split("+")
    return "<span class=keys>" + "+".join(f"<kbd>{k}</kbd>" for k in keys) + "</span>"


def style_shortcuts(body):
    """Turn bold text or whole table cells that are only a key combo into <kbd> keys."""
    body = re.sub(rf"<strong>({KEY})</strong>", lambda m: kbd(m.group(1)), body)
    body = re.sub(rf"<td>({KEY})</td>", lambda m: f"<td>{kbd(m.group(1))}</td>", body)
    return re.sub(rf"<td><strong>({KEY})</strong></td>", lambda m: f"<td>{kbd(m.group(1))}</td>", body)


def wrap_sections(body):
    """Wrap each h2 and its content in a <section> so search can show/hide whole sections."""
    intro, *sections = re.split(r"(?=<h2[ >])", body)
    return f'<div class="intro">{intro}</div>' + "".join(f'<section class="sec">{s}</section>' for s in sections)


def build_nav(toc_tokens):
    """Build the sidebar list of h2 sections with their h3 subsections."""
    items = []
    for t in toc_tokens:
        if t["level"] != 2:
            continue
        kids = "".join(f'<li><a href="#{c["id"]}">{c["name"]}</a></li>' for c in t["children"] if c["level"] == 3)
        items.append(f'<li><a href="#{t["id"]}">{t["name"]}</a>' + (f"<ul>{kids}</ul>" if kids else "") + "</li>")
    return "<ul>" + "".join(items) + "</ul>"


def render_page(title, nav, body, stamp):
    """Fill the page template with the converted guide."""
    return (PAGE_TEMPLATE.replace("__NAV__", nav).replace("__TITLE__", html.escape(title))
            .replace("__STAMP__", stamp).replace("__BODY__", body))


def main():
    body, toc = convert_markdown(open(SRC, encoding="utf-8").read())
    title, body = take_title(body)
    body = wrap_sections(style_shortcuts(body))
    stamp = datetime.date.fromtimestamp(os.path.getmtime(SRC)).isoformat()
    page = render_page(title, build_nav(toc), body, stamp)
    open(OUT, "w", encoding="utf-8").write(page)
    print(f"wrote {os.path.relpath(OUT)} ({len(page) // 1024} KB, {len(toc)} top sections)")


# Page shell: styles and scripts for the sidebar, search, copy buttons and theme toggle.
PAGE_TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>DPDK User Guide</title>
<style>
:root {
  --bg: #ffffff; --panel: #f6f7f9; --text: #1d2330; --muted: #5d6675; --border: #dde1e7;
  --accent: #2b62d9; --accent-soft: #e7eefc; --code-bg: #f1f3f6; --note-bg: #fff8e5;
  --note-border: #e9b949; --kbd-bg: #ffffff; --mark: #ffe58a;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: #14171c; --panel: #1b1f26; --text: #e3e7ee; --muted: #9aa3b2; --border: #2c323c;
    --accent: #7aa7ff; --accent-soft: #1f2b44; --code-bg: #1f242c; --note-bg: #2a2516;
    --note-border: #a3802c; --kbd-bg: #262c36; --mark: #6b5a12;
  }
}
:root[data-theme="dark"] {
  --bg: #14171c; --panel: #1b1f26; --text: #e3e7ee; --muted: #9aa3b2; --border: #2c323c;
  --accent: #7aa7ff; --accent-soft: #1f2b44; --code-bg: #1f242c; --note-bg: #2a2516;
  --note-border: #a3802c; --kbd-bg: #262c36; --mark: #6b5a12;
}
* { box-sizing: border-box; }
html { scroll-padding-top: 16px; }
body { margin: 0; background: var(--bg); color: var(--text);
  font: 15px/1.6 system-ui, -apple-system, "Segoe UI", Ubuntu, sans-serif; }
a { color: var(--accent); }
.layout { display: grid; grid-template-columns: 280px minmax(0, 1fr); min-height: 100vh; }
aside { position: sticky; top: 0; height: 100vh; overflow-y: auto; background: var(--panel);
  border-right: 1px solid var(--border); padding: 20px 16px; }
aside .brand { font-weight: 700; font-size: 16px; margin: 0 0 4px; }
aside .sub { color: var(--muted); font-size: 12px; margin: 0 0 14px; }
.search { width: 100%; padding: 8px 10px; border: 1px solid var(--border); border-radius: 6px;
  background: var(--bg); color: var(--text); font: inherit; }
.search:focus { outline: 2px solid var(--accent); outline-offset: -1px; }
.hint { color: var(--muted); font-size: 12px; margin: 6px 2px 12px; min-height: 18px; }
nav ul { list-style: none; margin: 0; padding: 0; }
nav > ul > li { margin: 2px 0; }
nav a { display: block; padding: 4px 8px; border-radius: 5px; color: var(--text);
  text-decoration: none; font-size: 14px; }
nav ul ul a { padding-left: 22px; font-size: 13px; color: var(--muted); }
nav a:hover { background: var(--accent-soft); }
nav a.active { background: var(--accent-soft); color: var(--accent); font-weight: 600; }
nav li.hidden { display: none; }
.theme { margin-top: 16px; background: none; border: 1px solid var(--border); color: var(--muted);
  border-radius: 6px; padding: 4px 10px; font: inherit; font-size: 12px; cursor: pointer; }
main { padding: 32px 48px 80px; max-width: 980px; }
header h1 { margin: 0 0 6px; font-size: 30px; }
header p { margin: 0 0 24px; color: var(--muted); font-size: 13px; }
h2 { margin: 40px 0 12px; padding-bottom: 6px; border-bottom: 1px solid var(--border); font-size: 22px; }
h3 { margin: 26px 0 8px; font-size: 17px; }
.sec.hidden { display: none; }
.intro p:first-child { font-size: 16px; }
code { font: 13px/1.5 ui-monospace, "SFMono-Regular", "DejaVu Sans Mono", monospace;
  background: var(--code-bg); padding: 1px 5px; border-radius: 4px; overflow-wrap: anywhere; }
pre { position: relative; background: var(--code-bg); border: 1px solid var(--border);
  border-radius: 8px; padding: 12px 14px; overflow-x: auto; }
pre code { background: none; padding: 0; overflow-wrap: normal; }
.copy { position: absolute; top: 6px; right: 6px; font: 12px system-ui, sans-serif;
  padding: 3px 8px; border-radius: 5px; border: 1px solid var(--border); background: var(--bg);
  color: var(--muted); cursor: pointer; opacity: 0; transition: opacity .15s; }
pre:hover .copy, .copy:focus { opacity: 1; }
table { border-collapse: collapse; width: 100%; margin: 12px 0; font-size: 14px; display: block;
  overflow-x: auto; }
th, td { border: 1px solid var(--border); padding: 7px 10px; text-align: left; vertical-align: top; }
th { background: var(--panel); }
blockquote { margin: 16px 0; padding: 10px 16px; background: var(--note-bg);
  border-left: 4px solid var(--note-border); border-radius: 0 8px 8px 0; }
blockquote p { margin: 6px 0; }
kbd { display: inline-block; min-width: 22px; padding: 1px 6px; font: 12px/1.6 ui-monospace, monospace;
  text-align: center; background: var(--kbd-bg); border: 1px solid var(--border);
  border-bottom-width: 2px; border-radius: 5px; color: var(--text); }
.keys { white-space: nowrap; }
mark { background: var(--mark); color: inherit; border-radius: 2px; }
.empty { display: none; color: var(--muted); padding: 24px 0; }
.toggle-nav { display: none; }
@media (max-width: 860px) {
  .layout { display: block; }
  aside { position: static; height: auto; border-right: none; border-bottom: 1px solid var(--border); }
  aside nav { display: none; }
  aside.open nav { display: block; }
  .toggle-nav { display: inline-block; margin-top: 10px; background: none; border: 1px solid var(--border);
    color: var(--text); border-radius: 6px; padding: 4px 10px; font: inherit; font-size: 13px; }
  main { padding: 20px 16px 60px; }
}
</style>
</head>
<body>
<div class="layout">
<aside id="aside">
  <p class="brand">DPDK User Guide</p>
  <p class="sub">NASDAQ-on-Kintex · ~/dpdk-projects</p>
  <input class="search" id="q" type="search" placeholder="Search (press /)" aria-label="Search the guide">
  <div class="hint" id="hint"></div>
  <button class="toggle-nav" id="toggleNav">Contents</button>
  <nav id="nav">__NAV__</nav>
  <button class="theme" id="theme">Toggle dark mode</button>
</aside>
<main>
  <header><h1>__TITLE__</h1>
  <p>Generated from <code>docs/user-guide.md</code> (__STAMP__). Edit that file, then run
  <code>python3 -I docs/build-user-guide.py</code>.</p></header>
  __BODY__
  <p class="empty" id="empty">No sections match your search.</p>
</main>
</div>
<script>
(function () {
  var q = document.getElementById("q"), hint = document.getElementById("hint");
  var secs = Array.prototype.slice.call(document.querySelectorAll(".sec"));
  var intro = document.querySelector(".intro");
  var links = Array.prototype.slice.call(document.querySelectorAll("nav a"));

  // Copy buttons on code blocks
  document.querySelectorAll("pre").forEach(function (pre) {
    var b = document.createElement("button");
    b.className = "copy"; b.type = "button"; b.textContent = "Copy";
    b.addEventListener("click", function () {
      var t = pre.querySelector("code").innerText.replace(/\\n$/, "");
      var done = function () { b.textContent = "Copied"; setTimeout(function () { b.textContent = "Copy"; }, 1200); };
      if (navigator.clipboard) navigator.clipboard.writeText(t).then(done, function () { b.textContent = "Select & copy"; });
    });
    pre.appendChild(b);
  });

  // Search: show only sections containing every word; highlight matches
  function clearMarks(root) {
    root.querySelectorAll("mark").forEach(function (m) { m.replaceWith(document.createTextNode(m.textContent)); });
    root.normalize();
  }
  function markWords(root, words) {
    var re = new RegExp("(" + words.map(function (w) { return w.replace(/[.*+?^${}()|[\\]\\\\]/g, "\\\\$&"); }).join("|") + ")", "gi");
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null), nodes = [], n;
    while ((n = walker.nextNode())) if (n.parentNode.nodeName !== "BUTTON" && re.test(n.nodeValue)) nodes.push(n);
    nodes.forEach(function (node) {
      var span = document.createElement("span");
      span.innerHTML = node.nodeValue.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(re, "<mark>$1</mark>");
      node.replaceWith.apply(node, Array.prototype.slice.call(span.childNodes));
    });
  }
  function search() {
    var words = q.value.trim().toLowerCase().split(/\\s+/).filter(Boolean), shown = 0;
    secs.concat([intro]).forEach(clearMarks);
    secs.forEach(function (s) {
      var hit = words.every(function (w) { return s.textContent.toLowerCase().indexOf(w) >= 0; });
      s.classList.toggle("hidden", !hit);
      if (hit) { shown++; if (words.length) markWords(s, words); }
      var id = s.querySelector("h2").id, link = document.querySelector('nav a[href="#' + id + '"]');
      if (link) link.parentNode.classList.toggle("hidden", !hit);
    });
    intro.style.display = words.length ? "none" : "";
    document.getElementById("empty").style.display = shown ? "none" : "block";
    hint.textContent = words.length ? shown + " of " + secs.length + " sections match · Esc to clear" : "";
  }
  q.addEventListener("input", search);
  document.addEventListener("keydown", function (e) {
    if (e.key === "/" && document.activeElement !== q) { e.preventDefault(); q.focus(); q.select(); }
    else if (e.key === "Escape" && document.activeElement === q) { q.value = ""; search(); q.blur(); }
  });

  // Highlight the section currently on screen
  var heads = Array.prototype.slice.call(document.querySelectorAll("main h2[id], main h3[id]"));
  function spy() {
    var cur = null;
    heads.forEach(function (h) { if (h.getBoundingClientRect().top < 120 && h.offsetParent) cur = h.id; });
    links.forEach(function (a) { a.classList.toggle("active", a.getAttribute("href") === "#" + cur); });
  }
  document.addEventListener("scroll", spy, { passive: true }); spy();

  // Contents toggle on narrow screens
  document.getElementById("toggleNav").addEventListener("click", function () {
    document.getElementById("aside").classList.toggle("open");
  });
  links.forEach(function (a) { a.addEventListener("click", function () {
    document.getElementById("aside").classList.remove("open");
  }); });

  // Theme toggle (remembered per browser when storage is available)
  var root = document.documentElement;
  try { var saved = localStorage.getItem("dpdk-guide-theme"); if (saved) root.dataset.theme = saved; } catch (e) {}
  document.getElementById("theme").addEventListener("click", function () {
    var dark = root.dataset.theme ? root.dataset.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
    root.dataset.theme = dark ? "light" : "dark";
    try { localStorage.setItem("dpdk-guide-theme", root.dataset.theme); } catch (e) {}
  });
})();
</script>
</body>
</html>
"""

if __name__ == "__main__":
    main()
