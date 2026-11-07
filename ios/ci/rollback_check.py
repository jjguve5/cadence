"""Checks the rollback run: the app container never changed, the user's records came through every install (old,
new, old again, new again) identical, the new build made validated copies, and the old build read the new file
(if it hadn't, it would have started fresh and written its starter habits over everything)."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rollback_fixture import fixture

r = sys.argv[1]
load = lambda name: json.load(open(os.path.join(r, name), encoding="utf-8"))
steps = ["1-old.json", "2-new.json", "3-old-again.json", "4-new-again.json"]
snaps = {s: load(s) for s in steps}
problems = []

def check(cond, what):
    print(("OK   " if cond else "FAIL ") + what)
    if not cond: problems.append(what)

# The container is the same folder at every install
containers = open(os.path.join(r, "containers.txt"), encoding="utf-8").read().split()
check(len(containers) == 4 and len(set(containers)) == 1, f"same data container across the 4 installs ({len(set(containers))} distinct)")

# What the first (old) run made of the file is the reference: it may fill in profile defaults and starter content
ref = snaps["1-old.json"]
for cat in ["logs", "days", "feedback", "health"]:
    check(ref.get(cat) == fixture[cat], f"old build kept {cat} exactly as given")
for t, recs in fixture["extra"].items():
    for i, v in recs.items():
        check(ref.get("extra", {}).get(t, {}).get(i) == v, f"old build kept extra/{t}/{i}")
check(ref["promises"].get("P1") is not None, "old build kept the habit")

# Every later step keeps every record of the reference, field for field, plus the queue and the revision
for s in steps[1:]:
    snap = snaps[s]
    for cat in ["promises", "logs", "days", "feedback", "profile", "health", "connection"]:
        check(snap.get(cat) == ref.get(cat), f"{s}: {cat} identical to the old build's file")
    for t, recs in ref.get("extra", {}).items():
        for i, v in recs.items():
            if t in ("prediction",): continue  # worked out again at each launch from the same data
            check(snap.get("extra", {}).get(t, {}).get(i) == v, f"{s}: extra/{t}/{i} identical")
    for k, v in fixture["dirty"].items():
        check(snap.get("dirty", {}).get(k) is not None, f"{s}: still queued for the server: {k}")
    check(set(fixture["tombstones"]) <= set(snap.get("tombstones", [])), f"{s}: deletions still queued")
    check(snap.get("rev") == fixture["rev"], f"{s}: sync revision unchanged")
    starter = {"Protein shake", "Read 30 min", "Brush teeth, night"}
    check(not starter & {p.get("title") for p in snap["promises"].values()}, f"{s}: no starter habits written over the data")

# The new build loaded the file cleanly: it made a daily copy and a before-update copy, both readable and identical
copies = os.path.join(r, "copies-after-new")
names = sorted(os.listdir(copies)) if os.path.isdir(copies) else []
check(any(n.startswith("diaria-") for n in names), f"new build made a daily copy ({names})")
check(any(n.startswith("antes-da-atualizacao-") for n in names), "new build made a before-update copy")
for n in names:
    if n.endswith(".json"):
        c = json.load(open(os.path.join(copies, n), encoding="utf-8"))
        check(c.get("logs") == ref["logs"] and c.get("extra", {}).get("water") == ref["extra"]["water"], f"copy {n} holds the records")
check(os.path.isdir(os.path.join(r, "copies-after-old-again")), "the old build left the copies folder alone")

print(f"\n{len(problems)} problem(s)")
sys.exit(1 if problems else 0)
