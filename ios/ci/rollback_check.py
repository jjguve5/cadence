"""Checks the rollback run (synthetic data only).

- The container's content survives every install over the top. Its path does not have to: the simulator, like iOS,
  may move an app's container on reinstall, so a marker file is checked instead of the path.
- The user's records come through every install (old, new, old again, new again) identical, field for field.
- The new build never loses the sync queue, deletions or revision it loaded, and makes validated copies.
- The old build (2 Nov) has a known defect: on a launch where nothing else changes, it saves before loading the
  sync queue, so the file loses the queue, the deletions and the revision. A control run of the old build on a
  file it wrote itself tells this apart from any incompatibility with files written by the new build.
Fails on anything the new build does wrong or any record lost; reports the old build's defect as a warning."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rollback_fixture import fixture

r = sys.argv[1]
load = lambda name: json.load(open(os.path.join(r, name), encoding="utf-8"))
steps = ["1-old", "2-new", "3-old-again", "4-new-again", "5-old-control"]
snaps = {s: load(s + ".json") for s in steps}
problems, warnings = [], []

def check(cond, what):
    print(("OK    " if cond else "FAIL  ") + what)
    if not cond: problems.append(what)

def warn(cond, what):
    print(("OK    " if cond else "AVISO ") + what)
    if not cond: warnings.append(what)

queue = lambda s: (s.get("dirty") or {}, sorted(s.get("tombstones") or []), s.get("rev"))
# Phase 2.2 answers carry a "source"; the 2 Nov build doesn't know the field and drops it when it saves (then the
# origin reads as unknown, never as yours). Records are compared without it; what happens to it is checked apart.
bare = lambda logs: {k: {f: v for f, v in r.items() if f != "source"} for k, r in (logs or {}).items()}
sources = lambda logs: {k: r.get("source") for k, r in (logs or {}).items()}
old_steps = {"1-old", "3-old-again", "5-old-control"}

# The container's content survives every install (the marker was put in once, at the start)
for s in steps:
    files = open(os.path.join(r, s + "-files.txt"), encoding="utf-8").read()
    check("rollback-marker.txt" in files and "cadence.json" in files, f"{s}: container content still there after installing over the top")

# The first (old) run is the reference: it may fill profile defaults and starter content
ref = snaps["1-old"]
check(bare(ref.get("logs")) == bare(fixture["logs"]), "1-old: kept logs exactly as given (besides where each answer came from)")
for cat in ["days", "feedback", "health"]:
    check(ref.get(cat) == fixture[cat], f"1-old: kept {cat} exactly as given")
warn(sources(ref.get("logs")) == sources(fixture["logs"]), "1-old: the 2 Nov build kept where each answer came from")
# The one-off migrations are marked done before the first launch, as on the phone: none may run here
check(ref["profile"].get("windDownLead") == fixture["profile"]["windDownLead"] and
      "Brush teeth, morning" not in {p.get("title") for p in ref["promises"].values()},
      "1-old: no one-off migration ran (already done, as on the phone)")
for t, recs in fixture["extra"].items():
    for i, v in recs.items():
        check(ref.get("extra", {}).get(t, {}).get(i) == v, f"1-old: kept extra/{t}/{i}")
check("P1" in ref["promises"], "1-old: kept the habit")

# Every record of the reference comes through every later step, field for field, with no starter habits over it
starter = {"Protein shake", "Read 30 min", "Brush teeth, night"}
for s in steps[1:]:
    snap = snaps[s]
    for cat in ["promises", "days", "feedback", "profile", "health", "connection"]:
        check(snap.get(cat) == ref.get(cat), f"{s}: {cat} identical")
    check(bare(snap.get("logs")) == bare(ref.get("logs")), f"{s}: logs identical (besides where each answer came from)")
    before = snaps[steps[steps.index(s) - 1]]
    if s in old_steps:
        warn(sources(snap.get("logs")) == sources(before.get("logs")), f"{s}: the 2 Nov build kept where each answer came from")
    else:
        check(sources(snap.get("logs")) == sources(before.get("logs")), f"{s}: the new build kept where each answer came from, as loaded")
    for t, recs in ref.get("extra", {}).items():
        if t == "prediction": continue  # worked out again at each launch from the same data
        for i, v in recs.items():
            check(snap.get("extra", {}).get(t, {}).get(i) == v, f"{s}: extra/{t}/{i} identical")
    check(not starter & {p.get("title") for p in snap["promises"].values()}, f"{s}: no starter habits written over the data")

# The new build keeps exactly the queue, deletions and revision it loaded
check(queue(snaps["2-new"]) == queue(snaps["1-old"]), "2-new: sync queue, deletions and revision as loaded")
check(queue(snaps["4-new-again"]) == queue(snaps["3-old-again"]), "4-new-again: sync queue, deletions and revision as loaded")

# The old build's own defect, measured on its own file (control) and after the new build's file
warn(queue(snaps["3-old-again"]) == queue(snaps["2-new"]), "3-old-again: the 2 Nov build kept the sync queue it loaded")
control_lost = queue(snaps["5-old-control"]) != queue(snaps["1-old"])
warn(not control_lost, "5-old-control: the 2 Nov build kept the sync queue of a file it wrote itself")
if control_lost:
    print("      -> the queue is lost by the 2 Nov build on its own file too: its defect, not an incompatibility with the new format")

# The new build loaded the file cleanly: a daily copy and a before-update copy, both holding the records
copies = os.path.join(r, "copies-after-new")
names = sorted(os.listdir(copies)) if os.path.isdir(copies) else []
check(any(n.startswith("diaria-") for n in names), f"new build made a daily copy ({names})")
check(any(n.startswith("antes-da-atualizacao-") for n in names), "new build made a before-update copy")
for n in names:
    if n.endswith(".json"):
        c = json.load(open(os.path.join(copies, n), encoding="utf-8"))
        check(c.get("logs") == ref["logs"] and c.get("extra", {}).get("water") == ref["extra"]["water"] and queue(c) == queue(ref),
              f"copy {n} holds the records and the queue")
check(os.path.isdir(os.path.join(r, "copies-after-old-again")), "the old build left the copies folder alone")

print(f"\n{len(problems)} problem(s), {len(warnings)} warning(s) about the 2 Nov build")
sys.exit(1 if problems else 0)
