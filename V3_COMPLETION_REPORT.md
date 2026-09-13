# Virtual Fly Lab V3 — Completion Report

Date: **2026-09-13**
Implementation status: **COMPLETE**
External/manual user validation: **PENDING BY USER**
Baseline Git commit: `447f7e234f91ec44da4e2e68ada50a00859f4375`

## Scope completed

V3 followed `VIRTUAL_FLY_LAB_V3_PLAN.md` and intentionally stayed inside the stabilization/minimal-boundary scope. It did not add humidity, taste, checkpointing, package import, a new neuron inspector, lockstep sessions, or other V4+ work.

### A — independent GPU reference

- `GPUCheck.swift` now independently reconstructs the V2 receptor histogram groups for ORN food left/right, warm/cool TRN and JO-C/E wind cells.
- Group mismatch diagnostics cover the compared histogram slots instead of hiding receptor groups behind the legacy 1–8 printout.
- A corrupted receptor-group negative control proves the oracle detects a wrong assignment.
- `--gpucheck` passes scenarios A–H, including the formerly failing C/H cases, with zero quantized-weight mismatches.
- `LIF.metal`, connectome binaries, Role IDs, network gains and shader semantics were not changed.

### B — simulation-time lab stimulus expiry

- `runLabLoopTest()` no longer assumes that wall-clock sleep equals MuJoCo simulation progress.
- Wind/touch expiry is observed using fresh body packet simulation timestamps and source state.
- Diagnostics include packet generation, receive age, simulation time/dt and active source strengths.
- The test cleans up only the object it created instead of resetting a pre-existing user's world/body.
- Mock and real FlyGym-headless TCP loops both pass.
- Python `test_lab.py` contains a negative control proving wall-clock delay alone does not advance the simulation-time wind timer.

### C — recorder completion and application termination

- `ExperimentRecorder` has serialized `recording → stopping → saved/failed` lifecycle semantics.
- Stop completion is delivered only after queued telemetry/events and final event writes finish and file handles close.
- Write failures are propagated as failed outcomes instead of reporting a false saved state.
- Rapid stop→start cannot overlap recorder sessions.
- `LabWindow` displays stopping and updates to saved/failed only from the completion result.
- AppKit termination uses `applicationShouldTerminate` / `.terminateLater` so an active recording drains before termination is approved.
- Regression tests cover queued tail preservation, stop/start ordering, injected write failure and the quit-drain path.

The recorder metadata format string remains V2-compatible intentionally because V3 did not redefine the telemetry CSV schema.

### D — launch/deployment path

- `Makefile` now builds/runs `ThongpariFlyNeuronSim`; it no longer launches the inherited `SiliconFly` binary.
- `LAUNCHERS.md` and README launch instructions match the current executable.
- A separate clean source copy with old binaries removed builds successfully and `make -n run` resolves to `./build.sh` then `./ThongpariFlyNeuronSim`.
- A fresh Python 3.12 virtual environment successfully installed `flygym_bridge/requirements.txt` during V3 validation.
- Observed dependency set for that fresh validation: Python 3.12.14, FlyGym 2.1.0, MuJoCo 3.9.0, NumPy 2.5.3, SciPy 1.18.1.
- A new real viewer + GUI process connected successfully on the development machine and sustained roughly 39–41 body packets/s, ~60 brain packets/s, and ~0.79–0.81 simulation/wall ratio during the smoke run.

### E — minimal sensory/motor boundaries

- New `SensoryModel.swift` owns the existing V2 source→drive transforms for backend wind/touch source state, food odor current, warm/cool thermal drive, JO-C/E wind drive, generic touch gating and modeled-physiology temperature tempo.
- New `MotorReadout.swift` owns `SignalBuilder` and the existing neural population rate→`BrainSignals` equations/state.
- `main.swift` remains the coordinator but no longer owns those formulas.
- `build.sh` explicitly includes both new files.
- `--labtest` contains frozen pre-extraction V2 formula oracles and verifies exact parity across representative ranges.
- A same-seed dual-`MetalSim` regression applies extracted-model drives versus frozen V2 equations and requires identical membrane, refractory state, group histogram and sorted spike set downstream.
- GPU spike-list append order is intentionally ignored because Metal atomic append ordering is not deterministic; spike membership/state remains identical.

## Final validation matrix

All commands below returned exit code **0** in the final V3 working tree unless noted otherwise.

```text
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
./ThongpariFlyNeuronSim --labloop   # with bridge.py --mock
./ThongpariFlyNeuronSim --labloop   # with bridge.py --flygym-headless
git diff --check
```

Additional clean-tree build validation:

```text
copy tracked + unignored working-tree sources to a new /tmp directory
remove SiliconFly and ThongpariFlyNeuronSim if present
./build.sh
make -n run
assert ./ThongpariFlyNeuronSim is executable
```

Result: `V3_FINAL_CLEAN_BUILD_OK`.

## Validation machine

```text
macOS 26.6.2 (25G83)
arm64
Apple M2
```

The measured throughput figures above are observations from this machine, not portable performance guarantees.

## Known limitation / user validation handoff

The real viewer + Lab GUI was launched as a fresh process and bridge connectivity/performance was observed. The assistant-side smoke was stopped from the validation terminal rather than by physically clicking the GUI's normal Quit menu while a recording was active. The underlying termination/recorder path is covered by automated regression, but **the user explicitly chose to perform final GUI validation separately**. This report therefore does not claim that manual menu interaction was exercised by the assistant.

Recommended manual validation focus:

1. Launch `Thongpari Fly Neuron Sim 실험실.command` with the real viewer.
2. Start recording, produce a few stimuli/markers, then use the normal app Quit command while recording is active.
3. Confirm the process exits normally and the experiment directory contains the final telemetry tail plus `recording_stopped` event.
4. Re-launch once to confirm the bridge port and recorder are not left in a stale state.

## Files changed for V3 implementation

Core implementation/tests include:

- `GPUCheck.swift`
- `FlyGymBridge.swift`
- `ExperimentRecorder.swift`
- `LabWindow.swift`
- `main.swift`
- `LabProtocol.swift`
- `flygym_bridge/test_lab.py`
- `Makefile`
- `build.sh`
- `SensoryModel.swift` (new)
- `MotorReadout.swift` (new)
- `README.md`
- `LAUNCHERS.md`
- `VIRTUAL_FLY_LAB_V3_PLAN.md`
- `VIRTUAL_FLY_LAB_ROADMAP.md`
- `V3_COMPLETION_REPORT.md` (new)

Pre-existing/uncommitted audit and validation files in the working tree were preserved rather than deleted or rewritten as part of V3 unless explicitly listed above.

## Rollback

No V3 commit was created automatically. Because the working tree already contained user/pre-existing changes before V3 work began, **do not use a blanket `git reset --hard` or broad `git restore .` as a rollback method**. The safest rollback after review is to commit the V3 change as one isolated commit and later use `git revert <that-commit>` if necessary. Before any rollback, preserve the existing uncommitted audit/roadmap/validation files.

## Next version boundary

V3 stops here. Per `VIRTUAL_FLY_LAB_ROADMAP.md`, V4 is the time/session-lifecycle release: fixed simulation tick/lockstep experiment mode, pause barrier, session epoch and applied-command timing. V4 should not silently absorb V5 checkpointing or later package/import work.
