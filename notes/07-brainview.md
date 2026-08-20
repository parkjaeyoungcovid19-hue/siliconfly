# 07 — Brain window at full scale

`BrainView.swift` was still the window the 668-neuron circuit was designed for:
the background cloud strided down to ~23k somas, a flash pool sized for a
handful of spikes per frame, and a click radius of 2.2 world units picked when
only 668 neurons existed. The sim underneath is now the whole FlyWire v783 brain
(139,255 neurons at 1 kHz on the GPU), so this pass scales the window to it.

**Result:** all 139,255 somas render as one point geometry, the 378-neuron
circuit overlay and the two giant-fiber markers sit on top unchanged, spikes
twinkle out of the same `SpikeBus`, and a click stimulates a bounded local
cluster (≤ 400 neurons) whose label names the role population it reached.
`--simtest` PASS, `--behaviortest` 17/17 on 6 of 8 runs (the other two hit the
documented `ledge attach` flake, §7.5), `notes/brainshot-before.png` →
`notes/brainshot-after.png`.

Only `BrainView.swift` changed. `main.swift`, `MetalSim.swift` and the data are
untouched — the window already received the `Connectome` and the `MetalSim`.

## 7.1 The cloud: 139,255 points, not 23,000

The strided loop is gone; `connectome.positions` is handed to the geometry
whole, so there is exactly one vertex buffer (139,255 × position + colour,
~4.5 MB) and no per-neuron nodes. Colours are still `CLASS_COLORS[superClass]`.

Six times the sprites in the same 340×280 panel with additive blending means six
times the accumulated brightness, so the requirement to keep the look was met by
shrinking and dimming, never by dropping neurons:

| knob | before | after | why |
|---|---|---|---|
| points | 23,000 (stride 6) | 139,255 (all) | the deliverable |
| `minimum/maximumPointScreenSpaceRadius` | 0.7 / 1.6 | 0.5 / 1.1 | ~0.5× the sprite area; 0.5 px is the floor where the rasteriser still shrinks the footprint instead of clamping to one pixel |
| `CLOUD_DIM` | — | 0.25 | palette multiplier; 6.05 × 0.51 × 0.25 ≈ 0.77 of the old brightness per screen area |

`CLOUD_DIM` was rendered at 0.35 first (≈ 1.1× the old brightness): correct
overall, but the central brain stacked into a solid amber mass with white
clipping near the top. At 0.25 the individual somas are separable again, which
is the point of a point cloud — and the extra 116k neurons buy real anatomy that
the strided cloud could not show: the medulla/lobula/lobula-plate strata read as
distinct arcs, the lamina is a separate teal shell, and the central brain is a
speckled amber body rather than a scatter.

The palette also gained a 10th entry. `stringTables.superClasses` has ten
classes and `CLASS_COLORS` had nine, so the 612 `sensory_ascending` neurons were
falling through to the grey fallback; they are now teal-green, between the
`sensory` teal and the `ascending` green they sit between anatomically.

Unchanged: circuit overlay (378 role neurons, `rMin/rMax` 1.6/2.6, same role
colours), the two GF spheres, the background colour, camera, and the 6 s
rotation. With the cloud dimmer, both read *more* clearly than before.

## 7.2 Flashes: sample the bus, don't drain it

The GPU sampler keeps up to 32 spikers per simulated ms and `MetalSim` pushes up
to 12 of them; the bus itself keeps the last 256 events. The fly's render loop
steps 8–16 sim ms per frame, so a brain frame drains 100–256 events into a
48-node pool — the pool was being overwritten ~5× per frame, every node lit at
full opacity every frame. That is 48 bright dots jumping to new positions 30
times a second, not a spike raster.

Now the drain lights a fixed, evenly spread slice:

| knob | value | why |
|---|---|---|
| `FLASHES_PER_FRAME` | 6 | 6 × 30 fps ≈ 180 halos/s; with a 0.36 s fade ~65 are alive at once, dense enough to look busy at 340×280 and sparse enough to see individual events |
| `FLASH_FADE` | 0.36 s | ~11 frames of fade, so a halo is legible as one event; the old 0.28 s never mattered because nodes were recycled long before it elapsed |
| `FLASH_FADE_GF` | 0.7 s | was 0.6 s; the GF is the money shot and it keeps the 3.2× scale |
| `FLASH_POOL` | 96 | 96 / 6 = 16 frames = 0.53 s before a node comes round again > 0.36 s fade, so nothing is ever stolen mid-fade, with headroom for GF flashes and the 24-halo click burst |

The slice is taken with `k % step == 0` across the whole batch rather than the
first N, so the halos are spread over the whole drained window (and therefore
over the whole brain) instead of all landing inside the last simulated
millisecond. Giant-fiber events bypass the slice entirely — only ~5% of GF
spikes survive the sampler (each spiker writes into one of 32 slots, ~245
spikers per ms overwrite each other, then Swift takes 12 of the 32), so during
an escape ~7 of the 147 GF spikes reach the window and every one of them must be
drawn.

## 7.3 Click: bounded cluster, role-aware label

The neighbourhood radius was the one number that had to move. Measured over 25
random anchors on the real positions (brain spans x ±10, y ±4.8, z ±3.4):

| radius | median somas | p10 | p90 | max |
|---|---|---|---|---|
| 0.6 | 368 | 214 | 1,199 | 2,499 |
| 1.0 | 2,077 | 601 | 2,825 | 2,973 |
| 2.2 (old) | 10,317 | 3,509 | 20,362 | 26,028 |

So `PICK_RADIUS = 0.6` (typical click ≈ 370 neurons) with `PICK_MAX = 400` for
the tighter spots. Strength and duration are untouched — `0.25` for `400 ms`,
the same numbers `--simtest` phase 6 probes. 400 neurons is 0.3% of the network
(the old cap of 60 was 9% of the 668-neuron circuit), so a click is a local poke
now, not a network-wide event. The stim ring shrank 2.2 → 0.9 to match, and the
click burst lights 24 halos *strided across* the cluster rather than its 16
nearest members, so the ball is visible rather than one blob at its core.

The anchor scan gained a depth tie-break: a ray through a 139k-soma slab grazes
hundreds of somas at essentially zero perpendicular distance, and the winner
among them was arbitrary in depth. `score = perp² + 0.002 × t` costs one
multiply and makes the front-most soma within ~0.2 units of the ray win, i.e.
the one under the cursor.

**The label.** A role population is 2–210 neurons out of 139,255, so it can
never win a plain majority of a 370-neuron cluster: the old `max` over all roles
would have said "other" for every click. `regionName` now counts only
role-tagged members and names the role if the click reached one at all, giant
fiber first. Verified statically against the real positions (anchor = the first
soma of each population, `R = 0.6`, cap 400):

```
role lc4    ball= 528 picked=400 roles={lc4:41}                  -> Looming detectors (LC4/LPLC2)
role lplc2  ball= 453 picked=400 roles={lplc2:36, lc4:1}         -> Looming detectors (LC4/LPLC2)
role gf     ball= 201 picked=201 roles={gf:1, escw:2, dnp09:1}   -> Giant Fiber (DNp01) — escape!
role dna01  ball= 182 picked=182 roles={dna01:1, dna02:1}        -> Steering neurons (DNa01/02)
role dna02  ball= 177 picked=177 roles={dna02:1, dna01:1}        -> Steering neurons (DNa01/02)
role dnp09  ball= 286 picked=286 roles={dnp09:1, escw:2, gf:1}   -> Giant Fiber (DNp01) — escape!
role dng11  ball= 181 picked=181 roles={dng11:3}                 -> Grooming command (DNg11)
role mdn    ball= 240 picked=240 roles={mdn:3}                   -> Moonwalker neurons (MDN)
role escw   ball= 341 picked=341 roles={escw:2, dnp09:1, gf:1}   -> Giant Fiber (DNp01) — escape!
role ascend ball=   3 picked=  3 roles={ascend:1}                -> Ascending neurons (leg feedback)
role sens   ball= 244 picked=244 roles={sens:10}                 -> Sensory afferents (wind/tap)
```

Every population is reachable, and clicking the GF marker does put a GF in the
stimulated set, which at 0.25 for 400 ms (≈ 5× threshold) fires it → takeoff.

Two consequences worth stating. First, `gf`/`dnp09`/`escw` somata are 0.16–0.56
units apart in the GNG — no radius that stimulates a useful cluster can separate
them, so a click anywhere in the descending cluster also stimulates the GF and
the fly takes off. Labelling that "Giant Fiber — escape!" is the honest
description of what the user is about to see; a "Walking command" label there
would be a lie. Second, `ascend` and `sens` finally have their own labels
instead of falling through to a cell-type string.

When no role is in range the label reports the cluster itself, from the
`Connectome` string tables (`typeName`, i.e. cell type falling back to super
class, plus the dominant `superClass`): `⚡ Mi1 + Tm3 · optic (400)`, or
`⚡ 286 central neurons` when the dominant type *is* the super class name. The
controller now holds the `Connectome` for this — `sim.roles`/`sim.types` are the
same arrays, but super class and `Role` ids only exist on the connectome.

## 7.4 Cost

Per frame the driver touches only the drained batch (≤ 256 events, 6 of them
turned into node updates) — no O(N) CPU work, and the 139k points are one draw
call the M4 does not notice. `preferredFramesPerSecond` stays at 30: the scene
rotates 0.35 rad per 6 s and the flash budget is derived from 30 fps, so 60
would only double GPU cost for a panel that shows no motion faster than a fade.
Scene build cost is one 139k-element `map` plus the geometry upload, once.

Click cost is two linear scans over 139,255 positions plus a sort of ≤ 2,499
pairs — a few ms, on a mouse-down, off the render loop's critical path.

## 7.5 Verification

```
$ ./build.sh
main.swift:500:13: warning: variable 'calm' was never mutated; ...   (pre-existing)
Built ./DesktopFly

$ ./DesktopFly --simtest | tail -3
click probes: GF cluster -> spike yes, DNg11 cluster -> groom rate 196 Hz
PASS realtime: 16-step batches 71 µs/step (budget 1000)
PASS: GF silent at rest, fires on loom; locomotor drive fluctuates; stim works; siesta alive

$ ./DesktopFly --behaviortest | tail -1
ALL BEHAVIOR TESTS PASS          (6 of 8 runs; 2 hit the known ledge flake)
```

The two failures are both `FAIL  ledge attach + follow window edge`, the
pre-existing flake `notes/03-metal-sim.md` records against the pre-port binary.
It is a `bodyCheck` — hand-built `BrainSignals`, a `Fly` and a `Ledge`, no sim
and no `BrainView` symbol anywhere in `runBehaviorTest` — so this pass cannot
have caused it. 2-in-8 here vs the ~1-in-8 recorded there is 8 samples of a
coin, not a trend.

Every `--simtest` line is identical to `notes/06-tuning-2.md` §6.3 — this pass
does not touch the sim.

- `notes/brainshot-before.png` — the strided cloud: two smooth blue-grey optic
  blobs, an amber speckle for the central brain, 40 white halos.
- `notes/brainshot-after.png` — the full brain: layered optic lobes (medulla /
  lobula / lobula plate visible as separate arcs), teal lamina shell, a dense
  amber central body with individual somas still resolvable, the cyan LC4/LPLC2
  overlay and the yellow GF glow reading more clearly than before against the
  dimmer background, same 40 halos.

## 7.6 Not verified

- **The live window was not observed rendering.** `perl -e 'alarm 15; exec
  "./DesktopFly"'` starts the app, loads the connectome and the Metal sim
  (`metal-sim: Apple M4 Pro N=139255 E=15091983 load 64 ms compile 1 ms`) and
  runs 15 s with no crash or exception, and `pgrep -fl DesktopFly` is empty
  afterwards. But as `notes/03-metal-sim.md` records, SceneKit never delivers
  `renderer(_:updateAtTime:)` to an app launched from a non-interactive shell,
  so the flash path, the hover pause and the click path could not be exercised
  live. `--brainshot` covers scene construction and `BrainRenderDriver.flash`;
  the drain arithmetic and the pick geometry are covered statically above.
- **Steady-state flash density (~65 live halos) is a calculation**, not an
  observation: `--brainshot` freezes exactly 40 flashes by design.
- **Non-Retina displays** put the same 139,255 sprites into a quarter of the
  pixels, so the cloud will read brighter there; the screen-space radius floor
  (1 px) cannot compensate. Untested — no such display available.
