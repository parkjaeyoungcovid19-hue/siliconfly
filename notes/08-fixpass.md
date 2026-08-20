# 08 — fix pass (code quality, zero behavior change)

Eight reviewer items applied to the finished whole-brain port. Constraint on every
one of them: the sim must stay bit-exact (`--gpucheck` PASS, `--simtest` and
`--brainstats` numbers unchanged), so each change was checked for float-order and
RNG-stream drift before it was made.

Line counts: `MetalSim.swift` 716 → 692, `main.swift` 1014 → 1013,
`Sim.swift` 264 → 260, `LIF.metal` 162 → 163.

## What changed

**1. Stale-cache key covers every knob the weight transform reads.**
`MetalShared.knobs` was `SIMD4(weightScale, modScale, gapJunctionBoost, sensGFBoost)`
but the transform also reads `gfInputScale`, so a `MetalSim` built with a different
GF input gain silently reused the cached weights. Now `MetalShared.Knobs`
(`MetalSim.swift:157`, `Equatable`, built straight from `SimParams`) carries all five;
stored at `:155`/`:176` and compared at `:375`.

**2. One place draws the seeded per-neuron values.**
`init` and `setSeed` each had their own `draw` closure and role switch.
`applySeed(_:)` (`MetalSim.swift:462`) now writes resting drive + gait phase directly
into the GPU buffers and restarts the burst schedule; `init` allocates the two buffers
empty and calls it last (`:454`), `setSeed` is one line (`:684`). Group membership,
input routing and the group index arrays stay in `init` — they do not depend on the
seed. Bit-exactness: the draws, salts and order are unchanged. The one semantic
difference is that the fixed-baseline roles (GF, command DNs, DNp09) are now
*rewritten with the same constants* instead of being skipped, which is a no-op unless
`setBaseline` is called first and `setSeed` after — nothing does that
(`setBaseline`'s only caller is `GPUCheck.swift:497`, at construction time).

**3. Comment diet.** `SimParams` (`MetalSim.swift:17-90`) keeps ≤3 lines of "why" per
knob and the whole resting-drive landmark table (0.0354 / 0.0424 / 0.0475 / 0.0488
against `v_rest = baseline × 20.49 + 0.026`), which is load-bearing for anyone
touching baselines. The measurement narratives (the kick-0.15 GF sweep, the
noise-granularity story, the `gfInputScale` essay, the per-range rate table) are
dropped in favour of one pointer to `notes/06-tuning-2.md` in the type doc comment.
Same treatment for `SignalBuilder.make` (`main.swift:567-596`): each signal keeps a
one/two-line rule (e.g. "MDN rests at ~28 Hz network-driven (p95 40 Hz): 60 Hz is
above that resting tail and far below the ~200 Hz an MDN stimulation reaches").

**4. `floorV` is real.** It was a `let` mirror of a `-2.0f` hardcoded in the shader.
Now `SimParams.floorV` is a `var` (default −2, `MetalSim.swift:25`), `StepParams`
carries it on both sides (`MetalSim.swift:130`, `LIF.metal:43`), it is uploaded per
step (`MetalSim.swift:584`) and both clamps use it (`LIF.metal:78`, `:108`).
`StepParams` is 19 four-byte scalars = 76 B on both sides; the stride assertion is
updated (`MetalSim.swift:362`). `GPUCheck.swift`'s `RefSim` already read `p.floorV`,
so it needed no change and still matches bit-for-bit.

**5. Two-pass max, one per-edge factor.** `MetalShared.init` (`MetalSim.swift:208-253`)
had a `max(1, p.gfInputScale)` guard, a duplicated role/boost decision and a
row-max special case. Now `gfGain(i, k)` (`:227`) is the single place that decides
the GF-path multiplier; pass 1 takes `max(|w16| × g × gfGain)` per edge and pass 2
quantizes with the same factors.
- The old bound was an over-estimate (it scored GF-post edges of ordinary pre-neurons
  at ×1 instead of ×0.12). Before changing it I recomputed both bounds directly from
  `data/{neurons,synapses}.bin`: both are 7.696 (= 2405 synapses × 0.0032, a non-GF
  edge), so the fixed-point scale stays at the 2^16 floor and every quantized weight
  is unchanged. `--gpucheck` confirms: "15091983 quantized edges, 0 differ".
- Deliberately *not* folded into a single `factor()` value: the row constant
  `g = weightScale × modScale × fx` must stay hoisted so the multiplication order
  remains `(w × g) × boost`. Float multiply is not associative and
  `GPUCheck.quantizeWeights(rowFactored:)` mirrors that exact order; reassociating
  would flip `.rounded()` on edges sitting on a .5 boundary.

**6. No duplicated signal formulas.** `SignalBuilder.walkDrive/groomDrive`
(`main.swift:564-565`) are static and used by both `make` (`:583`, `:587`) and the
three `--simtest` duty-cycle probes (`:198`, `:199`, `:214`), which previously
re-typed `(rateFwd - 10) / 33` and `rateGroom / 5`. The probes now measure in CGFloat
through the clamp instead of raw Float; the printed duty cycles are unchanged
(verified below).

**7. Header/usage.** No change needed: `main.swift:11-19` lists `--snapshot`,
`--brainshot`, `--simtest`, `--behaviortest`, `--gpucheck`, `--brainstats [s]` and
`--seed N`, which is exactly the dispatch at `main.swift:988-1006`. No other file
reads `CommandLine.arguments`.

**8. Dead `Connectome` fields removed.** `roleNames`, `cellTypeNames` and `cellType`
had no reader outside the loader (both string tables were dead; `cellType` only fed
`typeName`, which stays). All three are gone from the struct and from the initializer
call (`Sim.swift:70-88`, `:249-256`); the loader still reads and validates `cellType`
locally to build `typeName`. `rootId` is kept as instructed and documented as
label/debug data (`Sim.swift:78`). The `Role` doc comment no longer points at the
deleted `Connectome.roleNames` (`Sim.swift:53`).

## Verification (M4 Pro, seed 0x5eed1f1f)

```
GPUCHECK PASS
  rng: LIF.metal pcg() transcription vs MetalSim.pcgHash -> identical
  weights: 15091983 quantized edges, 0 differ from the GPU buffer (max 0 Q18 units,
           independent factor order)
  totals: ref 179688 spikes, gpu 179688 spikes over 786 steps
  batch invariance 96 steps: 96x1 vs 6x16 -> bit-identical; 96x1 vs 50+46 -> bit-identical

PASS: GF silent at rest, fires on loom; locomotor drive fluctuates; stim works; siesta alive
ALL BEHAVIOR TESTS PASS   (17/17, two consecutive runs)
```

`--simtest` before vs after: every numeric line identical, only timing differs
(`load 35 → 52 ms`, `156 → 174 µs/step`, `bench 71 → 72 / 164 → 186 µs/step`). The
sim lines are byte-identical, including the walk/groom duty cycles that item 6
touched:

```
spontaneous 4s: pop 1.72 Hz/neuron, LC 0.0 Hz, DNa02 L/R 45.0/37.5 Hz, MDN 15.7 Hz, GF spikes: 0
abrupt loom 0.4s: LC rate 172.5 Hz, GF spikes 147, first at 3 ms
behavior 20s: walk-drive on 30%, groom-drive on 8%, DNp09 0.3-39.1 Hz, pop 1.7 Hz
siesta 15s (scale 0.84): walk-drive on 40%
```

`--brainstats 4` before vs after: the only differing lines are the two `metal-sim:
load` lines and the `µs/step` figures inside `population:`. Rates, histogram, super
classes, roles and the top-cell-type table are identical (`1.75 Hz/neuron |
244 spikes/step`, `roles: loom 0.0 | gf 0.0 | dnaL 50.4 | dnaR 48.1 | mdn 18.8 |
fwd 15.5 | groom 0.9 | escw 0.5 | ascend 1.1 | sens 0.0`).

The four before/after capture files were deleted after the diffs above were taken.

## 9. Diagnostics reads the GPU's weights instead of re-deriving them (follow-up)

`Diagnostics.swift` held the third copy of the transform (`inWeightAudit` re-derived
`weightScale × modScale × GF boost`, `hotspotProbe` re-derived `weightScale × modScale`).
`MetalSim.edgeWeightsFx` (`MetalSim.swift:327`) now exposes the sim's own quantized
edge buffer; both passes take `Double(wfx[k]) / fixedPointScale` instead
(`Diagnostics.swift:62-76`, `:102-113`), and neither takes a `SimParams` any more
(`:53`, `:92`, call sites `:215-216`). That is ~20 lines less and leaves two copies of
the rules: `MetalShared` (the source of truth) and `GPUCheck.swift`'s deliberately
independent one. Reading it off the sim, not off `Connectome.gpu.shared`, also keeps
the audit correct if it is ever called after the `weightScale = 0` run that follows it.

Dequantize route, so the numbers move by the Q16 rounding. Recomputed both ways
straight from `data/*.bin`: the largest per-neuron drift is 3.6e-4 threshold units
(gf inh; dnaL 1.4e-4, fwd 3.0e-4), all far under the table's two printed decimals, so
the printed audit is unchanged:

```
in-weight per neuron (threshold units, 1.0 = one full volley fires it):
  gf exc    +2.30  inh    -0.91  net    +1.39  [electrical LC/sens path +1.78]
  dnaL exc   +17.46  inh   -11.47  net    +5.99
  dnaR exc   +18.79  inh   -12.80  net    +5.99
  mdn exc    +4.90  inh    -3.46  net    +1.43
  fwd exc    +9.87  inh    -6.57  net    +3.30
  groom exc    +0.99  inh    -0.89  net    +0.09
  escw exc    +6.25  inh    -4.00  net    +2.25
  loom exc    +2.27  inh    -1.00  net    +1.27
```

`hotspotProbe`'s weight column is unchanged too (`+1.25 / +1.14 / +0.30 / +0.29 /
+0.04 …`, "positive in-weight 4.0 total"), and the rate half of `--brainstats 4` still
reads `population: 1.75 Hz/neuron | 244 spikes/step`, `histogram: silent 58960
(42.3%) …`. `GPUCHECK PASS` and `--simtest` PASS after the change.

## Not done, deliberately

- `factor()` was not made to return the complete per-edge multiplier (item 5) — see
  the float-order note above. `gfGain` is the single decision point the item asked
  for; only the hoisting survives.
- `MetalSim.setSeed` currently has no caller in the tree (it is a documented test
  hook next to `setBaseline`/`membrane()`/`lastStepSpikes()`). It is kept, now as a
  one-line forward to `applySeed`.
- `GPUCheck.swift` keeps its own transcription of the transform: it is the
  cross-check's independent reference and must not share code with the sim.
