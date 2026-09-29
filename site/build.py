"""Assembles the GitHub Pages site into one folder.

    python3 site/build.py [OUT] [--install DIR]

OUT defaults to _site. The result is:

    OUT/                 everything in site/ (except this script)
    OUT/gallery/         site/gallery/index.html plus gallery/index.json
                         and gallery/decks/ from the repo root
    OUT/install/         the device install page, copied from DIR if given

The install page is built by the device job in .github/workflows/ios.yml
(IPA, manifest, icons). This script never creates install/ itself, and it
refuses to run if site/ ever grows its own install/ folder, so the two can
not collide.

It also checks the published text files: no em or en dashes, and no
scripts, stylesheets or images loaded from other hosts.
"""
import os
import re
import shutil
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SITE = os.path.join(ROOT, "site")
GALLERY = os.path.join(ROOT, "gallery")
SKIP = {"build.py", "__pycache__", ".DS_Store"}
TEXT = (".html", ".css", ".js", ".json", ".txt", ".xml", ".svg")
DASHES = ("\u2013", "\u2014")
# Tags that make the browser fetch something. <link> only counts when it
# loads a resource; canonical and hreflang links are plain references.
TAGS = re.compile(r"<(script|link|img|source|iframe|audio|video)\b[^>]*>", re.I)
REMOTE = re.compile(r"\b(src|href|srcset)\s*=\s*[\"'](https?:)?//", re.I)
LOADING_REL = re.compile(r"\brel\s*=\s*[\"'][^\"']*(stylesheet|icon|preload|prefetch|manifest|preconnect|dns-prefetch)", re.I)
CSS_EXTERNAL = re.compile(r"(@import|url\()\s*[\"']?(https?:)?//", re.I)


def loads_remote(html):
    for m in TAGS.finditer(html):
        tag = m.group(0)
        if not REMOTE.search(tag):
            continue
        if m.group(1).lower() == "link" and not LOADING_REL.search(tag):
            continue
        return True
    return False


def fail(msg):
    print(f"::error::{msg}" if os.environ.get("GITHUB_ACTIONS") else f"error: {msg}")
    sys.exit(1)


def copy_tree(src, dst):
    for base, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if d not in SKIP]
        rel = os.path.relpath(base, src)
        target = os.path.normpath(os.path.join(dst, rel))
        os.makedirs(target, exist_ok=True)
        for name in files:
            if name in SKIP:
                continue
            shutil.copy2(os.path.join(base, name), os.path.join(target, name))


def check(out):
    problems = []
    for base, _, files in os.walk(out):
        if os.path.relpath(base, out).split(os.sep)[0] == "install":
            continue  # built elsewhere, carries its own rules
        for name in files:
            if not name.endswith(TEXT):
                continue
            path = os.path.join(base, name)
            rel = os.path.relpath(path, out)
            text = open(path, encoding="utf-8").read()
            for ch in DASHES:
                if ch in text:
                    problems.append(f"{rel}: contains U+{ord(ch):04X}")
            if name.endswith(".html") and loads_remote(text):
                problems.append(f"{rel}: loads a resource from another host")
            if name.endswith(".css") and CSS_EXTERNAL.search(text):
                problems.append(f"{rel}: loads a resource from another host")
    if problems:
        fail("site check failed:\n  " + "\n  ".join(problems))


def main():
    args = sys.argv[1:]
    install = None
    if "--install" in args:
        i = args.index("--install")
        if i + 1 >= len(args):
            fail("--install needs a folder")
        install = os.path.abspath(args[i + 1])
        del args[i:i + 2]
    out = os.path.abspath(args[0] if args else os.path.join(ROOT, "_site"))

    if os.path.exists(os.path.join(SITE, "install")):
        fail("site/install exists; install/ is reserved for the device build")
    if out == SITE or out.startswith(SITE + os.sep):
        fail("OUT must not be inside site/")
    if install and not os.path.isfile(os.path.join(install, "index.html")):
        fail(f"{install} has no index.html, refusing to publish a broken install page")

    shutil.rmtree(out, ignore_errors=True)
    copy_tree(SITE, out)

    gallery_out = os.path.join(out, "gallery")
    os.makedirs(gallery_out, exist_ok=True)
    shutil.copy2(os.path.join(GALLERY, "index.json"), os.path.join(gallery_out, "index.json"))
    copy_tree(os.path.join(GALLERY, "decks"), os.path.join(gallery_out, "decks"))

    if install:
        copy_tree(install, os.path.join(out, "install"))

    # Pages from an Actions artifact skip Jekyll anyway; this keeps it that
    # way if the source is ever switched to a branch.
    open(os.path.join(out, ".nojekyll"), "w").close()

    check(out)
    count = sum(len(f) for _, _, f in os.walk(out))
    print(f"Site assembled in {out} ({count} files{', with install/' if install else ', no install/'})")


if __name__ == "__main__":
    main()
