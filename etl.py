#!/usr/bin/env python3
"""Build the FULL FlyWire v783 connectome for SiliconFly as compact binaries.

Inputs (<raw_dir>) — four Codex dumps plus the eonsystemspbc/fly-brain parquet:
  classification.csv.gz           root_id, flow, super_class, class, sub_class, hemilineage, side, nerve
  coordinates.csv.gz              root_id, position "[x y z]" (nm), supervoxel_id  (several rows/neuron)
  consolidated_cell_types.csv.gz  root_id, primary_type, additional_type(s)
  neurons.csv.gz                  root_id, group, nt_type, ...                     (per-neuron NT call)
  2025_Connectivity_783.parquet   Presynaptic_ID, Postsynaptic_ID, Connectivity    (15,091,983 pairs)

Outputs (data/):
  connectome.json  self-describing manifest: array layout, string tables, transform, provenance
  neurons.bin      per-neuron metadata arrays + CSR rowStart
  synapses.bin     CSR colIdx (uint32) + signed synapse weight (int16)

Neuron set = every row of classification.csv.gz, ordered by ascending root_id;
that order IS the neuron index used everywhere (CSR, metadata, the GPU sim).

Usage: /opt/anaconda3/bin/python3 etl.py cache/flywire783
       (needs numpy + pyarrow — Xcode's python3 has neither)
"""
import argparse, hashlib, json, os, re, sys, time
from datetime import datetime, timezone

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

T0 = time.time()
def lap(msg):
    print(f"[{time.time() - T0:6.1f}s] {msg}", flush=True)

# --- config -----------------------------------------------------------------
CORE_TYPES = {          # primary_type -> role slug (strict primary_type match only:
    "LC4": "lc4",       # additional_type matches pull in near-miss types like
    "LPLC2": "lplc2",   # DNp71-as-DNp09 or DNae001-as-DNa01)
    "DNp01": "gf",      # giant fiber (escape command neuron)
    "DNa02": "dna02",   # steering descending neuron
    "DNa01": "dna01",   # steering descending neuron (partner of DNa02)
    "DNp09": "dnp09",   # forward-walking command neuron
    "DNg11": "dng11",   # grooming command neuron
    "MDN": "mdn",       # moonwalker (backward walking) descending neuron
    "DNp02": "escw",    # loom-responsive escape-maneuver DNs (wing responses)
    "DNp04": "escw",
    "DNp11": "escw",
}
COMMAND_ROLES = ("gf", "dna01", "dna02", "dnp09", "dng11", "mdn", "escw")
ROLES = ["other", "lc4", "lplc2", "gf", "dna01", "dna02", "dnp09", "dng11",
         "mdn", "escw", "ascend", "sens"]
NTS = ["UNKNOWN", "ACH", "GABA", "GLUT", "DA", "SER", "OCT"]
# sign is baked into the int16 weight; modulatory NTs stay +1 here and are
# scaled by the Swift loader off the per-neuron `nt` byte. UNKNOWN is 0 =
# "ask the parquet" (see the sign fallback below), not "excitatory".
NT_SIGN = np.array([0, 1, -1, -1, 1, 1, 1], dtype=np.int16)
MODULATORY = ["DA", "SER", "OCT"]
SIDES = ["center", "left", "right"]     # 0 also covers a missing side
# Antennal-lobe local interneurons are canonically inhibitory (GABA, some Glut)
# but Codex leaves their nt_type blank; without a prior they form a mutual-
# excitation loop that pins the sim at the refractory ceiling.
AL_LN_RE = re.compile(r"^(lLN|il3LN|v2LN)")
SUPER_CLASSES = ["optic", "central", "sensory", "visual_projection", "visual_centrifugal",
                 "descending", "ascending", "motor", "endocrine"]
N_ASCEND, N_SENS = 24, 16               # reserved body->brain feedback partners
FILE_CAP = 95 * 1024 * 1024             # GitHub-friendly per-file ceiling
ALIGN = 16

ap = argparse.ArgumentParser(description="FlyWire v783 -> SiliconFly binary connectome")
ap.add_argument("raw_dir", nargs="?", default=".", help="dir with the Codex dumps + parquet")
ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "data"))
ap.add_argument("--parquet", default=None, help="override path to 2025_Connectivity_783.parquet")
ap.add_argument("--min-syn", type=int, default=1, help="drop pairs below this synapse count")
args = ap.parse_args()

RAW = args.raw_dir
OUT = args.out
PARQUET = args.parquet or os.path.join(RAW, "2025_Connectivity_783.parquet")
os.makedirs(OUT, exist_ok=True)
raw = lambda name: os.path.join(RAW, name)

# --- neuron set: classification.csv.gz, sorted by root_id --------------------
cls = pd.read_csv(raw("classification.csv.gz"), usecols=["root_id", "super_class", "side"],
                  dtype={"root_id": "int64"}).sort_values("root_id", kind="stable")
root_ids = cls.root_id.to_numpy()
N = len(root_ids)
if not np.all(np.diff(root_ids) > 0):
    sys.exit("FATAL: classification.csv.gz root_ids are not unique")

def index_of(ids, what):
    """root_id -> neuron index; hard-fails (loudly) on anything outside the neuron set."""
    i = np.searchsorted(root_ids, ids)
    bad = (i >= N) | (root_ids[np.minimum(i, N - 1)] != ids)
    if bad.any():
        u = np.unique(ids[bad])
        sys.exit(f"FATAL: {bad.sum()} {what} rows ({len(u)} distinct root_ids) are not in "
                 f"classification.csv.gz, e.g. {u[:5].tolist()}")
    return i

sc_col = cls.super_class.fillna("unknown")
sc_names = SUPER_CLASSES + sorted(set(sc_col.unique()) - set(SUPER_CLASSES))
super_class = sc_col.map({s: i for i, s in enumerate(sc_names)}).to_numpy(np.uint8)
side = cls.side.map({"center": 0, "left": 1, "right": 2}).fillna(0).to_numpy(np.uint8)
lap(f"neurons: {N} (super_classes {len(sc_names)}, sides {np.bincount(side, minlength=3).tolist()})")

# --- coordinates: first row per neuron, nm ----------------------------------
co = pd.read_csv(raw("coordinates.csv.gz"), usecols=["root_id", "position"],
                 dtype={"root_id": "int64"}).drop_duplicates("root_id", keep="first")
xyz = co.position.str.strip("[]").str.split(expand=True).to_numpy(np.float64)
raw_pos = np.full((N, 3), np.nan)
raw_pos[index_of(co.root_id.to_numpy(), "coordinates.csv.gz")] = xyz
has_pos = ~np.isnan(raw_pos[:, 0])

# fit the whole brain into [-10,10]; FAFB x = left-right, y = dorsal-ventral
# (image y points down), z = anterior-posterior -> flip y and z.
p = raw_pos[has_pos]
lo, hi = p.min(0), p.max(0)
center = (lo + hi) / 2
scale = 20.0 / (hi - lo).max()
pos = np.zeros((N, 3), np.float32)
pos[has_pos] = (p - center) * scale * np.array([1.0, -1.0, -1.0])
lap(f"coordinates: {int(has_pos.sum())}/{N} placed, scale {scale:.6g}, center {center.tolist()}")

# --- cell types --------------------------------------------------------------
ct = pd.read_csv(raw("consolidated_cell_types.csv.gz"), usecols=["root_id", "primary_type"],
                 dtype={"root_id": "int64"}).dropna(subset=["primary_type"])
ct_names = [""] + sorted(ct.primary_type.unique())
if len(ct_names) > 65535:
    sys.exit(f"FATAL: {len(ct_names)} cell types overflow uint16")
cell_type = np.zeros(N, np.uint16)
cell_type[index_of(ct.root_id.to_numpy(), "consolidated_cell_types.csv.gz")] = \
    ct.primary_type.map({s: i for i, s in enumerate(ct_names)}).to_numpy(np.uint16)
al_ln = np.array([bool(AL_LN_RE.match(t)) for t in ct_names])[cell_type]

# --- neurotransmitter (per PRE neuron, from Codex neurons.csv.gz) ------------
nr = pd.read_csv(raw("neurons.csv.gz"), usecols=["root_id", "nt_type"], dtype={"root_id": "int64"})
nt_raw = nr.nt_type.fillna("").str.strip().str.upper()
nt_code = nt_raw.map({s: i for i, s in enumerate(NTS)})
unrecognized = sorted(set(nt_raw[nt_code.isna() & (nt_raw != "")]))
nt = np.zeros(N, np.uint8)
nt[index_of(nr.root_id.to_numpy(), "neurons.csv.gz")] = nt_code.fillna(0).to_numpy(np.uint8)
n_unknown = int((nt == 0).sum())
lap(f"nt_type: {n_unknown} UNKNOWN of {N}" +
    (f", unrecognized labels {unrecognized}" if unrecognized else ""))

# --- edges: the parquet, no threshold ---------------------------------------
tab = pq.read_table(PARQUET, columns=["Presynaptic_ID", "Postsynaptic_ID",
                                      "Connectivity", "Excitatory"])
pre = index_of(tab["Presynaptic_ID"].to_numpy(), "parquet presynaptic").astype(np.uint32)
post = index_of(tab["Postsynaptic_ID"].to_numpy(), "parquet postsynaptic").astype(np.uint32)
conn = tab["Connectivity"].to_numpy().astype(np.int32)
exc = tab["Excitatory"].to_numpy().astype(np.int32)
del tab
lap(f"parquet: {len(pre)} pairs, Σ synapses {int(conn.sum())}, max pair {int(conn.max())}")

if args.min_syn > 1:
    keep = conn >= args.min_syn
    pre, post, conn, exc = pre[keep], post[keep], conn[keep], exc[keep]
    lap(f"--min-syn {args.min_syn}: kept {len(pre)} pairs, Σ synapses {int(conn.sum())}")
E = len(pre)

# sign per PRE neuron: Codex nt_type first; where that is missing (nt UNKNOWN)
# fall back to the parquet's own Excitatory call, which is constant per
# presynaptic neuron (Dale's law). Neither source -> +1, and no edges anyway.
n_pos = np.bincount(pre[exc > 0], minlength=N)
n_neg = np.bincount(pre[exc < 0], minlength=N)
if np.any((n_pos > 0) & (n_neg > 0)):
    sys.exit(f"FATAL: {int(((n_pos > 0) & (n_neg > 0)).sum())} presynaptic neurons carry both "
             f"Excitatory=+1 and -1 rows — the parquet is meant to obey Dale's law")
pq_sign = np.where(n_pos > 0, 1, np.where(n_neg > 0, -1, 0)).astype(np.int32)
out_mass = np.bincount(pre, weights=conn, minlength=N)
has_out = out_mass > 0

sign = NT_SIGN[nt].astype(np.int32)
al_prior = (sign == 0) & al_ln                   # AL local interneuron prior wins over the parquet
sign[al_prior] = -1
fallback = (sign == 0) & (pq_sign != 0)          # still UNKNOWN, but the parquet knows
sign[fallback] = pq_sign[fallback]
n_orphan = int((sign == 0).sum())                # no nt, no prior, no out-edges
sign[sign == 0] = 1
n_fb, n_fb_inh = int(fallback.sum()), int((fallback & (pq_sign < 0)).sum())
n_al, al_mass = int(al_prior.sum()), out_mass[al_prior].sum()
fb_mass = out_mass[fallback].sum()
fb_inh_mass = out_mass[fallback & (pq_sign < 0)].sum()

signed = conn * sign[pre]
if np.abs(signed).max() > 32767:
    sys.exit(f"FATAL: |weight| {int(np.abs(signed).max())} overflows int16")
if (signed == 0).any():
    sys.exit(f"FATAL: {int((signed == 0).sum())} zero-weight edges")

# CSR: one row per PRE neuron, cols ascending inside a row
key = pre.astype(np.int64) * N + post
if np.all(key[1:] > key[:-1]):
    order = None
else:
    order = np.argsort(key, kind="stable")
    if not np.all(np.diff(key[order]) > 0):
        sys.exit("FATAL: duplicate (pre,post) pairs in the parquet — it is meant to be aggregated")
col_idx = (post if order is None else post[order]).astype(np.uint32)
weight = (signed if order is None else signed[order]).astype(np.int16)
out_deg = np.bincount(pre, minlength=N)
row_start = np.zeros(N + 1, np.uint32)
row_start[1:] = np.cumsum(out_deg)
del key, order, exc, n_pos, n_neg
lap(f"CSR: {N} rows, {E} edges, Σ|w| {int(conn.sum())}")

# --- roles -------------------------------------------------------------------
role = np.zeros(N, np.uint8)
core = ct.primary_type.isin(CORE_TYPES).to_numpy()
role[index_of(ct.root_id.to_numpy()[core], "core cell types")] = \
    [ROLES.index(CORE_TYPES[t]) for t in ct.primary_type.to_numpy()[core]]
is_core = role > 0
missing = [r for r in dict.fromkeys(CORE_TYPES.values()) if not (role == ROLES.index(r)).any()]
if missing:
    sys.exit(f"FATAL: core populations {missing} are empty — check the names in CORE_TYPES")

# partner strength = synapses exchanged with the core populations, full graph
pre_core, post_core = is_core[pre], is_core[post]
strength = np.bincount(post[pre_core & ~post_core], weights=conn[pre_core & ~post_core], minlength=N)
strength += np.bincount(pre[post_core & ~pre_core], weights=conn[post_core & ~pre_core], minlength=N)
strength = strength.astype(np.int64)

def take(super_name, k, slug):
    """k strongest non-core partners from one super_class; ties break on root_id."""
    cand = np.flatnonzero((super_class == sc_names.index(super_name)) & (role == 0) & (strength > 0))
    if len(cand) < k:
        sys.exit(f"FATAL: only {len(cand)} '{super_name}' partners for role '{slug}' (need {k})")
    role[cand[np.lexsort((root_ids[cand], -strength[cand]))][:k]] = ROLES.index(slug)

take("ascending", N_ASCEND, "ascend")
take("sensory", N_SENS, "sens")
role_counts = {r: int((role == i).sum()) for i, r in enumerate(ROLES)}
lap(f"roles: { {k: v for k, v in role_counts.items() if k != 'other'} }")

# --- write -------------------------------------------------------------------
arrays = [("pos", pos, 3), ("superClass", super_class, 1), ("side", side, 1), ("nt", nt, 1),
          ("role", role, 1), ("cellType", cell_type, 1), ("rootId", root_ids.astype(np.uint64), 1),
          ("rowStart", row_start, 1)]
split = col_idx.nbytes + weight.nbytes > FILE_CAP
plan = [("neurons.bin", arrays),
        ("synapses.bin", [("colIdx", col_idx, 1)] + ([] if split else [("weight", weight, 1)]))]
if split:
    plan.append(("weights.bin", [("weight", weight, 1)]))

layout, files = {}, {}
for fname, entries in plan:
    blobs, off = [], 0
    for name, arr, comps in entries:
        pad = -off % ALIGN
        if pad:
            blobs.append(b"\0" * pad)
            off += pad
        a = np.ascontiguousarray(arr)
        layout[name] = {"file": fname, "byteOffset": off, "dtype": a.dtype.name,
                        "count": int(a.size), "components": comps}
        blobs.append(a.tobytes())
        off += a.nbytes
    blob = b"".join(blobs)
    with open(os.path.join(OUT, fname), "wb") as f:
        f.write(blob)
    files[fname] = {"bytes": len(blob), "sha256": hashlib.sha256(blob).hexdigest()}

manifest = {
    "format": "desktopfly-connectome-1",
    "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "etlArgs": sys.argv[1:],
    "neuronCount": N,
    "edgeCount": E,
    "synapseTotal": int(conn.sum()),
    "minSyn": args.min_syn,
    "byteOrder": "little",
    "files": files,
    "arrays": layout,
    "stringTables": {"superClasses": sc_names, "sides": SIDES, "nts": NTS,
                     "roles": ROLES, "cellTypes": ct_names},
    "ntSign": {n: int(NT_SIGN[i]) for i, n in enumerate(NTS)},
    "signPolicy": "weight = sign x synapse count. sign is per PRE neuron: Codex nt_type "
                  "(ACH/DA/SER/OCT +1, GABA/GLUT -1); where nt_type is missing (nt = UNKNOWN, "
                  "ntSign 0) it falls back to the parquet's Excitatory call, which is constant "
                  "per presynaptic neuron (Dale's law); a neuron with neither source gets +1 and "
                  "has no out-edges. So an UNKNOWN nt byte does NOT imply an excitatory weight. "
                  "One prior overrides the parquet step: an nt_type-less neuron whose primary_type "
                  f"matches {AL_LN_RE.pattern} is an antennal-lobe local interneuron and is forced "
                  "to -1, because those are canonically inhibitory and the parquet mislabels them "
                  "excitatory. Neurons that DO have a Codex nt_type are never overridden.",
    "signFallback": {"neurons": n_fb, "inhibitory": n_fb_inh, "excitatory": n_fb - n_fb_inh,
                     "synapses": int(fb_mass), "inhibitorySynapses": int(fb_inh_mass),
                     "noSource": n_orphan, "alPriorRegex": AL_LN_RE.pattern,
                     "alPriorNeurons": n_al, "alPriorSynapses": int(al_mass)},
    "modulatoryNts": MODULATORY,
    "roleCounts": role_counts,
    "normalization": {"center_nm": center.tolist(), "scale": float(scale),
                      "axisFlip": [1, -1, -1], "fits": [-10.0, 10.0],
                      "formula": "pos = (raw_nm - center_nm) * scale * axisFlip"},
    "sources": {
        "classification": "FlyWire Codex FAFB v783 classification.csv.gz",
        "coordinates": "FlyWire Codex FAFB v783 coordinates.csv.gz",
        "cellTypes": "FlyWire Codex FAFB v783 consolidated_cell_types.csv.gz",
        "neurotransmitters": "FlyWire Codex FAFB v783 neurons.csv.gz (nt_type)",
        "connectivity": "eonsystemspbc/fly-brain 2025_Connectivity_783.parquet "
                        "(aggregated FlyWire proofread_connections_783, Zenodo 10676866)",
        "connectivityPath": os.path.relpath(PARQUET, os.path.dirname(os.path.abspath(__file__))),
        "connectivityUrl": "https://github.com/eonsystemspbc/fly-brain/raw/main/data/"
                           "2025_Connectivity_783.parquet",
        "license": "FlyWire data CC BY-NC 4.0 — see data/DATA_LICENSE.md",
    },
    "notes": {
        "index": "neuron index = rank of root_id ascending in classification.csv.gz",
        "csr": "rowStart[i]..rowStart[i+1] are neuron i's OUT-edges; colIdx ascending per row",
        "weight": "see signPolicy; modulatory (DA/SER/OCT) synapses are +1 here — "
                  "scale them at load using the per-neuron nt byte",
        "pos": "interleaved xyz float32; neurons without a coordinate are (0,0,0)",
        "side": "0 center/unknown, 1 left, 2 right",
    },
}
with open(os.path.join(OUT, "connectome.json"), "w") as f:
    json.dump(manifest, f, indent=1)

# --- report ------------------------------------------------------------------
print()
print(f"N = {N} neurons, E = {E} edges, Σ|weight| = {int(conn.sum())} synapses")
for fname, info in files.items():
    print(f"  data/{fname:14s} {info['bytes'] / 1e6:8.2f} MB  sha256 {info['sha256'][:16]}…")
print(f"  data/connectome.json {os.path.getsize(os.path.join(OUT, 'connectome.json')) / 1e3:6.1f} kB "
      f"({len(ct_names)} cell types, {len(sc_names)} super_classes)")

print("\nroles:")
for slug in ROLES[1:]:
    print(f"  {slug:8s} {role_counts[slug]:5d}")
print(f"  other    {role_counts['other']:5d}")

print("\ndegree (full graph):")
print(f"  out-degree  mean {out_deg.mean():7.2f}  max {int(out_deg.max()):6d}  "
      f"neurons with no out-edge {int((out_deg == 0).sum())}")
in_deg = np.bincount(col_idx, minlength=N)
print(f"  in-degree   mean {in_deg.mean():7.2f}  max {int(in_deg.max()):6d}  "
      f"neurons with no in-edge  {int((in_deg == 0).sum())}")
print(f"  neurons with no coordinate {int((~has_pos).sum())}, self-edges {int((pre == post).sum())}")

in_syn = np.bincount(post, weights=conn, minlength=N)
print("\nin-degree onto each command population (full graph):")
for slug in COMMAND_ROLES:
    m = role == ROLES.index(slug)
    print(f"  onto {slug:6s} n={int(m.sum()):3d}  {int(in_syn[m].sum()):7d} syn "
          f"({int(in_deg[m].sum()):6d} edges)")

loom = (role == ROLES.index("lc4")) | (role == ROLES.index("lplc2"))
m = loom[pre] & (role[post] == ROLES.index("gf"))
print(f"\nsanity: direct loom->GF edges: {int(m.sum())}, total syn: {int(conn[m].sum())}")

nt_mass = np.bincount(nt[pre], weights=conn, minlength=len(NTS))
nt_edges = np.bincount(nt[pre], minlength=len(NTS))
total = conn.sum()
print(f"\nNT class mass (by PRE neuron, {n_unknown} neurons have no nt_type):")
for i, name in enumerate(NTS):
    tag = f"sign {int(NT_SIGN[i]):+d}" if NT_SIGN[i] else "sign  fb"
    print(f"  {name:8s} {tag}  {int(nt_mass[i]):9d} syn "
          f"({100 * nt_mass[i] / total:5.2f}%)  {int(nt_edges[i]):9d} edges")
print(f"\nsign fallback (UNKNOWN nt):")
print(f"  {n_al} AL local interneurons ({AL_LN_RE.pattern}) forced INHIBITORY by prior "
      f"({al_mass:.0f} syn, {100 * al_mass / total:.2f}% of all mass)")
print(f"  {n_fb} neurons signed from the parquet ({fb_mass:.0f} syn, "
      f"{100 * fb_mass / total:.2f}% of all mass)")
print(f"    of those {n_fb_inh} are INHIBITORY ({fb_inh_mass:.0f} syn, "
      f"{100 * fb_inh_mass / total:.2f}% of all mass, now negative)")
print(f"  {n_orphan} UNKNOWN neurons had no out-edge at all -> +1 (moot)")
agree = sign[has_out] == pq_sign[has_out]
print(f"  sign agreement with the parquet over {int(has_out.sum())} presynaptic neurons: "
      f"{100 * agree.mean():.2f}% ({100 * out_mass[has_out][agree].sum() / total:.2f}% "
      f"synapse-weighted)")

lap("done")
