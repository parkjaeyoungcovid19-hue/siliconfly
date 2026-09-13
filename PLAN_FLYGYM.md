# PLAN_FLYGYM — SiliconFly closed-loop with FlyGym 2.x

## 0. Existing architecture (audited)

- `Sim.swift`: `BrainSignals` (escape, nervous, turnBias, backward, walkDrive, groomDrive, wingDrive, arousal, tempo, sleep), `Connectome` CSR loader, `Role` table (lc4/lplc2/gf/dna01/dna02/dnp09/dng11/mdn/escw/ascend/sens).
- `MetalSim.swift`: 1 kHz Metal LIF, `loomL/loomR/gaitDrive/gaitPhase/airPuff/activityScale/sensoryGate` inputs, EMA rates (`rateLoom/rateDNaL/rateDNaR/rateMDN/rateFwd/rateGroom/rateEscW/ratePop`), `stimulate()` thread-safe, `consumeGF()` escape latch.
- `main.swift` `SignalBuilder.make()`: rate->BrainSignals mapping (walkDrive=(rateFwd-10)/33, groomDrive=rateGroom/5, turnBias=(DNaL-DNaR-baseline)*0.04, backward=rateMDN>60, escape=GF latch, nervous=rateLoom/115, arousal=ratePop/10). `Coordinator.renderer()` steps sim in <=50ms batches, sets `gaitDrive` from procedural `walkingIntensity`, `gaitPhase` from procedural gait.
- `FlyModel.swift`: procedural body consumes BrainSignals; `walkingIntensity`/`gaitPhasePublic` are the current proprioception source.
- Diagnostics: `--simtest`, `--behaviortest` (17 checks, ALL PASS on M2 2026-09-12), `--gpucheck`, `--brainstats`. `build.sh` bare swiftc, no Xcode project.

## 1. Strategy

- Keep Metal brain authoritative at 1 kHz. Never duplicate connectome in Python. Never send 139k states.
- New runtime mode `./SiliconFly --flygym`. Normal `./SiliconFly` unchanged. Existing diagnostics must keep passing.
- Bridge: localhost TCP 127.0.0.1:17841, newline-delimited compact JSON, Swift = client, Python = server. Brain->body at ~50-100 Hz from render loop via background queue; body->brain compact feedback parsed on background thread, applied centrally. Bounded queues, never block Metal/render.
- V1 control: DN-derived high-level drives -> existing FlyGym locomotion controller/CPG (NOT direct 42-joint control). Mappings that are engineering approximations live in ONE Python module (`flygym_bridge/neural_decoder.py`) and ONE Swift mapping (`FlyGymBridge.swift` `FlyGymSensoryMap`), clearly commented.
- Feedback V1: vx, yaw_rate, 6 leg contacts, left/right aggregate -> existing `gaitDrive/gaitPhase/airPuff` + `stimulate(ascend/sens)` paths. No new fake populations.
- Vision is milestone 2: FlyGym's real left/right eye-camera frames -> compact looming/brightness/bearing features; only left/right looming enters LC4/LPLC2 via existing `loomL/loomR`. Python must never set escape directly.

## 2. Protocol (v1)

Brain->body `{type:brain,t,walk,turn,escape,backward,groom,wing,arousal,tempo,sleep,nervous}`. Body->brain `{type:body,t,vx,yaw_rate,contacts[6],left_contact,right_contact,gait_phase,loom_left,loom_right,brightness,bearing}`. Unknown fields ignored, malformed lines skipped, clamping on parse. Exact Codable structs in `FlyGymBridge.swift`, mirror in `flygym_bridge/protocol.py`.

## 3. Files

- `FlyGymBridge.swift` (new): packets, TCP client, reconnect, bounded queues, stats, `FlyGymSensoryMap` (MODELING ASSUMPTION).
- `main.swift` (edit): `--flygym` flag, `--bridgetest` flag, Coordinator sends/receives, menu status item.
- `build.sh` (edit): add FlyGymBridge.swift.
- `flygym_bridge/` (new): `protocol.py`, `neural_decoder.py`, `vision_decoder.py`, `fly_body.py` (mock + real), `environment.py` (`ArenaConfig`), `bridge.py` (`--mock`, `--flygym` real), `requirements.txt`, `README.md`, `test_bridge.py`.
- `run_flygym.sh` (new): venv + bridge + Swift app, cleanup on exit.
- `PERFORMANCE_FLYGYM.md`: measured only, never fabricated.

## 4. Phases

A: audit+plan+baseline (this file; behaviortest PASS recorded). B: Swift bridge + mock + tests. C: venv FlyGym 2.x, inspect installed signatures first, real body + CPG/turning. D: proprio/contact feedback closed loop. E: obstacles + looming via visual pathway.

## 5. Constraints

M2 Air 8GB: no Torch/TF/RL/Docker/CUDA/Warp. MuJoCo CPU, modest rendering. No dense matrices, no per-spike traffic, no unbounded buffers. LIF dynamics untouched; adapt body decoder only.

## 6. Implementation status (2026-09-12)

- A complete: plan plus preserved baseline diagnostics.
- B complete: Swift client, Python mock, NDJSON protocol, protected escape pulse,
  bounded latest-state queues, reconnect behavior, and protocol/loop tests.
- C complete for the first milestone: local Python 3.12 venv, inspected FlyGym
  2.1.0 API, actual NeuroMechFly, HybridTurningController, flat floor, fixed box,
  and interactive free-camera viewer.
- D complete for compact feedback: forward velocity, yaw rate, six contacts,
  left/right aggregates, and CPG phase return to the existing ascending gait
  pathway. Transform remains explicitly labeled as a modeling assumption.
- E complete: the real FlyGym left/right eye cameras render the 3D world at a
  reduced 96x84 resolution at 5 Hz; `vision_decoder.py` measures expansion of the
  deliberately colored box stimulus from pixels only (never obstacle coordinates),
  sends left/right looming plus brightness/bearing, and Swift injects only the
  looming pair into the existing LC4/LPLC2 `loomL/loomR` pathway. GF/escape is
  still decided entirely by the Metal connectome.
