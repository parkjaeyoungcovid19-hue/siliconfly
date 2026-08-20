# 02 — Full-connectome ETL

Rewrote `etl.py` to emit the **entire** FlyWire FAFB v783 connectome (139,255
neurons / 15,091,983 edges) as binary CSR + per-neuron metadata, replacing the
668-neuron JSON circuit. Added `tools/verify_data.py`, an independent
re-reader. Both run clean; every headline number matches the recon note.

## Inputs

| input | rows | used for |
|---|---|---|
| `cache/flywire783/classification.csv.gz` | 139,255 | the neuron set + `super_class`, `side` |
| `cache/flywire783/coordinates.csv.gz` | 238,909 (139,255 unique) | `pos`, first row per neuron |
| `cache/flywire783/consolidated_cell_types.csv.gz` | 138,327 | `cellType`, core-population `role` |
| `cache/flywire783/neurons.csv.gz` | 139,255 | `nt_type` → synapse sign + `nt` byte |
| `cache/flywire783/2025_Connectivity_783.parquet` | 15,091,983 | every (pre, post, synapse count) pair |

**Parquet setup:** the parquet already lived in the repo at
`reference/fly-brain/data/2025_Connectivity_783.parquet` (100.8 MB). Rather
than copy 100 MB, I symlinked it so one `raw_dir` holds everything:

```sh
ln -sfn ../../reference/fly-brain/data/2025_Connectivity_783.parquet \
        cache/flywire783/2025_Connectivity_783.parquet
```

`cache/` and `reference/` are both in `.git/info/exclude`, so neither the
symlink nor the parquet is a git concern. `--parquet PATH` overrides it.

## Binary layout (the Swift loader's contract)

Everything is little-endian, 16-byte aligned, and described by
`data/connectome.json` — **read the manifest, do not hardcode offsets.** Each
array is a `{file, byteOffset, dtype, count, components}` record under
`arrays`. Current layout, N = 139,255, E = 15,091,983:

### `data/neurons.bin` — 4,177,712 B

| array | dtype | count | byteOffset | notes |
|---|---|---|---|---|
| `pos` | float32 | 417,765 | 0 | interleaved xyz, N×3 |
| `superClass` | uint8 | 139,255 | 1,671,072 | index into `stringTables.superClasses` (10) |
| `side` | uint8 | 139,255 | 1,810,336 | 0 center/unknown, 1 left, 2 right |
| `nt` | uint8 | 139,255 | 1,949,600 | 0 UNKNOWN, 1 ACH, 2 GABA, 3 GLUT, 4 DA, 5 SER, 6 OCT |
| `role` | uint8 | 139,255 | 2,088,864 | index into `stringTables.roles` (12, 0 = other) |
| `cellType` | uint16 | 139,255 | 2,228,128 | index into `stringTables.cellTypes` (8,773, 0 = none) |
| `rootId` | uint64 | 139,255 | 2,506,640 | FlyWire root ids, strictly ascending |
| `rowStart` | uint32 | 139,256 | 3,620,688 | CSR row offsets, `rowStart[N] == E` |

### `data/synapses.bin` — 90,551,902 B (86.4 MiB, under the 95 MB cap; no split needed)

| array | dtype | count | byteOffset |
|---|---|---|---|
| `colIdx` | uint32 | 15,091,983 | 0 |
| `weight` | int16 | 15,091,983 | 60,367,936 |

Semantics:

- **Neuron index** = rank of `root_id` ascending in `classification.csv.gz`.
  That single ordering is the index space for every array and for the CSR.
- **CSR row `i`** = neuron `i`'s **out**-edges, `rowStart[i] .. rowStart[i+1]`,
  `colIdx` strictly ascending inside a row.
- **`weight`** = `sign(PRE neuron) × synapse count`, one sign per presynaptic
  neuron (Dale's law, verified). Sign source, in order: Codex `nt_type`
  (ACH/DA/SER/OCT → `+1`, GABA/GLUT → `−1`); if `nt_type` is missing
  (`nt = UNKNOWN`, `ntSign["UNKNOWN"] == 0`) the parquet's own per-presynaptic
  `Excitatory` call; if neither, `+1` — which only happens for neurons with no
  out-edges. **One prior jumps ahead of the parquet step**: an `nt_type`-less
  neuron whose `primary_type` matches `^(lLN|il3LN|v2LN)` is an antennal-lobe
  local interneuron and is forced to `−1`. Neurons that *do* carry a Codex
  `nt_type` are never overridden. **An `UNKNOWN` `nt` byte does not imply an excitatory weight**;
  the manifest spells this out in `signPolicy`. Modulatory synapses are **not**
  pre-scaled: the loader scales them itself off the PRE neuron's `nt` byte
  (`modulatoryNts: ["DA","SER","OCT"]`).
- **`pos`** = `(raw_nm − center_nm) × scale × [1,−1,−1]`, the same transform the
  old ETL used: center the brain, uniform scale so the longest axis spans
  `[-10,10]`, flip y and z for FAFB's image-space axes. `center_nm =
  [494374, 247124, 139880]`, `scale = 2.4585125998770742e-05`. Rounding to 3
  decimals is gone (it was a JSON-size trick; float32 is exact enough).
  Neurons without a coordinate would be `(0,0,0)` — **there are none.**
- The manifest also carries `sha256` per file, `roleCounts`, the string
  tables, provenance strings, the generation timestamp and `etlArgs`.

## Run — `/opt/anaconda3/bin/python3 etl.py cache/flywire783`

```
[   0.1s] neurons: 139255 (super_classes 10, sides [203, 69959, 69093])
[   0.3s] coordinates: 139255/139255 placed, scale 2.45851e-05, center [494374.0, 247124.0, 139880.0]
[   0.4s] nt_type: 19658 UNKNOWN of 139255
[   3.2s] parquet: 15091983 pairs, Σ synapses 54492922, max pair 2405
[   3.7s] CSR: 139255 rows, 15091983 edges, Σ|w| 54492922
[   3.8s] roles: {'lc4': 104, 'lplc2': 210, 'gf': 2, 'dna01': 2, 'dna02': 2, 'dnp09': 2, 'dng11': 6, 'mdn': 4, 'escw': 6, 'ascend': 24, 'sens': 16}

N = 139255 neurons, E = 15091983 edges, Σ|weight| = 54492922 synapses
  data/neurons.bin        4.18 MB  sha256 c48bd4a0ab61dc91…
  data/synapses.bin      90.55 MB  sha256 8989e0b9b2316540…
  data/connectome.json  122.7 kB (8773 cell types, 10 super_classes)

roles:
  lc4        104
  lplc2      210
  gf           2
  dna01        2
  dna02        2
  dnp09        2
  dng11        6
  mdn          4
  escw         6
  ascend      24
  sens        16
  other    138877

degree (full graph):
  out-degree  mean  108.38  max   9783  neurons with no out-edge 1250
  in-degree   mean  108.38  max  10356  neurons with no in-edge  2165
  neurons with no coordinate 0, self-edges 0

in-degree onto each command population (full graph):
  onto gf     n=  2     9474 syn (   962 edges)
  onto dna01  n=  2    12495 syn (   855 edges)
  onto dna02  n=  2    25427 syn (  1493 edges)
  onto dnp09  n=  2    10287 syn (  1362 edges)
  onto dng11  n=  6     3535 syn (   589 edges)
  onto mdn    n=  4    10519 syn (  1772 edges)
  onto escw   n=  6    19253 syn (  3225 edges)

sanity: direct loom->GF edges: 293, total syn: 1885

NT class mass (by PRE neuron, 19658 neurons have no nt_type):
  UNKNOWN  sign  fb    3074064 syn ( 5.64%)     888842 edges
  ACH      sign +1   30604963 syn (56.16%)    8390201 edges
  GABA     sign -1   11808668 syn (21.67%)    2958815 edges
  GLUT     sign -1    8287368 syn (15.21%)    2554576 edges
  DA       sign +1     303110 syn ( 0.56%)     162743 edges
  SER      sign +1     280282 syn ( 0.51%)      75647 edges
  OCT      sign +1     134467 syn ( 0.25%)      61159 edges

sign fallback (UNKNOWN nt):
  94 AL local interneurons (^(lLN|il3LN|v2LN)) forced INHIBITORY by prior (298927 syn, 0.55% of all mass)
  18314 neurons signed from the parquet (2775137 syn, 5.09% of all mass)
    of those 5700 are INHIBITORY (1906535 syn, 3.50% of all mass, now negative)
  1250 UNKNOWN neurons had no out-edge at all -> +1 (moot)
  sign agreement with the parquet over 138005 presynaptic neurons: 99.61% (99.26% synapse-weighted)
[   4.2s] done
```

3.9 s wall, well under the 5-minute budget; peak RSS stays in the low
hundreds of MB (four int64 columns of 15M rows plus one radix argsort).
Two consecutive runs produced **byte-identical** binaries (same sha256s), so
the output is deterministic.

### Every expected number matched

| quantity | expected | got |
|---|---|---|
| N | 139,255 | 139,255 |
| E (`--min-syn 1`) | 15,091,983 | 15,091,983 |
| Σ Connectivity | 54,492,922 | 54,492,922 |
| LC4 / LPLC2 | 104 / 210 | 104 / 210 |
| gf / dna01 / dna02 / dnp09 | 2 / 2 / 2 / 2 | 2 / 2 / 2 / 2 |
| dng11 / mdn / escw | 6 / 4 / 6 | 6 / 4 / 6 |
| ascend / sens | 24 / 16 | 24 / 16 |

Zero deviations, so nothing to explain away.

### The in-degree numbers reconcile with recon

Recon's "in-circuit drive in the full graph" table was computed on the Codex
`syn>=5` graph. Restricting the new CSR to `|w| >= 5` reproduces it exactly,
which is the cleanest possible confirmation that the parquet ingest is right:

```
         full graph   |w|>=5   recon (syn>=5)
  gf          9474      8495      8495
  dna01      12495     11646     11646
  dna02      25427     23990     23990
  dnp09      10287      8691      8691
  dng11       3535      2838      2838
  mdn        10519      8453      8453
```

The gap is the 12.4M sub-threshold pairs the parquet adds. Same story for
loom→GF: 293 edges / 1,885 syn full graph, 188 edges / 1,601 syn at `syn>=5`.
**DNg11 now receives 3,535 synapses** instead of the 6 that the 668-neuron
subset delivered — the documented "noise-driven, not network-driven" bug is
structurally gone.

Also cross-checked: 1,250 neurons have no out-edge, 2,165 no in-edge, and
exactly **616 are fully isolated** — precisely recon's "in classification, NOT
in parquet: 616". No self-edges. All 15,091,983 parquet endpoints mapped into
the classification set; `index_of()` would have hard-exited otherwise.

## Verification — `/opt/anaconda3/bin/python3 tools/verify_data.py data`

`tools/verify_data.py` knows nothing about `etl.py`: it loads every array from
the manifest's `{file, byteOffset, dtype, count}` records with `np.fromfile`
and re-derives three edges straight from the parquet. **67 checks, 0 failures,
exit 0.**

```
manifest: desktopfly-connectome-1 generated 2026-08-19T01:55:15Z  args ['cache/flywire783']
N = 139255  E = 15091983  Σ synapses = 54492922  min_syn = 1

files:
  neurons.bin      4,177,712 B  sha256 c48bd4a0ab61dc912b82832720d456854b11b6b12f872b25c769b4e11fe48e6a
  PASS  neurons.bin size
  PASS  neurons.bin sha256
  PASS  neurons.bin under the 95 MB cap
  synapses.bin    90,551,902 B  sha256 8989e0b9b231654046c5726c92f5c825df1b0002aca4ed84b18dcaa76ed8c14b
  PASS  synapses.bin size
  PASS  synapses.bin sha256
  PASS  synapses.bin under the 95 MB cap

arrays:
  pos         float32  x417765     @         0 in neurons.bin
  PASS  pos fits in neurons.bin
  PASS  pos 16-byte aligned
  superClass  uint8    x139255     @   1671072 in neurons.bin
  PASS  superClass fits in neurons.bin
  PASS  superClass 16-byte aligned
  side        uint8    x139255     @   1810336 in neurons.bin
  PASS  side fits in neurons.bin
  PASS  side 16-byte aligned
  nt          uint8    x139255     @   1949600 in neurons.bin
  PASS  nt fits in neurons.bin
  PASS  nt 16-byte aligned
  role        uint8    x139255     @   2088864 in neurons.bin
  PASS  role fits in neurons.bin
  PASS  role 16-byte aligned
  cellType    uint16   x139255     @   2228128 in neurons.bin
  PASS  cellType fits in neurons.bin
  PASS  cellType 16-byte aligned
  rootId      uint64   x139255     @   2506640 in neurons.bin
  PASS  rootId fits in neurons.bin
  PASS  rootId 16-byte aligned
  rowStart    uint32   x139256     @   3620688 in neurons.bin
  PASS  rowStart fits in neurons.bin
  PASS  rowStart 16-byte aligned
  colIdx      uint32   x15091983   @         0 in synapses.bin
  PASS  colIdx fits in synapses.bin
  PASS  colIdx 16-byte aligned
  weight      int16    x15091983   @  60367936 in synapses.bin
  PASS  weight fits in synapses.bin
  PASS  weight 16-byte aligned
  PASS  pos count == 417765
  PASS  superClass count == 139255
  PASS  side count == 139255
  PASS  nt count == 139255
  PASS  role count == 139255
  PASS  cellType count == 139255
  PASS  rootId count == 139255
  PASS  rowStart count == 139256
  PASS  colIdx count == 15091983
  PASS  weight count == 15091983

CSR:
  PASS  rowStart[0] == 0
  PASS  rowStart[N] == E
  PASS  rowStart monotone non-decreasing
  PASS  all colIdx < N
  PASS  no zero weights
  PASS  |weight| within int16
  PASS  colIdx strictly ascending within each row

metadata:
  PASS  pos finite
  PASS  pos inside [-10,10]
  PASS  superClass in table
  PASS  side in table
  PASS  nt in table
  PASS  role in table
  PASS  cellType in table
  PASS  rootId strictly ascending
  PASS  role counts match manifest
  roles: lc4=104, lplc2=210, gf=2, dna01=2, dna02=2, dnp09=2, dng11=6, mdn=4, escw=6, ascend=24, sens=16
  PASS  every known-nt weight sign matches its PRE neuron's nt sign
  PASS  one sign per PRE neuron (Dale's law)
  PASS  AL local interneurons (^(lLN|il3LN|v2LN), no nt_type) have only non-positive weights
  PASS  signFallback.alPriorNeurons matches the data
  PASS  signFallback.alPriorSynapses matches the data
  PASS  sign fallback took effect (UNKNOWN-nt neurons with negative weights)
  PASS  signFallback.neurons matches the data
  PASS  signFallback.inhibitory matches the data
  PASS  signFallback.noSource matches the data
  PASS  signFallback.inhibitorySynapses matches the data
  fallback: 94 AL local interneurons forced inhibitory, 18314 signed from the parquet (5700 inhibitory)
  PASS  Σ|weight| matches manifest

parquet spot-checks (cache/flywire783/2025_Connectivity_783.parquet):
  PASS  heaviest edge: 720575940644702112 -> 720575940625952755 = 2405 syn
  PASS  strongest LC4->DNp01: 720575940614582946 -> 720575940632499757 = 16 syn
  PASS  random edge (seed 783): 720575940639837299 -> 720575940637872105 = 1 syn

N = 139255  E = 15091983  Σ|w| = 54492922  out-degree mean 108.38 max 9783

ALL CHECKS PASSED
```

Checks performed: file sizes + sha256 + the 95 MB cap; every array's extent
inside its file and 16-byte alignment; all ten array counts; `rowStart[0]==0`,
`rowStart[N]==E`, monotone; `colIdx < N`; no zero weights; `|weight|` within
int16; `colIdx` strictly ascending within every row; `pos` finite and inside
`[-10,10]`; every string-table index in range; `rootId` strictly ascending;
role counts equal to the manifest; **every known-nt weight's sign equal to its
PRE neuron's `nt` sign**, one sign per PRE neuron (Dale), the sign fallback
having actually fired, no AL local interneuron emitting a positive weight, and
all six `signFallback` counters equal to the data; Σ|w| equal to the manifest; and three parquet
spot-checks — heaviest edge, strongest LC4→DNp01, and a seeded random edge.

## Surprises / risks

1. **19,658 neurons (14.1%) have no `nt_type` in Codex `neurons.csv.gz`** —
   their per-NT average scores never clear the confidence cutoff (max score
   across all six columns is 0.53). They carry 3,074,064 synapses, 5.64% of
   total mass. **Resolved by the sign fallback** (coordinator decision, applied
   after the first run): 18,408 of them have out-edges and take their sign from
   the parquet's `Excitatory` column, of which **5,722 come out inhibitory,
   worth 1,924,102 synapses (3.53% of all mass) that the naive `+1` default
   would have signed excitatory**. The remaining 1,250 have no out-edge at all
   (they are exactly the 1,250 out-degree-zero neurons — a neuron with no
   presynapses gets no NT prediction) so their `+1` is moot. Their `nt` byte
   stays `UNKNOWN`, so the loader still knows the NT is unmeasured.
   Sign agreement with the parquet went 95.51% → 99.66% per neuron; after the
   AL prior below it settles at **99.61% per neuron, 99.26% synapse-weighted**.
   The residual is the ~2.5% of neurons where Codex `nt_type` and the parquet's
   NT snapshot genuinely disagree (recon §3b), plus the AL prior — in both
   cases we deliberately do not follow the parquet.

2. **Antennal-lobe local interneurons needed an inhibitory prior** (tuning-phase
   diagnosis, second coordinator change). 77 AL local neurons across
   `lLN1_bc`, `lLN2X03/04/05/11/12`, `lLN2T_c/e`, `lLN2F_a/b` have no Codex
   `nt_type`, and the parquet fallback signed most of them `+1` (29 of the 30
   `lLN1_bc`), producing a mutual-excitation loop pinned at the 500 Hz
   refractory ceiling. AL local neurons are canonically inhibitory (GABA, some
   Glut), so an `nt_type`-less neuron matching `^(lLN|il3LN|v2LN)` now gets
   `−1` before the parquet is consulted. **94 neurons take the prior**
   (the regex spans the whole family, not just the 10 diagnosed types),
   carrying **298,927 synapses, 0.55% of total mass**, all now negative;
   44 of the 77 diagnosed neurons are among them. Residual worth knowing:
   **148 regex-matching neurons DO have a Codex `nt_type` and were left alone
   per the rule — 43 GABA, 51 GLUT, 24 SER, and 30 that Codex calls ACH.**
   Those 30 stay excitatory. If the loop persists, they are the next suspects.
3. **`etl.py` no longer emits `data/brain_points.json` or `data/circuit.json`.**
   Both files are untouched on disk and the app still reads them, but they are
   now orphaned outputs: regenerating from scratch will not recreate them.
   They must be deleted when the Swift loader switches over, or the old ETL
   recovered from git history if they are ever needed again.
4. **`data/synapses.bin` is 90.6 MB.** Under the 95 MB cap and under GitHub's
   100 MB hard limit, but well over the 50 MB soft warning — pushes will print
   a large-file warning, and the repo gains ~91 MB permanently. `etl.py`
   auto-splits `colIdx` / `weight` into `synapses.bin` + `weights.bin` if the
   combined size ever crosses 95 MB, and the manifest is per-array
   file-addressed, so the loader needs no change if that happens.
   `--min-syn 2` would cut E to 7,595,967 (~45 MB) if size ever bites.
5. **Uniform scale over raw coordinate units.** `coordinates.csv` positions are
   FAFB nanometres; the transform assumes all three axes share one unit, which
   the old ETL also assumed. The resulting cloud spans x 20.0, y 9.63, z 6.85 in
   normalized units — plausible for a fly brain (wider than tall than deep), so
   no evidence of per-axis distortion. Unchanged from the shipped behavior
   either way.
6. **The parquet is not sorted by (pre, post)**, so the ETL always runs a
   radix argsort over 15M keys (`pre*N + post`). Cheap (~0.3 s) and it doubles
   as the duplicate-pair check: the ETL hard-exits if any (pre, post) repeats.
7. **`python3 -m py_compile` left a root `__pycache__/`** during development.
   Removed; `.gitignore` does not cover it, so avoid `py_compile` at the repo
   root (or add the pattern — out of scope for this pass).

Not verified: nothing in the Swift app was built or run (per the hard rules),
so the binaries have never been read by a Swift loader. The layout contract
above is the only thing standing between this data and that loader.

## Files created / modified

- `etl.py` — rewritten (312 lines): full connectome → binary CSR + metadata.
- `data/connectome.json` — new, 121,725 B manifest.
- `data/neurons.bin` — new, 4,177,712 B.
- `data/synapses.bin` — new, 90,551,902 B.
- `tools/verify_data.py` — new, independent manifest-driven verifier (67 checks).
- `README.md` — "Regenerating the data" section rewritten (file table, the
  five curl lines, the numpy/pyarrow interpreter note, verify command).
- `data/DATA_LICENSE.md` — parquet provenance added (eonsystemspbc/fly-brain
  aggregation of `proofread_connections_783`, Zenodo 10676866, CC BY-NC 4.0).
- `notes/02-etl.md` — this file.
- `cache/flywire783/2025_Connectivity_783.parquet` — symlink (git-excluded).
- `cache/etl_run.out`, `cache/verify_run.out` — captured stdout (git-excluded).

Untouched: all `.swift` files, `CLAUDE.md` (its only diff is the owner's
pre-existing protected section), `.gitignore`, `build.sh`,
`data/brain_points.json`, `data/circuit.json`. No git state was changed.

## Commands

```sh
/opt/anaconda3/bin/python3 etl.py cache/flywire783      # ~4 s, rebuilds data/
/opt/anaconda3/bin/python3 tools/verify_data.py data    # 67 checks, exit 0
```
