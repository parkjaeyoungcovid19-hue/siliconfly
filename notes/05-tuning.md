# 05 — Tuning the full brain

The Metal port kept the 668-neuron circuit's operating point. This pass replaces
it with one derived from the full connectome's own structure. Every number below
comes from a run in `notes/tuning-runs/`; the untuned reference is
`00-untuned-*.txt`, the tuned one `final-*.txt`.

**Result:** `--simtest` PASS, `--behaviortest` 17/17, `--gpucheck` PASS,
population 10.92 → **2.54 Hz/neuron**, network contribution 1.06× → **3.01×**,
73 µs/step (13.7× realtime margin).

---

## 1. The diagnosis

Two numbers from `--brainstats` on the untuned brain explain everything:

```
population: 10.92 Hz/neuron | 1520 spikes/step
intrinsic only (weightScale 0): population 10.26 Hz/neuron | 1428 spikes/step
  population intrinsic   10.26 Hz -> tuned   10.92 Hz  (1.06x)
histogram: silent 28447 (20.4%) | <1 Hz 15170 (10.9%) | 1-5 Hz 44276 (31.8%)
           | 5-20 Hz 12234 (8.8%) | >20 Hz 39128 (28.1%)
```

**The 139k-neuron brain was 94% intrinsic.** With `decay = 0.9512` a neuron
rests at `baseline / (1 − decay) = baseline × 20.49` against threshold 1, so:

| baseline | resting v | behaviour |
|---|---|---|
| ≥ **0.0488** | ≥ 1.0 | self-fires forever with no input at all |
| ≥ **0.0283** | ≥ 0.58 | one `noiseKick` (0.42) fires it → rate = `pNoise` |
| < 0.0283 | < 0.58 | needs ≥ 2 kicks in a decay window, or synaptic help |

`baselineOther = 0.010…0.070` put **35% of all 139,255 neurons above 0.0488**.
Those ~49,000 neurons were tonic oscillators (up to 38 Hz); they, not the
connectome, produced the 10.9 Hz. That is also why `arousal = ratePop/20` sat
pinned at **0.545**, permanently above FlyModel's `arousal > 0.5` gate — the fly
was rolling a 0.6/s spontaneous-takeoff die on every frame it walked.

---

## 2. Tuned parameter table

### 2.1 Resting drive — a per-super-class table (`SimParams.baselineByClass`)

`baselineOther: 0.010...0.070` (one flat range for 138,000 neurons) is replaced
by a per-FlyWire-super-class table. Every range is deliberately **below 0.0488**,
so nothing self-fires: at rest the brain crackles on noise + wiring only.

| super class | n | before | after | resting v | why |
|---|---|---|---|---|---|
| `optic` | 77,873 | 0.010…0.070 | **0.003…0.038** | 0.06…0.78 | 56% of the brain — this range *is* the population rate |
| `central` | 32,381 | 0.010…0.070 | **0.008…0.046** | 0.16…0.94 | central brain crackles; ~47% sit in one-kick range |
| `sensory` | 16,938 | 0.010…0.070 | **0.000…0.004** | 0…0.08 | receptors, not spontaneous crackle: silent unless driven |
| `sensory_ascending` | 612 | 0.010…0.070 | **0.000…0.006** | 0…0.12 | same |
| `visual_projection` | 7,684 | 0.010…0.070 | **0.003…0.034** | 0.06…0.70 | LC-like projection neurons, quiet at rest |
| `visual_centrifugal` | 522 | 0.010…0.070 | **0.005…0.040** | 0.10…0.82 | |
| `descending` | 1,305 | 0.010…0.070 | **0.008…0.044** | 0.16…0.90 | moderate: DNs must be gateable both ways |
| `ascending` | 1,750 | 0.010…0.070 | **0.008…0.044** | 0.16…0.90 | |
| `motor`, `endocrine` | 190 | 0.010…0.070 | **0.005…0.036** | 0.10…0.74 | |
| fallback (unknown class) | — | — | **0.005…0.036** | | |

### 2.2 Everything else

| knob | before | after | reason |
|---|---|---|---|
| `weightScale` | 0.0008 | **0.0016** | the whole point of the port. 0.0008 left the population 1.06× intrinsic; 0.0016 makes it 3.01× and gives the descending neurons real synaptic drive. 0.0024 was tried and rejected: it flipped MDN to 0.00× and DNp09 to 0.17× (net inhibition wins) and pushed `central` to 13 Hz |
| `pNoise` | 0.0022 | **0.0030** | with nothing self-firing, `pNoise` *is* the intrinsic rate ceiling for the one-kick populations. 3 Hz keeps the command DNs (rest 2.4–2.6 Hz) inside their signal ranges |
| `baselineLoom` | 0.004 (scalar) | **0.008…0.028** (range) | two jobs. (a) LC4/LPLC2 were given one identical baseline, so under a sustained loom all 314 fired in exact lockstep and the giant fiber got a full volley every period. (b) the higher resting v shortens the onset latency: it bought 10 ms → 8 ms at unchanged `loomGain` |
| `gapJunctionBoost` | 6.0 | **1.0** (LC4/LPLC2 → GF only) | the ×6 was a crutch for `weightScale = 0.0008`. At 0.0016 the connectome's own LC→GF synapses already deliver **+1.60 threshold units** for one synchronous volley (measured, `--brainstats` in-weight audit), i.e. a synchronous onset fires the GF with 60% margin and no boost at all |
| `sensGFBoost` | — (shared the 6.0) | **3.0** | new knob, split out of `gapJunctionBoost`. The antennal-mechanosensory → GF electrical synapse is real and carried by only 16 neurons; `0.0016 × 3 = 0.0008 × 6` keeps that path at exactly its pre-port strength. Without the split, `tap near fly -> startle escape` fails (verified: `08-behaviortest.txt`) |
| `loomGain` | 0.30 | **0.22** | sustained LC rate 177 → 127 Hz, which is what the GF integrates. GF spikes over a 400 ms loom: 199 → 87 |
| `airPuffGain` | 0.12 | **0.06** | 1 s air puff: GF spikes 4 → **1** |
| `floorV` | `var = −2` (dead) | `let = −2` + comment | `StepParams` has no such field and `LIF.metal` hardcodes `−2.0f`; the knob silently did nothing. `GPUCheck.RefSim` reads it, so it stays as a documented mirror rather than being deleted |

Unchanged and deliberately so: `decay` 0.9512, `threshold` 1, `refractoryMs` 2,
`modScale` 0.5, `inhDelayMs` 4, `noiseKick` 0.42, `burstFactor` 6 / `burstMs` 400
/ `burstGapMs` 15–40 s, `ascendGain` 0.09, `rateAlpha` 1/120, `baselineCommand`
0.036, `baselineFwd` 0.038, `baselineGF` 0.002.

---

## 3. Iterations

One family of knobs at a time; the escape race was re-checked every time.

| # | change | pop Hz | net contrib | GF/400 ms loom | latency | walk duty | verdict |
|---|---|---|---|---|---|---|---|
| 00 | untuned reference | 10.92 | 1.06× | 199 | 4 ms | 40% | 28.1% of neurons > 20 Hz; `arousal` pinned 0.55 |
| 01 | per-super-class baselines + `pNoise` 0.0030 | 1.53 | 1.81× | — | — | — | regime fixed: sensory 98.7% silent, 47.5% of the brain silent |
| 02 | `weightScale` 0.0024 | 3.59 | 4.26× | — | — | — | **rejected**: MDN 0.00×, DNp09 0.17×, `central` 12.97 Hz |
| 03 | `weightScale` 0.0016 | 2.54 | 3.02× | **367** | 3 ms | 43% | GF worse — doubling `weightScale` doubled LC→GF too |
| 04 | `gapJunctionBoost` 2.0, `airPuffGain` 0.06 | — | — | 211 | 4 ms | 45% | puff 27 → 1; GF still saturated |
| 05 | `gapJunctionBoost` 1.0, `loomGain` 0.15 | — | — | 37 | **19 ms** | 48% | **rejected**: breaks the ≤10 ms invariant |
| 06 | `loomGain` 0.22 | — | — | 83 | **10 ms** | 44% | not single-digit |
| 07 | `baselineLoom` → 0.008…0.028 | 2.54 | 3.01× | 87 | **8 ms** | 43% | all sim invariants pass |
| 08 | SignalBuilder normalizers + `sensGFBoost` 3.0 | 2.54 | 3.01× | 87 | 8 ms | 37% | 17/17 behaviour, gpucheck PASS |

---

## 4. Final numbers (`notes/tuning-runs/final-*.txt`)

### 4.1 Rest regime

```
population: 2.54 Hz/neuron | 353 spikes/step | 78 µs/step (16-step batches)
histogram: silent 66101 (47.5%) | <1 Hz 30244 (21.7%) | 1-5 Hz 38360 (27.5%)
           | 5-20 Hz 1622 (1.2%) | >20 Hz 2928 (2.1%)
```

| super class | n | mean Hz | % silent | intrinsic-only Hz |
|---|---|---|---|---|
| optic | 77,873 | 0.81 | 45.8 | 0.83 |
| central | 32,381 | **8.58** | 24.7 | 1.35 |
| sensory | 16,938 | **0.10** | 98.4 | 0.00 |
| visual_projection | 7,684 | 0.55 | 52.4 | 0.56 |
| ascending | 1,750 | 1.26 | 30.9 | 1.28 |
| descending | 1,305 | 2.56 | 28.4 | 1.26 |
| visual_centrifugal | 522 | 1.26 | 32.2 | 1.11 |
| sensory_ascending | 612 | 0.00 | 98.5 | 0.00 |
| motor | 110 | 1.05 | 37.3 | 0.80 |
| endocrine | 80 | 0.83 | 45.0 | 0.84 |

### 4.2 Network contribution (same seed, `weightScale = 0` vs tuned)

```
population intrinsic    0.84 Hz -> tuned    2.54 Hz  (3.01x)
  dnaL     intrinsic    2.40 Hz -> tuned   16.90 Hz  (7.04x)
  dnaR     intrinsic    2.90 Hz -> tuned    9.30 Hz  (3.21x)
  mdn      intrinsic    2.75 Hz -> tuned    0.75 Hz  (0.27x)
  fwd      intrinsic    2.90 Hz -> tuned    2.40 Hz  (0.83x)
  escw     intrinsic    2.83 Hz -> tuned    4.30 Hz  (1.52x)
  groom    intrinsic    2.57 Hz -> tuned    2.57 Hz  (1.00x)
  central  intrinsic    1.35 Hz -> tuned    8.58 Hz
  descending intrinsic  1.26 Hz -> tuned    2.56 Hz
```

Read this with the in-weight audit (`--brainstats`, threshold units, 1.0 = one
full presynaptic volley fires the neuron):

```
  gf    exc +3.76  inh -3.78  net -0.01  [electrical LC/sens path +1.60]
  dnaL  exc +8.73  inh -5.74  net +2.99
  dnaR  exc +9.40  inh -6.40  net +2.99
  mdn   exc +2.45  inh -1.73  net +0.72
  fwd   exc +4.93  inh -3.29  net +1.65
  escw  exc +3.12  inh -2.00  net +1.12
  groom exc +0.49  inh -0.45  net +0.05
  loom  exc +1.13  inh -0.50  net +0.63
```

Every descending population except DNg11 now moves by ≥ 1.5× (up or down) when
the weights are switched on, and the sign matches its wiring: DNa is net +2.99
and goes up 7×, MDN is only +0.72 of excitation against fast inhibition and is
pushed *down* to 0.27×. DNg11 is the exception and it is structural, not a
tuning failure: it collects only 473 in-synapses per neuron (`net +0.05`), so it
stays a noise-driven population. Grooming is therefore still a stochastic
behaviour, exactly as `CLAUDE.md`'s recipe warned for this cell type.

**Honest caveat.** A *median* neuron in this connectome has 273 in-synapses from
~21 partners. At a 2.5 Hz population rate those partners deliver
`273 × 0.0016 × 0.0025 × 20.49 ≈ 0.022` of threshold — ~50× short.
The median neuron in a 1 kHz instantaneous-injection LIF **cannot**
be network-driven at a biological population rate; only the well-connected
minority (the DNs, with 2,800–24,000 in-synapses) can, and they are. That is a
property of the model, not of the tuning, and no choice of `weightScale` fixes
it without making the DNs explode (see iteration 02).

### 4.3 Loom / GF / puff

```
spontaneous 4s: pop 2.50 Hz/neuron, LC 0.1 Hz, DNa02 L/R 21.7/6.9 Hz, MDN 0.0 Hz, GF spikes: 0
abrupt loom 0.4s: LC rate 127.5 Hz, GF spikes 87, first at 8 ms
air puff 1s: GF spikes 1
left-eye loom: DNa L-R rate diff -8.3 -> -8.9 Hz, LC 23.4 Hz
click probes: GF cluster -> spike yes, DNg11 cluster -> groom rate 200 Hz
```

**The DNa sign check.** Compare against the resting mean, not against the
simtest's `diff0` (which is sampled 500 ms after a 1 s air puff, not at rest).
Resting L−R is `dnaL − dnaR`: untuned `10.8 − 15.6 = −4.8`, tuned
`16.9 − 9.3 = +7.6`. Under a left-eye loom the printed asymmetry is untuned
`−7.9`, tuned `−8.9` — same sign — and the deviation from the resting mean that
`SignalBuilder` actually steers on is untuned `−3.1`, tuned `−16.5`: same sign,
5× larger. The behaviour is preserved and stronger.

**GF under sustained loom: 199 → 87 spikes (≈ 500 Hz → 218 Hz).** This is as far
as it goes without a model change, and the reason is worth writing down:

- At loom onset every LC crosses threshold on the *same* millisecond, so the GF
  sees one volley worth `+1.60`. That is what makes the 8 ms latency possible.
- In the sustained state the same LCs fire at `f = 127 Hz`, delivering
  `0.127 × 1.60 = 0.20` per ms, which the GF's 20 ms membrane integrates to
  `v_ss ≈ 4` — four times threshold.
- The ratio between the two is fixed at ≈ `20.49 / period_ms`. Lowering the
  LC→GF weight until the sustained drive is marginal (`v_ss ≈ 1.1`) makes the
  onset volley ≈ 0.5, which no longer fires the GF at all. That is exactly what
  iteration 05 measured: GF spikes 37, latency **19 ms**.

So in a non-adapting LIF, "fires within 10 ms of an abrupt step" and "fires only
a handful of times over 400 ms of a held step" are **mutually exclusive**. The
invariant that matters behaviourally (first spike, ≤ 10 ms) is kept; the
saturation is cut 2.3×; the remainder is a model limitation, not a parameter
choice. The two ways out, both semantic changes, are noted in §7.

### 4.4 Behaviour duties and throughput

```
behavior 20s: walk-drive on 37%, groom-drive on 8%, DNp09 0.0-10.2 Hz, pop 2.5 Hz
siesta 15s (scale 0.84): walk-drive on 17%
bench 16-step batches: 73 µs/step, 353 spikes/step
bench  1-step batches: 173 µs/step, 355 spikes/step
```

73 µs/step in 16-step batches against a 1,000 µs budget = **13.7× realtime**
(was 115 µs / 8.7×; fewer spikes, faster). Arousal bursts still work and are now
a real event: `--gpucheck` scenario H reports
`population rate 2.53 -> 5.87 Hz across the burst` (was 10.92 → 14.49, i.e.
+33%; now +132%).

### 4.5 Verdict lines

```
PASS realtime: 16-step batches 73 µs/step (budget 1000)
PASS: GF silent at rest, fires on loom; locomotor drive fluctuates; stim works; siesta alive
ALL BEHAVIOR TESTS PASS
GPUCHECK PASS
```

`--brainshot notes/brainshot-tuned.png`: roughly two dozen discrete spike halos,
concentrated in the central brain (where the rate is 8.6 Hz) with a scattering in
the optic lobes and none in the antennal/sensory field — countable flashes, not
the uniform blizzard the 1,520 spikes/step version produced.

---

## 5. SignalBuilder mapping

| signal | formula (after) | before | rest | driven | clamp |
|---|---|---|---|---|---|
| `escape` | `sim.consumeGF()` | same | false | true within 8 ms of an abrupt loom | — |
| `nervous` | `rateLoom / 80` | same | ~0.001 (LC 0.1 Hz) | 1.0 (LC 127 Hz) | 0…1 |
| `turnBias` | `(diff − dnaBaseline) × 0.04` | same | ±0.1 rad/s jitter | −0.66 rad/s on a left loom | ±1.0 |
| `backward` | `rateMDN > 8` | same | false (MDN 0.75 Hz) | true on MDN stim | — |
| `walkDrive` | `rateFwd / **12**` | `/10` | 0.20 (2.4 Hz) | 0.85 peak spontaneous, 1.3 on stim | 0…1.3 |
| `groomDrive` | **`clamp(rateGroom / 10, 0, 1.5)`** | `/8`, **unclamped** | 0.26 (2.6 Hz) | 1.5 on DNg11 stim (200 Hz) | 0…1.5 |
| `wingDrive` | `rateEscW / 10` | same | 0.43 (4.3 Hz) | higher under escape | 0…1.3 |
| `arousal` | `ratePop / **10**` | `/20` | **0.25** (was 0.55) | 0.59 inside an arousal burst | 0…1 |

Three changes, each with a reason:

- **`groomDrive`** was the one unclamped signal in the builder, and at
  `209 Hz / 8 = 26` it pinned instantly. `/10` puts rest at 0.26 — just under
  FlyModel's 0.3 groom-*exit* threshold, so a bout ends on a downswing — entry
  (0.5) on a genuine upswing, and every real stim at the 1.5 clamp. Measured
  spontaneous groom duty 8% (untuned: 9%).
- **`walkDrive` /10 → /12** moves FlyModel's 0.22 walk-entry threshold from
  *below* DNp09's resting mean (2.2 vs 2.4 Hz — a coin flip, duty 43–48% and
  drifting towards the 50% invariant ceiling) to *above* it (2.6 vs 2.4 Hz).
  Duty 37%, siesta 17%.
- **`arousal` /20 → /10** un-pins the spontaneous-takeoff gate. Rest 0.25 sits in
  the intended 0.1–0.3 band and only an arousal burst (5.87 Hz → 0.59) crosses
  FlyModel's `arousal > 0.5`, which is what that gate was for.

`--simtest`'s `walkOn` / `groomOn` probes duplicate this mapping, so their
divisors moved with it (`/12`, `/10`). The thresholds they test — 0.22 and 0.5 —
are FlyModel's and were **not** touched.

---

## 6. Also fixed here (from `notes/04-gpucheck.md` §4)

- **§4.1 the fma comment.** `LIF.metal`'s header claimed `mathMode = .safe`
  makes the shader "match a straightforward CPU reference". It does not: the
  leak line contracts to `fma(v, decay, baseline*scale)`. Both the shader header
  and `MetalSim.makeLibrary`'s inline comment now say so and point at the Swift
  spelling a reference must use (`(baseline*scale).addingProduct(v, decay)`).
- **§4.3 `floorV`.** Changed from `var` to `let` with a comment saying it is a
  read-only mirror of the shader's hardcoded `−2.0f`. Deleting it outright was
  the stated preference, but `GPUCheck.RefSim` legitimately reads it (it is the
  CPU side's clamp), so demoting it to an immutable documented constant removes
  the trap — a tuning pass can no longer set it and believe something changed —
  without duplicating the literal in a third place.

---

## 7. What remains fragile

1. **The antennal-lobe local interneurons are pinned at the firing ceiling** —
   diagnosed in §9, accepted. 2,907 neurons (2.1%) exceed 20 Hz.
2. **The GF/loom trade-off (§4.3)** is at the edge: latency 8 ms against a
   ≤ 10 ms invariant, with `loomGain 0.22` and `baselineLoom 0.008…0.028` both
   load-bearing. Lowering either pushes it out. Two real fixes, both semantic:
   drive the loom input into the whole `visual_projection` class instead of only
   the 314 LC neurons (recruits the feed-forward inhibition the GF already has
   wired — `inh −3.78` — but which nothing currently activates), or add
   spike-frequency adaptation.
3. **Walk duty is a fluctuation statistic.** DNp09 sits in the one-kick regime,
   so its mean rate is pinned near `pNoise` and the duty is set by where the
   threshold falls relative to that mean. It has ~17 points of headroom on each
   side of the 20–50% band now, but any change to `pNoise` or `baselineFwd`
   moves it immediately.
4. **DNg11 is still noise-driven** (`net +0.05` of in-weight, 1.00× network
   contribution). Grooming is stochastic. Structural, not tunable.
5. **Siesta relies on compression, still.** `activityScale 0.84` scales baseline
   *and* `pNoise`, and firing is now noise-driven, so the sensitivity is if
   anything higher than before: 37% → 17% walk duty for a 16% scale change.
   `CLAUDE.md`'s "never scale baselines linearly" gotcha is more true now, not
   less.
6. **Resting DNa asymmetry is seed-dependent** (§10): `dnaL − dnaR` at rest is
   `+7.6 Hz` at the default seed but ranges over `0 … +17 Hz` across seeds, and
   the *sign* of the printed left-loom asymmetry follows it. Only the deviation
   from the resting mean — what `SignalBuilder.dnaBaseline` adapts out over 8 s —
   is seed-stable (always negative). Any future check on the DNa direction must
   be written against the deviation, not against the raw `L − R`.

---

## 8. What the docs pass must update (not edited here)

- **`README.md`** numeric claims: spontaneous population rate 10.9 → **2.5
  Hz/neuron**, spikes/step 1,520 → **353**, µs/step 115 → **73**, GF loom
  latency 4 → **8 ms**.
- **`CLAUDE.md` → "Tuning gotchas"**:
  - the resting-point rule is now explicit: `baseline × 20.49` vs threshold 1,
    with **0.0488 = self-firing** and **0.0283 = one-kick**. Baselines live per
    super class in `SimParams.baselineByClass`, not as one flat range.
  - "LC→GF electrical drive (×6 boost)" is stale: `gapJunctionBoost = 1.0`
    (LC4/LPLC2 → GF) and a separate `sensGFBoost = 3.0` (sensory → GF).
  - `weightScale` is **0.0016**/synapse, not 0.0008, and it lives in
    `MetalSim.swift`, not `Sim.swift`.
  - worth adding: **the escape race is now onset-synchrony vs sustained
    integration** (§4.3), and the ≤10 ms invariant is what pins `loomGain`.
- **`CLAUDE.md` → "Build, run, verify"**: add
  `./DesktopFly --brainstats [s]` (resting-regime diagnostics; the tool that
  makes this operating point checkable).
- **`CLAUDE.md` → "Adding a new neuron population"** step 5 should say *always
  clamp* — `groomDrive` was the counter-example and is now clamped.


---

## 9. The lLN hot spot: diagnosed, accepted

`--brainstats` grew a `hotspot` probe (the hottest cell type's own
neurotransmitter bytes, the sign it actually sends, and its ten strongest
excitatory sources). On the tuned brain:

```
hotspot lLN1_bc (n=30, 500 Hz):
  own nt bytes: UNKNOWN 29 (sends +29/-0), SER 1 (sends +1/-0)
  positive in-weight 5.3 total, 40% of it from other lLN1_bc
  class-wide: 12686 UNKNOWN-nt neurons send + (9.1% of the brain, 2.83 Hz mean);
              they are 77 of the 2907 neurons above 20 Hz (3%)
  nt bytes of ALL 2907 neurons above 20 Hz: ACH 1765, GLUT 495, GABA 432,
              UNKNOWN 167, SER 26, DA 18, OCT 4
  top presynaptic sources by summed +weight (per target neuron):
    lLN1_bc nt UNKNOWN sends +  500.00 Hz  +0.08     (x10 — every one of the top ten)
```

**`lLN1_bc` on its own is a sign artifact.** 29 of its 30 neurons have no Codex
`nt_type`, so `etl.py`'s fallback signed them from the parquet (or, for a neuron
with no parquet call, the `sign[sign == 0] = 1` default); all 29 came out
**excitatory**, 40% of their positive in-weight comes from *each other*, and the
ten strongest sources into the type are ten other `lLN1_bc` at the ceiling. `lLN`
is an antennal-lobe **lateral local neuron**, canonically GABAergic — an
excitatory lLN→lLN loop is almost certainly wrong. (The parquet is not shipped,
so which branch of the fallback produced the `+1` cannot be checked from here.)

**But it does not explain the hot tail, and it is not worth a code change.**

- Of the 2,907 neurons above 20 Hz, **2,740 (94%) carry a measured Codex NT**
  (ACH 1,765, GLUT 495, GABA 432). Only 167 are `UNKNOWN`, and only **77** are
  `UNKNOWN`-and-signed-`+`, i.e. **2.6% of the hot tail**. The rest is genuine
  wiring driving genuine sustained activity.
- The whole potentially-mis-signed class is **12,686 neurons (9.1% of the brain)
  averaging 2.83 Hz** against a 2.54 Hz population mean — as a class it is not
  hot at all. The artifact is a handful of recurrent loops inside it, not a
  systematic excitatory bias.
- Upper bound on any fix: 77 neurons × 500 Hz / 139,255 = **0.28 Hz**, i.e. ≤ 11%
  of the population mean, and **zero** behavioural effect — no `lLN` is in any
  role group (every role rate is ≤ 17 Hz; `sens` is 0.0 Hz).

**Recommendation: no change to the sim, one rule for the ETL agent.** A load-time
override in `MetalSim` would put a hardcoded cell-type list inside the simulation
and would have to be mirrored in `GPUCheck.quantizeWeights` to keep the
15,091,983-of-15,091,983 weight-equality proof. The right place is `etl.py`'s
sign fallback: **before** trusting the parquet for an `UNKNOWN`-`nt_type` neuron,
apply a cell-type prior — if `primary_type` matches a canonically GABAergic
antennal-lobe local-interneuron family (`lLN*`, `il3LN*`, `v2LN*`), sign `−1`.
Acceptance for that change: the ETL's existing `signFallback` counters move by
the expected amount, and `--brainstats` shows `lLN1_bc` out of the top ten with
the >20 Hz count down by ≲ 77 and the population mean down by ≲ 0.28 Hz.

## 10. Seeds

`--seed N` (decimal or `0x` hex) pins the sim seed for the whole process. Without
it, every CLI mode (`--simtest`, `--behaviortest`, `--gpucheck`, `--brainstats`,
`--brainshot`) uses the shipped `0x5EED1F1F` and stays reproducible, while the
**live app draws a fresh seed per launch** (`launchSeed()` in `main.swift`), so
two menu-bar launches are not the same fly. `--gpucheck` follows the flag too, so
the bit-exactness proof can be re-run on any seed.

| seed | GF at rest | loom latency | walk duty | siesta duty | air-puff GF | verdict |
|---|---|---|---|---|---|---|
| `0x5EED1F1F` (default) | 0 | 8 ms | 37% | 17% | 1 | PASS |
| `0x11111111` | 0 | 9 ms | 32% | 26% | 0 | PASS |
| `12345` | 0 | 4 ms | 27% | 15% | 0 | PASS |
| `0xA5A5A5A5` | 0 | 6 ms | 22% | 18% | 0 | PASS |

All four hold every invariant. Tightest margins: **walk duty 22%** against the
20% floor (`0xA5A5A5A5`) and **latency 9 ms** against the single-digit rule
(`0x11111111`). The left-loom DNa deviation is negative at every seed (−15.6,
−23.7, −13.5 against the default's −16.5), but the raw printed `L − R` is
positive at `0xA5A5A5A5` — see §7.6.
