"""Turns README.md into the CurseForge project description. Writes two files
next to the README (git ignores them):

  curseforge-description.md    for the description set to Markdown
  curseforge-description.html  for the WYSIWYG editor's source / HTML view

Paste the one that matches the description's format.

For CurseForge both leave out the title (the page shows it) and the Installing
section (CurseForge installs it), make repository links point at GitHub, and
turn links to headings on the same page into plain text.

Run from the repository folder:  python tools/curseforge_description.py
"""
import html
import io
import re

REPO = "https://github.com/Scoots/CHUDForever/blob/master/"
SKIP_SECTIONS = {"Installing"}
LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def target(url):
    """Where a README link should go from CurseForge (None: no link at all)."""
    if url.startswith("#"):
        return None  # a heading on this page: no anchors on CurseForge
    if not re.match(r"[a-z]+://", url):
        return REPO + url
    return url


def kept_lines(markdown):
    """The README's lines, without the title and the sections left out."""
    skipping = False
    for line in markdown.split("\n"):
        heading = re.match(r"^(#{1,3}) (.*)$", line)
        if heading:
            level, text = len(heading.group(1)), heading.group(2)
            if level <= 2:
                skipping = text in SKIP_SECTIONS
            if level == 1:
                continue
        if not skipping:
            yield line


def to_markdown(markdown):
    def link(match):
        url = target(match.group(2))
        return match.group(1) if url is None else "[%s](%s)" % (match.group(1), url)

    lines = [LINK.sub(link, line) for line in kept_lines(markdown)]
    return "\n".join(lines).strip("\n") + "\n"


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)

    def link(match):
        url = target(match.group(2))
        return match.group(1) if url is None else '<a href="%s">%s</a>' % (url, match.group(1))

    return LINK.sub(link, text)


def to_html(markdown):
    out, paragraph, items, list_kind, table = [], [], [], None, []

    def flush():
        nonlocal paragraph, items, list_kind, table
        if paragraph:
            out.append("<p>%s</p>" % inline(" ".join(paragraph)))
            paragraph = []
        if items:
            out.append("<%s>%s</%s>" % (list_kind, "".join("<li>%s</li>" % inline(i) for i in items), list_kind))
            items, list_kind = [], None
        if table:
            rows = [r for r in table if not re.match(r"^\|[\s|:-]+\|$", r)]
            cells = [[c.strip() for c in r.strip("|").split("|")] for r in rows]
            head = "".join("<th>%s</th>" % inline(c) for c in cells[0])
            body = "".join("<tr>%s</tr>" % "".join("<td>%s</td>" % inline(c) for c in row) for row in cells[1:])
            out.append("<table><thead><tr>%s</tr></thead><tbody>%s</tbody></table>" % (head, body))
            table = []

    for line in kept_lines(markdown):
        heading = re.match(r"^(#{2,3}) (.*)$", line)
        if heading:
            flush()
            level = len(heading.group(1))
            out.append("<h%d>%s</h%d>" % (level, inline(heading.group(2)), level))
        elif not line.strip():
            flush()
        elif line.startswith("|"):
            if paragraph or items:
                flush()
            table.append(line.strip())
        elif line.startswith("> "):
            flush()
            out.append("<blockquote><p>%s</p></blockquote>" % inline(line[2:]))
        elif line.startswith("- "):
            if list_kind not in (None, "ul"):
                flush()
            list_kind = "ul"
            items.append(line[2:])
        elif re.match(r"^\d+\. ", line):
            if list_kind not in (None, "ol"):
                flush()
            list_kind = "ol"
            items.append(re.sub(r"^\d+\. ", "", line))
        elif items:
            items[-1] += " " + line.strip()
        else:
            paragraph.append(line.strip())
    flush()
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    source = io.open("README.md", encoding="utf-8").read()
    io.open("curseforge-description.md", "w", encoding="utf-8", newline="\n").write(to_markdown(source))
    io.open("curseforge-description.html", "w", encoding="utf-8", newline="\n").write(to_html(source))
    print("Wrote curseforge-description.md and curseforge-description.html")
