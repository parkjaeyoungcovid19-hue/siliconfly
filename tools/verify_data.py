#!/usr/bin/env python3
"""Independently re-read data/connectome.json + the .bin files and check them.

Knows nothing about etl.py: it loads every array purely from the manifest's
{file, byteOffset, dtype, count} records, checks the CSR invariants, and
re-derives three edges straight from the source parquet.

Usage: /opt/anaconda3/bin/python3 tools/verify_data.py [data_dir]
       --parquet PATH   override the parquet recorded in the manifest
       --no-parquet     skip the source spot-checks (structure only)
Exits non-zero if anything fails.
"""
import argparse, hashlib, json, os, re, sys

import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("data_dir", nargs="?", default="data")
ap.add_argument("--parquet", default=None)
ap.add_argument("--no-parquet", action="store_true")
args = ap.parse_args()

FAILS = []
def check(ok, label, detail=""):
    tail = f"  [{detail}]" if (detail and not ok) else ""
    print(f"  {'PASS' if ok else 'FAIL'}  {label}{tail}")
    if not ok:
        FAILS.append(label + tail)
    return ok

D = args.data_dir
man = json.load(open(os.path.join(D, "connectome.json")))
N, E = man["neuronCount"], man["edgeCount"]
tables = man["stringTables"]
ROLES = tables["roles"]

def load(name):
    a = man["arrays"][name]
    return np.fromfile(os.path.join(D, a["file"]), dtype=a["dtype"],
                       count=a["count"], offset=a["byteOffset"])

print(f"manifest: {man['format']} generated {man['generated']}  args {man['etlArgs']}")
print(f"N = {N}  E = {E}  Σ synapses = {man['synapseTotal']}  min_syn = {man['minSyn']}")

# --- files: size + sha256 ----------------------------------------------------
print("\nfiles:")
for fname, info in man["files"].items():
    path = os.path.join(D, fname)
    blob = open(path, "rb").read()
    digest = hashlib.sha256(blob).hexdigest()
    print(f"  {fname:14s} {len(blob):>11,d} B  sha256 {digest}")
    check(len(blob) == info["bytes"], f"{fname} size", f"{len(blob)} vs {info['bytes']}")
    check(digest == info["sha256"], f"{fname} sha256")
    check(len(blob) <= 95 * 1024 * 1024, f"{fname} under the 95 MB cap")

# --- array extents fit inside their files -----------------------------------
print("\narrays:")
sizes = {f: os.path.getsize(os.path.join(D, f)) for f in man["files"]}
for name, a in man["arrays"].items():
    itemsize = np.dtype(a["dtype"]).itemsize
    end = a["byteOffset"] + a["count"] * itemsize
    print(f"  {name:11s} {a['dtype']:8s} x{a['count']:<10d} @ {a['byteOffset']:>9d} in {a['file']}")
    check(end <= sizes[a["file"]], f"{name} fits in {a['file']}", f"{end} > {sizes[a['file']]}")
    check(a["byteOffset"] % 16 == 0, f"{name} 16-byte aligned")

expect = {"pos": 3 * N, "superClass": N, "side": N, "nt": N, "role": N,
          "cellType": N, "rootId": N, "rowStart": N + 1, "colIdx": E, "weight": E}
for name, count in expect.items():
    check(man["arrays"][name]["count"] == count, f"{name} count == {count}",
          str(man["arrays"][name]["count"]))

pos, sc, side = load("pos"), load("superClass"), load("side")
nt, role, cell = load("nt"), load("role"), load("cellType")
root_ids, row_start, col_idx, weight = load("rootId"), load("rowStart"), load("colIdx"), load("weight")

# --- CSR invariants ----------------------------------------------------------
print("\nCSR:")
rs = row_start.astype(np.int64)
check(rs[0] == 0, "rowStart[0] == 0", str(rs[0]))
check(rs[N] == E, "rowStart[N] == E", f"{rs[N]} vs {E}")
check(bool(np.all(np.diff(rs) >= 0)), "rowStart monotone non-decreasing")
check(bool(np.all(col_idx < N)), "all colIdx < N", f"max {int(col_idx.max())}")
check(bool(np.all(weight != 0)), "no zero weights")
check(int(np.abs(weight.astype(np.int64)).max()) <= 32767, "|weight| within int16")
# strictly increasing inside every row: diffs are only meaningful away from row starts
d = np.diff(col_idx.astype(np.int64))
boundary = np.zeros(E - 1, bool)
starts = rs[1:N]
boundary[starts[(starts > 0) & (starts < E)] - 1] = True
check(bool(np.all(d[~boundary] > 0)), "colIdx strictly ascending within each row",
      f"{int((d[~boundary] <= 0).sum())} violations")

# --- metadata ranges ---------------------------------------------------------
print("\nmetadata:")
check(bool(np.all(np.isfinite(pos))), "pos finite")
check(float(np.abs(pos).max()) <= 10.0001, "pos inside [-10,10]", f"max |p| {np.abs(pos).max():.4f}")
check(bool(np.all(sc < len(tables["superClasses"]))), "superClass in table")
check(bool(np.all(side < len(tables["sides"]))), "side in table")
check(bool(np.all(nt < len(tables["nts"]))), "nt in table")
check(bool(np.all(role < len(ROLES))), "role in table")
check(bool(np.all(cell < len(tables["cellTypes"]))), "cellType in table")
check(bool(np.all(np.diff(root_ids.astype(np.int64)) > 0)), "rootId strictly ascending")

counts = {r: int((role == i).sum()) for i, r in enumerate(ROLES)}
check(counts == man["roleCounts"], "role counts match manifest",
      f"{counts} vs {man['roleCounts']}")
print("  roles: " + ", ".join(f"{k}={v}" for k, v in counts.items() if k != "other"))

# --- sign policy: weight sign follows the PRE neuron's nt --------------------
pre = np.repeat(np.arange(N, dtype=np.int64), np.diff(rs))
sign_table = np.array([man["ntSign"][n] for n in tables["nts"]], np.int64)
wsign = np.sign(weight.astype(np.int64))
known = sign_table[nt[pre]] != 0                    # ntSign 0 (UNKNOWN) = parquet fallback
check(bool(np.all(wsign[known] == sign_table[nt[pre]][known])),
      "every known-nt weight sign matches its PRE neuron's nt sign",
      f"{int((wsign[known] != sign_table[nt[pre]][known]).sum())} violations")

# Dale's law: one sign per presynaptic neuron, fallback rows included
out_deg = np.diff(rs)
n_pos = np.bincount(pre[wsign > 0], minlength=N)
n_neg = np.bincount(pre[wsign < 0], minlength=N)
check(not bool(np.any((n_pos > 0) & (n_neg > 0))), "one sign per PRE neuron (Dale's law)",
      f"{int(((n_pos > 0) & (n_neg > 0)).sum())} mixed neurons")

fb = man.get("signFallback", {})
conn = np.abs(weight.astype(np.int64))
out_syn = np.bincount(pre, weights=conn, minlength=N).astype(np.int64)

# antennal-lobe local interneurons: nt_type-less + primary_type matching the
# manifest's regex must never emit a positive weight (inhibitory prior)
al_type = np.array([bool(re.match(fb["alPriorRegex"], t)) for t in tables["cellTypes"]])
al_prior = (nt == 0) & al_type[cell]
check(not bool(np.any(n_pos[al_prior] > 0)),
      f"AL local interneurons ({fb['alPriorRegex']}, no nt_type) have only non-positive weights",
      f"{int((n_pos[al_prior] > 0).sum())} neurons emit positive weights")
check(int(al_prior.sum()) == fb.get("alPriorNeurons"), "signFallback.alPriorNeurons matches the data",
      f"{int(al_prior.sum())} vs {fb.get('alPriorNeurons')}")
check(int(out_syn[al_prior].sum()) == fb.get("alPriorSynapses"),
      "signFallback.alPriorSynapses matches the data",
      f"{int(out_syn[al_prior].sum())} vs {fb.get('alPriorSynapses')}")

# the parquet fallback fired for everyone else with no nt_type
unk_out = (nt == 0) & (out_deg > 0) & ~al_prior
unk_inh = unk_out & (n_neg > 0)
check(int(unk_inh.sum()) > 0, "sign fallback took effect (UNKNOWN-nt neurons with negative weights)",
      "no UNKNOWN-nt neuron came out inhibitory")
check(int(unk_out.sum()) == fb.get("neurons"), "signFallback.neurons matches the data",
      f"{int(unk_out.sum())} vs {fb.get('neurons')}")
check(int(unk_inh.sum()) == fb.get("inhibitory"), "signFallback.inhibitory matches the data",
      f"{int(unk_inh.sum())} vs {fb.get('inhibitory')}")
check(int(((nt == 0) & (out_deg == 0) & ~al_prior).sum()) == fb.get("noSource"),
      "signFallback.noSource matches the data")
check(int(out_syn[unk_inh].sum()) == fb.get("inhibitorySynapses"),
      "signFallback.inhibitorySynapses matches the data")
print(f"  fallback: {int(al_prior.sum())} AL local interneurons forced inhibitory, "
      f"{int(unk_out.sum())} signed from the parquet ({int(unk_inh.sum())} inhibitory)")

total = int(conn.sum())
check(total == man["synapseTotal"], "Σ|weight| matches manifest", f"{total} vs {man['synapseTotal']}")

# --- spot-check 3 edges straight from the parquet ----------------------------
if args.no_parquet:
    print("\nparquet spot-checks: SKIPPED (--no-parquet)")
else:
    path = args.parquet or man["sources"]["connectivityPath"]
    print(f"\nparquet spot-checks ({path}):")
    if not os.path.exists(path):
        check(False, "parquet present", path)
    else:
        import pyarrow.parquet as pq
        t = pq.read_table(path, columns=["Presynaptic_ID", "Postsynaptic_ID", "Connectivity"])
        p_pre = t["Presynaptic_ID"].to_numpy()
        p_post = t["Postsynaptic_ID"].to_numpy()
        p_conn = t["Connectivity"].to_numpy()

        picks = [("heaviest edge", int(np.argmax(conn)))]
        lc4, gf = ROLES.index("lc4"), ROLES.index("gf")
        cand = np.flatnonzero((role[pre] == lc4) & (role[col_idx] == gf))
        if len(cand):
            picks.append(("strongest LC4->DNp01", int(cand[np.argmax(conn[cand])])))
        else:
            check(False, "found an LC4->DNp01 edge")
        picks.append(("random edge (seed 783)", int(np.random.default_rng(783).integers(E))))

        for label, e in picks:
            a, b, w = int(root_ids[pre[e]]), int(root_ids[col_idx[e]]), int(conn[e])
            hit = np.flatnonzero((p_pre == a) & (p_post == b))
            ok = len(hit) == 1 and int(p_conn[hit[0]]) == w
            check(ok, f"{label}: {a} -> {b} = {w} syn",
                  "" if ok else f"parquet has {len(hit)} rows"
                  + (f" w={int(p_conn[hit[0]])}" if len(hit) == 1 else ""))

# --- summary -----------------------------------------------------------------
print(f"\nN = {N}  E = {E}  Σ|w| = {total}  "
      f"out-degree mean {np.diff(rs).mean():.2f} max {int(np.diff(rs).max())}")
if FAILS:
    print(f"\n{len(FAILS)} FAILURE(S):")
    for f in FAILS:
        print("  -", f)
    sys.exit(1)
print("\nALL CHECKS PASSED")
