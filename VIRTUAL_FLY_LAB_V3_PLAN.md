# Virtual Fly Lab V3 — implementation plan only

Status: **PLANNED, NOT IMPLEMENTED**

V3 starts only after the current V2 GUI/integration state is committed. The goal is to extend the laboratory with additional biologically named sensory channels without introducing scripted behavior or synthetic neuron populations.

## 1. Non-negotiable rules

- Keep the FlyWire v783 whole-brain connectome authoritative. Do not create fake neuron populations.
- New sensory inputs must resolve to existing shipped FlyWire cell types at runtime.
- Physical/environmental variables and their receptor-current transforms are separate concepts.
- Any transform without measured peripheral transduction data is labeled **MODELING ASSUMPTION / SENSORY-MODEL**.
- Never turn taste, humidity, food proximity, or contact directly into walking, turning, escape, reward, feeding, or seeking commands.
- Direct-neural stimulation remains an explicit experimental bypass and is never presented as a natural stimulus.
- Continuous modeled sensory drive uses the existing persistent `extInput` path, is sleep/sensory-gated, and is cleared on stale data, disconnect, stop, body/world reset, brain reset, and reset-all.

## 2. V3 core additions

### 2.1 Humidity

Use audited existing FlyWire groups:

- dry: `HRN_VP4` — 29 neurons
- moist: `HRN_VP5` — 16 neurons

Proposed lab control:

- relative-humidity scalar, displayed as `% RH`
- modes:
  - `environment_only`: record/display only, no neural current
  - `flywire_sensory`: map dry/moist deviation around a neutral reference to HRN_VP4/VP5 persistent current

Model contract:

- define a documented neutral humidity reference
- use bounded monotonic dry/moist opponent drives
- expose the resulting HRN drive in telemetry
- do not claim a measured humidity-to-current transfer function
- no automatic locomotor or preference response

### 2.2 Taste / contact-gated gustation

Candidate existing FlyWire groups from the V2 audit:

- `claw_tpGRN + dorsal_tpGRN` — 71 neurons, primary V3 gustatory candidate
- `BM_Taste` — 72 neurons, optional mouth-contact/mechanosensory candidate
- `PhG*` — optional later pharyngeal/ingestion-related group; do not use unless an actual ingestion stage exists

Critical gating rule:

**Food distance or odor alone must never generate taste.** Taste requires an explicit geometry/contact event at a modeled taste-capable body target.

V3 should first implement a conservative contact-gated taste stimulus:

1. user marks an object as taste-capable or creates a dedicated taste stimulus object;
2. MuJoCo reports contact with an allowed taste target;
3. Python emits a bounded taste-contact scalar and target identity;
4. Swift maps that scalar to audited gustatory groups through persistent modeled sensory current;
5. removing contact immediately clears the taste drive.

Not included in V3 core:

- reward value
- hunger state
- feeding motor program
- ingestion
- learned preference
- scripted food seeking

### 2.3 Optional contact anatomy refinement

If FlyGym/MuJoCo exposes reliable contact geometry for proboscis/tarsal structures, distinguish:

- tarsal taste contact
- mouth/proboscis contact

If that anatomy is not reliably available, do not fabricate it. Keep one generic contact-gated taste channel and label the limitation.

## 3. Protocol changes

All new fields are optional and backward-compatible.

Body telemetry candidates:

- `humidity_percent`
- `humidity_dry_drive`
- `humidity_moist_drive`
- `taste_contact`
- `taste_target`
- `taste_source_id`

Lab commands:

- `set_humidity`
  - value / percent
  - mode
- `set_taste_source` or taste-capable flag on an object
- optional explicit taste-contact probe for diagnostic mode only, clearly marked `SENSORY-MODEL`

Do not overload existing vision `bearing`, food odor, or touch fields for these modalities.

## 4. MetalSim architecture

Continue the V2 runtime exact-cellType strategy:

- resolve HRN/gustatory indices from `Connectome.typeName`
- no Role enum expansion unless a later design genuinely requires it
- no connectome binary regeneration
- no `LIF.metal` / `StepParams` changes merely to add these channels
- merge persistent V3 drives additively with timed direct stimulation in `extInput`

Add exact group-count assertions to `--labtest` before enabling a UI control.

Gain tuning policy:

- start conservatively
- compare same-seed receptor-group baseline vs stimulated spike rate
- verify receptor response without tuning toward a desired behavior
- document chosen gain as a modeling parameter, not physiology

## 5. GUI plan

Extend the V2 user-friendly `Stimuli` tab rather than adding another expert-only screen.

### Humidity card

- `Humidity (% RH)` numeric field / slider
- mode popup with plain-language labels
- dry/moist receptor explanation
- current HRN dry/moist drive shown inline

### Taste card

- source object selector
- taste-capable toggle / stimulus classification
- contact status: `not touching` / `contact active`
- target/body-part display where reliable
- explicit note: odor/proximity does not equal taste

### Brain tab

Keep HRN and gustatory groups available as direct-neural probes, but visually separate them from natural sensory controls.

### Live Data

Add a compact V3 sensory graph or extend the FlyWire sensory graph only if it remains readable. Prefer a second clearly titled card over an overcrowded legend.

## 6. Recording / experiment format

Append backward-compatible CSV columns for:

- humidity value
- HRN dry/moist modeled drive
- taste-contact scalar
- taste source/target identifier where representable
- gustatory modeled drive

Event log should record:

- humidity changes
- taste-source changes
- taste contact start/end
- resets

Do not silently change the meaning of existing V2 columns.

## 7. Reset and stale-data behavior

Explicitly test:

- `environment_only` humidity -> HRN current zero
- `flywire_sensory` dry -> HRN_VP4 drive
- `flywire_sensory` moist -> HRN_VP5 drive
- humidity reset -> neutral value + zero current when environment-only
- no taste source/contact -> gustatory current zero
- food odor without contact -> gustatory current zero
- valid taste contact -> gustatory current nonzero
- contact end -> gustatory current zero
- packet stale/disconnect -> all V3 persistent currents zero
- reset brain/world/body/all -> no stuck V3 current
- sleep/sensory gate affects modeled V3 sensory current
- direct-neural HRN/gustatory stimulation remains intentionally ungated

## 8. Validation sequence

1. Audit exact V3 cell-type names/counts from shipped v783 arrays again before coding.
2. Python unit tests for humidity transform and contact gating.
3. Real MuJoCo contact smoke test before neural wiring.
4. Swift packet parse/clamp/stale tests.
5. `--labtest` exact group counts and persistent-current clear tests.
6. Same-seed receptor spike-response sanity tests.
7. Full V2 regression: bridge, lab, vision, sim, GPU, behavior, presets.
8. Real launcher smoke with the GUI.

## 9. V3 acceptance criteria

V3 is complete only when:

- humidity has honest environment-only and FlyWire sensory modes;
- HRN_VP4/VP5 drives are observable and clear correctly;
- taste is contact-gated rather than proximity/odor-gated;
- gustatory groups are existing FlyWire populations with audited counts;
- no reward/feeding/seeking behavior is scripted;
- UI explanations make the modeling boundary obvious to a non-expert;
- recording contains the new sensory values and events;
- all V2 tests plus new V3 tests pass;
- `SiliconFly 실험실.command` still launches the full lab normally.
