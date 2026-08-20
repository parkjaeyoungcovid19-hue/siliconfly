# 03 — Metal whole-brain sim

The 668-neuron CPU `LIFSim` is gone. The whole FlyWire v783 connectome
(**139,255 neurons, 15,091,983 signed edges**) now runs at 1 kHz in two Metal
compute kernels, driven from the SceneKit render thread exactly as before.

| file | what it is |
|---|---|
| `Sim.swift` | `BrainSignals`, `SpikeBus`, `Role`, `struct Connectome`, `loadConnectome()` |
| `MetalSim.swift` | `SimParams`, `MetalShared` (device/pipelines/CSR), `final class MetalSim` |
| `LIF.metal` | `lif_update` + `lif_propagate`, compiled at runtime |

`MetalSim` has the same public surface as `LIFSim` had, so `SignalBuilder`,
`FlyModel` and `BrainView` only changed where the type name or the data source
appears.

---

## 1. Loading

`loadConnectome()` finds `data/connectome.json` next to the executable, then in
the working directory (`findResource`, which `MetalShared` reuses for
`LIF.metal`). Every array is located through the manifest's
`{file, byteOffset, dtype, count, components}` records — **no offset is
hardcoded**. Both binaries are `Data(contentsOf:options:.mappedIfSafe)`; the two
60 MB edge arrays stay as raw mapped `Data` and are consumed exactly once, when
the `MTLBuffer`s are built.

Gotcha found the hard way: in the manifest `count` is the **total element
count** and `components` only describes the interleave — `pos` is
`count: 417765, components: 3`, i.e. 417,765 floats, *not* 417,765 × 3. The
loader asserts `count % components == 0` and sizes by `count` alone.

Structural checks, all fatal (load returns nil and logs why):

- `rowStart.count == N+1`, `rowStart[0] == 0`, `rowStart[N] == E`
- `colIdxData.count == 4E`, `weightData.count == 2E`
- `max(colIdx) < N` (full scan)
- no edge has `weight == 0` (full scan)
- per-role neuron tallies equal the manifest's `roleCounts`
- the manifest's `roles` string table equals `Role.names` (index order is
  load-bearing: `Role.gf == 3` etc.)

`Connectome` also precomputes `roleName[i]` and `typeName[i]` (cell type name,
falling back to the super-class name) once, so building a second `MetalSim`
costs nothing extra.

### Shared GPU resources

`Connectome.gpu` is a one-field class box holding a `MetalShared?`. The first
`MetalSim` built on a connectome fills it; later sims reuse the device, the
compiled pipelines and the 121 MB of CSR buffers, and only allocate their own
~6.8 MiB of state. That is what makes `--behaviortest` (7 sims) cheap. The box is
invalidated if the weight knobs (`weightScale`, `modScale`, `gapJunctionBoost`)
differ from the cached build, since those bake into the weight buffer.

### Shader compilation

`LIF.metal` is read from disk and compiled with
`device.makeLibrary(source:options:)`, `MTLCompileOptions.mathMode = .safe`
(macOS 15+; no `fastMathEnabled` fallback was needed on this SDK). No metallib
build step, no Metal toolchain dependency at build time — `build.sh` is still a
bare `swiftc` line, now with `MetalSim.swift` and `-framework Metal`.
First compile ~84 ms; Metal's on-disk shader cache makes subsequent launches
~1 ms.

---

## 2. Fixed point

All synaptic accumulation is **Int32 fixed point** so it can use integer
atomics: order-independent, exactly reproducible, and no float-atomic
dependency.

Load-time weight transform (per edge, from the raw `int16` = sign × synapse
count):

```
w = weight
  * weightScale                                        (0.0008)
  * (pre.nt in {DA,SER,OCT} ? modScale : 1)            (0.5,  299,549 edges)
  * (pre.role in {lc4,lplc2,sens} && post.role == gf
       ? gapJunctionBoost : 1)                         (6.0,  309 edges)
wFx = Int32(round(w * fxScale))
```

Pass 1 measures the exact `max|w|` (rows are scanned by pre-neuron, so the
gap-junction test only touches the 330 electrical rows); pass 2 quantizes.
`fxScale` is then the **largest power of two in [2^16, 2^20]** for which
`max|w| × fxScale × 4096` still fits in Int32. With the shipped data:

- `max|w| = 1.924`, `mean|w| = 0.00287`
- chosen scale: **Q18 = 262,144** (`1.924 × 2^18 × 4096 = 2.066e9 ≤ 2.147e9`)
- quantization step 3.8e-6 against a threshold of 1.0
- the *real* worst case is the largest per-postsynaptic-neuron in-weight sum
  (every presynaptic neuron spiking in the same millisecond):
  `max Σ|w| = 55.94` → `55.94 × 2^18 = 1.47e7`, i.e. **146× headroom** on Int32.

If a retune pushes `max|w|` up, the scale drops automatically to Q17/Q16; only
if Q16 also overflows does init fail with an explicit message.

---

## 3. Per-step semantics

Exactly the order the CPU sim ran, with one algebraically-equivalent move: the
CPU applied a spike's excitation at the end of step *t* (`v = max(-2, v + w)`),
then decayed at *t+1*; the GPU applies the accumulated excitation at the start
of *t+1* before the decay. `(v + exc) * decay + baseline` either way.

Per step, per neuron (`lif_update`):

1. `ex = atomic_exchange(excAcc[i], 0)`; if non-zero `v = max(-2, v + ex/fx)`
2. `r = refr[i]`
   - `r > 0` → `refr[i] = r-1`, `v *= decay` (no baseline, no noise)
   - else → `v = v*decay + baseline[i]*activityScale`, then
     `if rand01 < p: v += noiseKick`
3. external drive, **whether or not refractory**, by `inputKind[i]`:
   `1 loomL`, `2 loomR`, `3 ascend gait`, `4 air puff`; then `v += extInput[i]`
4. `inh = atomic_exchange(inhRing[curSlot][i], 0)`; if non-zero
   `v = max(-2, v + inh/fx)`
5. `spike = (r <= 1) && (v >= threshold)` — `r` is the **pre-decrement** value,
   so a neuron whose refractory period ends this step may fire, matching the
   CPU's decrement-then-test. On spike: `v = 0`, `refr[i] = 2`,
   `spikeList[atomic_inc(spikeCount[s])] = i`, `atomic_inc(groupCounts[s][g])`,
   `sample[s][(h>>3)&31] = i`

Then `lif_propagate`: one 32-lane SIMD group per spiker, grid-striding over
`spikeCount[s]`; lanes stride over that neuron's CSR range.
`w >= 0 → atomic_add(excAcc[j], w)`, else
`atomic_add(inhRing[inhSlot][j], w)`.

Ring: 5 slots, `curSlot = (simMs-1) % 5`, `inhSlot = (simMs-1+4) % 5`. They
differ by 4 mod 5 so a step never reads the slot it writes, and the slot written
at *t* is read at *t+4*.

Constants (all `SimParams` fields, all overridable without touching the shader):
`decay 0.9512`, `threshold 1`, `refractory 2`, `weightScale 0.0008`,
`modScale 0.5`, `gapJunctionBoost 6`, `pNoise 0.0022` (×6 in a burst),
`noiseKick 0.42`, `loomGain 0.30`, `ascendGain 0.09`, `airPuffGain 0.12`,
`rateAlpha 1/120`, `inhDelay 4`.

### Input gating

The CPU sim guarded each external input with `if x > 0.001`. That guard now
lives on the CPU side of the parameter block: `loomDriveL`, `loomDriveR`,
`ascendDrive`, `airPuffDrive` are precomputed (and forced to 0 below the gate),
so the kernel adds unconditionally and the float product order matches the CPU
exactly (`(loomL*loomGain)*sensoryGate`, `(airPuff*0.12)*sensoryGate`,
`(gaitDrive*0.09) * (0.5 + 0.5*sin(gaitPh + phase))`).

---

## 4. RNG (reproduce this exactly in any CPU reference)

PCG-style 32-bit hash, identical in `LIF.metal` (`pcg`) and `MetalSim.swift`
(`pcgHash`):

```
uint pcg(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word  = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}
float unit(uint h) { return float(h >> 8) * 5.9604645e-8f; }   // [0,1), 24 bits
```

Streams:

| stream | draw | used for |
|---|---|---|
| membrane noise (GPU) | `h = pcg(pcg(seed + stepIndex*2654435761) + i)`, `unit(h) < p` | the `noiseKick` |
| sample slot (GPU) | `(h >> 3) & 31` — same `h`, disjoint bits | brain-window spike sampling |
| baselines (CPU) | `unit(pcg(pcg(seed + 0x51ED2701) + i))` | `other`/`ascend`/`sens` resting drive |
| gait phase (CPU) | `unit(pcg(pcg(seed + 0x2F1B3C4D) + i))` × 2π | `ascend` phase offsets |
| burst schedule (CPU) | `unit(pcg(pcg(seed + 0x7A3B9F11) + burstCounter))` | next arousal burst |

`stepIndex` is 1-based (`= simMs` after the increment). Arousal bursts: when
`simMs >= burstNext`, `burstUntil = simMs + 400` and
`burstNext = simMs + 15000 + Int(draw * 25001)`; `p = (simMs < burstUntil ?
pNoise*6 : pNoise) * activityScale`. Default seed `0x5EED1F1F`; `burstNext`
starts at 12,000.

---

## 5. Buffers

All `.storageModeShared`. `N = 139,255`, `E = 15,091,983`, `S = 64` (max batch).

| index | buffer | type | bytes | shared? |
|---|---|---|---|---|
| 0 | `v` | float | 557 KB | per sim |
| 1 | `refr` | uchar | 139 KB | per sim |
| 2 | `baseline` | float | 557 KB | per sim |
| 3 | `inputKind` | uchar (0 none, 1 loomL, 2 loomR, 3 ascend, 4 sens) | 139 KB | per sim |
| 4 | `phase` | float (ascend gait offsets) | 557 KB | per sim |
| 5 | `groupOf` | uchar (0 none … 8 escw) | 139 KB | per sim |
| 6 | `extInput` | float (CPU-owned stim sum) | 557 KB | per sim |
| 7 | `excAcc` | atomic_int | 557 KB | per sim |
| 8 | `inhRing` | atomic_int[5][N] | 2.79 MB | per sim |
| 9 | `spikeList` | uint[N] (reused every step) | 557 KB | per sim |
| 10 | `spikeCount` | uint[S] | 256 B | per sim |
| 11 | `groupCounts` | uint[S][16] | 4 KB | per sim |
| 12 | `sample` | uint[S][32] | 8 KB | per sim |
| 13 | `rowStart` | uint[N+1] | 557 KB | **shared** |
| 14 | `colIdx` | uint[E] | 60.4 MB | **shared** |
| 15 | `weightFx` | int[E] | 60.4 MB | **shared** |
| 16 | `StepParams` | `setBytes`, 72 B, per dispatch | — | — |

Per sim ≈ **6.8 MiB**; shared ≈ **121.3 MB**.

The two kernels use **disjoint buffer indices**, so all 16 bindings are set once
per batch and only the 72-byte `StepParams` is re-sent per dispatch (6 encoder
calls per simulated millisecond). `StepParams` layout is asserted at init
(`MemoryLayout<StepParams>.stride == 72`).

### Batching

`step(ms)` loops sub-batches of at most `S = 64` steps. One command buffer, one
compute encoder, `2k` dispatches, `waitUntilCompleted()` — synchronous, no
background thread, called from the render thread exactly as the CPU sim was.
Dispatches in a serial encoder carry an implicit barrier, which is what
guarantees `lif_propagate(t)` completes before `lif_update(t+1)` and makes the
single reused `spikeList` safe.

Before each commit the CPU zeroes `spikeCount[0..k)` and `groupCounts[0..k)` and
fills `sample[0..k)` with `0xFFFFFFFF`. After the wait it folds the per-step
histograms into the rate EMAs (same formulas and `rateAlpha` as the CPU sim,
including the `nLoom = loomLeft+loomRight` normalization), adds to
`totalSpikes`, latches GF from `groupCounts[s][2] > 0`, and pushes up to 12
sampled spikers per step to the `SpikeBus`.

`dispatchThreads(N, tg 256)` for `lif_update`; `dispatchThreadgroups(1024, tg
32)` for `lif_propagate`.

### Stim sub-batching

`extInput` is CPU-owned and never rewritten wholesale. A sub-batch is cut so it
can never cross a stim expiry, which keeps `extInput` exact for every step in
it:

- pending stims merge at the **start of `step()`** (as the CPU sim did), with
  `untilMs = simMs + durationMs`
- a stim contributes while `simMs < untilMs`, so it is dropped as soon as
  `simMs + 1 >= untilMs`
- sub-batch length `k = min(remaining, 64, min(untilMs) - simMs - 1)`
- on any change to the active set, `extInput` is **rebuilt** for the touched
  indices (zero the dirty set, re-sum the active stims) rather than
  incremented/decremented, so overlapping stims can't drift

---

## 6. Test hooks

All are cheap synchronous reads of shared buffers, valid between `step()` calls.

| hook | returns |
|---|---|
| `membrane() -> [Float]` | membrane potential per neuron |
| `debugRefr() -> [UInt8]` | remaining refractory steps (0/1/2) |
| `lastStepSpikes() -> [Int32]` | full spike list of the most recent step, GPU-race order |
| `lastStepGroupCounts() -> [UInt32]` | that step's 16-slot group histogram |
| `setSeed(_ s: UInt32)` | reseeds baselines, gait phases, noise and the burst schedule |
| `setBaseline(_ v: [Float])` | overwrite per-neuron resting drive |
| `debugParams -> SimParams` | every constant in use |
| `deviceName`, `loadMs`, `compileMs`, `fixedPointScale` | provenance |
| `avgStepMicros` | EMA of wall µs per step over recent batches |
| `perfLogIntervalMs` | sim-ms between throughput log lines; 0 = off |

`init?(connectome:spikeBus:seed:params:)` — `seed` defaults to `0x5EED1F1F`,
`params` to the values above. Deterministic seeding: pass the same `seed`, keep
`params` at the default, and drive the same input sequence. Verified: two
`--simtest` runs are byte-identical outside the timing lines, and the run under
Metal API + GPU validation produced identical numbers again.

### Checklist for the GPU-vs-CPU cross-check agent

1. **Seed both sides identically.** Build the CPU reference's baselines and gait
   phases from `pcgDraw(seed, 0x51ED2701, i)` and `pcgDraw(seed, 0x2F1B3C4D, i)`
   (§4), not from `Float.random`. Same for the burst schedule.
2. **Quantize the reference's weights the same way.** Apply the §2 transform,
   `Int32(round(w * fxScale))` with `fxScale = sim.fixedPointScale`, accumulate
   in Int32 and convert once with `Float(acc) * (1/fxScale)`. Accumulating in
   Float on the CPU will *not* match — that is the intended difference, not a
   bug.
3. **Follow the §3 order exactly**, including the pre-decrement refractory test
   and the single `max(-2, …)` clamp per accumulator (not per edge).
4. **Compare after each step**: `membrane()` (expect bit-equal), `debugRefr()`,
   and `Set(lastStepSpikes())` (the list order is a GPU race; only the set is
   defined). `lastStepGroupCounts()` cross-checks the histogram.
5. **Drive `gaitDrive = 0` for the bit-exact phase.** The only op that may not
   be bit-identical is `precise::sin` in the ascend branch (Metal's libm vs
   Swift's). It touches 24 neurons; run a separate tolerance-based comparison
   for gait.
6. Stims: remember a stim submitted during `step()` starts on the **next** call,
   and applies for `durationMs - 1` steps (`simMs < untilMs`). That quirk is
   inherited verbatim from the CPU sim.
7. Suggested protocol: seed, `setBaseline` from the reference to remove any
   doubt, 2,000 steps of pure spontaneous activity, then 400 steps of abrupt
   loom, then a GF stim.

---

## 7. Measurements (Apple M4 Pro, macOS 26.6.1, Xcode 26 / Swift 6.2.1)

```
metal-sim: Apple M4 Pro N=139255 E=15091983 load 42 ms compile 1 ms      (warm cache)
metal-sim: Apple M4 Pro N=139255 E=15091983 load 38 ms compile 84 ms     (cold cache)
metal-sim: 30000 steps in 6505 ms (217 µs/step, 1397 spikes/step avg)    (periodic line)
```

- **Startup** 42–125 ms end to end (budget 5 s). `load` = connectome parse +
  validation + CSR upload + weight transform.
- **RSS** 196,336 KB ≈ **192 MB** for the full GUI app (budget 2 GB).
- **Throughput** (`--simtest` phase 8, 2,000 steps each):
  - 16-step batches: **107–114 µs/step** across runs, 1,520 spikes/step → **PASS realtime**
  - 1-step batches: **234–246 µs/step** (command-buffer round trip dominates)
- **Activity**: 1,520 spikes/step = **1.09 % of neurons per ms**, 10.9 Hz per
  neuron. Not epileptic, so the extra `activityScale = 0.3` benchmark did not
  trigger.
- **Metal API Validation + GPU Validation**: clean, no diagnostics, identical
  numeric results (2.2× slower, as expected).

`--simtest` (all probes kept from the CPU version):

```
connectome: 139255 neurons | 15091983 edges | Apple M4 Pro | fixed point Q18
groups: loom L/R 162/152 | GF: 2 | DNa L/R: 2/2 | MDN: 4 | DNp09: 2 | DNg11: 6 | escW: 6 | ascend: 24 | sens: 16
spontaneous 4s: pop 10.87 Hz/neuron, LC 0.0 Hz, DNa02 L/R 12.1/14.8 Hz, MDN 1.5 Hz, GF spikes: 0
abrupt loom 0.4s: LC rate 181.5 Hz, GF spikes 199, first at 4 ms
behavior 20s: walk-drive on 40%, groom-drive on 9%, DNp09 0.0-10.4 Hz, pop 10.9 Hz
siesta 15s (scale 0.84): walk-drive on 29%
air puff 1s: GF spikes 4
left-eye loom: DNa L-R rate diff -11.3 -> -7.9 Hz, LC 32.3 Hz
click probes: GF cluster -> spike yes, DNg11 cluster -> groom rate 209 Hz
state check: 200 steps, 304000 spikers (19 role-tagged) match membrane/refractory/histogram -> consistent
PASS: GF silent at rest, fires on loom; locomotor drive fluctuates; stim works; siesta alive
```

`--behaviortest`: `ALL BEHAVIOR TESTS PASS` (17/17).

---

## 8. Untuned, unverified, risks

- **Baselines are the 668-neuron circuit's, unchanged.** `other`/`ascend`/`sens`
  get a seeded uniform 0.010…0.070, LC 0.004, command DNs 0.036, DNp09 0.038,
  GF 0.002. They were never tuned for 139k neurons; that every probe still
  passes is luck plus the fact that the full network's extra inhibition happens
  to balance the extra excitation. Owned by the tuning phase.
- **Loom L/R is now 162/152, not 104/210 by type.** `side` comes from the
  manifest and `center` counts as right (as the CPU sim did with anything that
  was not `"left"`).
- **`GF spikes 199` over 400 ms of loom** is much hotter than the old circuit.
  Latency (4 ms) and rest silence (0) are still right, but the escape pathway is
  effectively saturated under sustained loom — a tuning target.
- **`air puff 1s: GF spikes 4`**: the wind pathway now also fires GF at rest-ish
  drive. Previously 0 unless strongly driven.
- **`groom rate 209 Hz`** from a click stim is far above the old operating
  point. `SignalBuilder` divides by 8, so `groomDrive` saturates instantly.
- **The 30 s periodic log could not be observed from the GUI app in this
  environment.** Launched from a non-interactive shell the app starts, allocates
  and logs, but SceneKit never delivers `renderer(_:updateAtTime:)` — the
  pre-port binary behaves identically (no `DESKTOPFLY_FPS` lines either), so
  this is environmental (App Nap / no active GUI session), not a regression.
  The log path itself is exercised and verified by `--simtest`, which reaches
  45 s of sim time.
- **`--behaviortest` has a pre-existing ~1-in-8 flake**, `ledge attach + follow
  window edge`. It is a `bodyCheck` — hand-built signals, no sim at all — and
  the pre-port binary flakes the same way (verified over 8 runs each). Not
  touched.
- **`precise::sin`** is the one arithmetic op that may differ from Swift's
  `sin`. 24 neurons, gait input only.
- **Load balance in `lif_propagate`** is one SIMD group per spiker; out-degree
  ranges 0…9,783 (mean 108). At 1.5k spikers/step the grid-stride hides it, but
  a much hotter network could see tail latency from the few huge rows.
- The `spikeList` is sized `N` and can never overflow (one spike per neuron per
  step), but nothing asserts it at runtime.

## 9. Removed

`data/brain_points.json` and `data/circuit.json` are deleted — `etl.py` stopped
emitting them and nothing in the code references them. `BrainPointsFile`,
`CircuitFile`, `CircuitNeuronFile`, `loadBrainData()` and `findDataDir()` are
gone from `Sim.swift`. The brain window's background cloud is now the full
connectome strided to ~23k points (`BACKGROUND_POINTS`), coloured by
`superClass`; the overlay draws only the 378 role-tagged neurons; click picking
measures all 139k somas once and sorts the shortlist.
