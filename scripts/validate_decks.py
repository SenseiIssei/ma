"""Checks the bundled decks before they ship. Run from the repo root:
python scripts/validate_decks.py

Two editions live side by side: deck-<id>.json (German original) and
deck-<id>.en.json (English). Both share deck and card ids by design, because
learning progress is keyed by them, so duplicate checks run per edition and
every English deck must mirror the card id list of its German original.
"""
import json, glob, os, re, sys

DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Resources", "Decks")
errors = []
card_ids_by_edition = {"de": set(), "en": set()}
card_lists = {"de": {}, "en": {}}  # edition -> deck id -> [card ids]


def edition_and_id(name):
    """deck-foo.en.json -> ("en", "foo"), deck-foo.json -> ("de", "foo")."""
    stem = name[len("deck-"):]
    if stem.endswith(".en.json"):
        return "en", stem[:-len(".en.json")]
    return "de", stem[:-len(".json")]


for path in sorted(glob.glob(os.path.join(DIR, "deck-*.json"))):
    name = os.path.basename(path)
    edition, exp_id = edition_and_id(name)
    raw = open(path, encoding="utf-8").read()
    for ch in ("—", "–"):
        if ch in raw:
            errors.append(f"{name}: contains dash U+{ord(ch):04X}")
    # emoji check (rough): symbols above U+1F000
    if re.search("[\U0001F000-\U0001FFFF☀-➿]", raw):
        errors.append(f"{name}: contains emoji-like character")
    d = json.loads(raw)
    if d.get("id") != exp_id:
        errors.append(f"{name}: id {d.get('id')} != {exp_id}")
    if edition == "en" and d.get("locale") != "en":
        errors.append(f"{name}: locale {d.get('locale')!r} != 'en'")
    for k in ("title", "subtitle", "symbol", "cards"):
        if k not in d:
            errors.append(f"{name}: missing {k}")
    if len(d["symbol"]) != 1:
        errors.append(f"{name}: symbol not one char: {d['symbol']!r}")
    # optional; older decks predate it
    if "category" in d and d["category"] not in ("languages", "knowledge", "mind", "tech", "life"):
        errors.append(f"{name}: unknown category {d['category']!r}")
    if len(d["subtitle"]) > 60:
        errors.append(f"{name}: subtitle too long ({len(d['subtitle'])})")
    all_card_ids = card_ids_by_edition[edition]
    ids = set()
    for i, c in enumerate(d["cards"], 1):
        cid = c.get("id")
        if cid != f"{exp_id}-{i:03d}":
            errors.append(f"{name}: card {i} id {cid}")
        if cid in ids or cid in all_card_ids:
            errors.append(f"{name}: duplicate id {cid}")
        ids.add(cid); all_card_ids.add(cid)
        ans = c.get("answer")
        if not c.get("prompt") or not ans:
            errors.append(f"{name} {cid}: missing prompt/answer")
            continue
        if len(ans) > 30:
            errors.append(f"{name} {cid}: answer long ({len(ans)}): {ans}")
        acc = c.get("accept", [])
        dis = c.get("distractors", [])
        dis_lower = [x.lower() for x in dis]
        if ans in dis:
            errors.append(f"{name} {cid}: answer in distractors")
        for a in acc:
            if a in dis or a.lower() in dis_lower:
                errors.append(f"{name} {cid}: accept {a!r} in distractors")
        if ans.lower() in dis_lower:
            errors.append(f"{name} {cid}: answer (ci) in distractors")
        if len(set(dis_lower)) != len(dis):
            errors.append(f"{name} {cid}: duplicate distractors")
        if dis and len(dis) != 3:
            errors.append(f"{name} {cid}: {len(dis)} distractors")
        ex = c.get("example")
        if ex is not None and ans not in ex:
            errors.append(f"{name} {cid}: example lacks answer")
        if exp_id == "jp-saetze":
            toks = ans.split(" ")
            if not 3 <= len(toks) <= 6 or "" in toks:
                errors.append(f"{name} {cid}: token count {len(toks)}")
    card_lists[edition][exp_id] = [c.get("id") for c in d["cards"]]
    print(f"{name}: {len(d['cards'])} cards")

# Every English deck must have a German original with the same card ids in the
# same order, otherwise progress would not carry over between languages.
for deck_id, en_ids in sorted(card_lists["en"].items()):
    de_ids = card_lists["de"].get(deck_id)
    if de_ids is None:
        errors.append(f"deck-{deck_id}.en.json: no German deck-{deck_id}.json")
    elif en_ids != de_ids:
        errors.append(f"deck-{deck_id}.en.json: card ids differ from deck-{deck_id}.json")

if errors:
    print("\nERRORS:")
    print("\n".join(errors))
    sys.exit(1)
print("\nValidation passed.")
