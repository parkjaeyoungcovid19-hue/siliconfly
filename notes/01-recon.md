# 01 — Recon for the full-connectome Metal port

Research only. No app code was changed. Every number below came from a command
run in this session; the reproducible script is `cache/recon_stats.py`
(output archived at `cache/recon_stats.out`).

---

## 1. Key numbers

### The graph (three candidate edge sets, all FAFB v783)

| edge set | neurons | edges | Σ synapses | source | on disk? |
|---|---|---|---|---|---|
| Codex `connections.csv.gz`, aggregated per (pre,post) | **134,181** endpoints | **2,700,513** | **34,153,566** | `cache/flywire783/connections.csv.gz` (50.3 MB) | yes, downloaded |
| fly-brain parquet (**no threshold**) | **138,639** | **15,091,983** | **54,492,922** | `reference/fly-brain/data/2025_Connectivity_783.parquet` (100.8 MB) | yes, already in repo |
| webgpu-fly (Zenodo `proofread_connections_783.feather`) | 139,255 | **15,091,983** | not reported | Zenodo 10676866, 852 MB | no |

The fly-brain parquet and webgpu-fly's feather are **the same 15,091,983-edge
graph** (see §4). The parquet is already on disk; the feather is an 852 MB
download we do not need.

### Neuron inventory (`classification.csv.gz`, 139,255 rows / 139,255 unique root_ids)

```
super_class counts:              side counts:          flow counts:
optic                 77873      left    69959         intrinsic  118464
central               32381      right   69093         afferent    19300
sensory               16938      center    173         efferent     1491
visual_projection      7684      NaN        30
ascending              1750
descending             1305
sensory_ascending       612
visual_centrifugal      522
motor                   110
endocrine                80
```

- `coordinates.csv.gz`: 238,909 rows, **139,255 unique root_ids** (multiple
  coordinate rows per neuron).
- `consolidated_cell_types.csv.gz`: 138,327 rows, all with a `primary_type`,
  **8,772 distinct primary_types**.
- Overlap: **139,255 neurons have BOTH a classification row and a coordinate.**
  `classified but NO coordinate: 0`, `coordinate but NOT classified: 0`.
- Connection endpoints lacking a coordinate: **0**. Lacking a classification
  row: **0**. Classified neurons with no edge at all (syn>=5): **5,074**.

### Degree structure (syn>=5 aggregated graph)

```
neurons with >=1 outgoing edge: 129351
neurons with >=1 incoming edge: 125192
distinct neurons appearing as an endpoint: 134181
out-degree: mean 20.88 max 6399
in-degree:  mean 21.57 max 5080
out-synapses per neuron: mean 264.0 max 92957
in-synapses per neuron:  mean 272.8 max 67616

out-degree percentiles: 50% 12   90% 43   99% 138   99.9% 466   max 6399
neurons with out-degree > 1000: 32
```

Top-5 out-degree:

```
720575940626979621  out_deg=  6399  out_syn=  92625  optic / optic_lobe_intrinsic / CT1
720575940628908548  out_deg=  6211  out_syn=  92957  optic / optic_lobe_intrinsic / CT1
720575940613583001  out_deg=  2763  out_syn=  50012  central / MBIN / APL
720575940624547622  out_deg=  2761  out_syn=  59464  central / MBIN / APL
720575940625952755  out_deg=  2053  out_syn=  36497  optic / optic_lobe_intrinsic / Li33
```

Top-5 in-degree: the same two CT1s (5,080 / 4,780), the same two APLs
(2,843 / 2,818), then `720575940620975696` DPM (2,568).

### Neurotransmitter distribution (`connections.csv.gz`, 3,869,878 raw rows)

```
nt_type ROWS:              nt_type SYNAPSE-WEIGHTED:
ACH     2258155            ACH     19547816
GABA     865318            GABA     8285491
GLUT     654183            GLUT     5646373
DA        37705            SER       340040
SER       37450            DA        238084
OCT       17067            OCT        95762
```

Excitatory (ACH) is 57.2% of synapses; inhibitory (GABA+GLUT) 40.8%;
modulatory (DA/SER/OCT) 2.0%.

### Core cell-type counts (`consolidated_cell_types.primary_type`)

```
LC4      104      DNp01    2      DNg11    6      DNp02    2
LPLC2    210      DNa01    2      MDN      4      DNp04    2
                  DNa02    2                      DNp11    2
                  DNp09    2
```

All match the counts in `CLAUDE.md`'s mapping table exactly — the current ETL
is picking up the right populations.

Side split + in-circuit drive **in the full graph** (this is the number
`CLAUDE.md` warns about for the 668-neuron subset):

```
LC4    n= 104 sides={'left': 54, 'right': 50} in_syn= 72894 (mean 701/neuron)
LPLC2  n= 210 sides={'left':108, 'right':102} in_syn= 64102 (mean 305/neuron)
DNp01  n=   2 L1/R1  in_syn=  8495 (mean 4248/neuron)
DNa01  n=   2 L1/R1  in_syn= 11646 (mean 5823/neuron)
DNa02  n=   2 L1/R1  in_syn= 23990 (mean 11995/neuron)
DNp09  n=   2 L1/R1  in_syn=  8691 (mean 4346/neuron)
DNg11  n=   6 L3/R3  in_syn=  2838 (mean  473/neuron)
MDN    n=   4 L2/R2  in_syn=  8453 (mean 2113/neuron)
DNp02  n=   2 L1/R1  in_syn=  4703 (mean 2352/neuron)
DNp04  n=   2 L1/R1  in_syn=  4818 (mean 2409/neuron)
DNp11  n=   2 L1/R1  in_syn=  5858 (mean 2929/neuron)
```

**DNg11 gets 2,838 in-synapses in the full graph** vs the 6 synapses that the
668-neuron subset delivered (the documented "noise-driven, not network-driven"
bug). Going full-connectome fixes that class of bug structurally.

### Other DN types

- `super_class == 'descending'`: **1,305 neurons**, all 1,305 have a
  `primary_type`, across **473 distinct primary_types**.
- Primary_types matching `DN*`/`aDN*`/`oviDN*`: **481 distinct types /
  1,342 neurons**; of those, **470 types / 1,331 neurons have >=2 members**.
- Explicitly requested counts:

```
DNp03 2   DNb01 2   DNa03 2   DNa06 2   DNg74 0   aDN1 0
DNp06 2   DNb02 4   DNa04 2   DNa07 2   oviDN 0   aDN2 0
DNp10 2   DNg13 2   DNa05 2   DNa08 2   DNpe  0
```

`DNg74`, `oviDN`, `aDN1/2`, `DNpe` are **0 as exact strings** — v783 uses
suffixed names: `DNg74_b` (2), `oviDNa_a` (2), `oviDNa_b` (2), and `DNpe001`
… `DNpe054` (many, 2–18 each). Match by prefix, not exact string.

Largest DN populations in v783 (>=8 members):

```
DNg12_b 18  DNpe008 18  DNge091 17  DNge071 16  DNg07 16  DNge094 14
DNg106  14  DNg08_a 14  DNp17   12  DNge019 12  DNg10 12  DNge085 11
DNg06   11  DNg03   10  DNpe015 10  DNg08_b  8  DNpe009 8  DNpe054  8
DN1pA    8  DNg09    8  DN1pD    8  DNpe012  8  DNge089 8  DNge020  8
DNg12_e  8  DNg01    8  DNge115  8  DNg12_a  8
```

Full list in `cache/recon_stats.out` §10.

### GPU footprint (u32 col_idx + f32 weight CSR, f32 v + i32 acc + u32 refr state)

```
Codex syn>=5 (aggregated)          N= 134181 E=  2700513  CSR=  22.1 MB  state=1.6 MB  total=  23.8 MB
fly-brain parquet (no threshold)   N= 138639 E= 15091983  CSR= 121.3 MB  state=1.7 MB  total= 123.0 MB
syn>=5 minus optic-internal edges  N=  63449 E=  1241027  CSR=  10.2 MB  state=0.8 MB  total=  10.9 MB
```

Both full options fit trivially in 48 GB unified memory. The relevant cost is
**app bundle / download size**, not VRAM.

Edge counts at every threshold (derived from the no-threshold histogram):

```
syn>=1: 15,091,983    syn>=3: 4,916,231    syn>=5: 2,700,513
syn>=2:  7,595,967    syn>=4: 3,537,227
```

Optic-lobe share (syn>=5): 86,079 neurons are in `optic` /
`visual_projection` / `visual_centrifugal`; **1,459,486 edges (54.0%) have
both endpoints optic**; 1,064,005 edges have neither endpoint optic.

---

## 2. webgpu-fly design summary

All citations relative to `reference/webgpu-fly/`.

### 2a. Data source & scale — **it does NOT use the Codex dumps**

The single biggest correction to our starting assumption. `tools/download_data.sh:10`
sets `ZENODO="https://zenodo.org/records/10676866/files"` and pulls three things
(`download_data.sh:12-15, 20-23, 28-30`):

1. `proofread_connections_783.feather` (**852 MB**) — Zenodo 10676866
2. `proofread_root_ids_783.npy` (1.1 MB) — same deposit
3. `git clone https://github.com/flyconnectome/flywire_annotations.git`, of which
   it reads `supplemental_files/Supplemental_file1_neuron_annotations.tsv`
   (`tools/build_csr.py:141`). That TSV replaces Codex's classification +
   coordinates + consolidated_cell_types in one file (it carries `soma_x/y/z`,
   `pos_x/y/z`, `top_nt`, `top_nt_conf`, `super_class`, `cell_type`).

**No synapse-count threshold is applied anywhere in the pipeline.** The only
threshold is on NT-prediction confidence: `CONF_THRESHOLD = 0.5`
(`build_csr.py:68`), applied at `build_csr.py:202`. Result: **15,091,983 edges**
(`LIMITATIONS.md:240`), described at `LIMITATIONS.md:47-51` as "the *aggregated*
proofread connection table (~15M unique (pre, post) pairs, with each pair's
synapse count summed into its weight), **not** the ~54M raw synapses."

Aggregation is a defensive re-groupby (`build_csr.py:252-256`):
```python
if "neuropil" in edges.columns or len(edges) > 5_000_000:
    edges = edges.groupby(["pre", "post"], as_index=False, sort=False)["weight"].sum()
```

**Signing** (`build_csr.py:70-77`, verbatim):
```python
NT_SIGN = {"acetylcholine": +1.0, "gaba": -1.0, "glutamate": -1.0,
           "dopamine": 0.0, "serotonin": 0.0, "octopamine": 0.0}
```
Applied **per presynaptic neuron** (Dale's law), not per edge. Unknown or
low-confidence NT → sign 0, and the edge is **kept as a zero-weight structural
entry**, not dropped (`build_csr.py:271-274`). Final weight is simply
`sign(pre_nt) × summed_synapse_count`, dtype **f32**, **no scaling, no
quantization, no in-degree or out-degree normalization** (verified: no
`normal*`/`clip`/`clamp` in `build_csr.py`).

**Layout: CSR indexed by POST (i.e. incoming edges / a gather)**
(`build_csr.py:276-287`). Rationale at `CLAUDE.md:96-99`: "Outgoing CSR would
require a scatter (atomicAdd contention on hot postsynaptic targets)."
`col_idx[k]` holds the **pre** index. Note: **within a row, `col_idx` is
unsorted** (`np.argsort(post_idx, kind="stable")` sorts on the post key only).

On-disk: one file `public/brain.bin`, magic `"WGFLYBRN"`, 64-byte header, then
N × 32-byte neuron records (pos xyz f32, sign f32, cell_type u32, super_class
u32, flags u32, nt_conf f32), then `row_ptr` u32[N+1], `col_idx` u32[E],
`weight` f32[E] (`build_csr.py:14-46`, `:292-304`; parser `src/brain.ts:49-113`).
Neuron dense index = position in `proofread_root_ids_783.npy`
(`build_csr.py:154-155`) — **no locality reordering**.

**brain.bin is a one-way door on identity**: root_ids are dropped entirely and
cell types are FNV-1a hashed to 24 bits + an 8-bit "hero" enum
(`build_csr.py:125-135`). Nothing downstream can recover a FlyWire ID or type
name. That is why the DN roster must be resolved at build time and shipped
separately in `brain.meta.json`.

**Hosting / can we grab their CSR?** Not from this repo. `upload_to_r2.sh:35`
uses `BUCKET="${R2_BUCKET:-webgpu-fly-assets}"` and every URL in-tree is a
`<placeholder>` template; the concrete `VITE_BRAIN_URL` lives in `.env.production`,
which is gitignored, so the literal only exists inside the deployed bundle.
`public/brain.bin` is also gitignored and **not present on disk here**. Size:
`DEPLOY.md:12-15` and `README.md:186` say "120 MB"; the format spec with the real
counts gives 64 + 32×139,255 + 4×139,256 + 8×15,091,983 = **125,749,112 B ≈ 125.7 MB**,
corroborated by `src/cache.ts:69` ("42.0 / 125.7 MB"). **We do not need it** — see §4.

### 2b. LIF model, exact (`src/shaders/lif.wgsl`, `src/sim.ts`)

`DEFAULT_PARAMS`, `src/sim.ts:31-40`:

| constant | value | citation |
|---|---|---|
| `dtMs` | **1.0 ms** | `sim.ts:32` |
| `tauMs` (membrane) | **20.0 ms** | `sim.ts:33` |
| `alpha` = `exp(-dt/tau)` | **0.9512294** (host-computed, uploaded as uniform) | `sim.ts:266` |
| `vThresh` | **−45.0 mV** | `sim.ts:34` |
| `vReset` | **−52.0 mV** | `sim.ts:35` |
| `vRest` | **−52.0 mV** | `sim.ts:36` |
| `refractoryMs` | **2.2 ms** → `round(2.2/1.0)` = **2 steps** | `sim.ts:37`, `:267` |
| `extGain` | **2.0** | `sim.ts:38` |
| `wSyn` | **0.005 mV** | `sim.ts:39` |
| `A_SYN` = `exp(-dt/tau_syn)`, tau_syn = 5 ms | **0.81873**, a hardcoded WGSL `const` | `lif.wgsl:44-48` |

These are Shiu et al. 2024 (Nature 632:210-217) values (`sim.ts:19-22`) — and
they match `reference/fly-brain/`'s Brian2 params exactly except for `w_syn`
(see §3).

Membrane update is **exponential Euler**, `lif.wgsl:91-93`:
```wgsl
let v_new = params.v_rest + params.alpha * (v_old - params.v_rest) + i_in;
```
`i_in` is a raw mV increment per step — **not** divided by dt or tau.

**Two-state alpha synapse** (this is the part Sim.swift doesn't have),
`lif.wgsl:72-77`:
```wgsl
let gy_new = g_y[i] * A_SYN + gx_old;
let gx_new = gx_old * A_SYN + delta_in;
let i_syn = gy_new * params.w_syn;
```

Spike: `if (v_new >= params.v_thresh)` → `vm = v_reset`, `refrac = 2`,
`atomicOr(&spikes_curr[i>>5], 1u << (i&31))` (`lif.wgsl:96-102`). `v_reset ==
v_rest` so there is **no post-spike undershoot**. Threshold gap = **7 mV**.
Max rate = 1 spike / 3 steps = **333 Hz**.

**Refractory ordering gotcha**: the early-return sits *after* the synapse update
and *before* the membrane integration (`lif.wgsl:83-88`), so `g_x`/`g_y` keep
integrating through the refractory window; only the membrane is pinned to
`v_reset`. Get this backwards and the dynamics change.

**Kernel structure**: one thread per **post**synaptic neuron, gathering its full
CSR row **every step regardless of activity** (`lif.wgsl:62-68`) — no spike
compaction, no indirect dispatch, no early-out. Presynaptic state is read from a
packed bitset (`lif.wgsl:50-53`), so the hot working set is
`ceil(139255/32)*4 = 17,408 B` (17 KB) and stays cache-resident.

**Atomics: exactly one, `atomicOr` on the spike bitset.** No `atomicAdd`, no
float atomics, no fixed-point scale factor anywhere — the gather design means no
thread ever writes another neuron's accumulator. Workgroup size **64**
(`lif.wgsl:42`). No subgroup/wave ops, no threadgroup memory.

Two dispatches per step in one compute pass: `clear_spikes` (68 workgroups) then
`step_lif` (2,176 workgroups) (`sim.ts:311-334`). Spike bitsets ping-pong
(`spikesA`/`spikesB`, two prebuilt bind groups, `sim.ts:130-139`, `:228-229`);
everything else (`vm`, `refrac`, `g_x`, `g_y`) is updated in place.

**Synaptic delay: none modelled.** No ring buffer, no per-edge or per-sign delay.
What you get is implicit: 1 step from the spike ping-pong (`lif.wgsl:14-15`) plus
1 step from the `g_y ← g_y*A + gx_old` ordering → **a presynaptic spike first
moves the postsynaptic Vm at t+2 ms**, identical for excitation and inhibition.

**Noise: none. Zero.** No PRNG, no Poisson, no tonic bias, no per-neuron
heterogeneity of any kind (every neuron shares the uniform's constants). The sim
is fully deterministic by design — `src/game.ts:17` relies on replay-by-URL
re-executing "the identical neuron cascade". The *only* drive is a host-written
`ext_input : f32[N]` buffer: `i_in = i_syn + ext_input[i] * params.ext_gain`
(`lif.wgsl:80`), with `ext_gain = 2.0` the single global "arousal" knob.
"Spontaneous" mode writes an all-zero buffer (`main.ts:86-90`) — with no noise
floor the network simply decays.

Stimulus amplitudes in use: visual flash 0.5 (`main.ts:65`), olfactory 0.8
(`main.ts:74`), mixed sensory 0.4 (`main.ts:83`), DN keypress `STIM_AMP = 4.0`
(`game.ts:45`), single-cell pulse 2.0 (`main.ts:1322`), closed-loop visual
`1.5 + 12*area` (`main.ts:1097-1099`).

**Stability guards: there are none.** No Vm clamp (`grep "clamp\|min(\|max("
src/shaders/lif.wgsl` → zero hits), no clamp on `delta_in`/`g_x`/`g_y`/`i_syn`,
no in-degree normalization, no adaptation, no homeostatic gain, no activity
controller. Stability rests **entirely on the one hand-tuned scalar
`w_syn = 0.005`** (`sim.ts:24-30`: 0.005 was chosen empirically to land Kenyon
cells at 5-15% active; peak-matching Shiu's 0.275 gave 73%, "way too hot a
brain"). The only bound in the system is cosmetic: `rate ∈ [0,1]`
(`sim.ts:420-421`).

**Buffers @ N=139,255 / E=15,091,983** (`sim.ts:103-177`): `row_ptr` u32[N+1]
0.53 MiB, `col_idx` u32[E] **57.57 MiB**, `weight` f32[E] **57.57 MiB**, two
spike bitsets 17 KB each, `vm`/`refrac`/`ext_input`/`g_x`/`g_y`/`accum` 0.53 MiB
each. **Total ≈ 118.9 MiB, of which the CSR is 97.3%** — and essentially all of
it is streamed every single step.

### 2c. Performance

**~0.25 kHz of biological time on an Apple M2 Pro 16 GB — i.e. 4× slower than
real time, ~4 ms wall per 1 ms simulated** (`LIMITATIONS.md:27-36`), which also
states plainly: "It is **memory-bandwidth-bound**, not compute-bound. The gather
over CSR rows dominates; adding more GPU ALUs would not help."

Same-machine comparison, `README.md:150-154`:

| engine | bio-time rate |
|---|---|
| NEST 3.10 (C++ reference) | **0.67 kHz** |
| hand-written multicore Rust (`tools/cpu-bench/`) | **0.45 kHz** |
| webgpu-fly (WebGPU) | **0.25 kHz** |

The Rust CPU port is **1.8× faster than the WebGPU kernel**. The 1 kHz target
(`CLAUDE.md:7-8`, `src/bench.ts:115`) was unreachable for all three on M2 Pro
(`README.md:156-157`). CI floor: `expect(result.bioKHz).toBeGreaterThan(0.12)`
(`tests/bench.spec.ts:78-83`, "~0.26 kHz on M2 Pro 16 GB as of 2026-05-07").
Derived: 0.25 kHz × 15.09M edges ≈ **3.8 G-edges/s**.

**Batching / readback**: `step(n)` submits **once per 1 ms step** (bench only).
The path everything real uses is `captureRollingRate(windowSteps)`
(`sim.ts:363-423`): **one `writeParams`, one command encoder, one submit for the
entire window**, then a single `copyBufferToBuffer` + `mapAsync` of the
`u32[N]` per-neuron spike-count accumulator. **No double buffering, no
pipelining** — the caller awaits the map, and a fresh staging buffer is
allocated and destroyed every call (`sim.ts:370-374`, `:417`). Windows in use:
10 steps for stim snapshots (`main.ts:93-94`), **50 steps for the game brain
loop** (`game.ts:46`), 50 for closed-loop visual (`main.ts:1106`), 20 for the VNC
(`main.ts:461`). Per-step CPU work inside the window is only bind-group select +
pass/dispatch calls; the O(N) `counts → rate` normalization happens once per
window (`sim.ts:419-422`).

### 2d. Brain → body mapping

There is **no DN list in `src/brain.ts`** — that file is a pure 114-line binary
parser. The roster is authored in Python and shipped in `brain.meta.json`.

Verbatim, `tools/build_csr.py:314-325`:
```python
famous_labels = {
    "DNa01": "forward walking (Cande et al. 2018)",
    "DNa02": "forward walking, faster (Bidaye et al.)",
    "DNb01": "backward walking — 'moonwalker' (Bidaye 2014)",
    "DNp01": "Giant Fiber — escape jump (Wyman 1984)",
    "DNp09": "looming-evoked freezing/jump (von Reyn et al. 2014)",
    "DNp52": "forward walking — Dallmann walking circuit (2026)",
    "DNg13": "turning",
    "MDN":   "moonwalking (backward) command — Bidaye et al.",
    "RRN":   "forward walking — Roadrunner neurons (Dallmann 2026); cell_type CB0257",
    "BPN":   "forward walking — Bolt protocerebral neurons (Bidaye 2020); 32 cells across BPN1-4",
}
```
**10 entries.** Two need alias resolution: `RRN → CB0257`
(`build_csr.py:328`) and `BPN → ("BPN1","BPN2","BPN3","BPN4")` resolved by
root_id from a manually-downloaded Dallmann et al. 2026 xlsx
(`build_csr.py:331`, `:352-366`). A second roster of **21 walking-circuit DNs**
is emitted but unused by the UI (`build_csr.py:375-382`): `DNp52, DNg101,
DNg102, DNp64, DNge050, DNd05, DNge048, DNa45, DNge082, DNpe020, DNg44,
DNge103, DNpe053, DNp13, DNp42, DNge150, DNp68, DNp69, DNpe042, DNp45, DNp55`.

**Rate = a spike-count window, not an EMA** (`sim.ts:356-358`): per-neuron spike
counts over `windowSteps`, normalised to spikes-per-step in [0,1]. dt = 1 ms so
window steps ≈ ms of biological time.

The actual brain→body handoff, `main.ts:451-459`:
```typescript
let sum = 0;
for (const i of brainIdxs) sum += brainRate[i];
const meanBrain = brainIdxs.length ? sum / brainIdxs.length : 0;
const drive = meanBrain * 30;
```
i.e. **mean spikes-per-step over that DN's L+R copies × gain 30**, written into
every VNC neuron sharing the cell-type *name string* — a join across two
different animals' connectomes (`README.md:112-113`, caveated at
`LIMITATIONS.md:195-196`). EMA appears only downstream on the two final scalars:
`const alpha = 0.35` blend on `driveFwd`/`driveTurn` (`main.ts:598-600`) and
`decayDrive()` `*= 0.85` (`main.ts:607-609`).

Scale of the funnel, `LIMITATIONS.md:240-243`:
```
FlyWire   139,255 neurons / 15,091,983 edges
   ↓  name join: 7 DN types → 16 of 23,188 VNC neurons (0.069%)
   ↓  L and R copies collapsed to one scalar each
MANC       23,188 neurons /  5,243,574 edges
```
`LIMITATIONS.md:14`: "Roughly 20.3 million connectome edges reach the body as
about one scalar magnitude plus a turn bias per tick."

### 2e. Stability & tuning lessons (LIMITATIONS.md / README.md / CLAUDE.md)

The headline: **there is no homeostasis, no arousal controller, no activity
target, no adaptive gain.** Stability comes from one hand-fitted scalar plus the
total absence of background drive.

- **`w_syn` is the whole story.** `src/sim.ts:25-30` (repeated at
  `LIMITATIONS.md:69-74`): "w_syn is tuned EMPIRICALLY (not from peak-matching)
  to land KC at the canonical 5-15% on Mixed sensory. Alpha synapse integrates
  each spike over ~5ms so the cascade amplifies non-linearly vs old single-step
  direct injection — **peak-matching gives way too hot a brain (73% KC)**. 0.005
  keeps the dataset's natural cascade strength visible without runaway."
  **That is their seize mode**: literature weight + a real alpha synapse →
  73% of Kenyon cells active. The fix was to shrink the weight, not to add a
  regulator.
- `LIMITATIONS.md:64-65`: "**`w_syn` is not taken from Shiu et al. — it is
  fitted to the number we then report.**" And `:76-82`: "KC sparsity is a
  **calibration target, not an independent validation**."
- **Silence is the pass condition, not a bug.** `CLAUDE.md:80-82`: "with no
  input, network goes silent within ~50 ms (no runaway)". The "Spontaneous"
  preset is literally an all-zero `ext` vector, hinted "no input — baseline
  drift" (`main.ts:85-90`), and the e2e test is named "Spontaneous keeps brain
  quiet (KC < 5%)" (`tests/smoke.spec.ts:648-661`). **There is no spontaneous
  firing rate to report — the intended baseline is ~0%.**
- **Ignition thresholds they found empirically**:
  - Direct DN stim needs `ext = 4.0`; `main.ts:973-977`: "**Lower than ~3.0
    leaves DN-with-weak-downstream (DNb01, DNg13, DNp01) firing only the 2
    stimmed cells with no propagation.**"
  - Optic drive needs *breadth*: they inject into 4,000 optic neurons per side,
    because `main.ts:1066-1068` "**Below ~2000 the signal dissipates before
    producing meaningful DN activity.**"
- **Guard bands enforced in CI** (`tests/smoke.spec.ts`): KC 5–30% on mixed
  sensory (`:78-79`), DN > 5% under broad sensory (`:326`), ORN > 80% under
  olfactory (`:315`), Spontaneous KC < 5% (`:648-661`), >1000 neurons above rest
  (`:90`).
- **Only firing rate in Hz anywhere in the repo** is for the VNC, not the brain:
  5–12 Hz leg-motor-pool oscillation, "in global synchrony rather than in a
  tripod gait, and **no global gain setting produces tripod alternation**"
  (`space/README.md:36-38`).
- Explicitly *not* validated: `LIMITATIONS.md:84-86` "We have **not** done a
  quantitative, cell-type-resolved firing-rate match against a published
  reference simulation across the whole brain." Turner et al. is never cited;
  the only published anchor is KC sparsity 5–15% from Honegger 2011 / Lin 2014
  (`main.ts:375`). `CONTRIBUTING.md:34-39` ranks a real firing-rate comparison
  as the single most valuable missing contribution.

**Honesty section worth inheriting** (`LIMITATIONS.md:42-58`, `:212-218`,
`:282-289`): no Hodgkin-Huxley channels, no dendritic compartments, no spatial
synapse positions, no neuromodulation dynamics, no spike-frequency adaptation,
no synaptic depression, **no conduction delay**, no rebound current. NT→sign is
a hard build-time mapping and "glutamate is 'mostly' inhibitory in fly via GluCl
but not always". Brain and VNC are **different animals** (female FAFB brain,
male MANC cord) joined by cell-type name string (`:191-199`).

Two framing lines worth stealing:
> **webgpu-fly is the most *reachable* fly-brain simulator, not the most
> *accurate* one.** (`LIMITATIONS.md:7-9`)

> **the connectome does not walk the fly.** Roughly 20.3M connectome edges reach
> the body as about one scalar magnitude plus a turn bias per tick, and those two
> numbers scale a hand-written `sin(t × 10 Hz)` tripod. (`LIMITATIONS.md:13-16`)

**Behaviors that do not exist in webgpu-fly**: no grooming, no flight controller
(the wing motion is a hand-written 218 Hz stroke), no takeoff sequence beyond a
direct `qvel[2]` write, no landing. DesktopFly already has all of those.

**Doc-drift warning**: `LIMITATIONS.md`'s line references into `src/main.ts` are
stale by +9 to +115 lines against the shipped source. Its `src/vnc.ts` refs are
accurate. And `src/vnc.ts:71` labels `rateAlpha = 0.85` as a "~50 ms time
constant" — at dt = 1 ms the actual τ is ≈ 6.2 ms.

---

## 3. fly-brain (`reference/fly-brain/`) — LIF constants and parquet verdict

### 3a. LIF constants (`code/paper-phil-drosophila/model.py:18-56`)

This is the Shiu et al. 2024 Brian2 model, verbatim:

```python
'v_0'   : -52 * mV,   # resting potential        (Kakaria & de Bivort 2017)
'v_rst' : -52 * mV,   # reset potential after spike
'v_th'  : -45 * mV,   # threshold for spiking
't_mbr' :  20 * ms,   # membrane time scale
'tau'   :   5 * ms,   # synaptic time constant   (Jürgensen et al.)
't_rfc' : 2.2 * ms,   # refractory period        (Lazar et al.)
't_dly' : 1.8 * ms,   # delay for changes in post-synaptic neuron  (Paul et al. 2015)
'w_syn' : .275 * mV,  # weight per synapse       (FREE PARAMETER)
'r_poi' : 150 * Hz,   # default rate of Poisson inputs
'f_poi' : 250,        # scaling factor for Poisson synapse
```
```python
'eqs'    : 'dv/dt = (v_0 - v + g) / t_mbr : volt (unless refractory)
            dg/dt = -g / tau               : volt (unless refractory)'
'eq_th'  : 'v > v_th'
'eq_rst' : 'v = v_rst; w = 0; g = 0 * mV'
```

Wiring (`model.py:177-183`):
```python
syn = Synapses(neu, neu, 'w : volt', on_pre='g += w', delay=params['t_dly'], ...)
syn.connect(i=df_con['Presynaptic_Index'], j=df_con['Postsynaptic_Index'])
syn.w = df_con['Excitatory x Connectivity'].values * params['w_syn']
```

Differences from webgpu-fly that matter:
1. **Single-state exponential synapse** (`dg/dt = -g/tau`), not a two-state
   alpha cascade.
2. **`g` drives the membrane through `/t_mbr`**, so its mV-per-step contribution
   is `g/20`. webgpu-fly adds `i_syn` to Vm undivided. **That, not physiology,
   is why 0.275 became 0.005.**
3. **An explicit 1.8 ms synaptic delay** (`t_dly`), uniform for E and I.
   webgpu-fly has 2 ms of *implicit* delay from buffer ordering.
4. **Poisson drive**: input neurons get a 150 Hz Poisson source with weight
   `w_syn * 250` (`model.py:88-106`). There is still no background noise on the
   other ~138k neurons.

Numerically, for one presynaptic spike over an `s`-synapse connection
(simulated both formulations at dt=1 ms, alpha=0.951229, A_SYN=0.818731):

```
s= 100 synapses | webgpu-fly peak dV=8.63013 mV int=15.21674
                | Shiu      peak dV=4.90158 mV int= 7.58540 | ratio peak=1.761
threshold gap v_th - v_rest = 7 mV
synapses needed in ONE spike to fire from rest: webgpu-fly 81, Shiu 143
```

So **webgpu-fly is ~1.76× stronger per synapse than Shiu once you account for
the different formulations** — the "55× lower `w_syn`" is almost entirely a
units artefact, not a real weakening. Worth knowing before we "copy 0.005".

For contrast, current `Sim.swift` (`Sim.swift:135-142`) uses normalized units:
`decay 0.9512` (same 20 ms tau), `threshold 1.0`, reset 0, refractory 2 ms,
`weightScale 0.0008`/synapse, instant injection (no synaptic state), and a 4 ms
delayed-inhibition ring buffer (`Sim.swift:285-305`). Its operating point:
baseline `0.036` → steady `v = 0.036/(1−0.9512) = 0.7377`, so from rest only
`(1.0 − 0.7377)/0.0008 ≈ 328` synapses in one spike are needed to fire — but a
neuron at baseline `0.002` (the GF) sits at `v = 0.041` and needs ≈ 1,199.
That is the "razor-thin operating point" `CLAUDE.md` warns about, and it is a
*deliberately* different design from webgpu-fly's silent-at-rest network.

### 3b. Parquet verdict

`data/2025_Connectivity_783.parquet`, 100.8 MB, 15 row groups:

```
Presynaptic_ID: int64        Postsynaptic_ID: int64
Presynaptic_Index: int64     Postsynaptic_Index: int64
Connectivity: int64          Excitatory: int64
Excitatory x Connectivity: int64
num_rows (metadata): 15091983
```

```
unique pre : 138005      unique post: 137090      union of endpoints: 138639
total weight sum: 54492922      min weight: 1   max weight: 2405
weight histogram: 1→7496016  2→2679736  3→1379004  4→836714  5→558356  6→393867 …
rows with weight >= 5: 2700513      rows with weight < 5: 12391470
Excitatory:  1 → 9059302     -1 → 6032681
```

**It is NOT thresholded.** It is the full no-threshold aggregated (pre,post)
table. `Excitatory` is a per-edge ±1 (never 0), and it is constant per
presynaptic neuron: `presyn neurons with >1 distinct sign: 0 of 138005` —
i.e. Dale's law is enforced, same as webgpu-fly.

`2025_Completeness_783.csv`: shape (138639, 2), columns `['Unnamed: 0',
'Completed']`, **all 138,639 rows `Completed == True`**. Its row order *is* the
`Presynaptic_Index` / `Postsynaptic_Index` space:
`Presynaptic_Index == completeness row order (200k sample): True`.
So the parquet ships a ready-made dense index — no ID→index build step needed.

Sign convention differs from a naive Codex `nt_type` map. Crosstabbing the
parquet's per-neuron sign against each neuron's dominant Codex `nt_type`:

```
sign        -1      1
ACH       1136  84104
GABA     18195    314
GLUT     21977   1132
DA          11    872
SER          3   1487
OCT         11    109
<no codex edges>  0   8654
```

Two things to note: (a) **monoamines (DA/SER/OCT) are signed EXCITATORY here**,
whereas webgpu-fly silences them to 0 (`build_csr.py:70-77`); (b) ~2.5% of
neurons disagree with the Codex `nt_type` majority, so this is a different NT
prediction snapshot, not a re-derivation of the Codex column.

---

## 4. Is the parquet the same edge set as Codex `connections.csv` (syn>=5)?

**No — the parquet is a strict superset, and the Codex set sits inside it
exactly.** Numbers:

```
parquet pairs:                        15,091,983
codex aggregated pairs (all):          2,700,513
codex aggregated pairs (weight>=5):    2,700,513
parquet & codex_all:                   2,700,513
parquet - codex_all:                  12,391,470
codex_all - parquet:                           0
weight equal on all 2700513 common pairs: 2700513 (100.000%)
codex syn_count sum on common pairs:      34,153,566
parquet Connectivity sum on common pairs: 34,153,566
parquet total Connectivity (all 15M rows):54,492,922
sub-threshold-only rows: 12,391,470  their Connectivity sum: 20,339,356  max: 4
```

Every one of the 2,700,513 Codex pairs is present in the parquet with an
**identical weight (100.000% match)**. The extra 12,391,470 rows all have
weight 1–4 (max 4), confirming Codex's syn>=5 threshold.

An important structural detail: **the syn>=5 threshold is applied to the
aggregated pair, not to the per-neuropil row.** `connections.csv.gz` has
3,869,878 rows with `min syn_count: 1` and 403,748 rows at exactly 1 — but after
grouping by (pre,post), `pairs with weight < 5: 0`. So a 7-synapse pair split
4/3 across two neuropils yields two rows of 4 and 3.

Neuron-set relationship (verified):
```
classification root_ids     : 139255
parquet endpoint root_ids   : 138639
completeness root_ids       : 138639
parquet == completeness set : True
parquet subset of classif.  : True
in classification, NOT in parquet: 616
```
The 616 difference is neurons with zero edges even at no threshold.
webgpu-fly's 139,255 = the full `proofread_root_ids_783.npy` set, which is
exactly the Codex `classification.csv.gz` row count.

**Conclusion: `reference/fly-brain/data/2025_Connectivity_783.parquet` is, for
practical purposes, webgpu-fly's `proofread_connections_783.feather` — same
v783 release, same 15,091,983 aggregated pairs, already on disk at 100.8 MB.
We never need the 852 MB Zenodo download.** (Caveat: the sign columns come from
different NT snapshots — see §3b.)

---

## 5. Does webgpu-fly's pipeline use anything outside the Codex dumps?

**Yes — it uses none of them.** Full list of its inputs:

| # | input | size | needed for brain? |
|---|---|---|---|
| 1 | `proofread_connections_783.feather` (Zenodo 10676866) | 852 MB | yes — but we have the equivalent parquet |
| 2 | `proofread_root_ids_783.npy` (same deposit) | 1.1 MB | yes — Codex `classification.csv.gz` is the same 139,255 IDs |
| 3 | `flyconnectome/flywire_annotations` → `Supplemental_file1_neuron_annotations.tsv` | git clone | yes — replaced by Codex classification + coordinates + consolidated_cell_types |
| 4 | Dallmann et al. 2026 Supp Table 1 `.xlsx` (manual download, needs `openpyxl`) | small | **optional**, only to resolve the `BPN` preset (`build_csr.py:351, 367-369`) |
| 5 | MANC v1.0 (`flyem-manc-exports` GCS) | ~88 MB | **no — VNC only** |
| 6 | flybody MJCF + 85 OBJ meshes (TuragaLab) | ~149 MB | **no — body only** |
| 7 | flybody RL walking policy (Janelia Figshare) | ~6.5 MB | **no** |
| 8 | flybody mocap walking reference | — | **no** |

Nothing on the brain side is unobtainable from what we already have. The one
thing the Codex dumps do **not** give us is webgpu-fly's `top_nt_conf` column
(the per-neuron NT prediction confidence used for the 0.5 cutoff); Codex ships
`nt_type` per (pre,post,neuropil) row without a confidence. The parquet's
`Excitatory` column is a usable substitute.

---

## 6. Recommendations for the port

1. **Use the fly-brain parquet as the edge source, not Codex `connections.csv`.**
   It is the same graph webgpu-fly runs (15,091,983 pairs), already on disk at
   100.8 MB, already carries a dense index (`Presynaptic_Index` /
   `Postsynaptic_Index` matching `2025_Completeness_783.csv` row order), and
   already carries a signed `Excitatory x Connectivity` column. The only reason
   to prefer Codex syn>=5 is asset size — 2.7M edges (22 MB CSR) vs 15.1M
   (121 MB CSR). Given DesktopFly is a shipped macOS app with a git repo, the
   ~121 MB derived asset is the real decision, not the sim cost.
2. **If asset size matters, threshold at syn>=2 or syn>=3, not syn>=5.**
   Full retention curve (computed from the no-threshold histogram):

   | threshold | edges | synapses kept | % of 54,492,922 | CSR MB @ 8 B/edge |
   |---|---|---|---|---|
   | syn>=1 | 15,091,983 | 54,492,922 | 100.0% | 120.7 |
   | syn>=2 |  7,595,967 | 46,996,906 |  86.2% |  60.8 |
   | syn>=3 |  4,916,231 | 41,637,434 |  76.4% |  39.3 |
   | syn>=4 |  3,537,227 | 37,500,422 |  68.8% |  28.3 |
   | syn>=5 |  2,700,513 | 34,153,566 |  62.7% |  21.6 |

   **syn>=3 is the sweet spot**: a third of the edges of the full table for
   76% of the synaptic mass. syn>=5 (what Codex ships) throws away 37% of the
   synapses to save only 18 MB more.
3. **Copy webgpu-fly's kernel structure wholesale: gather over a CSR indexed by
   POST, one thread per postsynaptic neuron, presynaptic state in a packed u32
   bitset, `atomicOr` for the spike bits, ping-ponged spike buffers.** No
   scatter, no atomicAdd, no fixed-point. On Metal this is a direct translation;
   a serial `MTLComputeCommandEncoder` gives the intra-pass barrier for free and
   the 8-storage-buffer WebGPU workaround (`sim.ts:80-89`) is irrelevant.
4. **Do NOT copy `w_syn = 0.005` blindly.** It is only meaningful in
   webgpu-fly's exact formulation (`i_syn` added to Vm undivided, two-state
   alpha with `A_SYN = 0.81873`). Reproduce the whole arithmetic or re-derive.
   The equivalence calc in §3a is the check: 81 synapses to fire from rest.
5. **Keep DesktopFly's noise + per-role baselines; do not inherit
   silent-at-rest.** webgpu-fly's network is deterministic and quiescent with no
   input, which is right for a science demo and wrong for a desktop pet that has
   to be "lively" 24/7. `Sim.swift`'s `pNoise 0.0022` / `noiseKick 0.42` /
   random 400 ms bursts every 15–40 s is the feature, not a bug. Add it as a
   per-neuron RNG in the Metal kernel (a cheap PCG/xorshift keyed on
   `neuron_index ^ step`) — webgpu-fly has nothing to copy here.
6. **Keep the 4 ms delayed-inhibition ring.** webgpu-fly has no delay model at
   all (only 2 ms implicit, identical for E and I). DesktopFly's asymmetric
   inhibitory delay is what makes the LC→GF escape race work
   (`CLAUDE.md` "Escape is a race"), and both suites test it. Losing it would
   break `--simtest`.
7. **Adopt the two-state alpha synapse** (`g_x`/`g_y`, `A_SYN = exp(-dt/5ms)`).
   It is 2 extra f32[N] buffers (1.1 MB) and it is what makes cascades
   biologically shaped rather than a single-step impulse. It also makes the
   Shiu constants directly usable.
8. **Switch to the mV parameterization** (`v_rest = v_reset = -52`,
   `v_thresh = -45`, 7 mV gap) rather than DesktopFly's normalized 0→1. Both
   references agree on it, it makes weights directly comparable to two published
   models, and it kills the "razor-thin operating point" class of bug (baseline
   at 0.7377 of threshold).
9. **Plan on batching ~50 steps per submit with one readback**, matching
   `captureRollingRate` (`sim.ts:363-423`) — but fix the two things they left on
   the table: **pool the staging buffer** (they allocate+destroy per call) and
   **double-buffer the readback** so the CPU never stalls on `mapAsync`.
   DesktopFly needs 60 fps compositing; a synchronous drain per frame is not
   acceptable.
10. **Expect ~0.25–1 kHz, not 1 kHz+.** webgpu-fly measures 0.25 kHz bio on M2
    Pro; NEST hits 0.67 kHz and a multicore Rust CPU port 0.45 kHz on the same
    machine. It is **memory-bandwidth-bound** (115 MiB of CSR streamed per 1 ms
    step). M4 Pro has roughly 2.5× the bandwidth of M2 Pro, so ~0.6 kHz at 15.1M
    edges is a realistic guess and **~3–4 kHz at 2.7M edges (syn>=5)**. If we
    want a genuine 1 kHz sim clock, quantize weights to f16 (halves the 57.6 MiB
    weight buffer) or threshold the graph — both beat any ALU-side work.
11. **Keep the brain→behavior layer we already have.** DesktopFly's role→signal
    mapping (walk/turn/groom/escape/flight/backward, hysteresis, dwell guards)
    is richer than webgpu-fly's two scalars, and webgpu-fly has no grooming, no
    flight, and no landing at all. The only thing worth stealing is the readout
    *shape*: mean spikes-per-step over a fixed window per DN type, then an EMA
    on the final scalars — which is already what `SignalBuilder` does.
12. **Ship the DN readout as a name→indices map built at ETL time.** Do not
    hash cell types into the binary the way `build_csr.py:125-135` does — it
    makes the asset a one-way door (webgpu-fly literally cannot recover a
    root_id or type name from `brain.bin`, which is why
    `patch_brain_meta_walking_dns.py` exists). Keep a side JSON of
    `{primary_type: [dense_index, …]}` and `root_id[]`.

---

## 7. Surprises / risks

1. **webgpu-fly does not use the Codex dumps at all.** Everything in our brief
   that assumed "Codex connections.csv syn>=5" was wrong for them. They pull an
   852 MB Zenodo feather and the `flywire_annotations` TSV.
2. **The fly-brain parquet already in our repo IS webgpu-fly's graph.** Same
   15,091,983 edges, same v783. This was not obvious from either README and it
   removes the largest download from the plan.
3. **Codex's syn>=5 threshold is applied per aggregated pair, not per row.**
   The raw CSV contains 403,748 rows with `syn_count == 1`. Anyone filtering
   rows by `syn_count >= 5` (rather than aggregating first) silently drops
   ~1.16M rows and ~15% of the synapse mass of the pairs Codex intended to keep.
4. **webgpu-fly is 4× slower than realtime** and its own docs say a multicore
   Rust CPU implementation beats the GPU by 1.8×. The GPU is not automatically
   the win here — the win is bandwidth, and a 2.7M-edge graph on an M4 Pro may
   simply not need a GPU at all. Worth a CPU baseline before committing.
5. **There are no stability guards in webgpu-fly** — no Vm clamp, no in-degree
   normalization, no adaptation, no homeostasis. Stability is one fitted number.
   Porting the constants without porting the tuning discipline is a real risk;
   `Sim.swift` at least clamps at `max(-2, …)` (`Sim.swift:288, 302`).
6. **Sign conventions disagree three ways.** Codex `nt_type` per-neuropil-row;
   webgpu-fly per-neuron `top_nt` with conf ≥ 0.5 and DA/SER/OCT → **0**;
   fly-brain parquet per-neuron ±1 with DA/SER/OCT → **+1**; `etl.py:36` maps
   DA/SER/OCT → **+0.5**. Three different answers for 2% of synapses. Pick one
   deliberately and write it down.
7. **`DNg74`, `oviDN`, `aDN1`, `aDN2`, `DNpe` do not exist as exact strings in
   v783** — the names are suffixed (`DNg74_b`, `oviDNa_a/b`, `DNpe001`…).
   Any new-population recipe that greps for an exact type will silently find 0.
8. **webgpu-fly's `LIMITATIONS.md` line refs into `main.ts` are stale** (+9 to
   +115 lines). Trust the code, not the doc's line numbers.
9. **The 616-neuron gap** between classification (139,255) and the parquet
   (138,639) has to be handled explicitly, or brain-viz point indices and sim
   indices will silently diverge.
10. **DNg11's in-degree jumps from 6 to 2,838 synapses** in the full graph. Good
    news, but it means every existing baseline/tuning constant in `Sim.swift`
    will be wrong by a large factor once the real drive arrives. Budget for a
    full retune, not a port-and-run.

---

## 8. Files created

| path | what |
|---|---|
| `cache/flywire783/classification.csv.gz` | 934,402 B — Codex v783, 139,255 rows |
| `cache/flywire783/coordinates.csv.gz` | 5,314,546 B — 238,909 rows |
| `cache/flywire783/connections.csv.gz` | 50,289,304 B — 3,869,878 rows |
| `cache/flywire783/consolidated_cell_types.csv.gz` | 901,707 B — 138,327 rows |
| `cache/recon_stats.py` | reproducible analysis script (`/opt/anaconda3/bin/python3 cache/recon_stats.py`) |
| `cache/recon_stats.out` | archived full output of the above |
| `notes/01-recon.md` | this file |

All four downloads returned `http=200`, and `gzip -t` passed on each.
Total `cache/` size: **55 MB**. No repo file was modified; nothing was written
outside the project directory.
