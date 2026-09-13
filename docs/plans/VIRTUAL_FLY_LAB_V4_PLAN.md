# Virtual Fly Lab V4 — deterministic time and session lifecycle

Status: **COMPLETE — 2026-09-13**
Prepared: **2026-09-13**
Baseline: `af8c0ba` (`Update README for V3 verification fixes`)
Previous release: V3 implementation `31bd106` + verification remediation `4995162`

## 0. 2026-09-13 completion status

Final acceptance was performed on inspected HEAD `3ad60db` plus the preserved dirty V4 working tree. V4 is complete in that local working tree; no V4 Git commit was created by the acceptance pass. Preserve the existing dirty/untracked work rather than resetting it.

The complete final Swift/Python suite, mock and real-headless TCP lockstep, real MuJoCo/vision tests, and a fresh real Viewer + GUI pause/resume/applied-tick smoke all pass. The GUI acceptance exposed and fixed one lifecycle bug: a persistent successful `session_state` snapshot could be consumed repeatedly after the local tick advanced. `LabSession` now consumes lifecycle confirmations monotonically by control sequence and `--v4test` covers that regression.

Required order remains [V4 → V5 → … → V14](VIRTUAL_FLY_LAB_ROADMAP.md). V4 is now complete, so V5 is the next permitted implementation version. V5 is the participant Viewer, not the old checkpoint milestone. Full evidence is in [V4_COMPLETION_REPORT.md](../reports/V4_COMPLETION_REPORT.md).

Completed finish checklist:

1. [x] Inventory existing dirty V4 implementation against sections 3–10 and preserve unrelated work.
2. [x] Build and run `--v4test`, `--v4timingtest` and Python `test_v4.py` with fresh exit-0 logs.
3. [x] Run mock and real-headless `--v4loop` against managed test backends.
4. [x] Execute pause/old epoch/duplicate/stall faults and the legacy regression suite sequentially.
5. [x] Perform a fresh real Viewer smoke, including real deterministic start, >1 s pause freeze, paused command, Resume and applied tick.
6. [x] Write `docs/reports/V4_COMPLETION_REPORT.md`; V5 may now begin.

## 1. V4 scope

V4 has one job: make experiment time and session transitions explicit enough that **render FPS and wall-clock stalls do not change the simulated experiment**.

The release contains only:

1. a fixed-tick deterministic experiment mode alongside the existing interactive mode;
2. an actual brain/body pause barrier rather than a display-only pause;
3. `session_id` + `epoch` + monotonic sequence/tick metadata on the V4 protocol path;
4. exact recording of the simulation tick at which a lab command was applied;
5. stale/old-epoch and duplicate-command rejection needed to make those guarantees real.

V4 explicitly does **not** implement the participant Viewer (V5), basic editor (V6), exact neuron inspector (V7), external I/O host (V8), checkpoint/individual/replay (V9), advanced environment/humidity/taste (V10), state interpretation (V11), or any gain/connectome/shader retuning. See the revised V4–V14 roadmap for the mandatory sequence.

## 2. Current V3 timing facts that V4 must replace or preserve

The implementation was inspected at baseline `af8c0ba` before writing this plan.

### 2.1 Neural time is currently render-driven

`Coordinator.renderer(_:updateAtTime:)` derives `dt` from SceneKit frame timestamps, accumulates `dt * 1000`, caps one frame to at most 50 neural steps, calls `MetalSim.step(steps)`, and passes the same variable render `dt` into `SignalBuilder.make`.

Consequences:

- changing render FPS changes batching and command-observation boundaries;
- a long render stall is truncated by the 50 ms cap;
- DNa adaptation in `MotorReadout` advances by render `dt`, not an explicit experiment tick schedule.

The Metal backend itself already has the right primitive: `MetalSim` advances in exact 1 ms integer `simMs` ticks. V4 should drive that primitive from a session clock rather than rewriting the neural model.

### 2.2 FlyGym time is currently wall-driven in interactive mode

`flygym_bridge/bridge.py` runs an autonomous approximately 60 Hz loop. Each iteration derives a clamped `dt` from `time.monotonic()` and passes it to `body.step`.

`RealFlyBody.step` then converts that requested duration into a variable count of native MuJoCo substeps, capped to a 20 ms simulation chunk. Timed wind/touch/flash already expire using MuJoCo simulation time, which V4 must preserve.

### 2.3 Current Pause is not a simulation pause

The status-menu Pause currently changes only `scnView.isPlaying` and clears `Coordinator.lastTime`. The Python bridge remains autonomous, so MuJoCo, LabWorld timers and body state continue to advance while the UI appears paused.

V4 Pause is complete only when both owners have reached an agreed simulation boundary and neither neural nor body simulation advances until Resume.

### 2.4 Reconnect generation is not a session epoch

`FlyGymBridge.connectionGeneration` correctly protects Swift from old packets belonging to a prior TCP connection. It does not identify a reset/restarted experiment inside one connection, and it is local receive metadata rather than an end-to-end protocol field.

V4 keeps connection generation for transport freshness and adds an independent simulation `epoch` carried on the wire.

### 2.5 Command ACK means accepted/applied, but not when

Lab commands already have monotonic IDs and Python applies them on the simulation-owner thread before the next body step. ACK/state packets identify the command but do not carry the exact simulation tick at which it took effect. The recorder currently records the UI/wall event, not authoritative backend application time.

## 3. Time model

V4 exposes two session modes. The model equations remain identical; only scheduling changes.

### Interactive mode

- Preserve the V3 real-time user experience and current bounded/latest-wins bridge behavior.
- Wall time may determine how quickly simulation progresses.
- Continue to report packet age, body Hz and simulation/wall ratio.
- The new Pause control must still stop **both** neural and body advancement.
- Interactive mode is not advertised as deterministic replay.

### Deterministic experiment mode

- Neural tick is fixed at **1 ms**, using existing `MetalSim.simMs` / `step(_:)` semantics.
- The Python backend declares its native physics timestep during V4 capability negotiation. For the current real backend this is the actual `self.sim.timestep`; it must not be guessed in Swift.
- V4 uses a fixed **experiment quantum of 20 neural ticks (20 ms)** initially. This matches the existing real-body maximum simulation chunk and keeps cross-process traffic practical while the neural backend still executes every 1 ms tick internally.
- A 20 ms quantum is valid only when it is an integer number of backend physics substeps. Otherwise deterministic mode fails closed with a clear capability error rather than rounding to a different duration.
- Sensory/body feedback is sampled at the quantum boundary. The sample schedule is therefore explicit: one body observation per 20 ms experiment quantum, while the existing real-eye renderer remains a separately declared lower-rate sensor (currently approximately 5 Hz in simulation time).
- Neural output is held for one body quantum, matching the existing low-rate brain/body boundary rather than pretending there is a 1 kHz MuJoCo control exchange.
- The next quantum does not begin until the body result for the previous quantum has been accepted for the current session/epoch. If the backend is slow, **simulation time slows down; ticks are never skipped to catch up with wall time**.

The 20 ms quantum is a V4 scheduling constant, not a biological claim. It should be named/configured centrally and recorded in metadata so later versions can benchmark another quantum without changing the meaning silently.

## 4. Session identity and wire envelope

Add a small V4 envelope rather than a generic plugin framework:

- `protocol_version` — V4 path starts at an explicit integer version;
- `session_id` — UUID string created for one app experiment session;
- `epoch` — unsigned monotonic counter within the session;
- `seq` — monotonic message/command sequence where ordering matters;
- `sim_tick` — integer neural tick in milliseconds;
- existing payload fields remain as payload data and V3-compatible interactive parsing remains available where safe.

### Capability handshake

On connection, exchange a minimal hello/capability packet containing at least:

- protocol version;
- support for `deterministic_experiment`, `pause_barrier`, `epoch`, and `applied_tick`;
- native body physics timestep;
- supported experiment quantum or enough information to validate it.

If the peer lacks V4 capabilities, the app may continue in V3-compatible **interactive** mode, but deterministic experiment mode and V4 guarantees stay disabled with the reason visible. Do not silently claim lockstep over a legacy peer.

## 5. Deterministic lockstep protocol

Use an explicit experiment-step request/result on the V4 path rather than depending on autonomous 60 Hz stepping.

### Swift -> Python step request

The request contains current `session_id`, `epoch`, `seq`, start `sim_tick`, fixed quantum length, and the current decoded `BrainSignals`/tempo needed by the body controller.

### Python step execution

For one request the simulation-owner thread must:

1. reject wrong-session/wrong-epoch/duplicate or out-of-order step requests;
2. apply commands scheduled for that boundary in deterministic sequence order;
3. record each command's authoritative `applied_tick` before stepping;
4. advance exactly the required number of native physics substeps;
5. advance LabWorld timers/forces only through those same physics substeps;
6. sample body/sensory state at the declared boundary;
7. return one step result tagged with the same session, epoch and request sequence plus the ending `sim_tick`.

Swift accepts a result only if it matches the outstanding step request and current epoch. It then applies that sensory snapshot to the next neural quantum. Old results are discarded, not blended with current state.

## 6. Pause barrier

Pause is a session lifecycle transition with three visible states: `running -> pausing -> paused`.

### Deterministic mode

1. Stop issuing a new experiment quantum after the currently outstanding step completes.
2. Send/confirm the backend pause state at that exact boundary.
3. Mark `paused` only after Swift and Python report the same epoch/tick boundary.
4. While paused, render/UI refresh may continue, but `MetalSim.simMs`, MuJoCo time, LabWorld timers, approach motion, vision sampling timers and controller integration must not advance.
5. Resume changes `paused -> running` without injecting a wall-time catch-up interval.

### Interactive mode

Python must gain a control path that is processed even while body stepping is paused. A pause request stops the autonomous body loop at a step boundary; Resume is still accepted without requiring physics to advance first. Swift likewise stops neural stepping rather than merely stopping SceneKit playback.

Commands submitted while paused go to a bounded queue. They do not mutate simulation state until Resume (unless the command is itself a permitted session-control command). Their eventual `applied_tick` must show that fact.

## 7. Epoch and reset rules

Epoch represents a discontinuity in experiment state, not a TCP reconnect.

- Create the session with epoch `1`.
- Increment epoch whenever a reset invalidates the previous simulation timeline. V4 covers existing brain/body/world reset operations; later world swap/restore rules belong to the V6/V9/V10 contracts.
- Clear/retag pending experiment-step state and stale natural sensory state at the boundary.
- A packet, command, ACK or result from an older epoch is rejected and must not alter the new epoch.
- `connectionGeneration` remains in Swift solely as a transport/reconnect freshness guard.
- Presets that logically perform one reset sequence should use one coordinator reset transaction so they do not create accidental multiple epochs from `brain + world + body` implementation details.

V4 does not serialize the epoch state to disk for continuation. That is V9 checkpoint work.

## 8. Command scheduling and idempotency

Extend lab commands with V4 metadata:

- `session_id`, `epoch`, `seq`;
- `requested_tick` or an equivalent next-boundary schedule;
- authoritative ACK fields `applied_tick`, `applied_epoch`, and result status.

Rules:

- UI commands received between deterministic boundaries are scheduled for the next valid boundary unless an explicit future tick API is later added.
- The backend applies commands in deterministic sequence order at that boundary.
- Repeating the same `(session_id, epoch, seq)` is idempotent: do not apply the physical/sensory mutation twice. Return the prior result/ACK from a bounded recent-command cache.
- A command from an old epoch fails explicitly.
- Queue overflow remains fail-closed and visible; do not drop a discrete experiment mutation and later report it as applied.
- Continuous latest-wins controls may retain coalescing only when the recorded final command sequence and applied tick make the replacement visible.

## 9. Recorder and telemetry changes

This is still the existing CSV/events recorder, **not** the V9 portable experiment package.

Add enough fields to audit V4 timing:

- metadata: session mode, protocol version, `session_id`, initial epoch, neural tick size, experiment quantum, backend physics timestep/capabilities;
- telemetry: `session_id`, `epoch`, `sim_tick`, session mode/paused state, body result tick where applicable;
- command event: command sequence, requested tick, `applied_tick`, applied epoch, success/failure;
- pause/resume/reset event: old/new state, epoch and agreed barrier tick.

Keep wall timestamps for human correlation, but never use them as the authoritative experiment application time.

## 10. Implementation boundaries and target files

### New Swift file

`LabSession.swift` — narrowly owns V4 session mode/state, `session_id`, epoch, fixed tick/quantum scheduling, pause state machine, outstanding deterministic step and command application metadata. It is not a checkpoint/package/plugin framework.

### Existing Swift files

- `main.swift` — remove experiment-time ownership from SceneKit `dt`; renderer becomes presentation/input collection while `LabSession` owns deterministic stepping. Preserve interactive presentation behavior.
- `FlyGymBridge.swift` — V4 handshake/envelope, deterministic step request/result, pause/session control, epoch filtering and applied-command metadata. Keep socket work off AppKit/render threads.
- `LabProtocol.swift` — V4 packet/session types plus telemetry columns/tests.
- `ExperimentRecorder.swift` — session/tick metadata and authoritative command-applied events; preserve the V3 drain/close lifecycle.
- `LabWindow.swift` — compact mode/pause/session diagnostics and command requested-vs-applied status. Do not redesign the whole UI in V4.
- `MotorReadout.swift` — adaptation must receive fixed simulation duration in deterministic mode; do not change equations or gains.
- `build.sh` — include `LabSession.swift`.

`MetalSim.swift`, `SensoryModel.swift`, `LIF.metal`, connectome binaries and model gains should remain unchanged unless a concrete V4 timing defect cannot be fixed at the session boundary. Any such exception needs its own parity test.

### Python files

- `flygym_bridge/protocol.py` — V4 envelope/hello/step/control/result structures with tolerant legacy parsing.
- `flygym_bridge/bridge.py` — mode-specific scheduler: existing autonomous interactive loop plus request-driven deterministic stepping and pause control.
- `flygym_bridge/fly_body.py` — add an exact-substep deterministic stepping entry point that reuses the same controller/LabWorld/observe path without wall-derived `dt` or rounding ambiguity.
- `flygym_bridge/test_bridge.py`, `test_lab.py` and focused new V4 tests as needed.

`lab_world.py`, `vision_decoder.py` and `neural_decoder.py` should not need model-semantic changes; they are exercised through the new clock.

## 11. Implementation sequence

### A. Freeze V3 baseline and add protocol tests

1. Keep current V3 model outputs as parity fixtures where practical.
2. Add encode/decode tests for hello/session/epoch/tick/applied-tick fields before runtime changes.
3. Add negative tests for wrong epoch, duplicate command and unsupported deterministic capability.

### B. Exact Python stepping primitive

1. Refactor body stepping so existing interactive `step(cmd, dt, tempo)` and new deterministic exact-substep stepping share the same controller, LabWorld, MuJoCo and observation code.
2. Exact mode accepts an integer substep count, never derives it from wall elapsed time.
3. Prove a requested 20 ms quantum advances exactly the expected MuJoCo time and timed sources by the same amount.

### C. V4 handshake and session envelope

1. Negotiate protocol/capabilities and native physics timestep.
2. Create `session_id`, epoch and sequence ownership in `LabSession`.
3. Keep legacy peers interactive-only.

### D. Deterministic step request/result

1. Add one-outstanding-step lockstep to avoid hidden queues of simulated future time.
2. Move deterministic neural/body advancement off render FPS.
3. Feed fixed 20 ms to `SignalBuilder` adaptation per quantum while Metal runs its exact 20 one-ms ticks.
4. Reject old/wrong/mismatched results.

### E. Pause barrier and reset epoch

1. Implement `running/pausing/paused` state and backend pause control.
2. Verify timers and both simulations freeze across arbitrary wall sleeps.
3. Centralize reset transactions enough to increment one epoch per logical reset and clear old in-flight work.

### F. Applied-command recording

1. Schedule deterministic commands at boundaries.
2. ACK with authoritative applied tick and idempotent duplicate handling.
3. Record request/applied timing and epoch in events/telemetry.

### G. UI/status and complete regression

Expose only the information needed to understand mode, tick, epoch, pause transition and command application. Then run the complete V3 suite plus V4-specific timing/fault tests.

## 12. V4 acceptance tests

V4 is not complete until all of the following are reproducible.

### Deterministic timing

- Same seed + same initial state + same tick-scheduled command sequence produces the same Swift neural state/spike membership and the same mock-body state when the driver is subjected to radically different wall sleeps/render callback schedules.
- At minimum test synthetic 30/60/120 FPS presentation schedules plus injected long UI stalls; experiment tick sequence and final simulation state must be identical.
- No catch-up tick is skipped because wall time ran late.
- `SignalBuilder` adaptation is identical for the same simulation ticks regardless of wall timing.

### Real FlyGym lockstep

- Real headless backend declares its actual physics timestep.
- Every 20 ms deterministic quantum advances an exact integer number of native MuJoCo substeps and reports the expected end tick/time.
- A short same-machine repeated real-headless deterministic trial with fixed seed/commands matches the predefined exact fields where deterministic and otherwise stays within explicitly documented numeric tolerance; do not claim cross-hardware bit identity.

### Pause barrier

- Pause reaches an agreed epoch/tick.
- Sleep for at least one wall second while paused: neural `simMs`, body simulation time, wind/touch/flash remaining duration, approach position and deterministic command application count do not change.
- Resume advances exactly the next quantum with no wall-time catch-up.
- Interactive mode also stops body physics instead of only hiding SceneKit updates.

### Epoch safety

- Reset increments epoch exactly once per logical reset transaction.
- Delayed old-epoch body result, lab ACK and command are all rejected.
- A reconnect changes transport generation but does not by itself masquerade as a new simulation epoch.

### Command timing/idempotency

- Command sent between deterministic boundaries applies on the documented next boundary and ACK/event carries that exact tick.
- Duplicate `(session_id, epoch, seq)` does not apply touch/wind/spawn/delete twice.
- Queue overflow and wrong-epoch command produce explicit failure and no mutation.
- Commands queued during pause remain bounded and apply only after Resume at a recorded tick.

### Regression/parity

Run sequentially from the repository root:

```sh
./build.sh
./ThongpariFlyNeuronSim --bridgetest
./ThongpariFlyNeuronSim --labtest
./ThongpariFlyNeuronSim --simtest
./ThongpariFlyNeuronSim --behaviortest
./ThongpariFlyNeuronSim --gpucheck
./flygym-venv/bin/python tools/verify_data.py --no-parquet
./flygym-venv/bin/python flygym_bridge/test_bridge.py
./flygym-venv/bin/python flygym_bridge/test_lab.py
./flygym-venv/bin/python flygym_bridge/validate_experiment_presets.py
./flygym-venv/bin/python flygym_bridge/test_lab_real.py
./flygym-venv/bin/python flygym_bridge/test_vision_real.py
```

Add focused V4 Swift/Python tests for deterministic scheduling, pause, epoch and applied ticks rather than hiding them inside one GUI smoke.

### User-visible smoke

Run a fresh real viewer + Lab GUI process and verify:

1. interactive mode still behaves as V3;
2. deterministic mode exposes fixed tick/epoch and continues even when rendering is visually slowed;
3. Pause visibly reaches `paused` and the real body stops advancing;
4. a stimulus issued around Pause/Resume shows the authoritative applied tick;
5. switching/starting a deterministic experiment does not silently enable V9 checkpoint semantics.

The user's previously reserved manual V3 recording-menu-Quit check remains a separate user-side smoke and is not redefined as a V4 implementation blocker.

## 13. Completion report and rollback

When implementation is complete, create `docs/reports/V4_COMPLETION_REPORT.md` with:

- baseline and implementation commit IDs;
- exact files changed;
- protocol/capability version;
- test commands and exit codes;
- mock and real-headless deterministic evidence;
- pause/old-epoch/duplicate-command fault-injection evidence;
- GUI smoke result and machine/runtime versions;
- known limitations and rollback instructions.

Do not mark V4 complete while any timing test still depends on render FPS or while Pause allows either backend to continue advancing. Do not start V5 participant Viewer work until those gates are green. Checkpoint work belongs to V9.
