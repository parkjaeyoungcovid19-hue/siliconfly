# SiliconFly: the whole-brain Metal port of DesktopFly

_Written 2026-08-19, after the port landed. Working reports with all the evidence live in `notes/` (01–09); this is the narrative._

## TL;DR

SiliconFly is a 3D fruit fly that lives on the macOS desktop, driven by a live spiking simulation of real FlyWire connectome data. It began as [DesktopFly](https://github.com/DenisSergeevitch/desktop-fly) by Denis Shiryaev, which simulated a hand-picked 668-neuron escape/steering circuit on the CPU. It now simulates the **entire FlyWire v783 brain, 139,255 neurons and 15,091,983 signed connections (54.5 M synapses), as a 1 kHz leaky-integrate-and-fire model in a Metal compute shader**, at ~75 µs per simulated millisecond (about 13× faster than real time; the app clocks it to real time), in ~250 MB of memory, with startup under 150 ms. The desktop behavior, menu bar, multi-fly support, terrain walking and procedural body are unchanged; the brain window now shows all 139 K somas with live spikes. Every legacy invariant still holds (giant fiber silent at rest, fires 3 ms after an abrupt loom, walking duty 30 %), the GPU sim is bit-exact against an independent CPU reference, and the command neurons that drive the body are now genuinely driven by the upstream brain instead of by their own noise.

## 1. State when I got it

Cloned from `DenisSergeevitch/desktop-fly` (master, 2 commits, ~2,500 lines of Swift + a 179-line Python ETL, MIT code / CC BY-NC data):

| piece | then |
|---|---|
| `Sim.swift` | CPU LIF, 668 neurons: 350 "core" neurons (LC4 104, LPLC2 210, DNp01 2, DNa01/02 2+2, DNp09 2, DNg11 6, MDN 4, DNp02/04/11 6) plus their 330 strongest partners; ~30 K edges from Codex `connections.csv` (syn ≥ 5). dt 1 ms, tau 20 ms, threshold 1, reset 0, refractory 2 ms, `weightScale` 0.0008/synapse, immediate excitation, 4 ms delayed inhibition through a 5-slot ring, per-role constant baselines + Poisson-ish noise kicks, LC→GF "gap-junction" ×6 boost |
| `etl.py` | stdlib only; downloaded 4 Codex dumps (~60 MB), filtered to the 668 circuit, wrote `data/circuit.json` + a strided 22 K-soma `brain_points.json` |
| `main.swift` | overlay scene, menu bar, `Coordinator` stepping the sim from the SceneKit render thread (`min(50, elapsed ms)` steps per frame), `SignalBuilder` (rates → `BrainSignals`), `--simtest` (circuit invariants) and `--behaviortest` (17 sim→body scenarios) |
| `FlyModel.swift` | procedural body + behavior state machine consuming `BrainSignals` |
| `BrainView.swift` | 23 K-point cloud, 668-neuron overlay, click-to-stimulate, spike flashes via `SpikeBus` |
| `CLAUDE.md` | good agent notes: threading model, neuron→behavior table, "add a population" recipe, tuning gotchas ("razor-thin operating point": rest at `baseline × 20.4` vs threshold 1) |

Known weaknesses the upstream notes admitted: DNg11 was driven by 6 synapses (noise-driven), every DN saw only its hand-picked partners, and the whole operating point depended on per-role baselines rather than network input.

The plan I was given (written by another model) asked for: full connectome via a modified ETL, a Metal compute shader replacing `Sim.swift`, the same behavior mapping, BrainView scaled up, real-time at 1 kHz, startup < 5 s, memory < 2 GB, tests updated, nothing else changed. It assumed ~50 M synapse rows and 200–400 MB of data.

## 2. How the work was run

Per the protected "Fable 5 orchestration" section in `CLAUDE.md`: Fable (this conversation) read context, wrote specs and reviewed; Opus subagents did the research, code and verification, one deliverable at a time, each booting from the previous agent's written report in `notes/`. Every report had to carry evidence (exact command output), Fable spot-checked at least one load-bearing claim per report by re-running it, every flagged risk got an explicit disposition, and fixes went back to the originating agent unless its context had bloated (then a fresh agent booted from the notes). Nothing was installed on the machine; everything stayed inside the project directory; no git state was changed.

Sequence: recon → ETL → Metal sim + integration → independent GPU-vs-CPU cross-check → tuning (round 1) → data-artifact fix + tuning (round 2) → BrainView → Fable code review → fix pass → docs. Nine reports, `notes/01-recon.md` … `notes/09-docs.md`, indexed in `notes/README.md`.

## 3. What was done, phase by phase

### 3.1 Recon (`notes/01-recon.md`)
Surveyed the two reference repos and the raw data before deciding anything.
- **webgpu-fly** (MIT) runs the full brain in WebGPU with a *gather* kernel (one thread per postsynaptic neuron over a CSR-by-post, touching all edges every step). It is memory-bandwidth-bound at 0.25 kHz on an M2 Pro, silent at rest (no noise, no delays), and uses the unthresholded FlyWire release (15.09 M edges) from an 852 MB Zenodo download.
- **eonsystemspbc/fly-brain** ships `2025_Connectivity_783.parquet` (100 MB): the same 15,091,983 aggregated (pre, post) pairs, verified **identical to Codex's `connections.csv` on every one of the 2,700,513 syn ≥ 5 pairs** (same weights). So the full graph was already on disk; the 852 MB download was unnecessary.
- Confirmed all 139,255 Codex neurons have coordinates and classification; core-type counts match upstream exactly; DNg11's in-degree goes from 6 synapses in the old subset to 3,535 in the full graph.
- Decisions taken from this: use the full parquet graph (per-pair edges, not per-synapse rows, so ~15 M edges rather than 50 M), sign edges per presynaptic neuron, keep `Sim.swift`'s noise + delayed-inhibition formulation (webgpu-fly's silent-at-rest network is wrong for a desktop pet, and the escape race depends on the delay), and use push-based scatter on the GPU so only spiking neurons' edges are touched.

### 3.2 ETL (`notes/02-etl.md`)
`etl.py` rewritten (numpy + pyarrow, 371 lines, ~4 s): all 139,255 neurons ordered by root_id; edges from the parquet as one CSR row per presynaptic neuron; per-neuron metadata (position normalized into [−10, 10], super class, side, NT class, role, cell type, root id). Output: `data/connectome.json` (self-describing manifest: array offsets/dtypes, string tables, sign policy, provenance) + `data/neurons.bin` (4.2 MB) + `data/synapses.bin` (90.6 MB: uint32 targets + int16 signed synapse counts). Roles as before (`CORE_TYPES` strict primary-type match; 24 ascending + 16 sensory "strongest partners" now chosen over the full graph). `tools/verify_data.py` re-reads the binaries independently through the manifest and asserts 67 invariants incl. spot-checks against the parquet.

Sign policy, evolved in three steps: Codex `neurons.csv` `nt_type` per presynaptic neuron (ACh/DA/SER/OCT +, GABA/Glu −; monoamines flagged modulatory and scaled ×0.5 at load) → for the 14 % of neurons with no prediction, fall back to the parquet's own Dale-law sign (raised agreement with the parquet from 95.5 % to 99.7 %) → one narrow prior: antennal-lobe local interneurons (`^(lLN|il3LN|v2LN)`) lacking a prediction are inhibitory (94 neurons; see 3.5 for why).

### 3.3 Metal sim + integration (`notes/03-metal-sim.md`)
- `Sim.swift` became the loader (`Connectome`, `loadConnectome()`: manifest-driven, memory-mapped, validates CSR structure and role counts) plus the shared `BrainSignals`/`SpikeBus`.
- `MetalSim.swift` + `LIF.metal`: two kernels per simulated millisecond. `lif_update` (one thread per neuron) applies last step's excitation, leaks/refractory, adds baseline + hash-RNG noise, external drive (loom L/R, gait rhythm into ascending neurons, air puff into sensory neurons, click stims via a CPU-owned `extInput` array), delivers the inhibition scheduled 4 ms earlier, thresholds, appends spikers to a compact list, bumps per-group counters and drops a random sample for the brain window. `lif_propagate` (one SIMD group per spiking neuron, grid-striding) scatters that neuron's edges: excitatory weights into an accumulator for the next step, inhibitory into the ring slot 4 steps ahead. All accumulation is Int32 fixed point (integer atomics: order-independent, deterministic). One command buffer per ≤ 64-step batch, sub-batched at stimulation boundaries so semantics match the CPU sim exactly; `step()` stays synchronous on the render thread (unchanged threading model). The shader is compiled at runtime from `LIF.metal` (`makeLibrary(source:)`), so `build.sh` is still a bare `swiftc` line and no Metal toolchain is needed.
- Every random stream (baselines, gait phases, noise, arousal bursts) derives from one PCG hash mirrored bit-for-bit in Swift and MSL, so a seed reproduces a run exactly. `--seed N` pins it; CLI diagnostics use a fixed default; the live app draws a fresh seed per launch.
- All callers switched (`LIFSim` → `MetalSim`), `--simtest` gained a state-consistency check and a benchmark (`PASS realtime` if 16-step batches average < 1000 µs/step). Metal API + shader validation ran clean.
- First numbers, untuned: load 38 ms + shader compile 84 ms cold (1 ms warm), 192 MB RSS, 107–114 µs/step at 1,500 spikes/step, all legacy probes passing, behaviortest 17/17.

### 3.4 Independent cross-check (`notes/04-gpucheck.md`)
A fresh agent, told to distrust the shader author's notes, wrote `GPUCheck.swift` (`--gpucheck`): a CPU `RefSim` implementing the *original* `Sim.swift` step semantics over the full connectome, driven with the same seed and quantized weights, compared after every step. Result: **bit-for-bit identical spikes, refractory state, membrane potentials, group counts and rate outputs over 13,000+ simulated ms across rest, loom + puff, mid-batch stimulation, siesta scaling, overlapping stims, gait and a full arousal burst**; batch-invariant (96×1 vs 6×16 vs 50+46 steps identical); excitatory targets move at exactly +1 ms and inhibitory at exactly +4 ms; all 15,091,983 quantized weights match a from-scratch recomputation. It also found that Metal's `mathMode = .safe` does not disable FMA contraction (a one-ulp difference flips a spike within ~100 steps in this chaotic regime), so the reference fuses the same way; comments were corrected. `--gpucheck` stays in the repo as the regression test for any shader change.

### 3.5 Tuning, and the artifact it exposed (`notes/05-tuning.md`, `notes/06-tuning-2.md`)
The port had kept the 668-circuit operating point: 35 % of all neurons were above the self-firing point, giving 10.9 Hz/neuron of pure tonic oscillation and a giant fiber that machine-gunned at 500 Hz under a held loom.

Round 1 introduced per-super-class resting-drive ranges (sensory neurons silent unless driven, optic lobe low, central brain higher), doubled `weightScale`, split the GF's electrical boosts, added `--brainstats` (per-class/per-role rates, histogram, in-weight audit, hotspot probe, and an "intrinsic vs. wired" comparison that runs the same seed with `weightScale = 0`), and moved `SignalBuilder`'s normalizers. It reached 2.54 Hz/neuron with all invariants green, but the hotspot probe showed a family of antennal-lobe local neurons pinned at the 500 Hz refractory ceiling: 29 of 30 `lLN1_bc` had no NT prediction, had been fallback-signed excitatory, and were exciting each other in a loop. The estimated impact was ≤ 0.28 Hz of the mean; the actual effect of fixing it at the data level (the ETL prior in 3.2) was a drop from 2.54 to 0.85 Hz, because that loop had been secretly driving a 2,900-neuron hot tail. With it gone the network contribution collapsed to 1.01× (rest was almost purely intrinsic noise), which defeats the purpose of the port.

Round 2 found the real lever was not `weightScale` (which hits the fixed-point overflow guard around 0.0033) but **noise granularity**: a single 0.42 kick was 42 % of threshold against ~2 % for a median neuron's entire synaptic input, so noise decided every spike. Same mean noise drive delivered as 1.7× more, 1.7× smaller kicks (`pNoise` 0.0050 × `noiseKick` 0.25), `weightScale` 0.0032, command-DN baselines below the one-kick point, a dedicated gain on the GF's chemical inputs (`gfInputScale` 0.12; the GF collects ~3,800 synapses and otherwise fires spontaneously long before the rest of the brain is network-driven), and a rebased per-class table around the new landmarks (`v_rest = baseline × 20.49 + 0.026`; one kick fires at ≥ 0.0354, still fires after the siesta at ≥ 0.0424, self-fires at ≥ 0.0475). Result: 1.75 Hz/neuron, 42 % silent, hottest cell type 61 Hz, and **all six command populations network-driven (DNa/MDN/DNg11 0.00 Hz intrinsic → 50/19/0.9 Hz wired; DNp09 0.5 → 15.5 Hz)**; the escape race improved to 3 ms; three seeds pass every invariant. `SignalBuilder` was refitted (walkDrive rectified-linear `(rate−10)/33`, MDN threshold 60 Hz, groom `/5`, arousal `/10`, nervous `/115`, all clamped).

### 3.6 Brain window (`notes/07-brainview.md`)
All 139,255 somas as one point geometry, palette dimmed and sprites shrunk instead of dropping neurons (a missing 10th super-class color was found and added), role overlay and GF highlight on top; flashes take an even slice of the spike-bus batch (6 per frame, 0.36 s fade, GF never dropped); click-to-stimulate picks a ≤ 400-neuron ball (radius 0.6) with a front-most-soma anchor and labels the dominant cell types + region, or the role if the click reaches one (GF first).

### 3.7 Review, fix pass, docs (`notes/08-fixpass.md`, `notes/09-docs.md`)
Fable read the diff as if it had written it. Fixes applied bit-exactly (all suites re-run, numeric lines identical): a stale-cache key that omitted `gfInputScale`, duplicated resting-drive generation between `init` and `setSeed`, a dead `floorV` knob (now plumbed through `StepParams`), a convoluted two-pass overflow bound, tuning-history essays trimmed out of `SimParams` (they live in the notes), duplicated `SignalBuilder` formulas in `--simtest` (now shared statics), unused `Connectome` fields, and a third copy of the weight-transform rules in `Diagnostics.swift`. README and the non-protected parts of `CLAUDE.md` were then rewritten from actual suite output.

## 4. State now

### Architecture
```
data/connectome.json + neurons.bin + synapses.bin      (etl.py, verified by tools/verify_data.py)
        │  loadConnectome()  (Sim.swift, mmap + manifest, ~40 ms)
        ▼
MetalShared   compiled LIF.metal + immutable CSR buffers (colIdx u32, weightFx i32 Q16), built once
        │
MetalSim      per-neuron state, step(ms): ≤64-step batches, 2 dispatches/step, sync on render thread
        │  group spike counts → rate EMAs; sampled spikers → SpikeBus
        ▼
SignalBuilder (main.swift)  rates → BrainSignals (escape, nervous, turnBias, walkDrive, ...)
        ▼
Fly (FlyModel.swift)        procedural body, unchanged      BrainView.swift  139k cloud + flashes
```

### Numbers (my final run, M4 Pro, macOS 26.6.1)
| | |
|---|---|
| neurons / edges / synapses | 139,255 / 15,091,983 / 54,492,922 |
| shipped data | 95 MB (`synapses.bin` 90.6 MB, under GitHub's 100 MB hard limit) |
| startup | ~40 ms load + ~85 ms shader compile cold (≈1 ms warm) |
| memory | ~200–250 MB RSS |
| speed | 75 µs per 1 ms step in 16-step batches (≈13× real time), ~190 µs in 1-step batches; the app clocks it 1:1 to wall time |
| rest regime | 1.75 Hz/neuron, 42 % silent, ~245 spikes/ms; central 3.8 Hz, optic 0.8, sensory 0 |
| network contribution | population 1.31× intrinsic; all six command-DN populations ≈0 Hz intrinsic → tens of Hz wired |
| escape | GF silent over 4 s of rest; first spike 3 ms after an abrupt loom; air puff → ≤ 1 GF spike/s |
| body drives | walk duty 30 % (siesta 40 %), groom duty 8 %, MDN bursts rare at rest |
| tests | `--simtest` PASS, `--behaviortest` 17/17, `--gpucheck` bit-exact PASS, `verify_data.py` 67/67 |

### Files
`main.swift` (overlay, menu, Coordinator, SignalBuilder, simtest/behaviortest, seeds), `FlyModel.swift` (untouched), `Sim.swift` (loader + shared types), `MetalSim.swift` (SimParams, MetalShared, MetalSim), `LIF.metal`, `BrainView.swift`, `Environment.swift` (untouched), `Diagnostics.swift` (`--brainstats`), `GPUCheck.swift` (`--gpucheck`), `etl.py`, `tools/verify_data.py`, `build.sh`, `data/`, `README.md`, `CLAUDE.md`, `notes/` (working reports), plus local-only `reference/` (webgpu-fly, sparse fly-brain) and `cache/` (Codex dumps), both excluded via `.git/info/exclude`. Everything is uncommitted; `git status` shows the full change set. Nothing was installed on the machine.

### Honest limitations
- It is a LIF with invented physiology: constant baselines, hash noise, one 4 ms delay for all inhibition, no adaptation, no gap junctions beyond the two GF boosts, monoamines as weak fast excitation. The connectome supplies wiring, not dynamics.
- Under a *sustained* artificial max loom the GF keeps firing (~150 spikes/400 ms); onset latency and sustained saturation cannot both be fixed in a non-adapting LIF. The body only uses the first spike, and real looms are transient.
- DNg11 (grooming) is structurally weakly wired (net in-weight +0.09) and stays noise-driven.
- Female brain (FAFB): no male-specific P1 circuitry.
- The live render loop cannot be observed from a non-interactive shell (SceneKit never fires the delegate; the pre-port binary behaves the same), so the moving fly and live brain window were verified only through the headless modes and offscreen renders; a human launch is the remaining check.
- Requirement moved to macOS 15+ (`MTLCompileOptions.mathMode`), Apple Silicon.

## 5. How to run and verify
```sh
./build.sh
./SiliconFly                       # menu-bar 🪰, brain window, fresh seed each launch
./SiliconFly --simtest             # invariants + GPU benchmark
./SiliconFly --behaviortest        # 17 sim → body scenarios
./SiliconFly --gpucheck            # GPU vs independent CPU reference (bit-exact)
./SiliconFly --brainstats 4        # resting regime, per-class rates, intrinsic vs wired
./SiliconFly --seed 12345 --simtest
/opt/anaconda3/bin/python3 etl.py cache/flywire783 && /opt/anaconda3/bin/python3 tools/verify_data.py data
```

## 6. Future directions

### 6.1 Directly stimulating the fly's "pleasure" neurons
The fly brain has no pleasure center in the mammalian sense, but it has a well-mapped **reward system**, and it is all in the shipped connectome (counts from `data/connectome.json`):
- **PAM dopaminergic neurons**: 15 types, 307 neurons (261 predicted DA). These are the reward-signaling DANs of the mushroom body; sugar reward, water reward and courtship-related reward are carried by specific PAM types (hemibrain naming: PAM01 γ5, PAM02 β′2a, PAM04 β2, PAM08 γ4, PAM11 α1 …). Optogenetically activating them makes a fly *prefer* whatever it experiences at the time. This is the closest thing to "pleasure neurons" a fly has.
- **PPL1 dopaminergic neurons**: 8 types, 16 neurons — the punishment counterpart. Useful as the negative pole (or to deliberately avoid).
- **MBONs**: 35 types, 96 neurons — the mushroom-body output neurons whose balance encodes valence (approach vs. avoid). Their rates are the natural *readout* of the reward state.
- **Octopaminergic neurons** (OA-VPM3/4, OA-VUMa1/2, OA-ASM…, 31 neurons predicted OCT): sugar-reward relay and general arousal/"reward expectation".
- **NPF** (NPFL1-l, 2 neurons) and other peptidergic modulators (DSK, SIFa) for satiety/craving-style state, if desired.

How to do it with the current code (this is exactly the `CLAUDE.md` "add a population" recipe):
1. `etl.py`: add `"PAM01" … "PAM15": "reward"` (and optionally `"PPL1*": "punish"`, `"MBON*": "mbon"`) to `CORE_TYPES`/`ROLES`; regenerate; `verify_data.py` checks the counts.
2. `Sim.swift` `Role` enum + `MetalSim.init`: give the new roles a group id (for rate readout) and, for the MBONs, a `groupOf` so `--brainstats`/`SignalBuilder` can read a **valence signal** = (approach-MBON rate − avoid-MBON rate), slow-adapted like `turnBias`.
3. Stimulation entry points already exist: `MetalSim.stimulate(indices, strength, durationMs)` is thread-safe; wire it to a menu item ("Reward the fly"), a keyboard shortcut, or automatic pairing with an event (e.g. the cursor resting near the fly for a few seconds, or a click on the fly). Strength/duration like the existing click stims (0.25 for 400 ms) is a sane start; PAM neurons are DA-signed so their downstream fast effect is `modScale`-scaled — you may want a dedicated `rewardScale` on their outgoing edges, because dopamine's real effect on KC→MBON synapses is modulatory, not a fast current.
4. Behavior mapping in `FlyModel`: what does a "pleased" fly do? Candidates that fit the procedural body: slower, calmer walking (lower `walkDrive`, higher `groomDrive` — flies groom when content), a wing-flick or a brief "wiggle", staying near the cursor instead of fleeing (raise the loom threshold via `sensoryGate` while the valence signal is positive), or a proboscis-extension pose (would need a new animation). Conversely PPL1 → nervous darting/escape bias.
5. The truly interesting version is **learning**: implement dopamine-gated plasticity on Kenyon-cell → MBON synapses (the actual mechanism of fly reward learning; ~2,000 KCs and 96 MBONs are in the data). Rule: when a KC is active and a PAM neuron innervating that MB compartment fires within a short window, depress the KC→"avoid" MBON weight in that compartment (the canonical fly rule). Then pairing PAM stimulation with a sensory pattern (e.g. a stylised "odor" injected into a stable subset of projection neurons whenever the cursor approaches from the left) would make the fly *learn* to approach the cursor. That needs a small extension of the shader (a plasticity kernel touching only KC→MBON edges, a few hundred thousand of the 15 M) and a persistence format for the learned weights, but the connectome, the readouts and the stimulation API are already there. It would also give the "pleasure" a memory, which is what makes it feel real.
Caveats worth stating up front: it is a female brain (FAFB), so male courtship reward circuitry (P1) is absent; PAM subtypes carry *different* rewards (sugar vs. water vs. others), so stimulating all 307 at once is a blunt instrument — start with the sugar-reward types (γ5/β′2a/α1) and read the MBONs to see what moved; DA sign/strength in the model is a modeling choice, not a measurement.

### 6.2 Other directions, roughly in order of payoff/effort
- **Spike-frequency adaptation** (per-neuron adaptation current in `lif_update`): fixes GF saturation under sustained loom, tames remaining hot cell types, and is biologically the missing ingredient; requires mirroring in `GPUCheck.swift`.
- **Real visual input**: the optic lobe (78 K neurons, 56 % of the brain) currently gets no drive except the LC4/LPLC2 loom injection. Feeding a coarse rendition of what is under the fly (screen content, cursor motion) into the lamina/medulla inputs would let the actual visual pathways compute looming and motion instead of us injecting it.
- **VNC / body from the connectome** (as webgpu-fly does with MANC + flybody): descending neurons → nerve cord → motor neurons; the DNs are already the interface. Big project.
- **Circadian and sleep from clock neurons** (LNv/DN1 exist in the data) instead of `Environment.swift`'s curve.
- **Learning beyond reward**: homeostatic plasticity to keep the operating point stable across seeds; the seed-dependence of some resting asymmetries suggests it.
- **Engineering**: background sim thread with double-buffered outputs (frees the render thread entirely; not needed at 75 µs/step but cleaner), 30 Hz full spike-vector readback for the brain window (today it samples 12/ms), save/restore of brain state, `--min-syn` experiments (2 → 7.6 M edges) to test how much the weak edges matter, per-neuron delays.
- **Data**: an ETL option to take the parquet's Dale sign everywhere (to A/B against Codex), and shipping the `class` column (gustatory/olfactory/mechanosensory) so sensory sub-populations can be targeted by name.
