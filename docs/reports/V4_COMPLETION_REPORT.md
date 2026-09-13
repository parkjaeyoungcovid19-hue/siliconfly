# Virtual Fly Lab V4 — Completion Report

Date: **2026-09-13**
Implementation status: **COMPLETE**
Git HEAD inspected at acceptance start: `3ad60dbd1951a7c062d841beef17c87ad8c793ae` (`Prepare Virtual Fly Lab V4 implementation`)
V3 baseline used by the V4 plan: `af8c0ba` (`Update README for V3 verification fixes`)

The repository already contained substantial uncommitted V4 implementation and planning work when final acceptance began. That work was preserved rather than reset, cleaned, or broadly restored. This report and the accepted V4 tree are committed together in the V4 completion commit.

## User-visible result

V4 makes experiment time and lifecycle explicit instead of allowing render FPS or wall-clock stalls to define the experiment:

- deterministic mode advances the Metal brain in exact **1 ms** neural ticks and the brain/body boundary in exact **20 ms** quanta;
- the real FlyGym backend advertises and uses its actual **0.1 ms** MuJoCo timestep, so one 20 ms quantum is exactly **200 native physics substeps**;
- one deterministic body quantum is outstanding at a time, with no skipped catch-up ticks when wall time is slow;
- Pause is a real brain/body barrier, not a display-only pause;
- V4 packets carry protocol/session/epoch/sequence/tick identity, and old-epoch or duplicate work cannot mutate the current timeline;
- lab commands record the authoritative backend `applied_tick` / `applied_epoch`;
- interactive mode remains available and also uses the real backend pause barrier when V4 capability is negotiated.

V4 intentionally does **not** implement the V5 participant Viewer, V6 environment editor, V7 neuron inspector, V8 external-I/O host, V9 checkpoint/replay, or later roadmap work.

## Final acceptance defect found and fixed

The first fresh real Viewer + GUI smoke found a defect that the CLI tests had not exposed. `FlyGymBridge.latestSessionState()` intentionally returns the latest lifecycle state as a persistent snapshot. The 1 ms deterministic driver therefore saw the same successful `begin` confirmation more than once. After the local session had already advanced beyond tick 0, `LabSession` revalidated that old tick-0 confirmation against the newer local tick and incorrectly moved the GUI session to `failed`.

Evidence of the failure is preserved in:

- `notes/validation/v4-final-2026-09-13/gui_smoke_deterministic.png`
- `notes/validation/v4-final-2026-09-13/gui_smoke_runtime.txt`

The fix is in `LabSession.swift`: lifecycle confirmations are now consumed monotonically by their V4 control `seq`, so an already-consumed or older `session_state` snapshot is an idempotent no-op. `--v4test` now contains a regression asserting that a stale successful begin confirmation cannot fail a session after its tick advances.

## Protocol and state ownership

V4 protocol version: **4**.

Required negotiated capabilities:

- `deterministic_experiment`
- `pause_barrier`
- `epoch`
- `applied_tick`

Current deterministic timing contract:

- neural tick: **1 ms**;
- experiment quantum: **20 ticks / 20 ms**;
- installed real backend physics timestep observed in final validation: **0.0001 s / 0.1 ms**;
- exact native substeps per real quantum: **200**.

`LabSession` owns session mode, lifecycle phase, session ID, epoch, deterministic tick ordering and the one-outstanding-step rule. The Python simulation-owner thread remains authoritative for MuJoCo/LabWorld mutation and returns the application boundary. `connectionGeneration` remains a transport freshness guard and is not treated as a simulation epoch.

## Main implementation files

The current V4 working tree spans these principal files:

- `LabSession.swift` — fixed-tick session/lifecycle state, pause barrier state, epoch/tick ordering and step reservation;
- `main.swift` — deterministic driver, neural quantum advancement, pause/reset coordination and UI/session integration;
- `FlyGymBridge.swift` — V4 handshake, ordered control lane, lockstep request/result packets, filtering and live TCP tests;
- `LabProtocol.swift` — V4 metadata and telemetry fields;
- `ExperimentRecorder.swift` — V4 session/tick metadata and command application timing;
- `LabWindow.swift` — deterministic controls, session diagnostics and requested/applied command display;
- `build.sh` — V4 source inclusion;
- `flygym_bridge/protocol.py` — V4 wire types and tolerant legacy parsing;
- `flygym_bridge/bridge.py` — interactive vs request-driven deterministic scheduling, lifecycle controls, epoch/idempotency handling;
- `flygym_bridge/fly_body.py` — exact native-substep body stepping;
- `flygym_bridge/test_v4.py` and the existing Swift/Python regression suites — focused timing/session/fault coverage.

The completion pass itself added only the lifecycle-confirmation idempotency fix/test in `LabSession.swift` plus this completion/status documentation. Existing dirty V4 changes in the other files predate this final pass and were preserved.

## Final automated validation

The final fixed tree was rebuilt and the suite below was executed sequentially. Every listed command returned **exit 0**. Fresh logs are under `notes/validation/v4-final-2026-09-13/` as `final_*.txt`.

| Command | Result | Main evidence |
|---|---|---|
| `./build.sh` | PASS | `final_build.txt` |
| `./ThongpariFlyNeuronSim --v4test` | PASS | session lifecycle + stale-confirmation regression, `final_v4test.txt` |
| `./ThongpariFlyNeuronSim --v4timingtest` | PASS | 30/60/120/stall scheduling invariance surrogate and exact neural time, `final_v4timingtest.txt` |
| `./ThongpariFlyNeuronSim --bridgetest` | PASS | epoch/filter/queue/wire-order tests, `final_bridgetest.txt` |
| `./ThongpariFlyNeuronSim --labtest` | PASS | telemetry/recorder/sensory regressions, `final_labtest.txt` |
| `./ThongpariFlyNeuronSim --simtest` | PASS | whole-brain simulation invariants, `final_simtest.txt` |
| `./ThongpariFlyNeuronSim --behaviortest` | PASS | end-to-end neural/body behavior regression, `final_behaviortest.txt` |
| `./ThongpariFlyNeuronSim --gpucheck` | PASS | independent CPU/GPU reference, `final_gpucheck.txt` |
| `./flygym-venv/bin/python tools/verify_data.py --no-parquet` | PASS | connectome binary/CSR checks, `final_data.txt` |
| `./flygym-venv/bin/python flygym_bridge/test_bridge.py` | PASS | protocol/decoder/mock regression, `final_py_bridge.txt` |
| `./flygym-venv/bin/python flygym_bridge/test_lab.py` | PASS | LabWorld/queue/mock integration, `final_py_lab.txt` |
| `./flygym-venv/bin/python flygym_bridge/validate_experiment_presets.py` | PASS | 11 presets validated, `final_presets.txt` |
| `./flygym-venv/bin/python flygym_bridge/test_v4.py` | PASS | exact quantum, pause, duplicate, wrong epoch and wall-stall invariance, `final_py_v4.txt` |
| `./flygym-venv/bin/python flygym_bridge/test_lab_real.py` | PASS | real MuJoCo exact stepping and world/body integration, `final_lab_real.txt` |
| `./flygym-venv/bin/python flygym_bridge/test_vision_real.py` | PASS | real rendered-eye expansion/false-loom/cover tests, `final_vision_real.txt` |
| `git diff --check` | PASS | `final_diff_check.txt` |

Final managed TCP acceptance was also rerun on the fixed tree:

- mock backend + `./ThongpariFlyNeuronSim --v4loop` — **PASS**, `final_v4loop_mock.txt`;
- real FlyGym headless backend + `./ThongpariFlyNeuronSim --v4loop` — **PASS**, `final_v4loop_real.txt`.

Both runs verified capability negotiation, exact 20 ms lockstep, command application at the requested boundary, >1 s deterministic pause freeze, resume without catch-up, epoch reset, interactive physical pause and same-machine repeatability. The real backend declared **0.100000 ms** physics steps.

The existing mock and real-headless `--labloop` tests were also run during this final acceptance session and passed; their logs are `labloop_mock.txt` and `labloop_real.txt`.

## Fresh real Viewer + GUI acceptance

The final GUI acceptance used a newly launched real backend and app via `./run_flygym.sh --flygym`. The Lab window, Brain window and the passive MuJoCo window (`MuJoCo : flat_ground_world`) were all live against the same real backend.

After applying the lifecycle fix:

1. **Deterministic start stayed healthy.** `gui_smoke_deterministic_after_fix.png` shows `DETERMINISTIC · running · epoch 1 · tick 1940 ms · body result 1940` rather than the earlier failure.
2. **Pause froze the real timeline.** `gui_smoke_paused_1.png` and `gui_smoke_paused_3.png`, captured more than two wall seconds apart, both show epoch 1, tick **24920 ms**, body result **24920**, and backend environment time **24.9 s**.
3. **A world mutation submitted while paused did not apply early.** `gui_smoke_paused_command.png` still shows one object while the new `box_1` command is queued.
4. **Resume applied the queued mutation at the paused boundary.** After Resume, `gui_smoke_resumed_applied_tick.png` shows two objects, and the live AX status reported exactly: `Object status — OK · create box ‘box_1’ at tick 24920`.
5. **The session continued after Resume.** A later live status was `DETERMINISTIC · running · epoch 1 · tick 56760 ms · body result 56760`.
6. **The real MuJoCo Viewer was visually present.** `gui_smoke_real_mujoco_viewer.png` captures the actual `flat_ground_world` scene using the same real backend.
7. **Normal GUI Quit cleaned up the run.** After pressing `Quit Lab`, no project `ThongpariFlyNeuronSim` / bridge / `mjpython` process remained and nothing listened on localhost port 17841.

Action/status details are preserved in `gui_smoke_actions_after_fix.txt`; launcher/backend output is in `gui_smoke_runtime_after_fix.txt`.

## Performance observed during the real GUI smoke

Development machine:

```text
macOS 26.6.2 (25G83)
arm64
Apple M2
Python 3.12.14
FlyGym 2.1.0
MuJoCo 3.9.0
NumPy 2.5.3
```

During the interactive part of the fresh real Viewer run, observed samples were approximately:

- body feedback: **33.1–34.4 Hz**;
- brain packets: **59.8–60.6 Hz**;
- recent maximum body gap: **71–98 ms**;
- simulation/wall ratio: **0.668–0.698×**.

These figures are machine- and scene-specific observations. Deterministic mode deliberately prioritizes exact simulation ticks over wall-time throughput; when the real backend is slower, simulated time slows instead of skipping ticks. The existing UI's generic `<30 Hz` body-feedback warning can therefore appear during deterministic operation even when lockstep is correct.

## Known limitations and boundaries

- V4 deterministic replay guarantees are about the explicit tick/order contract and tested same-machine fields; this report does not claim cross-hardware bit-identical MuJoCo physics.
- During a true pause, body packet age becomes stale because the backend is intentionally not producing advancing body samples. Session tick/phase is the authoritative pause diagnostic.
- The previous V3 user-reserved recording→normal-menu-Quit manual check remains a separate V3 manual validation item as documented in the V3 report. It is not redefined as a V4 blocker.
- Full checkpoint/continuation is **not** a V4 feature; it belongs to V9 in the current roadmap.
- V5 begins the participant/integrated Viewer work; V4 does not claim that interface is already implemented.

## Cleanup and rollback

All temporary bridge/viewer/app processes started for the completion checks were terminated, and the fixed local bridge port was confirmed free after the GUI smoke.

Because the working tree contains substantial pre-existing user/V4/planning changes and V4 has not yet been committed, **do not** use `git reset --hard`, broad `git restore .`, or `git clean` as rollback. Preserve the dirty tree and revert only explicitly identified changes after making a backup or after V4 receives its own commit.

## Next version boundary

All V4 gates required by `VIRTUAL_FLY_LAB_V4_PLAN.md` are green in the current local working tree. The next permitted implementation version is **V5 — integrated Viewer and in-world participant**, following `VIRTUAL_FLY_LAB_V5_PLAN.md` and the common implementation playbook.
