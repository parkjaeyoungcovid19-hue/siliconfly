# Virtual Fly Lab V2 — correctness / responsiveness repair plan

This plan is based on the 2026-09-13 read-only V2 audit after the locomotion CPG clock fix.
V3 humidity/taste work stays frozen until this V2 gate is green.

## 0. Completion status

**Completed and revalidated on 2026-09-13.** The defect list below is retained as the historical audit that drove the repair. The implemented V2 now uses Python LabWorld body-packet wind/touch state as the Swift neural source of truth, has reset/queue/freshness/telemetry fixes in place, and passed the full Swift/Python/real-FlyGym regression gate including repeated behavior tests and viewer-open launcher smoke. V3 remains planning-only.


## 1. Confirmed defects

### P0 — fix before trusting experiments

1. **Physical and neural stimulus clocks diverge.**
   - Swift neural wind/touch durations use Metal brain `simMs`.
   - Python physical wind/touch/flash timers advance only with MuJoCo substeps.
   - RealFlyBody currently advances at most 20 × 0.1 ms = 2 ms of MuJoCo time per body tick.
   - Therefore one UI stimulus can end neurally while its physical force is still active for much longer.

2. **Recommended launcher runs the real body too slowly under full load.**
   - Measured with the actual `SiliconFly 실험실.command`: about 12 Hz body feedback with the MuJoCo viewer open.
   - Running the viewer bridge without `nice +10`: about 17 Hz.
   - Closing the MuJoCo viewer raised the same run to about 40 Hz; clean headless runs reached about 49 Hz.
   - The launcher currently lowers bridge priority with `nice -n 10`, which makes the contention worse.
   - At 12 Hz with the 20-substep cap, MuJoCo advances only ~24 ms of simulation time per wall second, making otherwise valid locomotion look nearly stationary.

3. **Reset semantics are split across Swift and Python.**
   - Python `reset_world` clears wind/touch/flash/eyes/temperature as well as objects.
   - UI `Reset world` sends only the Python reset, leaving Swift local JO/TRN/tempo state potentially active.
   - `Reset brain` currently clears Swift lab wind even if the physical environment still contains continuous wind.

4. **Left/right eye commands can overwrite each other before Python applies them.**
   - Both `set_eye_state` commands use the same continuous queue key `eyes`.
   - Reproduced: a queued left-eye change followed by a right-eye change drains only the second command.
   - This can break presets/reset sequences that send both eyes separately.

5. **Lab-command traffic can starve ordinary brain packets.**
   - Swift send priority is escape → all queued lab work → ordinary latest brain packet, with one shared throttle.
   - A burst of 32 lab commands can hold the prior locomotor command for hundreds of milliseconds.

6. **Real body feedback is contaminated by desktop-fly proprioception.**
   - Even with fresh MuJoCo feedback, `gaitDrive` is 70% real body + 30% procedural desktop fly.
   - A real FlyGym experiment should not mix unrelated SceneKit body state into fresh body afference.

7. **Current `gaitDrive` treats standing foot contact as walking.**
   - Formula is 65% mean ground contact + 35% forward speed.
   - Measured stationary real fly contact mean: ~0.67–1.0, so a stationary fly can generate ~0.43–0.65 gait drive before any speed contribution.
   - This is not a valid walking-intensity signal and can create artificial positive feedback.

### P1 — biologically / behaviorally misleading

8. **Lab touch is not a body-part tactile neural pathway.**
   - Physical force targets the chosen body segment.
   - Neural side always directly stimulates the same legacy 16-cell `sens` population (JO-A/B-like from the prior audit), regardless of head/thorax/leg target.
   - It bypasses `sensoryGate`, despite the UI labeling it as a sensory-model pathway.

9. **`modeled_physiology` temperature does nothing to the real FlyGym body.**
   - Swift changes `BrainSignals.tempo`.
   - Python `neural_decoder.py` ignores `tempo`, so this mode only affects the desktop procedural fly.

10. **Default food geometry is far weaker than the only ORN gain test.**
    - UI default food around x=60 mm gives modeled odor ~0.073 per side in the audited geometry.
    - With gain 0.060, injected current is only ~0.0044.
    - Existing receptor-spike sanity test uses the full 0.060 current, about 14× stronger.
    - Food intentionally has no taste/reward/feeding/scripted seeking; this is a sensory calibration gap, not a reason to add scripted approach.

11. **Wind physical effect is visually subtle at current settings.**
    - Isolated audit displacement was only modestly above baseline drift.
    - Calibration must happen after timebase/performance repair, otherwise force tuning is meaningless.

12. **FlyWire sensory graph scale is wrong for the values it plots.**
    - Graph is fixed at 0...1.2.
    - Actual ORN/TRN currents cap near 0.060 and JO near 0.055, so full drive occupies only ~5% of the plot height.
    - Help text currently implies a normalized 0...1 scale although the graph contains injected current.

13. **Thorax-touch preset can use the wrong selected body part.**
    - UI title is now `Thorax`, but preset still selects item title `thorax`.
    - Selection can fail and the preset then uses whichever target was previously selected.

14. **Production approach motion and vision use different notions of elapsed time.**
    - Object approach advances in capped MuJoCo simulation time.
    - Vision scheduling uses caller/wall `dt` at ~5 Hz.
    - Under time dilation, the rendered object moves much less between vision samples than the UI speed suggests, weakening looming.

### P2 — diagnostics / state-honesty / edge cases

15. Swift parses body packet `t` but drops it from `FlyGymBodyFeedback`; brain/body simulation time cannot be aligned or checked after reset/lag.
16. Latest lab state/ack/event has no age or connection generation and can remain stale across a reconnect.
17. UI `bodyHz` is a historical interval average and can look healthy during a live body stall unless freshness is shown separately.
18. Coordinator reads body feedback once for neural input and again for telemetry, so a later packet can be recorded than the packet that actually drove that brain step.
19. Python stale-brain timeout uses wall `time.time()` instead of monotonic time.
20. Proprioceptive `ascendDrive` is not sleep-gated while other modeled sensory channels are; touch also bypasses sensory gating.
21. Python `reset_world` leaves queued old events and some option flags semantically stale until subsequent activity.
22. `reset_body` settle steps consume active physical stimulus timers while protocol time is reset to zero.
23. A zero-intensity flash can retain a timer that never drains because timer advancement checks intensity > 0.
24. Raw optic-expansion telemetry is sample-held between 5 Hz renders while loom itself decays, which can mislead live diagnosis.
25. Python food object state says `neural_connected=false` even though the integrated Swift side does inject its odor into ORN_DM1/VA2; this is subsystem-local state but reads as whole-system state.
26. UI does not expose receptor spike rates, decoded BrainSignals, body controller L/R command, or freshness, so a failed source→receptor→DN→command→motion chain looks identical to a biologically valid no-response.
27. `--behaviortest` ledge attachment showed one failure followed by three passes, indicating a flaky/non-deterministic regression test that should not be treated as a reliable gate yet.

## 2. Things that are working and must not be "fixed" by scripting behavior

- Real locomotion adapter can move the MuJoCo fly after the CPG clock fix: direct test ~2.5 mm forward and ~5.7 mm/s peak simulated forward velocity.
- Generic rendered-eye expansion works on non-target-color real objects; contraction/pan suppression works.
- Food geometry produces bilateral odor and removal/reset clears it.
- Full ORN drive raises ORN receptor spiking.
- Flash is intentionally brightness telemetry only.
- Eye cover/open intentionally changes future visual input only.
- Food intentionally has no automatic seeking, feeding, taste, or reward behavior.
- A receptor signal is not itself a guarantee of motor behavior.

## 3. Repair order

### Phase A — restore one coherent experiment clock and adequate body throughput

1. Remove the launcher's `nice +10` penalty and remeasure before any biological gain tuning.
2. Benchmark viewer-open / viewer-closed / headless modes under the full 139k-neuron app.
3. Optimize the controller without reintroducing the old 10× CPG-clock bug:
   - keep the oscillator clock correct for every physics step;
   - decimate expensive observation/action construction only with an explicitly compensated stride;
   - never translate the body directly or inject fake locomotion.
4. Propagate MuJoCo body `t` into Swift feedback and recording.
5. Define one canonical stimulus duration contract and test physical vs neural end times to <=10% mismatch.
6. Expose `body_sim_seconds / wall_second` in diagnostics so slow playback can never be mistaken for "no movement".

**Gate A:** actual recommended launcher with viewer open should maintain useful closed-loop freshness (target >=40 Hz body feedback if achievable on M2; never below 30 Hz without an explicit degraded-mode warning), with no >250 ms stale-body gaps during an ordinary trial.

### Phase B — make state ownership/reset/queues deterministic

1. Write a state-ownership table: world objects, wind physical state, wind neural model, eyes, temp environment, TRN mode, brain state, body pose.
2. Split/reset commands so names match semantics:
   - world-object reset does not silently reset unrelated senses; or
   - if `Reset world` is defined as whole environment reset, mirror that reset in Swift in the same transaction.
3. `Reset brain` must reset brain state without turning off an environmental stimulus; active environment should immediately re-drive receptors after reset.
4. Give left/right eye state separate coalescing keys, or send one atomic combined-eye command.
5. Interleave lab and ordinary brain traffic; enforce a maximum normal-brain packet gap while lab commands are queued.
6. Clear/age lab state, ack, event and body freshness by connection generation.
7. Use monotonic time for Python stale-brain safety logic.

**Gate B:** reset/eye/burst-traffic stress tests pass repeatedly with identical Swift and Python state.

### Phase C — repair real-body proprioception

1. When MuJoCo feedback is fresh, use the real body only; do not blend the SceneKit procedural fly.
2. Replace raw contact occupancy as "gait" with movement-sensitive feedback (speed + gait/contact transitions/phase), while preserving an explicit contact channel if needed.
3. Verify an idle standing fly produces low gait drive and a genuinely walking fly produces higher drive.
4. Keep the previously measured stationary DNp09 spontaneous activity test so locomotion is not bootstrapped by fake gait feedback.

**Gate C:** idle vs walking feedback separates cleanly and the real closed loop starts/stops without procedural contamination.

### Phase D — make each sensory pathway honest and calibratable

#### Touch
- Until audited real tactile receptor groups are wired, stop presenting the legacy `sens` stimulation as body-part-specific tactile transduction.
- Either label it explicitly as a legacy generic startle probe or implement an audited tactile mapping.
- Any modeled sensory touch path must respect sensory gating; direct-neural probes remain ungated.
- Test physical force and neural effect independently per target.

#### Temperature
- `environment_only`: keep as record-only.
- `flywire_sensory`: calibrate TRN receptor spikes at representative temperatures.
- `modeled_physiology`: either wire `tempo` into the real FlyGym controller/CPG as an explicit modeling assumption or disable this mode for real-body runs; do not leave it silently desktop-only.

#### Food
- Add an end-to-end default-UI-geometry test: food position → odor → ORN current → ORN spike rate.
- Calibrate source decay/gain or default placement to a useful receptor range without adding seeking/reward/feeding.
- Report both modeled odor scalar and receptor spike Hz.

#### Wind
- Test physical force/displacement separately from JO-C/E neural drive.
- Calibrate JO receptor spiking and physical strength only after clock/throughput repair.
- Keep generic `Role.sens` out of the V2 wind pathway.

**Gate D:** each sense has a source-level test, receptor-level test, and clear expected/no-expected behavior statement.

### Phase E — vision timing and false-positive hardening

1. Align approach animation timing with the chosen experiment clock.
2. Preserve the existing real-rendered expansion tests for arbitrary objects.
3. Add production eye-cover/open sequence tests through the real queue.
4. Timestamp or decay raw optic-expansion telemetry instead of sample-holding it indefinitely.
5. Add a textured full-field physical brightness-step regression so future real flash implementations do not become false looming.
6. Do not create a fake flash→escape pathway.

### Phase F — make failure location visible in the GUI

For every trial, expose a compact chain:

`physical/source state → sensor scalar → injected current → receptor spike Hz → downstream GF/DN rates → decoded BrainSignals → FlyGym L/R controller command → measured body motion`

Also:
- fix FlyWire current graph range/units;
- show Fresh/Stale and packet age, not body Hz alone;
- show sensoryGate/sleep state;
- expose DNa L/R and escW already present in telemetry;
- show command ack/error/last applied action in a diagnostics area;
- fix the `Thorax touch` preset target selection;
- make `environment_only` temperature visibly say “no neural input”.

## 4. Regression gate before commit

Run all of the following after the repair, before committing:

1. `./build.sh`
2. `./SiliconFly --labtest`
3. `./SiliconFly --bridgetest`
4. `./SiliconFly --simtest`
5. `./SiliconFly --behaviortest` repeatedly (minimum 5 runs; eliminate ledge flake)
6. `flygym_bridge/test_bridge.py`
7. `flygym_bridge/test_lab.py`
8. `flygym_bridge/test_lab_real.py`
9. `flygym_bridge/test_vision_real.py`
10. real `--bridgeloop` with speed + packet-gap assertions
11. real launcher smoke with MuJoCo viewer open, reporting body Hz, brain packet Hz, body-sim/wall ratio and stale gaps
12. physical/neural duration parity test for wind and touch
13. reset-world/reset-brain cross-process state test
14. two-eye same-tick command test
15. 32-command lab burst fairness test
16. default-food → ORN receptor-spike test
17. isolated JO/TRN receptor-spike calibration tests

No scripted food seeking/feeding/reward or hard-coded escape/walk behavior may be added merely to make a behavioral assertion pass.

## 5. Commit policy

Do not commit until all P0 items and their regression gates pass. V3 remains planning-only until the repaired V2 launcher is responsive and state-consistent.
