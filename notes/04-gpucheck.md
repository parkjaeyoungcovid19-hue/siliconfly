# 04 — GPU-vs-CPU cross-check

`./DesktopFly --gpucheck` (new, `GPUCheck.swift`) runs an **independent CPU
reference** of the sim next to the Metal one and compares them after every
step. The reference was written from `git show HEAD:Sim.swift` (`LIFSim.step`,
the 668-neuron sim), not from `MetalSim.swift`/`LIF.metal`.

**Verdict: PASS.** Over 13,000 simulated milliseconds across seven scenarios the
two sims are **bit-identical** — same spike sets, same refractory counters, same
group histograms, same rate EMAs, `max |Δv| = 0` — with two exceptions that are
understood and quantified: overlapping click stims (1–2 ulp, §4.2) and the gait
input's `sin` (1 ulp on 24 neurons, §4.5).

Getting there took one non-obvious fact: **`mathMode = .safe` does not disable
fused multiply-add contraction**, so a "straightforward" CPU reference does *not*
match the shader (§4.1).

---

## 1. What the reference is

`RefSim` (in `GPUCheck.swift`) implements HEAD's `LIFSim.step` literally on the
full connectome:

1. `simMs += 1`, arousal-burst schedule, `p = (burst ? pNoise*6 : pNoise) * activityScale`
2. per neuron: `refr > 0 ? (refr--, v *= decay) : (v = v*decay + baseline*scale, + noiseKick)`
3. loom L/R → LC neurons, gait → ascend, air puff → sens (applied refractory or not)
4. click stims, `untilMs = simMs + duration` at merge, active while `simMs < untilMs`
5. delayed inhibition for this millisecond, one `max(-2, …)` per accumulator
6. threshold on the **post-decrement** refractory value, `v = 0`, `refr = 2`
7. propagation: excitation into this step's `v` (HEAD's placement), inhibition
   into the `+4 ms` ring slot; then the group histogram and the rate EMAs

Three deliberate departures, all forced by the port and all verified rather
than assumed:

| departure | why | verified how |
|---|---|---|
| synapses accumulate in Int32 Q18, one clamped add per target | integer atomics are order-independent | the reference quantizes the same way; **0 of 15,091,983** weights differ from the GPU's buffer, computed with an independent factor order |
| noise is `pcg(pcg(seed + step*2654435761) + i)`, not a sequential RNG | a hashed stream is reproducible per (step, neuron) | transcribed from `LIF.metal` (not from `MetalSim.pcgHash`) and checked against it; every rest scenario is noise-driven and bit-exact |
| excitation is applied at the top of *t+1* instead of the end of *t* | `(v+exc)*decay + baseline` either way | the reference keeps HEAD's placement and exposes `membrane` = v *before* that add, which is exactly what the GPU's `v` buffer holds between steps; `max \|Δv\| = 0` |

`membrane()`, `debugRefr()`, `lastStepSpikes()`, `lastStepGroupCounts()`,
`setSeed`, `setBaseline`, `debugParams`, `fixedPointScale` were enough — **no new
test hooks were added to `MetalSim.swift` or `LIF.metal`** (the quantized-weight
check reads `Connectome.gpu.shared!.weightFx`, which was already reachable).

---

## 2. Results (M4 Pro, seed `0x5EED1F1F`, default `SimParams`, 27.3 s)

| scenario | steps | spikes+GF | refr | groups | rates | max \|Δv\| |
|---|---|---|---|---|---|---|
| init baselines / arithmetic probe (rest, `MetalSim.init`'s own baselines) | 120 | = | = | = | = | **0** |
| A rest | 300 | = | = | = | = | **0** |
| B loom L 1.0 / R 0.5 + air puff 0.3 | 300 | = (185 GF) | = | = | = | **0** |
| C stim 200 × 0.5 for 7 ms, 1 ms steps | 16 | = | = | = | = | **0** |
| D activityScale 0.84 + sensoryGate 0.6 + loom + puff | 150 | = | = | = | = | **0** |
| E two overlapping stims (0.1/9 ms + 0.3/5 ms, sets overlap) | 20 | = | = | = | = | 1.19e-07 |
| E′ same, reference switched to the GPU's stim summation | 20 | = | = | = | = | **0** |
| G gait 0.5 @ 8 Hz | 200 | = | = | = | = | 1.19e-07 |
| H 12.2 s spontaneous, through the first arousal burst | 12,200 | = | = | = | = | **0** |

`totals: ref 1084491 spikes, gpu 1084491 spikes over 786 steps` (A–E on one
pair of sims, state carried across scenarios). **No first divergence to report**
for A–D and H: the runs are bit-identical, so `firstDivergence` never fired.

Rate EMAs (`rateLoom`, `rateDNaL/R`, `rateMDN`, `rateFwd`, `rateGroom`,
`rateEscW`, `ratePop`) were compared every step at 1e-3 relative; they are in
fact bit-equal, as is `simMs`, `consumeGF()` and `totalSpikes`.

Scenario H is the only place the burst branch (`p × 6` for 400 ms) can be
reached: `population rate 10.92 -> 14.49 Hz across the burst; reference burst
window [12000, 12400), next at 29150`. The reference draws that schedule from
its own seeded stream, so 300 bit-identical steps inside the window confirm the
GPU's schedule and `p × 6` path agree.

### 2.1 Batch invariance

```
batch invariance 96 steps: 96x1 vs 6x16 -> bit-identical; 96x1 vs 50+46 -> bit-identical
stim invariance (0.5/7 ms on 200 neurons): 16x1 vs 1x16 -> bit-identical
```

`step(50) + step(46)` also exercises the `maxBatch = 64` split inside `step()`.
The stim case exercises the sub-batch that must not cross a stim expiry.

### 2.2 Synaptic delay probe

Both probes force one spike with `stimulate([i], strength: 5, durationMs: 2)`
from a state identical to a control sim, and time the arrival at the targets.

| pre | targets | first Δv at offset | arrival size vs the Q18 weight |
|---|---|---|---|
| n91297 (largest negative out-sum, 9,783 out-edges — the max-out-degree neuron) | 9,783 inhibitory | **+4 ms: 9,751**, +5 ms: 32 | 9,709 checked, max \|Δv − w\| = **2.98e-08** |
| n86289 (largest positive out-sum) | 8,454 excitatory | **+1 ms: 8,398**, 0 (never): 39, +2…+8: 17 | 8,389 checked, max \|Δv − w·decay\| = **9.76e-08** |

Reading: excitation lands one step later and is then decayed once (so the
expected step is `w · decay`); inhibition lands exactly four steps later and is
applied *after* the decay (so the expected step is `w`, undecayed). The
residuals are half an ulp of the membrane values (~0.5–1.0), i.e. the rounding
of `v + Δ`, not a weight error. The stragglers are second-order: a target that
also spiked or hit the −2 floor on the arrival step has its difference erased
(39 excitatory targets never differ at all), and 32 inhibitory targets are
reached one step later through another neuron.

### 2.3 Gait probe

`gaitDrive 0.5`, phase advancing 8 Hz, 200 steps, 24 ascend neurons:

```
ascend-only |Δv|: step 1 3.73e-09, worst over 200 steps 1.19e-07
```

3.73e-09 is exactly 1 ulp of the drive term (`0.5 × 0.09 × (0.5+0.5 sin)` ≈
0.045), i.e. `precise::sin` and Swift's `sin` differ by an ulp. Trying all four
fma placements of `v + drive * (0.5 + 0.5*sin(φ))` gives the *same* residual, so
the difference is in `sin` itself, not in contraction. Over 200 steps this never
flipped a spike (spikes, refr, groups and rates stayed equal), but it is not
bit-exact and must not be treated as such.

---

## 3. What this proves about the port

- The **per-step order** (§1) is the CPU sim's, including the pre-decrement
  refractory test (a neuron leaving refractoriness may fire on the same step)
  and the single clamped add per accumulator.
- The **excitation deferral** is algebraically and numerically transparent.
- **4 ms inhibition, 1-step excitation** hold exactly, on the two heaviest
  neurons in the graph.
- The **load-time weight transform** (weightScale 0.0008 × modulatory 0.5 ×
  gap-junction 6 for `lc4/lplc2/sens → gf`) is exactly what HEAD did plus the
  documented neuromodulator scaling: 15,091,983 of 15,091,983 quantized weights
  match a from-scratch recomputation.
- **Batching is invisible**: 1/16/50-step batches and stim expiries give
  bit-identical state.
- `MetalSim.init`'s own per-neuron baselines and gait phases match a from-scratch
  regeneration from the seed (the arithmetic probe runs without `setBaseline`).

---

## 4. Findings

### 4.1 `mathMode = .safe` does not stop fma contraction — the header comment is wrong

`LIF.metal:3-4` says the shader's float arithmetic "matches a straightforward CPU
reference", and `MetalSim.swift:131` says `.safe` means "match a CPU reference".
It does not. The leak line

```metal
vi = vi * P.decay + baseline[gid] * P.activityScale;
```

compiles to a **fused** multiply-add (one rounding), while a CPU's `a*b + c`
rounds twice. Measured, with the reference stepping the same seed and baselines:

```
0 plain a*b+c  120 steps | spikes X | refr X | max|Δv| 1.02 | FAIL | spike sets first differ at step 99
  first divergence at step 2: max |Δv| 5.96046e-08 at n14185 — ref 0.514962077 gpu 0.514962018
1 fma leak     120 steps | spikes = | refr = | max|Δv| 0 | ok
```

One ulp at step 2 becomes a **flipped spike at step 99** and a full-scale
divergence by step 116 — the razor-thin operating point (`baseline × 20.4` vs
threshold 1.0) makes the sim chaotic. This is not a correctness bug in the sim,
but it silently invalidates any future CPU reference, and it is the single fact
that decides whether such a check passes or fails. (The synaptic add
`v + acc × 2^-18` is insensitive: `acc × 2^-18` is exact, so fused and unfused
agree — variants 1 and 3 both pass.)

Proposed diff (not applied):

```diff
--- a/LIF.metal
+++ b/LIF.metal
-// MTLCompileOptions.mathMode = .safe (no fast-math reassociation), so the
-// float arithmetic here matches a straightforward CPU reference.
+// MTLCompileOptions.mathMode = .safe (no fast-math reassociation). It does NOT
+// disable fused multiply-add contraction: the leak below compiles to
+// fma(v, decay, baseline*scale), one rounding where a CPU's `a*b + c` has two.
+// A bit-exact CPU reference must fuse the same way — in Swift,
+// `(baseline*scale).addingProduct(v, decay)`. One ulp flips a spike within
+// ~100 ms; see notes/04-gpucheck.md.
--- a/MetalSim.swift
+++ b/MetalSim.swift
-        opts.mathMode = .safe       // no fast-math reassociation: match a CPU reference
+        opts.mathMode = .safe       // no reassociation (fma contraction still applies)
```

### 4.2 Overlapping click stims round differently from the CPU sim

HEAD added each active stim's strength to `v` in turn; `MetalSim` sums them into
one `extInput` value per neuron (`rebuildExtInput`) and adds that once. For a
neuron covered by two stims at once this is a different rounding: scenario E
shows `max |Δv| = 1.19e-07` (1–2 ulp), and switching *the reference* to the
GPU's summation makes it bit-exact (scenario E′, `max |Δv| = 0`) — so that is
the whole cause. Harmless numerically (spikes, refr, groups and rates stayed
equal over 20 steps), but chaos means it can eventually flip a spike, and the
brain window can produce overlapping stims (`pendingStims` holds up to 8).
Worth one line in the notes rather than a code change; disjoint or
non-overlapping stims are unaffected.

### 4.3 `SimParams.floorV` is a dead knob

`floorV` is declared with the comment "matched in LIF.metal", but nothing reads
it: `StepParams` has no such field and the kernel hardcodes `max(-2.0f, …)` in
two places. Setting it during tuning would silently change nothing on the GPU
while a CPU reference (and a reader) would honour it.

```diff
--- a/MetalSim.swift
+++ b/MetalSim.swift
-    var floorV: Float = -2             // hyperpolarization clamp (matched in LIF.metal)
+    // Hyperpolarization clamp. LIF.metal hardcodes -2.0f and StepParams does not
+    // carry it, so this is documentation only: change both or add a field.
+    let floorV: Float = -2
```

### 4.4 `durationMs: n` stimulates for `n − 1` steps (inherited, load-bearing)

Confirmed empirically on both sides: `durationMs: 1` applies to **zero** steps
and is a complete no-op (`delay probe … durationMs 1 -> 0 stimulated steps
(spiked false, states still identical true)`). The GPU reproduces HEAD exactly —
`untilMs = simMs + duration` at merge, active while `simMs < untilMs`, and
`dropFinishedStims`'s `simMs + 1 >= untilMs` is the same predicate one step
early, which is also what bounds the sub-batch. Nothing to fix; noted because
`--simtest` and the brain window pass durations that are all off by one.

### 4.5 Gait input is not bit-exact (expected)

See §2.3: 1 ulp from `precise::sin`, 24 neurons, gait only. Any future
determinism claim ("two runs are byte-identical") holds only because both runs
call the *same* `sin`; it does not extend to a CPU reference.

### 4.6 Minor: `refr` is a `uchar`, `P.refractory` a `uint`

`refr[gid] = uchar(P.refractory)` truncates silently. Only reachable if a tuning
pass sets `refractoryMs > 255`; a `precondition` in `MetalSim.init` would be
cheap.

---

## 5. Not verified

- **The spike bus.** Every sim here was built with `spikeBus: nil`. The GPU's
  sampling (32 hash-bucketed slots, last-writer-wins, up to 12 pushed) is a
  deliberate redesign of HEAD's strided sample and was not compared.
- **Non-default `SimParams`.** Everything ran at the defaults; `activityScale`
  (0.84) and `sensoryGate` (0.6) are runtime inputs and *were* exercised. A
  different `weightScale`/`modScale`/`gapJunctionBoost` rebuilds `MetalShared`
  and would change `fxScale` — the reference follows `sim.fixedPointScale`, so
  it should hold, but it was not run.
- **One seed** (`0x5EED1F1F`). `setSeed()` was not exercised (the reference
  regenerates baselines/phases from the same seed through `init`).
- **Thread safety.** `stimulate()` was only called from the test thread.
- **Beyond 12.2 s / a second arousal burst**, and any state after the first
  burst's `burstNext = 29,150`.
- **`--behaviortest`** was not re-run here (it makes many short sims and is
  unaffected by this file); `--simtest` was, and passes unchanged.

---

## 6. Commands

```sh
./build.sh
./DesktopFly --gpucheck    # 27 s, prints GPUCHECK PASS, exits non-zero on FAIL
./DesktopFly --simtest     # unchanged: PASS realtime + PASS invariants
```

`--gpucheck` is self-contained: it loads the connectome once, builds 21 short-lived
`MetalSim`s on the shared (cached) GPU resources, and holds one `RefSim`
(≈120 MB: its own copy of `colIdx` and the quantized weights).
