"""Checks the bundled decks before they ship. Run from the repo root:
python scripts/validate_decks.py
"""
import json, glob, os, re, sys

DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Resources", "Decks")
errors = []
all_card_ids = set()
for path in sorted(glob.glob(os.path.join(DIR, "deck-*.json"))):
    name = os.path.basename(path)
    raw = open(path, encoding="utf-8").read()
    for ch in ("\u2014", "\u2013"):
        if ch in raw:
            errors.append(f"{name}: contains dash U+{ord(ch):04X}")
    # emoji check (rough): symbols above U+1F000
    if re.search("[\U0001F000-\U0001FFFF\u2600-\u27BF]", raw):
        errors.append(f"{name}: contains emoji-like character")
    d = json.loads(raw)
    exp_id = name[len("deck-"):-len(".json")]
    if d.get("id") != exp_id:
        errors.append(f"{name}: id {d.get('id')} != {exp_id}")
    for k in ("title", "subtitle", "symbol", "cards"):
        if k not in d:
            errors.append(f"{name}: missing {k}")
    if len(d["symbol"]) != 1:
        errors.append(f"{name}: symbol not one char: {d['symbol']!r}")
    if len(d["subtitle"]) > 60:
        errors.append(f"{name}: subtitle too long ({len(d['subtitle'])})")
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
            errors.append(f"{cid}: missing prompt/answer")
        if len(ans) > 30:
            errors.append(f"{cid}: answer long ({len(ans)}): {ans}")
        acc = c.get("accept", [])
        dis = c.get("distractors", [])
        if ans in dis:
            errors.append(f"{cid}: answer in distractors")
        for a in acc:
            if a in dis or a.lower() in [x.lower() for x in dis]:
                errors.append(f"{cid}: accept {a!r} in distractors")
        if ans.lower() in [x.lower() for x in dis]:
            errors.append(f"{cid}: answer (ci) in distractors")
        if len(set(dis)) != len(dis):
            errors.append(f"{cid}: duplicate distractors")
        if dis and len(dis) != 3:
            errors.append(f"{cid}: {len(dis)} distractors")
        ex = c.get("example")
        if ex is not None and ans not in ex:
            errors.append(f"{cid}: example lacks answer")
        if exp_id == "jp-saetze":
            toks = ans.split(" ")
            if not 3 <= len(toks) <= 6 or "" in toks:
                errors.append(f"{cid}: token count {len(toks)}")
    print(f"{name}: {len(d['cards'])} cards")

if errors:
    print("\nERRORS:")
    print("\n".join(errors))
    sys.exit(1)
print("\nValidation passed.")
