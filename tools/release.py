"""Packaging CHUDForever: version bumps, tags and the CurseForge zip.

Run from the repository folder:

  python tools/release.py release 0.19.0-beta4 [--yes]
                                            everything in one go: sets the version, commits the
                                            working folder, pushes, tags, pushes the tag, zips,
                                            and prints where the zip is. It shows what it will
                                            commit and asks first (--yes skips the question).

  python tools/release.py status            what's released, what isn't, and what's next
  python tools/release.py bump 0.19.0-beta5 sets the .toc version and turns the changelog's
                                            [Unreleased] section into that version, dated today
  python tools/release.py package [--push]  for a committed release: tags HEAD v<version>,
                                            writes CHUDForever-<version>.zip and the CurseForge
                                            description; --push also pushes the tag
  python tools/release.py zip [--dev]       just the zip, from HEAD; --dev zips the working
                                            folder as it is (uncommitted changes too), for testing

The same, step by step:
  1. python tools/release.py bump 0.19.0-beta5
  2. look over the changes, then commit and push them yourself
  3. python tools/release.py package --push
  4. upload the zip it names to CurseForge (and paste the description if it changed)

The release's notes are the changelog's [Unreleased] section, which becomes
the version's section. If the version already has an untagged section, the
[Unreleased] notes are added to it. Either way it's dated today.

The zip holds a CHUDForever/ folder with what the game needs; paths marked
export-ignore in .gitattributes (tools/, .github/...) are left out. Only the
release command commits, and only it and --push push.
"""
import datetime
import os
import re
import subprocess
import sys
import zipfile

ADDON = "CHUDForever"
TOC = ADDON + ".toc"
CHANGELOG = "CHANGELOG.md"
VERSION_LINE = re.compile(r"^## Version:\s*(\S+)\s*$", re.M)
SECTION = re.compile(r"^## \[([^\]]+)\]", re.M)
VERSION = re.compile(r"^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
sys.stdout.reconfigure(line_buffering=True)  # in order with what git and the description script print


# Helpers -----------------------------------------------------------------------------------

class Stop(Exception):
    """Something's not ready: the message says what to do."""


def git(*args, check=True):
    result = subprocess.run(["git", *args], capture_output=True, text=True, encoding="utf-8")
    if check and result.returncode != 0:
        raise Stop("git %s failed: %s" % (" ".join(args), (result.stderr or result.stdout).strip()))
    return result.stdout.strip()


def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def toc_version(text=None):
    match = VERSION_LINE.search(text if text is not None else read(TOC))
    if not match:
        raise Stop("%s has no '## Version:' line." % TOC)
    return match.group(1)


def head_version():
    return toc_version(git("show", "HEAD:" + TOC))


def changelog_section(version, text=None):
    """The changelog's notes for one version (or "Unreleased"), without its heading; None if missing."""
    text = text if text is not None else read(CHANGELOG)
    sections = list(SECTION.finditer(text))
    for i, match in enumerate(sections):
        if match.group(1) == version:
            end = sections[i + 1].start() if i + 1 < len(sections) else len(text)
            body = text[match.end():end]
            body = body.split("\n", 1)[1] if "\n" in body else ""
            # The notes stop at the next top-level heading too (the version history).
            body = re.split(r"^## ", body, flags=re.M)[0]
            return body.strip()
    return None


def changed_files():
    """Uncommitted changes and new files, as git status lines."""
    out = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True, encoding="utf-8").stdout
    return [line for line in out.splitlines() if line.strip()]


def tag_name(version):
    return "v" + version


def tag_commit(tag):
    return git("rev-list", "-n", "1", tag, check=False) or None


def branch():
    return git("rev-parse", "--abbrev-ref", "HEAD")


def zip_name(version):
    return "%s-%s.zip" % (ADDON, version)


# Commands ------------------------------------------------------------------------------------

def status(_args):
    head = git("rev-parse", "--short", "HEAD")
    current = branch()
    working, committed = toc_version(), head_version()
    tags = [t for t in git("tag", "--list", "v*", "--sort=-v:refname").splitlines() if t]
    print("Branch:            %s at %s" % (current, head))
    print("Version (.toc):    %s%s" % (working, "" if working == committed else "   (committed: %s)" % committed))
    print("Latest tag:        %s" % (tags[0] if tags else "none"))
    on_head = [t for t in tags if tag_commit(t) == git("rev-parse", "HEAD")]
    print("Tags on HEAD:      %s" % (", ".join(on_head) or "none"))
    upstream = git("rev-parse", "--abbrev-ref", "@{upstream}", check=False)
    if upstream:
        ahead = git("rev-list", "--count", "%s..HEAD" % upstream, check=False)
        print("Not pushed:        %s commit(s) ahead of %s" % (ahead or "?", upstream))
    files = changed_files()
    print("Uncommitted:       %d file(s)%s" % (len(files), ":" if files else ""))
    for line in files:
        print("                   " + line)
    unreleased = changelog_section("Unreleased")
    print("Changelog:         %s" % ("[Unreleased] has notes" if unreleased else "no [Unreleased] notes"))
    if changelog_section(working) is None:
        print("                   no section for %s yet" % working)

    print()
    if unreleased:
        print("Next: python tools/release.py bump <new version>, then commit.")
    elif files:
        print("Next: commit the changes above, then python tools/release.py package.")
    elif tag_name(committed) not in tags:
        print("Next: python tools/release.py package --push")
    else:
        print("%s is tagged. Nothing to release." % tag_name(committed))


def bump(args):
    if len(args) != 1:
        raise Stop("Usage: python tools/release.py bump <version>, like 0.19.0-beta5")
    version = args[0].lstrip("v")
    if not VERSION.match(version):
        raise Stop("'%s' doesn't look like a version (1.2.3 or 1.2.3-beta4)." % version)
    if git("tag", "--list", tag_name(version)):
        raise Stop("%s is already tagged." % tag_name(version))

    log = read(CHANGELOG)
    if changelog_section(version, log) is not None:
        raise Stop("%s already has a %s section." % (CHANGELOG, version))
    if changelog_section("Unreleased", log) is None:
        raise Stop("%s has no '## [Unreleased]' section to turn into %s." % (CHANGELOG, version))
    if not changelog_section("Unreleased", log):
        raise Stop("The [Unreleased] section is empty: there's nothing to release.")

    today = datetime.date.today().strftime("%m/%d/%Y")
    log = log.replace("## [Unreleased]", "## [%s] - %s" % (version, today), 1)
    toc = read(TOC)
    old = toc_version(toc)
    toc = VERSION_LINE.sub("## Version: " + version, toc, count=1)
    write(TOC, toc)
    write(CHANGELOG, log)
    print("%s: %s -> %s" % (TOC, old, version))
    print("%s: [Unreleased] is now [%s] - %s" % (CHANGELOG, version, today))
    print()
    print("Next: look over the changes, commit and push them, then: python tools/release.py package --push")


def build_zip(version, ref=None, dev=False):
    """Writes the zip next to the repository; returns its name."""
    name = zip_name(version)
    if dev:
        files = working_files()
        with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED) as z:
            for path in files:
                z.write(path, "%s/%s" % (ADDON, path))
    else:
        git("archive", "--format=zip", "--prefix=%s/" % ADDON, "-o", name, ref or "HEAD")
    with zipfile.ZipFile(name) as z:
        names = z.namelist()
    if "%s/%s" % (ADDON, TOC) not in names:
        raise Stop("%s has no %s/%s: something's wrong with the zip." % (name, ADDON, TOC))
    leaked = [n for n in names if n.startswith("%s/tools/" % ADDON) or n.startswith("%s/.git" % ADDON)]
    if leaked:
        raise Stop("%s holds files the game doesn't need: %s" % (name, ", ".join(leaked[:3])))
    size = os.path.getsize(name)
    print("Wrote %s: %d files, %d KB" % (name, len([n for n in names if not n.endswith("/")]), size // 1024))
    return name


def working_files():
    """What a zip of the working folder holds: tracked and new files, less ignored and export-ignore ones."""
    listed = git("ls-files", "--cached", "--others", "--exclude-standard", "-z")
    paths = sorted(p for p in listed.split("\0") if p and os.path.isfile(p))
    if not paths:
        return []
    # A folder pattern like "tools/" only matches the folder (asked about as "tools/"), not the files in it.
    folders = {path[:i + 1] for path in paths for i, c in enumerate(path) if c == "/"}
    asked = paths + sorted(folders)
    result = subprocess.run(["git", "check-attr", "-z", "--stdin", "export-ignore"], input="\0".join(asked) + "\0",
                            capture_output=True, text=True, encoding="utf-8")
    fields = result.stdout.split("\0")
    ignored = {fields[i] for i in range(0, len(fields) - 2, 3) if fields[i + 2] == "set"}

    def left_out(path):
        return path in ignored or any(path.startswith(f) for f in ignored if f.endswith("/"))
    return [p for p in paths if not left_out(p)]


def zip_command(args):
    dev = "--dev" in args
    if dev:
        version = "%s-dev" % toc_version()
        build_zip(version, dev=True)
        print("A test build of the working folder (uncommitted changes included). Not for CurseForge.")
        return
    version = head_version()
    files = changed_files()
    if files:
        print("Note: %d uncommitted file(s) aren't in this zip; it's what HEAD has (%s)." % (len(files), version))
    build_zip(version)


def package(args):
    push = "--push" in args
    files = changed_files()
    if files:
        raise Stop("Commit these first (the zip is built from what's committed):\n  " + "\n  ".join(files))
    version = head_version()
    upstream = git("rev-parse", "--abbrev-ref", "@{upstream}", check=False)
    name, notes = tag_and_zip(version, push)
    if upstream and git("rev-list", "--count", "%s..HEAD" % upstream, check=False) not in ("", "0"):
        print("Your branch has commits %s doesn't have yet: git push" % upstream)
    upload_notes(name, version, notes)


def upload_notes(name, version, notes):
    print()
    print("Changelog for the upload:")
    print()
    print(notes)
    print()
    kind = "Beta" if "beta" in version else "Alpha" if "alpha" in version else "Release"
    print("=" * 72)
    print("Zip:  %s" % os.path.join(ROOT, name))
    print("Upload it to CurseForge as %s, release type %s." % (version, kind))
    print("=" * 72)


def tag_and_zip(version, push):
    """Tags HEAD v<version> (unless it already is), zips the tag, writes the CurseForge description and,
    with push, pushes the tag. Returns the zip's name and the version's notes."""
    tag = tag_name(version)
    notes = changelog_section(version)
    if notes is None:
        raise Stop("%s has no [%s] section. Run: python tools/release.py bump %s" % (CHANGELOG, version, version))
    if changelog_section("Unreleased"):
        raise Stop("[Unreleased] still has notes; they wouldn't be in %s. Bump to a new version first." % version)

    head = git("rev-parse", "HEAD")
    existing = tag_commit(tag)
    if existing and existing != head:
        raise Stop("%s is already on another commit (%s). Bump to a new version." % (tag, existing[:7]))
    if existing:
        print("%s is already on HEAD." % tag)
    else:
        message = "%s %s\n\n%s\n" % (ADDON, version, notes)
        result = subprocess.run(["git", "tag", "-a", tag, "--cleanup=verbatim", "-F", "-"], input=message, capture_output=True, text=True,
                                encoding="utf-8")
        if result.returncode != 0:
            raise Stop("git tag failed: " + (result.stderr or result.stdout).strip())
        print("Tagged %s on %s (%s)." % (tag, branch(), head[:7]))

    name = build_zip(version, ref=tag)

    describe = os.path.join("tools", "curseforge_description.py")
    if os.path.exists(describe):
        subprocess.run([sys.executable, describe], check=False)

    if push:
        remote = remote_name()
        git("push", remote, tag)
        print("Pushed %s to %s." % (tag, remote))
    else:
        print("The tag is only here. To push it: git push origin %s" % tag)
    return name, notes


def remote_name():
    upstream = git("rev-parse", "--abbrev-ref", "@{upstream}", check=False)
    return upstream.split("/", 1)[0] if upstream else "origin"


# The one-step release ------------------------------------------------------------------------

def notes_groups(body):
    """A version's notes as [(heading or None, [lines])], split at its ### headings."""
    groups, heading, lines = [], None, []
    for line in body.splitlines():
        if line.startswith("### "):
            if heading or any(l.strip() for l in lines):
                groups.append((heading, lines))
            heading, lines = line[4:].strip(), []
        else:
            lines.append(line)
    if heading or any(l.strip() for l in lines):
        groups.append((heading, lines))
    return groups


def merge_notes(newer, older):
    """Both versions' notes in one: under each ### heading, the newer notes first."""
    merged = []
    for heading, lines in notes_groups(older):
        merged.append([heading, [l for l in lines if l.strip()]])
    for heading, lines in reversed(notes_groups(newer)):
        lines = [l for l in lines if l.strip()]
        same = next((g for g in merged if g[0] == heading), None)
        if same:
            same[1] = lines + same[1]
        else:
            merged.insert(0, [heading, lines])
    order = {"Added": 0, "Changed": 1, "Fixed": 2, "Removed": 3}
    merged.sort(key=lambda g: order.get(g[0], 4))
    parts = []
    for heading, lines in merged:
        parts.append(("### %s\n\n" % heading if heading else "") + "\n".join(lines))
    return "\n\n".join(parts)


def section_span(text, version):
    """Where a version's section starts and ends in the changelog (heading included)."""
    sections = list(SECTION.finditer(text))
    for i, match in enumerate(sections):
        if match.group(1) == version:
            end = sections[i + 1].start() if i + 1 < len(sections) else len(text)
            # The last section stops at the next top-level heading (the version history), if any.
            later = re.search(r"^## ", text[match.end():end], re.M)
            if later:
                end = match.end() + later.start()
            return match.start(), end
    return None


def prepare_changelog(version):
    """The changelog with this version's section ready (dated today): the [Unreleased] notes become it,
    or are added to it. Returns the new text and the version's notes."""
    log = read(CHANGELOG)
    today = datetime.date.today().strftime("%m/%d/%Y")
    unreleased = changelog_section("Unreleased", log) or ""
    existing = changelog_section(version, log)
    if existing is None and not unreleased:
        raise Stop("%s has no notes for %s and nothing under [Unreleased]: write what changed first." % (CHANGELOG, version))
    notes = merge_notes(unreleased, existing) if existing is not None and unreleased else (existing or unreleased)
    heading = "## [%s] - %s\n\n%s\n\n" % (version, today, notes)

    span = section_span(log, version)
    if span:
        log = log[:span[0]] + heading + log[span[1]:]
    gone = section_span(log, "Unreleased")
    if gone and span:
        log = log[:gone[0]] + log[gone[1]:]  # its notes went into the version's section
    elif gone:
        log = log[:gone[0]] + heading + log[gone[1]:]
    return log, notes


def ask(question):
    if not sys.stdin or not sys.stdin.isatty():
        return False
    try:
        return input(question + " [y/N] ").strip().lower() in ("y", "yes")
    except EOFError:
        return False


def release(args):
    flags = [a for a in args if a.startswith("--")]
    rest = [a for a in args if not a.startswith("--")]
    if len(rest) != 1 or set(flags) - {"--yes"}:
        raise Stop("Usage: python tools/release.py release <version> [--yes], like 0.19.0-beta4")
    version = rest[0].lstrip("v")
    if not VERSION.match(version):
        raise Stop("'%s' doesn't look like a version (1.2.3 or 1.2.3-beta4)." % version)
    tag = tag_name(version)
    current = branch()
    if current == "HEAD":
        raise Stop("No branch is checked out. Check out the branch to release from first.")
    if tag_commit(tag):
        raise Stop("%s is already tagged. Pick a new version." % tag)
    if git("ls-remote", "--tags", remote_name(), "refs/tags/" + tag, check=False):
        raise Stop("%s already has a %s tag. Pick a new version." % (remote_name(), tag))

    # 1. The version, in the .toc and the changelog.
    old_toc, old_log = read(TOC), read(CHANGELOG)
    log, notes = prepare_changelog(version)
    write(CHANGELOG, log)
    write(TOC, VERSION_LINE.sub("## Version: " + version, old_toc, count=1))

    # 2. What goes in, and a last look.
    files = changed_files()
    print("Releasing %s %s from %s. Committing:" % (ADDON, version, current))
    for line in files:
        print("  " + line)
    print()
    print("Notes:")
    print(notes)
    print()
    if "--yes" not in flags and not ask("Commit, push, tag and zip %s?" % version):
        write(TOC, old_toc)
        write(CHANGELOG, old_log)
        raise Stop("Stopped. Nothing was committed; the .toc and changelog are as they were.")

    # 3. Commit and push the branch.
    if files:
        git("add", "-A")
        git("commit", "-q", "-m", "%s %s" % (ADDON, version))
        print("Committed %s %s (%s)." % (ADDON, version, git("rev-parse", "--short", "HEAD")))
    upstream = git("rev-parse", "--abbrev-ref", "@{upstream}", check=False)
    if upstream:
        git("push", "-q")
        print("Pushed %s to %s." % (current, upstream))
    else:
        git("push", "-q", "-u", "origin", current)
        print("Pushed %s to origin/%s." % (current, current))

    # 4. Tag, push the tag, zip.
    name, notes = tag_and_zip(version, push=True)
    upload_notes(name, version, notes)


COMMANDS = {"release": release, "status": status, "bump": bump, "package": package, "zip": zip_command}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(__doc__)
        return 1 if len(sys.argv) >= 2 and sys.argv[1] not in ("-h", "--help", "help") else 0
    try:
        COMMANDS[sys.argv[1]](sys.argv[2:])
    except Stop as stop:
        print(stop)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
