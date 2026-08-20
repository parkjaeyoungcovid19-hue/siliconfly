# 09 — docs pass

`README.md` and the non-protected sections of `CLAUDE.md` brought up to the
whole-brain port. Every numeric claim in both files traces to
`data/connectome.json`, to `notes/docs-runs.txt` (a capture made for this pass on
this machine), or to an earlier note; the table in §3 lists them one by one.

**Machine for every run below:** Apple M4 Pro, macOS 26.6.1, Swift 6.2.1, built
with `./build.sh` (bare `swiftc`), shipped seed `0x5EED1F1F`.

---

## 1. What changed

### `README.md`

Rewritten end to end except "Regenerating the data", which the ETL phase had
already updated and which was only re-verified here (its `etl.py` /
`tools/verify_data.py` command lines still match both scripts' usage strings, and
`verify_data.py data --no-parquet` passes — see §4).

- **Intro / "What's real"** — 668-neuron circuit → whole connectome: 139,255
  neurons, 15,091,983 signed edges, 54,492,922 synapses, ~95 MB shipped, 1 kHz
  LIF in a Metal compute shader. Named populations kept, with the two input
  populations (24 ascending, 16 sensory) named as such. Added the claim the
  `weightScale = 0` control run supports: the command DNs are intrinsically
  silent, so every spike they emit is the connectome's. GF loom latency 4 ms →
  **3 ms**; "~1,200 synapses of inhibition" → the GF pair's real **9,474**
  synapses of mixed input.
- **New "How it works" section** — the data → `MetalSim` → two kernels per
  simulated ms → rates → `SignalBuilder` → body pipeline, with the push-based
  scatter (only spiking neurons' CSR rows), Int32 fixed-point atomics, 4 ms
  delayed inhibition, PCG noise, per-super-class resting drive, and the measured
  throughput / startup / RSS block.
- **Installation** — was "macOS 13+, Swift 5.9+". Now Apple Silicon + **macOS
  15+** (`MTLCompileOptions.mathMode`), built and tested on macOS 26.6.1 / M4 Pro
  / Swift 6.2.1, bare `swiftc`, no Metal toolchain (runtime shader compile),
  Python only for regenerating data.
- **Controls** — brain-window click is now "up to 400 somas within 0.6 world
  units" (was "~60 nearest circuit neurons"), matching `PICK_RADIUS` / `PICK_MAX`.
- **"How real neurons drive the body"** — same roles, plus population sizes and
  each population's real in-degree, and the DNg11 6 → 3,535 synapse contrast that
  is the point of the port. MDN's threshold stated (60 Hz).
- **Diagnostics** — all seven modes (`--simtest`, `--behaviortest`, `--gpucheck`,
  `--brainstats [s]`, `--snapshot`, `--brainshot`, `--seed N`), the invariants
  `runSimtest` actually asserts, and the two numbers it prints but does not
  assert (loom latency, walk duty).
- **"What's modeled vs. measured"** — expanded from one paragraph to the full
  honesty list: LIF constants, NT signs + parquet fallback + the AL prior,
  modulatory ×0.5, the GF's three input gains and why the third exists, invented
  resting drive/noise, single 4 ms inhibitory delay, no VNC / no body physics, no
  adaptation or plasticity or gap junctions beyond the GF boosts, and the escape
  race caveat (147 GF spikes under a sustained artificial loom; the body uses the
  first).
- **License & citation** — added the eonsystemspbc/fly-brain parquet provenance
  (Zenodo 10676866) and webgpu-fly (MIT) as the design reference.

### `CLAUDE.md`

The `## Fable 5 orchestration` section is **untouched** (see §5). Everything else
rewritten:

- **Intro** — 668-neuron CPU circuit → whole connectome in a Metal shader.
- **Files** — added `MetalSim.swift`, `LIF.metal`, `Diagnostics.swift`,
  `GPUCheck.swift`, `tools/verify_data.py`, `notes/`, and `reference/` + `cache/`
  (local-only, git-excluded via `.git/info/exclude`); `Sim.swift` and `etl.py`
  re-described.
- **Build, run, verify** — all modes including `--brainstats` and `--seed`;
  "always run `--simtest`, `--behaviortest` **and** `--gpucheck`"; the invariant
  list updated (GF silent 4 s, GF ≤ 10 ms after an abrupt loom, walk duty
  20–50 %, siesta > 3 %, air-puff GF ≤ 2, realtime, `--gpucheck` bit-exact); the
  `ledge attach` flake recorded so it is not re-investigated. SourceKit note kept
  (still true — single-module `swiftc` build), "five" → "eight" .swift files.
- **Threading model** — model unchanged, plus: `step()` is synchronous on the
  render thread, one command buffer per ≤64-step batch sub-batched at stim
  expiries, `MetalShared` shared/immutable, `stimulate()` the only cross-thread
  method.
- **Neuron → behavior mapping** — role table with the real counts, plus the full
  `SignalBuilder` table (walkDrive rectified-linear `(rate − 10)/33`, MDN > 60 Hz,
  arousal `ratePop/10`) and why walkDrive is not a divisor.
- **Adding a new neuron population** — rewritten for the current pipeline:
  `etl.py` `CORE_TYPES`/`ROLES`/`COMMAND_ROLES` → `Role` in `Sim.swift` →
  `MetalSim` (group, `Group` id, `inputKind`, `applySeed` baseline, rate EMA) →
  `SignalBuilder` → `FlyModel` → `BrainView` `regionName` → tests, including
  `tools/verify_data.py` role counts and re-running `--gpucheck` when the weight
  transform or step semantics change.
- **Tuning gotchas** — rewritten from `notes/05` + `notes/06`: the
  `v_rest = baseline × 20.49 + 0.026` landmark table (0.0354 / 0.0424 / 0.0475 /
  0.0488), "noise granularity decides whether the wiring matters", `weightScale`
  ~4 % below the fixed-point overflow (with the exact error text), the GF's three
  gains, abrupt-step escape testing, don't scale baselines linearly, the AL sign
  prior in one bullet, `--brainstats` as the instrument, seeds and their margins.
- **Repo conventions** — `data/` file sizes, manifest-first rule, README claims
  must match `connectome.json` + suite output, `notes/` described as the port's
  working reports, `reference/`/`cache/` exclusion.

---

## 2. Runs made for this pass

Captured in `notes/docs-runs.txt` (kept):

| run | result |
|---|---|
| `./DesktopFly --simtest` | PASS (realtime 69 µs/step, 16-step batches), peak RSS sampled alongside |
| `./DesktopFly --brainstats 4` | full rest-regime report, exit 0, 2 s |
| `./DesktopFly --gpucheck` | `GPUCHECK PASS`, 11 s (`gpucheck ran in 12.3 s` internally) |
| `./DesktopFly --behaviortest` ×4 | 3 × `ALL BEHAVIOR TESTS PASS`; 1 run hit the pre-existing `ledge attach + follow window edge` flake (a `bodyCheck`, no sim involved) |
| `/opt/anaconda3/bin/python3 tools/verify_data.py data --no-parquet` | `ALL CHECKS PASSED`, exit 0, 64 PASS lines |

---

## 3. Where every number came from

`M` = `data/connectome.json`, `R` = `notes/docs-runs.txt`, `Nxx` = `notes/xx-*.md`,
`C` = source code.

| claim | value | source |
|---|---|---|
| neurons / edges / synapses | 139,255 / 15,091,983 / 54,492,922 | M (`neuronCount`, `edgeCount`, `synapseTotal`); R (`--simtest`, `verify_data`) |
| shipped data size | 122 kB + 4.2 MB + 90.6 MB ≈ 95 MB | M `files.*.bytes`; `ls -l data/` |
| role counts (104/210/2/2/2/2/6/4/6/24/16, other 138,877) | — | M `roleCounts`; R (`--simtest` groups line, `verify_data` roles line) |
| loom L/R split 162/152 | — | R `--simtest` groups line (side-based, not type-based) |
| role-tagged neurons in the overlay | 378 | 139,255 − 138,877 (M `roleCounts`) |
| sign fallback: 18,314 neurons, 5,700 inhibitory, 94 AL interneurons | — | M `signFallback`; R (`verify_data` PASS lines re-derive all four) |
| in-degree onto gf/dnp09/dna01/dna02/dng11/mdn/escw | 9,474 / 10,287 / 12,495 / 25,427 / 3,535 / 10,519 / 19,253 syn | N02 §"Run" (etl.py's own report) |
| loom→GF | 293 edges / 1,885 syn | N02 §"Run" |
| GF ordinary chemical synapses | ~3,800 per cell | N06 §4 |
| in-weight audit (gf +2.30/−0.91, electrical +1.78; dnaL +17.46/−11.47; fwd +9.87/−6.57) | threshold units | R `--brainstats` in-weight audit |
| population rate at rest | 1.75 Hz/neuron, 244 spikes/step | R `--brainstats` |
| intrinsic (weightScale 0) rates: DNa/MDN/DNg11 0.00 Hz, escW 0.04 Hz, pop 1.34 → 1.75 (1.31×) | — | R `--brainstats` network-contribution block |
| wired command-DN range 0.5–50 Hz | escw 0.5 … dnaL 50.4 | R `--brainstats` roles line |
| throughput 69 µs/step (16-step), 192 µs/step (1-step), 78 µs/step in brainstats | — | R `--simtest` bench + `--brainstats` |
| real-time margin ~13–14× | 1,000 µs budget ÷ 69–78 µs | R (budget printed by `--simtest`) |
| spikes/step 229 (rest average) / 249 (bench) | — | R `--simtest` |
| startup: load 40–52 ms, compile 1 ms | — | R `metal-sim:` lines across the four runs |
| cold shader-cache compile ~84 ms | — | N03 §7 (could not be reproduced here — cache was warm) |
| peak RSS ~240 MB | 247,216 KB | R (`ps -o rss=` sampled during `--simtest`) |
| GF silent over 4 s of rest; 147 GF spikes / first at 3 ms under a 400 ms abrupt loom; air-puff GF 1 | — | R `--simtest` |
| walk duty 30 %, groom duty 8 %, siesta duty 40 % | — | R `--simtest` |
| `--gpucheck`: 15,091,983 weights, 0 differ; ref 179,688 = gpu 179,688 spikes over 786 steps | — | R `--gpucheck` |
| 17 behavior checks | — | R (17 `PASS`/`FAIL` lines in `--behaviortest`) |
| SimParams values (decay 0.9512, weightScale 0.0032, kick 0.25, pNoise 0.005, gains 0.5/1.5/0.12, loomGain 0.32, inhDelay 4 ms, refractory 2 ms) | — | C `MetalSim.swift`; R `--brainstats` params line echoes six of them |
| resting landmarks 0.0354 / 0.0424 / 0.0475 / 0.0488 and `v_rest = baseline × 20.49 + 0.026` | — | C `SimParams` doc comment; N06 §2.1 |
| overflow error text (`max|w| 11.5440 x scale 65536 x 4096`) | — | N06 §2 (measured at `weightScale` 0.0048) |
| noise-granularity contrast 1.01× (kick 0.42) → 1.31× (kick 0.25); siesta survival `(kick − 0.144)/kick` | — | N06 §3, §9.2 |
| network contribution restricted to classes with an input source (central 1.98→3.76, descending 1.16→7.14, motor 1.30→6.98) | — | R `--brainstats` |
| `weightScale` ~4 % headroom | 0.0032 vs ~0.0033 cap | N06 §2, §9.6 |
| click cluster: ≤400 somas within 0.6 world units, 400 ms, strength 0.25 | — | C `BrainView.swift` (`PICK_RADIUS`, `PICK_MAX`, `stimulate` call) |
| SignalBuilder rest values (walkDrive 0.12, arousal 0.175, groomDrive 0.09–0.43, MDN p95 31 Hz) | — | N06 §7 |
| seed margins (walk duty 40 % vs 50 %, groom duty 8–41 %, puff GF 1 vs ≤2) | — | N06 §6.5, §9 |
| macOS 15+ requirement | `MTLCompileOptions.mathMode` | C `MetalSim.swift`; Apple's API availability |
| webgpu-fly MIT | — | `reference/webgpu-fly/LICENSE`, `package.json` |
| parquet provenance / Zenodo 10676866 | — | M `sources`; `data/DATA_LICENSE.md` |

---

## 4. Verified while writing

- `README.md`'s "Regenerating the data" command lines match `etl.py`'s docstring
  and `argparse` block (`raw_dir`, `--out`, `--min-syn`, `--parquet`) and
  `tools/verify_data.py`'s usage (`data_dir`, `--parquet`, `--no-parquet`).
- `tools/verify_data.py data --no-parquet` re-derives the counts, role counts and
  all four `signFallback` fields straight from the binaries: `ALL CHECKS PASSED`.
- Menu-item titles, the `Pause`/`Resume` toggle, "only fly #1 carries the brain"
  (`signals: i == 0 ? signals : nil`), and the seven CLI modes were checked
  against `main.swift` rather than carried over from the old README.
- `--simtest`'s asserted invariants were read off the `pass` expression
  (`gfSpont == 0 && gfLoom > 0 && walkOn > 0 && gfStim && siestaPct > 3 &&
  consistent && realtime`), so the README does not claim it asserts latency or
  duty bounds — it prints them.

## 5. Protected section

`CLAUDE.md`'s `## Fable 5 orchestration` section was extracted verbatim before
editing (`sed -n '8,30p'`, 23 lines / 4,661 bytes, sha256
`809121b05ad373abd43ff1c5c5969e1ec73556341e1868d0e36d47d06918e041`) and the new
file was assembled as `new head + that exact block + new tail`. After the write,
`cmp` of the extracted block against the same range of the new file exits 0, the
sha256 is unchanged, and every one of its lines appears verbatim among the added
lines of `git diff HEAD -- CLAUDE.md` (the section is part of the uncommitted WIP,
so it does not exist in `HEAD`).

## 6. Could not verify / left alone

- **`assets/brain.png` is stale.** It is the pre-port screenshot (23k strided
  points, committed with the original repo). Regenerating it was out of scope for
  this pass (`assets/` is not mine to modify), so the caption now says so
  explicitly and the body text states the window draws all 139,255 somas.
  `notes/brainshot-after.png` is what the current window looks like.
- **Cold shader-compile time (~84 ms)** is quoted from `notes/03-metal-sim.md`;
  every run in this session had a warm cache (1 ms, occasionally 0 ms).
- **RSS is from `--simtest`, not the GUI app** (247,216 KB peak). The port
  measured 192 MB for the full app; the README quotes the number this pass
  actually measured and calls it peak resident memory. The GUI app was not run
  deliberately — see §7.
- **`--behaviortest`'s flake rate** was sampled four times here (1 failure), which
  is consistent with the ~1-in-8 recorded in `notes/03`/`notes/07` but does not
  refine it.
- **The live app was not exercised** (no GUI session in this environment; SceneKit
  does not deliver `renderer(_:updateAtTime:)` from a non-interactive shell, as
  `notes/03` and `notes/07` both record). All README claims about the running app
  come from the CLI modes, the code, or earlier notes.

## 7. Failure recorded

The first capture attempt ran the four modes from a zsh `for` loop as
`./DesktopFly $m` with `m="--brainstats 4"`. **zsh does not word-split unquoted
parameter expansions**, so the binary received one argument, `"--brainstats 4"`,
matched no CLI mode, fell through to `NSApplication.run` and started the GUI app,
which then sat in the menu bar for ~5 minutes looking like a slow `--brainstats`.
Diagnosed with `sample <pid>` (main thread parked in `-[NSApplication run]`),
killed, and the capture was regenerated with the arguments passed correctly. No
output from that attempt was used; `notes/docs-runs.txt` is entirely from the
corrected runs. `pgrep -fl DesktopFly` is clean.
