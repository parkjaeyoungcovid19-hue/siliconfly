#!/usr/bin/env python3
"""Validate Virtual Fly Lab experiment_presets.json using only stdlib."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


FORMAT = "siliconfly.virtual-fly-lab.presets"
CLASSIFICATIONS = {"PHYSICAL", "SENSORY-MODEL", "DIRECT-NEURAL"}
PHASES = {"setup", "stimulus", "cleanup"}
BRIDGE_ACTIONS = {
    "spawn_object",
    "spawn_box",
    "spawn_sphere",
    "spawn_wall",
    "spawn_food",
    "move_object",
    "resize_object",
    "delete_object",
    "approach_object",
    "reset_world",
    "reset_body",
    "set_eye_state",
    "flash_eye",
    "wind",
    "stop_wind",
    "touch",
    "temperature",
}
SWIFT_ACTIONS = {
    "apply_modeled_wind",
    "apply_modeled_touch",
    "stimulate_population",
    "reset_brain",
    "reset_modeled_stimuli",
}
NEURAL_ROLES = {
    "GF", "DNa-left", "DNa-right", "MDN", "DNp09", "DNg11", "escW",
    "LC4/LPLC2-left", "LC4/LPLC2-right", "LC4/LPLC2", "ascend", "sens",
}
REQUIRED_IDS = {
    "loom-frontal",
    "loom-left",
    "loom-right",
    "wind-puff",
    "thorax-touch",
    "loom-left-eye-covered",
    "stim-gf",
    "stim-dna-left",
    "stim-dna-right",
    "stim-mdn",
    "stim-dnp09",
}


def finite_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def validate(path: Path) -> list[str]:
    errors: list[str] = []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return [f"could not parse {path}: {exc}"]

    if not isinstance(data, dict):
        return ["top-level JSON must be an object"]
    if data.get("format") != FORMAT:
        errors.append(f"format must be {FORMAT!r}")
    if data.get("version") != 1:
        errors.append("version must be 1")

    presets = data.get("presets")
    if not isinstance(presets, list) or not presets:
        return errors + ["presets must be a non-empty array"]

    seen: set[str] = set()
    for index, preset in enumerate(presets):
        where = f"presets[{index}]"
        if not isinstance(preset, dict):
            errors.append(f"{where} must be an object")
            continue
        preset_id = preset.get("id")
        if not isinstance(preset_id, str) or not preset_id:
            errors.append(f"{where}.id must be a non-empty string")
            preset_id = where
        elif preset_id in seen:
            errors.append(f"duplicate preset id: {preset_id}")
        else:
            seen.add(preset_id)
        where = f"preset {preset_id!r}"

        if not isinstance(preset.get("name"), str) or not preset["name"].strip():
            errors.append(f"{where}: name must be a non-empty string")
        classes = preset.get("classification")
        if not isinstance(classes, list) or not classes:
            errors.append(f"{where}: classification must be a non-empty array")
        elif any(c not in CLASSIFICATIONS for c in classes):
            errors.append(f"{where}: unknown classification in {classes!r}")

        for field in ("baseline_ms", "observe_ms"):
            value = preset.get(field)
            if not finite_number(value) or value < 0 or value > 60_000:
                errors.append(f"{where}: {field} must be a finite number in 0..60000")

        readouts = preset.get("primary_readouts")
        if not isinstance(readouts, list) or not readouts or not all(isinstance(v, str) and v for v in readouts):
            errors.append(f"{where}: primary_readouts must be a non-empty string array")

        steps = preset.get("steps")
        if not isinstance(steps, list) or not steps:
            errors.append(f"{where}: steps must be a non-empty array")
            continue

        for step_index, step in enumerate(steps):
            sw = f"{where} step {step_index}"
            if not isinstance(step, dict):
                errors.append(f"{sw}: must be an object")
                continue
            if step.get("phase") not in PHASES:
                errors.append(f"{sw}: phase must be one of {sorted(PHASES)}")
            executor = step.get("executor")
            action = step.get("action")
            if executor == "bridge":
                if action not in BRIDGE_ACTIONS:
                    errors.append(f"{sw}: unknown bridge action {action!r}")
            elif executor == "swift":
                if action not in SWIFT_ACTIONS:
                    errors.append(f"{sw}: unknown Swift action {action!r}")
            else:
                errors.append(f"{sw}: executor must be 'bridge' or 'swift'")

            if action == "stimulate_population":
                if step.get("role") not in NEURAL_ROLES:
                    errors.append(f"{sw}: role must be one of {sorted(NEURAL_ROLES)}")
            if action in {"wind", "touch", "apply_modeled_wind", "apply_modeled_touch"}:
                strength = step.get("strength")
                if not finite_number(strength) or not 0 <= strength <= 1:
                    errors.append(f"{sw}: strength must be in 0..1")
            if action == "stimulate_population":
                strength = step.get("strength")
                if not finite_number(strength) or not 0 <= strength <= 2:
                    errors.append(f"{sw}: direct-neural strength must be in 0..2")
            if "duration_ms" in step:
                duration = step["duration_ms"]
                if not finite_number(duration) or not 1 <= duration <= 60_000:
                    errors.append(f"{sw}: duration_ms must be in 1..60000")
            if "speed_mm_s" in step:
                speed = step["speed_mm_s"]
                if not finite_number(speed) or speed <= 0 or speed > 2000:
                    errors.append(f"{sw}: speed_mm_s must be in (0, 2000]")
            if "end_distance_mm" in step:
                distance = step["end_distance_mm"]
                if not finite_number(distance) or not 0.5 <= distance <= 500:
                    errors.append(f"{sw}: end_distance_mm must be in 0.5..500")
            if "direction_deg" in step and not finite_number(step["direction_deg"]):
                errors.append(f"{sw}: direction_deg must be finite")
            for flag in ("physical", "sensory", "continuous"):
                if flag in step and not isinstance(step[flag], bool):
                    errors.append(f"{sw}: {flag} must be boolean")
            if action in {"spawn_object", "spawn_box", "spawn_sphere", "spawn_wall", "spawn_food",
                          "move_object", "resize_object", "delete_object", "approach_object"}:
                if not isinstance(step.get("target"), str) or not step["target"]:
                    errors.append(f"{sw}: object action needs a target id")

            if action in {"spawn_object", "spawn_box", "spawn_sphere", "spawn_wall", "spawn_food"}:
                for field in ("x", "y", "z", "size_mm"):
                    if field in step and not finite_number(step[field]):
                        errors.append(f"{sw}: {field} must be finite")

            placement = step.get("placement")
            if placement is not None:
                if not isinstance(placement, dict) or placement.get("frame") != "fly_relative":
                    errors.append(f"{sw}: placement must use frame='fly_relative'")
                else:
                    for field in ("forward_mm", "lateral_mm", "z_mm"):
                        if not finite_number(placement.get(field)):
                            errors.append(f"{sw}: placement.{field} must be finite")

    missing = sorted(REQUIRED_IDS - seen)
    if missing:
        errors.append("missing required presets: " + ", ".join(missing))

    covered = next((p for p in presets if isinstance(p, dict) and p.get("id") == "loom-left-eye-covered"), None)
    if covered:
        steps = covered.get("steps", [])
        covered_on = any(s.get("action") == "set_eye_state" and s.get("target") == "left" and s.get("value") == 1.0 for s in steps if isinstance(s, dict))
        right_open = any(s.get("action") == "set_eye_state" and s.get("target") == "right" and s.get("value") == 0.0 for s in steps if isinstance(s, dict))
        if not covered_on or not right_open:
            errors.append("loom-left-eye-covered must cover the left eye and explicitly leave the right eye open")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", type=Path,
                        default=Path(__file__).with_name("experiment_presets.json"))
    args = parser.parse_args()
    errors = validate(args.path)
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    count = len(json.loads(args.path.read_text(encoding="utf-8"))["presets"])
    print(f"OK: {args.path} — {count} presets validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
