"""Validates the community decks and regenerates gallery/index.json.

Run from anywhere:
    python gallery/build_index.py          # validate, then write index.json
    python gallery/build_index.py --check  # validate, fail if index.json is stale

Layout: every deck lives in gallery/decks/<id>.<locale>.json, for example
wine-basics.en.json and wine-basics.de.json. Editions of one deck share the
deck id and the card ids, so the same rules as scripts/validate_decks.py
apply: card ids are <id>-001, <id>-002 and so on, and every edition of a
deck must list the same card ids in the same order.

The website (site/gallery/) and the app (App/Gallery/) both read index.json.
Its paths are relative to the gallery folder.
"""
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DECKS = os.path.join(HERE, "decks")
INDEX = os.path.join(HERE, "index.json")
BUNDLED = os.path.join(HERE, "..", "App", "Resources", "Decks")

CATEGORIES = ("languages", "knowledge", "mind", "tech", "life")
LOCALES = ("en", "de")
KEYS = ("id", "title", "subtitle", "symbol", "category", "locale", "cardCount", "path")
MIN_CARDS = 10
FILE_RE = re.compile(r"^([a-z0-9]+(?:-[a-z0-9]+)*)\.([a-z]{2})\.json$")
EMOJI_RE = re.compile("[\U0001F000-\U0001FFFF\u2600-\u27bf]")


def bundled_ids():
    """Ids of decks that ship inside the app. A gallery deck with the same id
    would be renamed on import, so it is refused here instead."""
    ids = set()
    for path in glob.glob(os.path.join(BUNDLED, "deck-*.json")):
        try:
            ids.add(json.load(open(path, encoding="utf-8")).get("id"))
        except (OSError, ValueError):
            pass
    return ids


def check_deck(name, raw, deck_id, locale, errors):
    """Returns the parsed deck, or None when it cannot be used at all."""
    for ch in ("\u2014", "\u2013"):
        if ch in raw:
            errors.append(f"{name}: contains dash U+{ord(ch):04X}")
    if EMOJI_RE.search(raw):
        errors.append(f"{name}: contains emoji-like character")
    try:
        d = json.loads(raw)
    except ValueError as e:
        errors.append(f"{name}: not valid JSON ({e})")
        return None
    if not isinstance(d, dict):
        errors.append(f"{name}: top level must be one deck object")
        return None

    for k in ("id", "locale", "title", "subtitle", "symbol", "category", "cards"):
        if k not in d:
            errors.append(f"{name}: missing {k}")
    if errors and any(e.startswith(f"{name}: missing") for e in errors):
        return None
    if d["id"] != deck_id:
        errors.append(f"{name}: id {d['id']!r} != {deck_id!r} from the file name")
    if d["locale"] != locale:
        errors.append(f"{name}: locale {d['locale']!r} != {locale!r} from the file name")
    if locale not in LOCALES:
        errors.append(f"{name}: locale {locale!r} not one of {LOCALES}")
    if d["category"] not in CATEGORIES:
        errors.append(f"{name}: category {d['category']!r} not one of {CATEGORIES}")
    if not d["title"].strip():
        errors.append(f"{name}: empty title")
    if len(d["symbol"]) != 1:
        errors.append(f"{name}: symbol not one char: {d['symbol']!r}")
    if len(d["subtitle"]) > 60:
        errors.append(f"{name}: subtitle too long ({len(d['subtitle'])})")
    if len(d["cards"]) < MIN_CARDS:
        errors.append(f"{name}: only {len(d['cards'])} cards, at least {MIN_CARDS}")

    ids = set()
    for i, c in enumerate(d["cards"], 1):
        cid = c.get("id")
        if cid != f"{deck_id}-{i:03d}":
            errors.append(f"{name}: card {i} id {cid!r}, expected {deck_id}-{i:03d}")
        if cid in ids:
            errors.append(f"{name}: duplicate id {cid}")
        ids.add(cid)
        ans = c.get("answer")
        if not c.get("prompt") or not ans:
            errors.append(f"{name} {cid}: missing prompt/answer")
            continue
        if len(ans) > 30:
            errors.append(f"{name} {cid}: answer long ({len(ans)}): {ans}")
        acc = c.get("accept", [])
        dis = c.get("distractors", [])
        dis_lower = [x.lower() for x in dis]
        for a in acc:
            if a.lower() in dis_lower:
                errors.append(f"{name} {cid}: accept {a!r} in distractors")
        if ans.lower() in dis_lower:
            errors.append(f"{name} {cid}: answer in distractors")
        if len(set(dis_lower)) != len(dis):
            errors.append(f"{name} {cid}: duplicate distractors")
        if dis and len(dis) != 3:
            errors.append(f"{name} {cid}: {len(dis)} distractors, expected 3")
        ex = c.get("example")
        if ex is not None and ans not in ex:
            errors.append(f"{name} {cid}: example lacks answer")
    return d


def build():
    errors = []
    entries = []
    card_lists = {}  # deck id -> {locale: [card ids]}
    taken = bundled_ids()

    for path in sorted(glob.glob(os.path.join(DECKS, "*.json"))):
        name = os.path.basename(path)
        m = FILE_RE.match(name)
        if not m:
            errors.append(f"{name}: file name must be <id>.<locale>.json with a lowercase id")
            continue
        deck_id, locale = m.groups()
        if deck_id in taken:
            errors.append(f"{name}: id {deck_id!r} is already used by a deck bundled with the app")
        raw = open(path, encoding="utf-8").read()
        d = check_deck(name, raw, deck_id, locale, errors)
        if d is None:
            continue
        card_lists.setdefault(deck_id, {})[locale] = [c.get("id") for c in d["cards"]]
        entries.append({
            "id": deck_id,
            "title": d["title"],
            "subtitle": d["subtitle"],
            "symbol": d["symbol"],
            "category": d["category"],
            "locale": locale,
            "cardCount": len(d["cards"]),
            "path": f"decks/{name}",
        })
        print(f"{name}: {len(d['cards'])} cards")

    # Editions of one deck must share card ids, otherwise progress would not
    # line up between languages.
    for deck_id, editions in sorted(card_lists.items()):
        lists = list(editions.values())
        if any(ids != lists[0] for ids in lists[1:]):
            errors.append(f"{deck_id}: card ids differ between editions {sorted(editions)}")

    order = {c: i for i, c in enumerate(CATEGORIES)}
    entries.sort(key=lambda e: (order.get(e["category"], 99), e["id"], e["locale"]))
    index = {"version": 1, "decks": [{k: e[k] for k in KEYS} for e in entries]}
    return index, errors


def main():
    check_only = "--check" in sys.argv[1:]
    index, errors = build()
    if errors:
        print("\nERRORS:")
        print("\n".join(errors))
        sys.exit(1)

    text = json.dumps(index, ensure_ascii=False, indent=2) + "\n"
    current = open(INDEX, encoding="utf-8").read() if os.path.exists(INDEX) else None
    if check_only:
        if current != text:
            print("\nindex.json is out of date. Run: python gallery/build_index.py")
            sys.exit(1)
        print(f"\nValidation passed, index.json is current ({len(index['decks'])} decks).")
        return
    if current != text:
        with open(INDEX, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"\nWrote index.json with {len(index['decks'])} decks.")
    else:
        print(f"\nValidation passed, index.json unchanged ({len(index['decks'])} decks).")


if __name__ == "__main__":
    main()
