#!/usr/bin/env python3
"""Build the StormFS documentation books from Markdown sources.

Usage:
    build.py [--mode {nochunks,chunks}] [--title TITLE] [--out DIR] [--stamp FILE] README.md CHAPTERS_DIR

Produces, inside --out (default: html):
    index.html             front page (README) + table of contents
    <chapter>.html         one page per chapter with prev/next navigation (chunks mode)
    book.html              the whole book on a single page with internal anchors (nochunks mode)

Requires the Python "markdown" package:
    pip install markdown
"""

import argparse
import re
import sys
from pathlib import Path

try:
    import markdown
except ImportError:
    sys.exit(
        "error: the 'markdown' Python package is required.\n"
        "       install it with:  python3 -m pip install markdown"
    )

MD_EXTENSIONS = ["fenced_code", "tables", "toc", "sane_lists"]

CSS = """
:root { color-scheme: light dark; }
* { box-sizing: border-box; }
body {
  margin: 0 auto; padding: 2rem 1rem;
  max-width: 52rem; line-height: 1.6;
  font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}
h1, h2, h3, h4 { line-height: 1.25; margin-top: 1.8em; }
h1 { border-bottom: 2px solid #8884; padding-bottom: .3em; }
pre {
  background: #1e1e28; color: #e0e0ea; padding: .9em 1em;
  border-radius: 6px; overflow-x: auto; font-size: .88em; line-height: 1.45;
}
code { font-family: ui-monospace, "Cascadia Code", Consolas, monospace; }
:not(pre) > code {
  background: #8882; padding: .12em .35em; border-radius: 4px; font-size: .9em;
}
blockquote {
  margin: 1em 0; padding: .4em 1em;
  border-left: 4px solid #d8a038; background: #d8a03822;
}
table { border-collapse: collapse; margin: 1em 0; display: block; overflow-x: auto; }
th, td { border: 1px solid #8886; padding: .35em .7em; text-align: left; }
th { background: #8881; }
.toc { columns: 2; column-gap: 2.5rem; }
@media (max-width: 40rem) { .toc { columns: 1; } }
.toc ol { padding-left: 1.2em; }
.nav { display: flex; justify-content: space-between; gap: 1rem; margin-top: 2.5em; }
.nav a, .back a { font-weight: 600; }
.back { margin-top: 2.5em; }
.subtitle { color: #888; font-style: italic; margin-top: -.5em; }
footer { margin-top: 3em; font-size: .85em; color: #888; border-top: 1px solid #8884; padding-top: .8em; }
@media (prefers-color-scheme: dark) {
  body { background: #16161c; color: #d6d6de; }
  :not(pre) > code { background: #ffffff22; }
}
"""


def md_to_html(text: str) -> str:
    return markdown.markdown(text, extensions=MD_EXTENSIONS)


def first_heading(text: str, fallback: str) -> str:
    m = re.search(r"^#\s+(.+?)\s*$", text, re.MULTILINE)
    return m.group(1).strip() if m else fallback


def strip_first_heading(html: str) -> str:
    """Remove the leading <h1>...</h1> since page chrome supplies the title."""
    return re.sub(r"^\s*<h1[^>]*>.*?</h1>", "", html, count=1, flags=re.DOTALL)


def page(title: str, body: str, subtitle: str = "") -> str:
    sub = f'\n<p class="subtitle">{subtitle}</p>' if subtitle else ""
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>{CSS}</style>
</head>
<body>
{body}
</body>
</html>
"""


def load_chapters(chapters_dir: Path):
    chapters = []
    for path in sorted(chapters_dir.glob("*.md")):
        text = path.read_text(encoding="utf-8", newline="\n")
        chapters.append(
            {
                "stem": path.stem,
                "title": first_heading(text, path.stem),
                "text": text,
            }
        )
    return chapters


def toc_list(chapters, href=lambda c: f"{c['stem']}.html", anchor=lambda c: ""):
    items = "\n".join(
        f'    <li><a href="{href(c)}">{c["title"]}</a></li>' for c in chapters
    )
    return f'<ol class="toc">\n{items}\n</ol>'


def rewrite_chapter_links(html: str, chapters, mode: str) -> str:
    """Point Markdown chapter links at generated pages or single-page anchors."""
    by_stem = {c["stem"]: c for c in chapters}

    def replace(match):
        stem = match.group(1)
        normalized = stem.removeprefix("chapter-")
        chapter = by_stem.get(normalized)
        if not chapter:
            return match.group(0)
        target = f"#ch-{chapter['stem']}" if mode == "nochunks" else f"{chapter['stem']}.html"
        return f'href="{target}"'

    return re.sub(r'href="(?:chapters/)?((?:chapter-)?[0-9][^"]*)\.md"', replace, html)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--mode", choices=("nochunks", "chunks"), default="nochunks",
                    help="write one self-contained book.html or separate chapter pages (default: nochunks)")
    ap.add_argument("intro", help="path to README.md (front matter)")
    ap.add_argument("chapters", help="directory containing chapter .md files")
    ap.add_argument("--title", default="StormFS Book", help="book title")
    ap.add_argument("--subtitle", default="", help="subtitle line on the front page")
    ap.add_argument("--out", default="html", help="output directory")
    ap.add_argument("--stamp", default="", help="file to touch after a successful build")
    args = ap.parse_args()

    intro_path = Path(args.intro)
    chapters_dir = Path(args.chapters)
    out_dir = Path(args.out)
    if not intro_path.is_file():
        sys.exit(f"error: intro file not found: {intro_path}")
    if not chapters_dir.is_dir():
        sys.exit(f"error: chapters directory not found: {chapters_dir}")

    chapters = load_chapters(chapters_dir)
    if not chapters:
        sys.exit(f"error: no .md chapters found in {chapters_dir}")

    out_dir.mkdir(parents=True, exist_ok=True)

    readme_text = intro_path.read_text(encoding="utf-8", newline="\n")

    # ---- front page (index.html): README content + linked TOC -------------
    intro_body = rewrite_chapter_links(strip_first_heading(md_to_html(readme_text)), chapters, args.mode)
    toc_href = (lambda c: f"{c['stem']}.html") if args.mode == "chunks" else (lambda c: f"book.html#ch-{c['stem']}")
    toc = toc_list(chapters, href=toc_href)
    sub_html = f'\n<p class="subtitle">{args.subtitle}</p>' if args.subtitle else ""
    index_body = (
        f"<h1>{args.title}</h1>{sub_html}\n"
        f"{intro_body}\n"
        f"<h2 id=\"contents\">Table of Contents</h2>\n{toc}\n"
        f'<p><a href="book.html">Open the complete book</a></p>\n'
        f'<footer>Generated from Markdown sources &mdash; do not edit.</footer>'
    )
    (out_dir / "index.html").write_text(
        page(f"{args.title} &mdash; Table of Contents".replace("&mdash;", "-"), index_body, args.subtitle),
        encoding="utf-8", newline="\n",
    )

    # ---- per-chapter pages -------------------------------------------------
    if args.mode == "chunks":
        for i, ch in enumerate(chapters):
            prev_ch = chapters[i - 1] if i > 0 else None
            next_ch = chapters[i + 1] if i + 1 < len(chapters) else None
            prev_link = f'<a href="{prev_ch["stem"]}.html">&larr; {prev_ch["title"]}</a>' if prev_ch else "<span></span>"
            next_link = f'<a href="{next_ch["stem"]}.html">{next_ch["title"]} &rarr;</a>' if next_ch else "<span></span>"
            body = (
                f"<h1>{ch['title']}</h1>\n"
                f"{rewrite_chapter_links(strip_first_heading(md_to_html(ch['text'])), chapters, args.mode)}\n"
                f'<div class="nav">{prev_link}{next_link}</div>\n'
                f'<p class="back"><a href="index.html">Back to Table of Contents</a></p>'
            )
            (out_dir / f"{ch['stem']}.html").write_text(page(ch["title"], body), encoding="utf-8", newline="\n")
    else:
        # Remove stale chapter pages so the output directory is genuinely no-chunks.
        for ch in chapters:
            (out_dir / f"{ch['stem']}.html").unlink(missing_ok=True)

    # ---- single-page book.html ---------------------------------------------
    parts = [f"<h1>{args.title}</h1>{sub_html}", '<h2 id="contents">Table of Contents</h2>', toc_list(chapters, href=lambda c: f"#ch-{c['stem']}")]
    parts.append('<hr>')
    for i, ch in enumerate(chapters):
        anchor = f'ch-{ch["stem"]}'
        parts.append(f'<h2 id="{anchor}">{i + 1}. {ch["title"]}</h2>')
        parts.append(f'<p><a href="#contents">Back to Table of Contents</a></p>')
    parts.append('<hr>')
    for ch in chapters:
        parts.append(rewrite_chapter_links(strip_first_heading(md_to_html(ch["text"])), chapters, args.mode))
        parts.append("<hr>")
    parts.append("<footer>Generated from Markdown sources &mdash; do not edit.</footer>")
    (out_dir / "book.html").write_text(page(args.title, "\n".join(parts)), encoding="utf-8", newline="\n")

    n = len(chapters)
    output = "nochunks book.html" if args.mode == "nochunks" else f"{n} chapter pages + book.html"
    print(f"built {output} + index.html in {out_dir}/")
    if args.stamp:
        Path(args.stamp).parent.mkdir(parents=True, exist_ok=True)
        Path(args.stamp).write_text("", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
