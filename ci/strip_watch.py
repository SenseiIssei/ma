"""Takes the Apple Watch app out of project.yml for one signed build.

Used when the bundle id com.sensei.ma.watchkitapp does not exist at Apple
yet (ci/bundle_ids.py sets MA_SKIP_WATCH). The iPhone app still builds with
everything else; the phone side of the watch sync simply never finds a
paired watch app.

    python3 ci/strip_watch.py
"""

from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent / "project.yml"

EMBED = """      - target: MaWatch
        embed: true
        codeSign: false             # the watch app is signed in its own build
        copy:
          destination: productsDirectory
          subpath: $(CONTENTS_FOLDER_PATH)/Watch
"""
TARGET_START = "  # Apple Watch companion:"


def main() -> None:
    text = PROJECT.read_text(encoding="utf-8")
    if EMBED not in text or TARGET_START not in text:
        raise SystemExit("project.yml changed: update ci/strip_watch.py")
    text = text.replace(EMBED, "")
    text = text[: text.index(TARGET_START)].rstrip("\n") + "\n"
    PROJECT.write_text(text, encoding="utf-8")
    print("Built without the Apple Watch app this time.")


if __name__ == "__main__":
    main()
