# Virtual Fly Lab V5 — implementation progress

Prepared: **2026-09-13**
Baseline HEAD: `e900b272e1df4131edba51476f0d213a8d166ca1` (`Complete Virtual Fly Lab V4 deterministic sessions`)
Status: **READY TO IMPLEMENT — V5.1 is next; no V5 runtime feature is claimed complete**

## Start gate

V4 is committed and the V5 prerequisite is satisfied. The repository was clean when this V5 preparation pass began. The active repository is `siliconfly/`; the workspace-level legacy bridge copy is not an implementation source.

Fresh preflight checks on the V5 baseline:

| Check | Result |
|---|---|
| `./build.sh` | PASS |
| `./ThongpariFlyNeuronSim --v4test` | PASS — `ALL V4 SESSION TESTS PASS` |
| `./flygym-venv/bin/python flygym_bridge/test_v4.py` | PASS — `ALL V4 TESTS PASS` |
| `git diff --check` | PASS |

These checks confirm the committed V4 scheduling/session baseline before V5 work. They are not a substitute for the full V5 completion suite or the V4 completion report's real-backend/GUI evidence.

## Progress table

| 단계 ID | 요구 | 상태 | 변경 파일 | 실행 검사/로그 | 실패/다음 조치 |
|---|---|---|---|---|---|
| V5.1 | 현재 API 조사 및 viewport prototype | planned / ready | 미정 | API preflight below; runtime prototype not yet executed | first implementation step |
| V5.2 | 공통 화면 상태 소유권 | planned | 미정 | 미실행 | V5.1 renderer decision required |
| V5.3 | 관찰 camera | planned | 미정 | 미실행 | camera must stay read-only to simulation |
| V5.4 | 실제 사용자 참여체 | planned | 미정 | 미실행 | backend geometry + eye visibility required |
| V5.5 | WASD/look/E/Esc 및 focus handling | planned | 미정 | 미실행 | backend player contract required |
| V5.6 | 집기/놓기 | planned | 미정 | 미실행 | authoritative backend ray/hit/contact required |
| V5.7 | 기존 activity card 연결 | planned | 미정 | 미실행 | reuse existing telemetry only; no new state model |

No V6 terrain/environment editor, V7 neuron inspector, V8 module host, V9 checkpoint, or V11 desire/emotion model is pulled forward into this version.

## V5.1 API preflight — verified installed surface

The installed environment inspected for this preparation pass reports **MuJoCo 3.9.0**. The current real body already runs FlyGym 2.1 with the same compiled `MjModel`/`MjData` used by the stereo eye renderer and the passive MuJoCo viewer.

Verified public Python APIs/symbols:

- `mujoco.viewer.launch_passive(model, data, key_callback=..., show_left_ui=..., show_right_ui=...)` exists. On macOS its installed source explicitly requires running under `mjpython` and launches the Simulate GUI on the Python UI thread. The public function does not accept an AppKit host view/window handle, so embedding that existing Simulate window directly inside `LabWindow` must not be assumed.
- `mujoco.Renderer(model, height, width, ...)` exists with `update_scene(...)`, `render()`, and depth-rendering enable/disable methods. This is a viable offscreen-render comparison path, but transporting continuous frames over the current newline-JSON control protocol would require a new bounded frame transport and performance budget.
- `mujoco.mj_ray(...)` exists and returns the nearest visible-geometry intersection distance/geom ID.
- `mujoco.mjv_select(...)` exists for view-relative selection when a MuJoCo scene/camera is available.
- The existing Swift app already links **SceneKit** and uses `SCNScene`/`SCNRenderer`, so an AppKit-native `SCNView` mirror does not add a new framework dependency.

Current project facts that constrain the prototype:

- `LabWindow.swift` currently renders the world only through the custom 2D `LabArenaPlacementView`.
- Real MuJoCo rendering is a separate passive viewer window owned by the Python process.
- lab object state already exposes ID, shape, `position_mm`, `size_mm`, and `yaw_deg`.
- body packets already expose the fly's X/Y position and heading, but not a complete 3D pose/quaternion suitable for the V5 `WorldRenderSnapshot` contract.
- objects and fly pose currently arrive through different packet streams/cadences. A V5 renderer must not pretend those independently sampled values form one authoritative simulation-tick snapshot.

## Prototype direction for V5.1

The first V5.1 implementation should compare these paths with a minimal real scene, then record the measured result before V5.2:

1. **AppKit-native SceneKit viewport fed by immutable backend snapshots — preferred first candidate.** `WorldViewer.swift` owns only presentation camera, selection preview and rendering. It mirrors backend object/fly/player geometry but never mutates MuJoCo directly. Pick rays are sent to the backend, where MuJoCo `mj_ray` is authoritative. This gives normal AppKit keyboard/focus behavior and keeps the integrated viewer inside the Lab window.
2. **MuJoCo offscreen `Renderer` frames — comparison candidate.** Prove whether acceptable frame rate/latency is possible without starving the existing body/eye renderer. Do not send unbounded/base64 frame traffic through the current NDJSON command lane as the production design.
3. **Existing passive Simulate viewer — control/baseline only.** Keep it for visual parity and debugging. Because the installed macOS API launches a separate Python-owned window, it is not the default integrated-viewer implementation unless the prototype discovers a supported host/embedding API that was not visible in the installed public surface.

V5.1 is complete only after a real runtime prototype proves that one selected path can show the same backend geometry used for collision/eye visibility, accept keyboard focus, support authoritative picking, and meet a measured viewport budget. This preparation pass does **not** mark that gate complete.

## Contract work to do before UI construction

The first code change should define/validate the world/player wire contract before creating the full Lab shell.

### Atomic render snapshot

Create one immutable backend-originated snapshot at a declared simulation boundary containing at least:

- session ID, epoch, simulation tick and monotonically increasing snapshot/revision ID;
- object IDs, shape/geometry revision and 3D poses;
- full fly body pose needed by the viewer;
- optional player pose when participation is enabled;
- enough revision information to reject stale/out-of-order snapshots.

Do not synthesize an authoritative snapshot by joining an arbitrary `lab_state` object list with a differently timed `body` packet on the Swift side.

### Player input

Player movement is a simulation command, not camera motion. Continuous axes may be latest-wins/coalesced, but discrete interaction events must remain bounded and non-dropping. Movement distance is integrated from simulation time on the backend, never from render FPS. Focus loss, Esc, disconnect and mode exit must send/establish a neutral held-input state so a stale W/A/S/D press cannot continue moving the participant.

### Picking/interactions

The viewport may calculate a local ray for hover/preview, but the backend decides the actual hit against current MuJoCo geometry. A miss is a no-op. The response should include target ID plus applied tick and, when available, hit point/normal. A UI click by itself must never be converted into a fly touch event.

### Player body

The V5 participant begins as a small fly-scale probe/avatar, not a human-scale body. Its visual and collision pose must come from one backend-owned state. It must exist in the same compiled MuJoCo world used by collisions and the fly's real eye cameras. Merely moving the observer camera is not participation.

## Existing code to reuse

- `LabSession` remains the owner of session/epoch/tick/pause ordering.
- `FlyGymBridge` already provides bounded lanes, connection generation filtering, V4 lifecycle/session control and requested/applied tick semantics; extend these instead of creating a second socket/session owner.
- `LabWorld` remains the authority for existing world objects; V5 participant state should not silently become a second object registry.
- current `LabTelemetry` already carries arousal, decoded `BrainSignals`, receptor rates and controller output needed for V5.7 read-only cards. V5 must not invent hunger/desire/emotion values.
- `LabArenaPlacementView` can survive as a minimap/coordinate helper while the 3D viewport becomes the primary interaction surface.

## First implementation slice

When implementation starts, keep the first slice intentionally small:

1. add focused V5 schema/validation fixtures for render snapshot, player pose/input and backend pick result, including missing field, NaN/invalid length and old-epoch negatives;
2. expose one atomic backend snapshot from the existing simulation-owner path;
3. build the smallest `WorldViewer.swift` prototype that renders ground + one existing lab object + fly pose from that snapshot and has a read-only camera;
4. send one pick ray to backend `mj_ray` and verify hit + miss without world mutation;
5. run the same real scene in the existing passive viewer/eye renderer and confirm IDs/poses agree before selecting the production viewport path;
6. record frame cost, snapshot rate and input-to-pick ACK latency before V5.2.

Do not create `PlayerController.swift`, `WorldInteraction.swift` and `player_body.py` as empty stubs before their owning step starts; the common playbook explicitly avoids bulk stub creation.

## V5 completion target retained from the roadmap

The final V5 user path remains: enter participation mode → move a real participant body near the fly → place/move an object → verify the participant/object can appear through the actual eye path and contact is physical → inspect existing neural/activity telemetry → pause without advancing world/brain/player tick → return to observation mode, all from one integrated Lab viewer.

The next code change is **V5.1**, not V6 work.
