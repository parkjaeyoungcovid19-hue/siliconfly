# 06 — Re-tuning after the antennal-lobe sign fix

`notes/05-tuning.md` tuned the full brain while a data artifact was live: 94
antennal-lobe local interneurons with no NT prediction were fallback-signed
excitatory, formed a mutual-excitation loop pinned at the 500 Hz ceiling, and
secretly carried the whole "network contribution 3.01×" result. The ETL now
applies a cell-type sign prior (`data/connectome.json.signFallback.alPrior*`),
the loop is gone — and so was the network: **population 2.54 → 0.85 Hz/neuron,
contribution 3.01× → 1.01×**. Invariants still passed, but the connectome was
doing nothing.

This pass re-derives the operating point. Every number below is from a run in
`notes/tuning-runs/r2-*`; the starting state is `r2-00-start-*`, the shipped one
`r2-final-*`.

**Result:** `--simtest` PASS, `--behaviortest` 17/17, `--gpucheck` PASS on three
seeds. Population **1.75 Hz/neuron**, contribution **1.31×**, all six command
populations 13×–∞ (intrinsically silent, 100% network-driven), 0.8% of neurons
above 20 Hz, 74 µs/step (13.5× realtime).

---

## 1. What the start state actually was

```
population: 0.85 Hz/neuron | 118 spikes/step
histogram: silent 71727 (51.5%) | <1 Hz 27056 (19.4%) | 1-5 Hz 39848 (28.6%)
           | 5-20 Hz 605 (0.4%) | >20 Hz 19 (0.0%)
population intrinsic 0.84 Hz -> tuned 0.85 Hz (1.01x)
  dnaL 3.47x | dnaR 3.04x | mdn 1.02x | fwd 1.23x | groom 1.00x | escw 0.94x
```

Two structural facts explain it, and they set the whole pass:

1. **A median neuron cannot hear the network over the noise.** With
   `noiseKick 0.42` a single noise event was 42% of threshold. A median neuron
   has 273 in-synapses; at `weightScale 0.0016` and a ~1 Hz population that is
   `273 × 0.0016 × 0.001 × 20.49 ≈ 0.009` of steady-state depolarisation — 2% of
   one kick. Noise decided every spike; the wiring was rounding error.
2. **The optic lobe is 56% of the brain and is net-inhibitory at rest.** It has
   no drive source at rest (no photoreceptor input) and its own recurrent wiring
   suppresses it: measured `optic intrinsic 0.90 → tuned 0.83` at every setting
   tried. Whatever the rest of the brain does, the population *average* carries
   this dead weight.

---

## 2. Final parameter table

| knob | before (05) | after | reason |
|---|---|---|---|
| `noiseKick` | 0.42 | **0.25** | the pass's main lever. See §3 |
| `pNoise` | 0.0030 | **0.0050** | holds the mean noise drive at 0.00125/ms, so only the *granularity* changed |
| `weightScale` | 0.0016 | **0.0032** | doubling is the whole headroom there is: at 0.0048 the load-time transform hits `fixed-point overflow: max|w| 11.5440 x scale 65536 x 4096 exceeds Int32` (`r2-03`). ~0.0033 is a hard cap |
| `gfInputScale` | — (new) | **0.12** | gain on the GF's *ordinary chemical* in-synapses only. Forced; see §4 |
| `gapJunctionBoost` | 1.0 | **0.5** | LC→GF is stated relative to `weightScale`; 0.0032 × 0.5 = the 0.0016 the escape race was calibrated at (one synchronous LC volley = +1.6 threshold units) |
| `sensGFBoost` | 3.0 | **1.5** | same, for the 16-neuron antennal-mechanosensory path: 0.0032 × 1.5 = 0.0048 |
| `loomGain` | 0.22 | **0.32** | not for latency (3 ms with room to spare) but for the DNa steering signal-to-noise: at 0.22 the left-eye-loom asymmetry deviation came out **positive** on seed `0xA5A5A5A5` (`r2-final-seeds` before/after: `-10.8 -> -7.5` vs `+13.7 -> -20.2`) |
| `airPuffGain` | 0.06 | **0.05** | puff GF spikes 2 → 0–1 against a ≤2 invariant; 2 was no margin |
| `baselineFwd` | 0.038 | **0.032** | DNp09's own resting point, below the one-kick line so it stays network-driven (0.50 Hz intrinsic → 15.5 Hz wired) |
| `baselineCommand` | 0.036 | **0.022** | v_rest 0.48, far below the one-kick line: DNa/MDN/DNg11/escW are **0.00 Hz intrinsic**, so every spike they emit is the connectome's |
| `baselineGF` | 0.002 | 0.002 | unchanged — see §4, a negative value does not work |
| `baselineLoom` | 0.008…0.028 | unchanged | LCs stay silent at rest (0.0 Hz) and heterogeneous enough to desynchronise under a held loom |

### 2.1 The per-super-class table

The landmarks moved with `noiseKick`. A neuron rests at
`baseline × 20.49 + pNoise × noiseKick × 20.49` = `baseline × 20.49 + 0.026`:

| landmark | at kick 0.42 (05) | at kick 0.25 (now) |
|---|---|---|
| one kick fires it | 0.0283 | **0.0354** |
| still one-kick after the siesta's ×0.84 | 0.0403 | **0.0424** |
| self-fires on the mean noise drive | 0.0475 | 0.0475 |
| self-fires with no noise at all | 0.0488 | 0.0488 |

| super class | n | before (05) | after | why |
|---|---|---|---|---|
| `optic` | 77,873 | 0.003…0.038 | **0.021…0.043** | straddles 0.0354 with the mass just under it, and clears 0.0424 at the top so the class survives the siesta |
| `central` | 32,381 | 0.008…0.046 | **0.023…0.047** | same, wider — this is where the network contribution comes from (1.98 → 3.76 Hz) |
| `visual_projection` | 7,684 | 0.003…0.034 | **0.021…0.043** | |
| `visual_centrifugal` | 522 | 0.005…0.040 | **0.019…0.043** | |
| `descending` | 1,305 | 0.008…0.044 | **0.019…0.043** | 1.16 → 7.14 Hz, the strongest class contribution |
| `ascending` | 1,750 | 0.008…0.044 | **0.019…0.043** | |
| `motor`, `endocrine` | 190 | 0.005…0.036 | **0.019…0.043** | |
| `sensory` | 16,938 | 0.000…0.004 | unchanged | receptors: silent unless driven |
| `sensory_ascending` | 612 | 0.000…0.006 | unchanged | |
| fallback | — | 0.005…0.036 | **0.019…0.043** | |

Unchanged and deliberately so: `decay` 0.9512, `threshold` 1, `refractoryMs` 2,
`modScale` 0.5, `inhDelayMs` 4, `burstFactor` 6 / `burstMs` 400 /
`burstGapMs` 15–40 s, `ascendGain` 0.09, `rateAlpha` 1/120.

---

## 3. The finding: noise granularity, not weight scale, is the lever

`weightScale` alone cannot do it. Doubled to 0.0032 (`r2-01`) the population went
0.85 → 1.00 Hz (1.19×) while the DNs exploded (DNa02 36 Hz) and the GF started
firing at rest. Above 0.0048 the sim will not even build. Two other candidates
died the same way:

- **Spontaneously active sensory neurons** (`sensory` → 0.026…0.046, so the
  16,938-neuron input layer fires at 2.4 Hz, `r2-02`): population went up by
  exactly the sensory neurons' own contribution and *nothing propagated* —
  `optic 0.83 → 0.81`, `central 1.35 → 1.42`, ratio still 1.01×.
- **Tonic pacemakers** (class tops pushed past 0.0488, `r2-04`): population rose
  to 1.3–1.7 Hz but the ratio stayed 1.02–1.19×, because a tonic neuron fires in
  the `weightScale = 0` run too.

What works is changing *how the noise is delivered*. Same mean drive
(`pNoise × noiseKick` = 0.00125/ms, within 1% of the old 0.00126), smaller and
more frequent events, so a noise event is no longer 17× a synaptic one:

| kick / pNoise | population | intrinsic | ratio | >20 Hz | siesta walk duty |
|---|---|---|---|---|---|
| 0.42 / 0.0030 (05) | 1.01 | 0.84 | 1.20× | 0.2% | — |
| 0.25 / 0.0050 | 1.30 | 0.94 | 1.39× | 0.6% | — |
| **0.25 / 0.0050 + rebalanced table (shipped)** | **1.75** | **1.34** | **1.31×** | **0.8%** | **17–42%** |
| 0.20 / 0.0063 + table | 2.32 | 1.71 | 1.35× | 1.6% | 0% on seed 12345 |
| 0.15 / 0.0084 + table | 1.92 | 1.11 | **1.73×** | 1.4% | 1% on seed 12345 |

**Why the finest noise was rejected.** The siesta multiplies baseline *and*
`pNoise` by `activityScale` 0.84, which costs ~0.144 of resting v. A neuron that
was one-kick stays one-kick only if its gap was under `kick − 0.144`, so the
fraction of the firing population that survives the siesta is `(kick − 0.144)/kick`:

| kick | survives the siesta |
|---|---|
| 0.42 (05) | 66% |
| **0.25 (shipped)** | **42%** |
| 0.20 | 28% |
| 0.15 | **4%** |

At 0.15 the whole brain fell off a cliff at 2 p.m. and DNp09's siesta walk duty
measured 7% on the shipped seed but **1% on seed 12345 and 0% on a neighbouring
config** — a failed invariant, twice. 0.25 is the point where the network still
competes with the noise and the siesta still has a brain to run on. It costs
0.42× of contribution ratio and that is the single biggest miss of this pass
(§8).

---

## 4. The giant fiber had to be taken off the global weight scale

This is the one **logic** change, in `MetalShared`'s load-time weight transform
and mirrored in `GPUCheck.quantizeWeights` and `Diagnostics.inWeightAudit`:

```
w = synapses * weightScale * (pre nt in {DA,SER,OCT} ? modScale : 1)
      * (post role == gf ? (pre lc4/lplc2 ? gapJunctionBoost
                            : pre sens ? sensGFBoost : gfInputScale) : 1)
```

`gfInputScale` (0.12) is a fourth gain, on the GF's ordinary chemical
in-synapses. The GF's three input routes are now three independent gains.

**Why it is not optional.** The GF collects ~3,800 in-synapses per neuron, so at
one shared `weightScale` it is an order of magnitude more excitable than a median
neuron and starts firing spontaneously long before the rest of the brain is
network-driven. Measured GF rate at rest as `weightScale` rises (kick 0.15 table,
`r2-11`): **silent at 0.0016, 3.2 Hz at 0.0020, 6.0 Hz at 0.0024, 13.0 Hz at
0.0028.** And no baseline fixes it — `baselineGF` swept at `weightScale` 0.0028
(`r2-12`):

| `baselineGF` | resting v | GF spikes / 4 s rest | loom first spike | puff GF |
|---|---|---|---|---|
| −0.030 | −0.59 | 36 | 4 ms | 29 |
| −0.070 | −1.41 | 29 | 7 ms | 10 |
| −0.098 | pinned at the −2 floor | **21** | **16 ms** | 9 |

Even hyperpolarised onto the floor the GF still fires 5 Hz at rest (its input
fluctuates by ±1.5 threshold units), and the ≤10 ms invariant is gone. Sweeping
`gfInputScale` instead, at `weightScale` 0.0032 (`r2-14`):

| `gfInputScale` | GF spikes / 4 s rest | loom first spike | puff GF spikes |
|---|---|---|---|
| 0.40 | 33 | 5 ms | 20 |
| 0.25 | 7 | 5 ms | 9 |
| **0.12** | **0** | **5 ms** | **1** |

The honest reading: this is a *model* fix, not a connectome fix. A LIF that gives
every neuron the same threshold and time constant makes in-degree a proxy for
excitability, which is unphysiological; the GF is where that bites hardest. The
alternative (normalising every neuron by its in-weight) is a much larger semantic
change and would break the "these are the connectome's own weights" story for
139,255 neurons rather than 2.

---

## 5. Iterations

One knob family at a time; the escape race was re-checked every iteration.

| # | change | pop | ratio | GF rest | latency | walk | siesta | verdict |
|---|---|---|---|---|---|---|---|---|
| 00 | start (05 params, fixed data) | 0.85 | 1.01× | 0 | 4 ms | 48% | 28% | invariants pass, connectome inert |
| 01 | `weightScale` 0.0032 (GF paths held) | 1.00 | 1.19× | **36** | 5 ms | 99% | 82% | **rejected**: GF fires at rest, puff 27 |
| 02 | `sensory` 0.026…0.046 at ws 0.0016 | 1.16 | 1.01× | 0 | — | — | — | **rejected**: input spikes do not propagate |
| 03 | `weightScale` 0.0048 / 0.0064 / 0.0096 | — | — | — | — | — | — | **fixed-point overflow**; hard cap ≈ 0.0033 |
| 04 | tonic tails (class tops > 0.0488) | 1.30–1.74 | 1.02–1.19× | — | — | — | — | **rejected**: tonic firing is intrinsic |
| 05 | compress `optic` to 0.024…0.030 | 1.03 | 1.12× | — | — | — | — | **rejected**: optic 0.96 → 0.81, worse |
| 06 | kick 0.25 / 0.15, same mean drive | 1.30 / 2.19 | 1.39× / 1.40× | — | — | — | — | **the lever** |
| 07 | ws 0.0010–0.0020 in the fine-noise regime | 1.56–1.62 | 1.00–1.03× | 0–3.5 | — | — | — | needs *both* fine noise and ws 0.0032 |
| 08 | quiet `optic`, kick 0.15, ws 0.0032 | 1.86 | **1.70×** | 28 Hz | — | — | — | best ratio; GF and DNs unusable |
| 09–12 | `baselineGF` −0.030 … −0.098 | — | — | 36/29/21 | 4/7/**16** ms | — | — | **rejected**: no baseline silences the GF |
| 13–14 | `gfInputScale` 0.50 → 0.12 | 1.91 | — | 37→**0** | 5 ms | — | — | GF solved (§4) |
| 15 | kick 0.15 operating point + SignalBuilder | 1.92 | **1.73×** | 0 | 5 ms | 38% | 7% | **rejected**: siesta 1% on seed 12345 |
| 16 | `loomGain` 0.22 → 0.32 | — | — | 0 | 3 ms | — | — | left-loom DNa sign now negative on all 3 seeds |
| 17 | kick 0.20 + rebalanced table | 2.32 | 1.35× | 0 | 4 ms | 26% | **0%** on 12345 | **rejected** |
| 18 | **kick 0.25 + rebalanced table (shipped)** | **1.75** | **1.31×** | **0** | **3 ms** | **30%** | **40%** | all invariants, 3 seeds |

---

## 6. Final numbers (`notes/tuning-runs/r2-final-*`)

### 6.1 Rest regime

```
population: 1.75 Hz/neuron | 244 spikes/step | 203 µs/step (1-step) | 77 µs/step (16-step batches)
histogram: silent 58960 (42.3%) | <1 Hz 32256 (23.2%) | 1-5 Hz 36541 (26.2%)
           | 5-20 Hz 10356 (7.4%) | >20 Hz 1142 (0.8%)
```

Broader than 05's: the 5–20 Hz band went 1.2% → 7.4% and the >20 Hz tail 2.1% →
0.8%. Hottest cell type **LAL112 at 61 Hz** (05: `lLN2X03` at 500 Hz); nothing is
pinned at the ceiling, and the hot tail is NT-diverse (ACH/GABA/GLUT), i.e. real
wiring rather than one artifact loop.

| super class | n | mean Hz | % silent | intrinsic-only Hz |
|---|---|---|---|---|
| optic | 77,873 | 1.28 | 37.0 | 1.38 |
| central | 32,381 | **3.76** | 24.2 | 1.98 |
| sensory | 16,938 | 0.00 | 100.0 | 0.00 |
| visual_projection | 7,684 | 1.07 | 46.7 | 1.30 |
| ascending | 1,750 | 1.15 | 40.8 | 1.27 |
| descending | 1,305 | **7.14** | 22.0 | 1.16 |
| sensory_ascending | 612 | 0.00 | 100.0 | 0.00 |
| visual_centrifugal | 522 | 5.00 | 22.0 | 1.37 |
| motor | 110 | 6.98 | 10.9 | 1.30 |
| endocrine | 80 | 1.32 | 40.0 | 1.34 |

### 6.2 Network contribution (same seed, `weightScale = 0` vs tuned)

```
population intrinsic    1.34 Hz -> tuned    1.75 Hz  (1.31x)
  dnaL   intrinsic    0.00 Hz -> tuned   50.38 Hz  (inf)
  dnaR   intrinsic    0.00 Hz -> tuned   48.12 Hz  (inf)
  mdn    intrinsic    0.00 Hz -> tuned   18.75 Hz  (inf)
  fwd    intrinsic    0.50 Hz -> tuned   15.50 Hz  (31.00x)
  groom  intrinsic    0.00 Hz -> tuned    0.92 Hz  (inf)
  escw   intrinsic    0.04 Hz -> tuned    0.54 Hz  (13.00x)
  ascend intrinsic    0.73 Hz -> tuned    1.14 Hz  (1.56x)
  central    intrinsic 1.98 -> 3.76 | descending 1.16 -> 7.14
  motor      intrinsic 1.30 -> 6.98 | visual_centrifugal 1.37 -> 5.00
  optic      intrinsic 1.38 -> 1.28 | visual_projection  1.30 -> 1.07
```

**All six command populations are intrinsically silent or near-silent and
entirely network-driven** — a stronger statement than the "≥ 1.5×" target, and
including `groom`, which 05 had to write off as structurally stuck at 1.00×.
DNg11 is still barely wired (`net +0.09`), but at `baselineCommand 0.022` it no
longer has a noise floor to hide behind, so the 0.92 Hz it does run at is the
connectome's.

In-weight audit (threshold units, 1.0 = one full presynaptic volley fires it):

```
  gf    exc +2.30  inh -0.91  net +1.39  [electrical LC/sens path +1.78]
  dnaL  exc +17.46 inh -11.47 net +5.99
  dnaR  exc +18.79 inh -12.80 net +5.99
  mdn   exc +4.90  inh -3.46  net +1.43
  fwd   exc +9.87  inh -6.57  net +3.30
  groom exc +0.99  inh -0.89  net +0.09
  escw  exc +6.25  inh -4.00  net +2.25
  loom  exc +2.27  inh -1.00  net +1.27
```

The GF's line is what `gfInputScale` did: exc +3.76 / inh −3.78 in 05 became
+2.30 / −0.91, with the electrical path *up* at +1.78 (it also fixes a
diagnostic bug — the audit used to apply `gapJunctionBoost` to the sensory rows
instead of `sensGFBoost`). Net +1.39 with the chemical input turned down is what
lets one synchronous LC volley fire it in 3 ms while 1.7 Hz of background
chatter never does.

### 6.3 Loom / GF / puff / duties / throughput

```
spontaneous 4s: pop 1.72 Hz/neuron, LC 0.0 Hz, DNa02 L/R 45.0/37.5 Hz, MDN 15.7 Hz, GF spikes: 0
abrupt loom 0.4s: LC rate 172.5 Hz, GF spikes 147, first at 3 ms
behavior 20s: walk-drive on 30%, groom-drive on 8%, DNp09 0.3-39.1 Hz, pop 1.7 Hz
siesta 15s (scale 0.84): walk-drive on 40%
air puff 1s: GF spikes 1
left-eye loom: DNa L-R rate diff -16.1 -> -22.5 Hz, LC 31.5 Hz
click probes: GF cluster -> spike yes, DNg11 cluster -> groom rate 196 Hz
bench 16-step batches: 74 µs/step, 249 spikes/step
bench  1-step batches: 203 µs/step, 240 spikes/step
```

74 µs/step against a 1,000 µs budget = **13.5× realtime**. The arousal burst is a
real event: `--gpucheck` scenario H reports
`population rate 1.71 -> 5.52 Hz across the burst` (3.2×), which crosses
FlyModel's `arousal > 0.5` gate at `ratePop / 10`.

### 6.4 Verdict lines

```
PASS realtime: 16-step batches 74 µs/step (budget 1000)
PASS: GF silent at rest, fires on loom; locomotor drive fluctuates; stim works; siesta alive
ALL BEHAVIOR TESTS PASS
GPUCHECK PASS
```

### 6.5 Seeds (`r2-final-seeds.txt`)

| seed | pop | GF at rest | loom latency | walk duty | siesta duty | puff GF | left-loom DNa deviation | verdict |
|---|---|---|---|---|---|---|---|---|
| `0x5EED1F1F` (default) | 1.72 | 0 | 3 ms | 30% | 40% | 1 | −6.4 | PASS |
| `12345` | 1.74 | 0 | 3 ms | 40% | 17% | 0 | −13.9 | PASS |
| `0xA5A5A5A5` | 1.79 | 0 | 3 ms | 29% | 42% | 0 | −33.9 | PASS |

Tightest margins: **walk duty 40%** against the 50% ceiling (`12345`), **puff GF
1** against ≤2 (default), and **groom duty 41%** on `0xA5A5A5A5` — not an
invariant, but see §7.4.

### 6.6 `notes/brainshot-tuned2.png`

Two dozen discrete spike halos, concentrated in the central brain (3.76 Hz) with
a scattering through both optic lobes (1.28 Hz) and none at all in the
antennal/sensory field at the bottom (0.00 Hz, silent by design) — countable
flashes, and visibly more of them in the optic lobes than 05's shot, which is the
`optic` range moving from 0.003…0.038 to 0.021…0.043.

---

## 7. SignalBuilder mapping

| signal | formula (after) | before | rest | driven | clamp |
|---|---|---|---|---|---|
| `escape` | `sim.consumeGF()` | same | false | true within 3 ms of an abrupt loom | — |
| `nervous` | `rateLoom / **115**` | `/80` | 0 (LC 0.0 Hz) | 1.0 (LC 172 Hz); 0.27 on a gentle loom | 0…1 |
| `turnBias` | `(diff − dnaBaseline) × 0.04` | same | wander (see §9.5) | −0.26…−1.0 rad/s on a left loom, by seed | ±1.0 |
| `backward` | `rateMDN > **60**` | `> 8` | false (MDN p95 31 Hz) | true on MDN stim (~200 Hz) | — |
| `walkDrive` | **`clamp((rateFwd − 10) / 33, 0, 1.3)`** | `rateFwd / 12` | 0.12 (p50 14 Hz) | 1.3 on stim | 0…1.3 |
| `groomDrive` | `clamp(rateGroom / **5**, 0, 1.5)` | `/10` | 0.09–0.43 by seed | 1.5 on DNg11 stim | 0…1.5 |
| `wingDrive` | `rateEscW / 10` | same | 0.00 | 1.3 under escape (escW peaks at 204 Hz) | 0…1.3 |
| `arousal` | `ratePop / 10` | same | **0.175** | 0.55 inside an arousal burst | 0…1 |

Four changes:

- **`walkDrive` is rectified-linear now, not a divisor.** DNp09 no longer rests
  near zero — the connectome drives it to a p50 of 14 Hz and it modulates
  *around* that (p05 6, p95 25). A bare divisor puts FlyModel's whole
  0.08…0.22 hysteresis band below the entire resting swing, which measured **duty
  100%**. `(f − 10)/33` puts walk-entry at 17.3 Hz (~65th percentile) and
  walk-exit at 12.6 Hz (~35th), so the band straddles the distribution and the
  fly actually starts and stops. Duty 30% (05: 37%).
- **`backward` 8 → 60 Hz.** MDN is network-driven at 15–20 Hz now; the old
  threshold latched backward walking on permanently. 60 Hz is above the resting
  tail (p95 31) and far below a stim (~200 Hz).
- **`groomDrive` /10 → /5.** DNg11's rate fell with `baselineCommand`; at /10 its
  p95 never reached FlyModel's 0.5 groom-entry, so spontaneous grooming
  disappeared. /5 restores it (duty 8% on the default seed, 05: 8%).
- **`nervous` /80 → /115** tracks `loomGain` 0.22 → 0.32, so a *gentle* loom
  still lands at 0.27 — below FlyModel's 0.40 dart threshold — while an abrupt
  one still saturates. Without it a gentle steering loom would also trigger a
  dart.

`--simtest`'s `walkOn` / `groomOn` probes duplicate this mapping, so their
formulas moved with it. The thresholds they test (0.22, 0.5) are FlyModel's and
were **not** touched.

---

## 8. What is missed, and by how much

**Population contribution ratio 1.31× against a 1.5× target — short by 0.19.**
The closest attempt that met it was iteration 15 (kick 0.15): **1.73×** with
population 1.92 Hz and every other sim invariant green — and a siesta walk duty
of **1% on seed 12345 and 0% on a neighbouring config**, against a >3% floor.
Goal 1 outranks goal 2, so the shipped point trades 0.42× of ratio for a siesta
that survives on every seed (17–42%).

The ceiling on this number is structural, and it is worth stating precisely: the
network's *absolute* contribution is +0.41 Hz across 139,255 neurons, and it is
delivered almost entirely to the central brain (+1.78 Hz over 32,381 neurons),
the descending class (+5.98 over 1,305) and the motor/centrifugal classes. The
optic lobe — **56% of every population average** — has no drive source at rest
and is net-inhibited by its own wiring (1.38 → 1.28 Hz), so it subtracts. Any
ratio computed over the whole brain is diluted by a majority that cannot be
network-driven until the model has photoreceptor input. Restricted to the classes
that *have* an input source, the same run reads 1.90× (central), 6.2×
(descending), 5.4× (motor), 3.7× (visual_centrifugal).

Everything else in goal 2 is met or beaten: population 1.75 Hz (target 1.5–4),
0.8% above 20 Hz (target ≤ ~1%), nothing at the 500 Hz ceiling (hottest type 61
Hz), a broad distribution (42% silent / 23% sub-Hz / 26% 1–5 Hz / 7% 5–20 Hz),
and **six of six** command populations network-driven where the target was four.

---

## 9. What remains fragile

1. **The siesta response direction is seed-dependent, and on the default seed it
   is inverted** — walk duty 30% awake, **40%** at `activityScale` 0.84 (seed
   12345: 40% → 17%, monotone; `0xA5A5A5A5`: 29% → 42%, inverted). DNp09 is now
   purely network-driven with `exc +9.87 / inh −6.57`, and compressing the brain
   by 16% relieves the inhibition on some seeds more than it removes the
   excitation. The invariant ("not paralysed", >3%) holds with a large margin on
   every seed, but the *intent* — the fly is calmer at 2 p.m. — is no longer
   carried by the walk drive. It is still carried by FlyModel's `tempo`. A real
   fix needs DNp09's E and I pools to compress together, which is a modelling
   change, not a knob.
2. **`noiseKick` is now a first-class knob with a sharp trade-off** in both
   directions: larger → the connectome stops mattering (0.42 gave 1.01×);
   smaller → the siesta dies (`(kick − 0.144)/kick` of the firing population
   survives it: 42% at 0.25, 4% at 0.15). It should never be changed without
   re-running the siesta probe on at least three seeds.
3. **The GF is off the global weight scale** (`gfInputScale` 0.12, §4). Anyone
   changing `weightScale` must re-derive all three GF gains, or the escape race
   silently breaks in one direction or the other. The three are stated *relative*
   to `weightScale` on purpose.
4. **DNg11's rate is seed-noise.** `net +0.09` of in-weight over 6 neurons, so
   its resting p50 ranges 0.5–2.1 Hz across seeds and the measured groom duty
   ranges **8% → 18% → 41%**. Grooming is a stochastic behaviour whose *frequency*
   is not reproducible across seeds. Structural (05 §7.4 said the same); it is
   more visible now only because DNg11 lost its noise floor.
5. **The DNa steering signal-to-noise is thin.** The command DNs run at 35–50 Hz
   over 2 neurons per side with a 120 ms rate EMA, so the L−R difference is
   dominated by spike-counting noise: instrumented over 20 s at the (hotter)
   kick-0.15 point the adapted deviation ran p05 −13.4 / p50 −0.1 / p95 +12.9 Hz,
   against a left-loom deviation that measures −6.4 / −13.9 / −33.9 Hz on the
   three seeds. `loomGain` 0.32 is what keeps that sign reliable; at 0.22 seed
   `0xA5A5A5A5` came out **positive** (`-10.8 -> -7.5`). The wander this implies
   through `turnBias × 0.04` is a few tenths of a rad/s at rest — larger than
   05's, and it shows up as a curvier walk.
6. **`weightScale` has ~4% of headroom left.** 0.0032 is just under the Int32
   fixed-point bound; 0.0048 refuses to build. Any future increase needs the
   `4096` accumulation headroom in `MetalShared.init` revisited, which is a
   shader-adjacent change.
7. **`--gpucheck`'s delay probe needed its arming constant re-derived** (§10).
   Anything that raises `weightScale` or the population rate again will need the
   same treatment.

---

## 10. Also changed here

- **`GPUCheck` delay probe, arming strength 5 → 12.** The probe forces one spike
  on the largest-out-weight hub and times the arrival at its targets. Its `+5`
  was calibrated for the old weight scale and its comment claimed "+5 on a
  non-refractory neuron always clears threshold (the −2 floor bounds the
  inhibition it can meet)" — which is wrong: `LIF.metal` applies external drive
  (step 3) *before* the same step's inhibition (step 4) and floors the sum, so
  the stim has to out-run the inhibition arriving that millisecond. At this
  operating point that hub meets ~5.6 threshold units of it: the armed neuron
  reached `v = −0.605` and never fired, and `--gpucheck` failed with *"a
  durationMs 1 stim was not a no-op; a failed arming attempt perturbed the
  state"*. The no-op assertion is now control-relative too (these hubs spike
  spontaneously now, and "the test spiked" alone never meant the stim did it).
  Neither change weakens what the probe verifies — all bit-equality checks
  (`totals: ref 179688 spikes, gpu 179688 spikes over 786 steps`, batch and stim
  invariance bit-identical) passed throughout, before and after.
- **`Diagnostics.inWeightAudit`** now applies `gfInputScale`, and applies
  `sensGFBoost` (not `gapJunctionBoost`) to sensory rows — the GF's electrical
  line was previously under-reported.

---

## 11. What the docs pass must update (not edited here)

- **`README.md`** numeric claims: spontaneous population rate 2.5 → **1.75
  Hz/neuron**, spikes/step 353 → **244**, µs/step 73 → **74**, GF loom latency 8
  → **3 ms**. If it quotes a network-contribution figure, 3.01× → **1.31×**
  (with §8's caveat, or the per-class numbers, which are the honest ones).
- **`CLAUDE.md` → "Tuning gotchas"**:
  - the resting-point rule is now `baseline × 20.49 + 0.026` against threshold 1,
    with **0.0354 = one-kick**, **0.0424 = survives the siesta**, **0.0475 =
    self-fires**. The 0.0283 / 0.0488 pair is stale (it was for `noiseKick` 0.42).
  - **`noiseKick` is the network-vs-noise knob**, and the siesta survival rule
    `(kick − 0.144)/kick` belongs next to the existing "never scale baselines
    linearly" gotcha — it is the same failure mode, one level down.
  - `weightScale` is **0.0032**, and it is **capped near 0.0033** by the Int32
    fixed-point bound in `MetalShared.init` — not a free knob.
  - the GF gains: `gapJunctionBoost` **0.5**, `sensGFBoost` **1.5**, and a new
    `gfInputScale` **0.12** on the GF's chemical synapses. All three are stated
    relative to `weightScale`; changing it means re-deriving all three.
  - the escape race framing from 05 §4.3 still holds, but the numbers moved:
    latency **3 ms**, 147 GF spikes over a 400 ms held loom.
- **`CLAUDE.md` → "Neuron → behavior mapping"**: `mdn` drives backward walking
  above **60 Hz**, not 8; `dnp09` → `walkDrive` is **rectified-linear**
  (`(rate − 10)/33`), not a divisor.
- **`CLAUDE.md` → "Build, run, verify"**: add `./DesktopFly --brainstats [s]`
  (still missing; 05 §8 asked for it too).
- **`CLAUDE.md` → "Adding a new neuron population"** step 4: the command-DN
  baseline is **0.022** (`baselineCommand`), deliberately below the one-kick
  line, and DNp09 has its own (**0.032**).
