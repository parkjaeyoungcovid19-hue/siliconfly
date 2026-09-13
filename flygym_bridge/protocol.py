"""protocol.py - newline-delimited JSON protocol (mirror of FlyGymBridge.swift)."""
from __future__ import annotations
import json
import math
import threading
from collections import OrderedDict, deque
from dataclasses import dataclass, field

BRAIN_TYPE = "brain"
BODY_TYPE = "body"
LAB_COMMAND_TYPE = "lab_command"
LAB_STATE_TYPE = "lab_state"
LAB_EVENT_TYPE = "lab_event"

MAX_DISCRETE_LAB_COMMANDS = 128
MAX_CONTINUOUS_LAB_SLOTS = 64
CONTINUOUS_LAB_OPS = {
    "move_object", "resize_object", "wind", "set_eye_state", "eye_state",
    "temperature", "set_temperature",
}

def clamp(x, lo, hi):
    try:
        v = float(x)
    except (TypeError, ValueError):
        v = 0.0
    if not math.isfinite(v):
        v = 0.0
    return max(lo, min(hi, v))

@dataclass
class BrainPacket:
    t: float = 0.0
    walk: float = 0.0
    turn: float = 0.0
    escape: bool = False
    backward: bool = False
    groom: float = 0.0
    wing: float = 0.0
    arousal: float = 0.0
    tempo: float = 1.0
    sleep: bool = False
    nervous: float = 0.0

    @staticmethod
    def from_dict(d: dict) -> "BrainPacket":
        if not isinstance(d, dict):
            raise ValueError("brain packet must be an object")
        b = BrainPacket()
        b.t = clamp(d.get("t", 0.0), 0.0, 1e12)
        b.walk = clamp(d.get("walk", 0.0), 0.0, 1.5)
        b.turn = clamp(d.get("turn", 0.0), -1.0, 1.0)
        b.escape = bool(d.get("escape", False))
        b.backward = bool(d.get("backward", False))
        b.groom = clamp(d.get("groom", 0.0), 0.0, 1.5)
        b.wing = clamp(d.get("wing", 0.0), 0.0, 1.5)
        b.arousal = clamp(d.get("arousal", 0.0), 0.0, 1.0)
        b.tempo = clamp(d.get("tempo", 1.0), 0.2, 2.0)
        b.sleep = bool(d.get("sleep", False))
        b.nervous = clamp(d.get("nervous", 0.0), 0.0, 1.0)
        return b

    def to_dict(self) -> dict:
        return {"type": BRAIN_TYPE, "t": self.t, "walk": self.walk, "turn": self.turn,
                "escape": self.escape, "backward": self.backward, "groom": self.groom,
                "wing": self.wing, "arousal": self.arousal, "tempo": self.tempo,
                "sleep": self.sleep, "nervous": self.nervous}

@dataclass
class BodyPacket:
    t: float = 0.0
    sim_dt: float = 0.0
    wall_dt: float = 0.0
    sim_wall_ratio: float = 0.0
    controller_left: float = 0.0
    controller_right: float = 0.0
    wind_strength: float = 0.0
    wind_direction_deg: float = 0.0
    wind_sensory: bool = False
    touch_strength: float = 0.0
    touch_sensory: bool = False
    vx: float = 0.0
    yaw_rate: float = 0.0
    contacts: list = field(default_factory=lambda: [0, 0, 0, 0, 0, 0])
    left_contact: float = 0.0
    right_contact: float = 0.0
    gait_phase: float | None = None
    loom_left: float = 0.0
    loom_right: float = 0.0
    brightness: float = 0.0
    brightness_left: float = 0.0
    brightness_right: float = 0.0
    occupancy_left: float = 0.0
    occupancy_right: float = 0.0
    optic_expansion_left: float = 0.0
    optic_expansion_right: float = 0.0
    flash_left: float = 0.0
    flash_right: float = 0.0
    odor_left: float = 0.0
    odor_right: float = 0.0
    nearest_food_distance_mm: float | None = None
    heading_rad: float = 0.0
    bearing: float = 0.0

    @staticmethod
    def from_dict(d: dict) -> "BodyPacket":
        if not isinstance(d, dict):
            raise ValueError("body packet must be an object")
        p = BodyPacket()
        p.t = clamp(d.get("t", 0.0), 0.0, 1e12)
        p.sim_dt = clamp(d.get("sim_dt", 0.0), 0.0, 1.0)
        p.wall_dt = clamp(d.get("wall_dt", 0.0), 0.0, 1.0)
        p.sim_wall_ratio = clamp(d.get("sim_wall_ratio", 0.0), 0.0, 100.0)
        p.controller_left = clamp(d.get("controller_left", 0.0), -2.0, 2.0)
        p.controller_right = clamp(d.get("controller_right", 0.0), -2.0, 2.0)
        p.wind_strength = clamp(d.get("wind_strength", 0.0), 0.0, 1.0)
        p.wind_direction_deg = clamp(d.get("wind_direction_deg", 0.0), -36000.0, 36000.0) % 360.0
        p.wind_sensory = bool(d.get("wind_sensory", False))
        p.touch_strength = clamp(d.get("touch_strength", 0.0), 0.0, 1.0)
        p.touch_sensory = bool(d.get("touch_sensory", False))
        p.vx = clamp(d.get("vx", 0.0), -2.0, 2.0)
        p.yaw_rate = clamp(d.get("yaw_rate", 0.0), -20.0, 20.0)
        raw = d.get("contacts", []) or []
        cc = [clamp(v, 0.0, 1.0) for v in list(raw)[:6]]
        while len(cc) < 6:
            cc.append(0.0)
        p.contacts = cc
        p.left_contact = clamp(d.get("left_contact", 0.0), 0.0, 1.0)
        p.right_contact = clamp(d.get("right_contact", 0.0), 0.0, 1.0)
        g = d.get("gait_phase", None)
        p.gait_phase = clamp(g, 0.0, 1.0) if g is not None else None
        p.loom_left = clamp(d.get("loom_left", 0.0), 0.0, 1.0)
        p.loom_right = clamp(d.get("loom_right", 0.0), 0.0, 1.0)
        p.brightness = clamp(d.get("brightness", 0.0), 0.0, 1.0)
        p.brightness_left = clamp(d.get("brightness_left", p.brightness), 0.0, 1.0)
        p.brightness_right = clamp(d.get("brightness_right", p.brightness), 0.0, 1.0)
        p.occupancy_left = clamp(d.get("occupancy_left", 0.0), 0.0, 1.0)
        p.occupancy_right = clamp(d.get("occupancy_right", 0.0), 0.0, 1.0)
        p.optic_expansion_left = clamp(d.get("optic_expansion_left", 0.0), 0.0, 1.0)
        p.optic_expansion_right = clamp(d.get("optic_expansion_right", 0.0), 0.0, 1.0)
        p.flash_left = clamp(d.get("flash_left", 0.0), 0.0, 1.0)
        p.flash_right = clamp(d.get("flash_right", 0.0), 0.0, 1.0)
        p.odor_left = clamp(d.get("odor_left", 0.0), 0.0, 1.0)
        p.odor_right = clamp(d.get("odor_right", 0.0), 0.0, 1.0)
        nearest_food = d.get("nearest_food_distance_mm", None)
        p.nearest_food_distance_mm = (
            clamp(nearest_food, 0.0, 1e6) if nearest_food is not None else None)
        p.heading_rad = clamp(d.get("heading_rad", 0.0), -math.pi, math.pi)
        p.bearing = clamp(d.get("bearing", 0.0), -1.0, 1.0)
        return p

    def to_dict(self) -> dict:
        d = {"type": BODY_TYPE, "t": self.t, "sim_dt": self.sim_dt,
             "wall_dt": self.wall_dt, "sim_wall_ratio": self.sim_wall_ratio,
             "controller_left": self.controller_left,
             "controller_right": self.controller_right,
             "wind_strength": self.wind_strength,
             "wind_direction_deg": self.wind_direction_deg,
             "wind_sensory": self.wind_sensory,
             "touch_strength": self.touch_strength,
             "touch_sensory": self.touch_sensory,
             "vx": self.vx, "yaw_rate": self.yaw_rate,
             "contacts": self.contacts, "left_contact": self.left_contact,
             "right_contact": self.right_contact, "loom_left": self.loom_left,
             "loom_right": self.loom_right, "brightness": self.brightness,
             "brightness_left": self.brightness_left,
             "brightness_right": self.brightness_right,
             "occupancy_left": self.occupancy_left,
             "occupancy_right": self.occupancy_right,
             "optic_expansion_left": self.optic_expansion_left,
             "optic_expansion_right": self.optic_expansion_right,
             "flash_left": self.flash_left, "flash_right": self.flash_right,
             "odor_left": self.odor_left, "odor_right": self.odor_right,
             "heading_rad": self.heading_rad, "bearing": self.bearing}
        if self.nearest_food_distance_mm is not None:
            d["nearest_food_distance_mm"] = self.nearest_food_distance_mm
        if self.gait_phase is not None:
            d["gait_phase"] = self.gait_phase
        return d


@dataclass
class LabCommand:
    """One UI->Python lab command.

    Stable wire shape is `{type, seq, op, args}`.  For compatibility with the
    original plan/examples, unknown top-level fields are merged into `args` when
    an explicit args object is absent/present.
    """
    seq: int = 0
    op: str = ""
    args: dict = field(default_factory=dict)

    @staticmethod
    def from_dict(d: dict) -> "LabCommand":
        if not isinstance(d, dict):
            raise ValueError("lab command must be an object")
        try:
            # Swift V1 uses `id`/`action`; the nested `seq`/`op` form remains
            # accepted for tools/tests and older plan examples.
            seq = int(d.get("seq", d.get("id", 0)))
        except (TypeError, ValueError, OverflowError):
            seq = 0
        seq = max(0, min(2_147_483_647, seq))
        op = str(d.get("op", d.get("action", ""))).strip().lower()
        if not op or len(op) > 64:
            raise ValueError("invalid lab op")
        raw_args = d.get("args", {})
        args = dict(raw_args) if isinstance(raw_args, dict) else {}
        for key, value in d.items():
            if key not in ("type", "seq", "op", "id", "action", "args") and key not in args:
                args[key] = value

        # Normalize the flat Swift V1 command into the internal argument names.
        target = d.get("target")
        if target is not None and "id" not in args:
            args["id"] = str(target)
        if op == "touch" and target is not None:
            args.setdefault("target", str(target))
        if op == "flash_eye" and target is not None:
            args.setdefault("eye", str(target))
        if any(k in d for k in ("x", "y", "z")) and "position_mm" not in args:
            args["position_mm"] = [
                d.get("x", 0.0), d.get("y", 0.0), d.get("z", 0.0)]
        if "size" in d and "size_mm" not in args:
            size = d.get("size")
            args["size_mm"] = [size, size, size]
        if "speed" in d and "speed_mm_s" not in args:
            args["speed_mm_s"] = d.get("speed")
        if "strength" in d:
            args.setdefault("strength", d.get("strength"))
        if "duration_ms" in d:
            args.setdefault("duration_ms", d.get("duration_ms"))
        if op in ("temperature", "set_temperature") and "value" in d:
            args.setdefault("celsius", d.get("value"))
        if op == "flash_eye":
            if "strength" in d:
                args.setdefault("intensity", d.get("strength"))
            elif "value" in d:
                args.setdefault("intensity", d.get("value"))
        if op in ("set_eye_state", "eye_state") and target in ("left", "right") and "value" in d:
            # Swift value=1 means covered; value=0 means restored.
            args[f"{target}_mask"] = d.get("value")
        return LabCommand(seq=seq, op=op, args=args)

    def to_dict(self) -> dict:
        return {"type": LAB_COMMAND_TYPE, "seq": self.seq, "op": self.op, "args": self.args}

    def continuous_key(self):
        if self.op not in CONTINUOUS_LAB_OPS:
            return None
        if self.op in ("move_object", "resize_object"):
            return f"{self.op}:{self.args.get('id', '')}"
        if self.op in ("set_eye_state", "eye_state"):
            left_keys = ("left_enabled", "left_mask")
            right_keys = ("right_enabled", "right_mask")
            touches_left = any(key in self.args for key in left_keys)
            touches_right = any(key in self.args for key in right_keys)
            eye = str(self.args.get("eye", "")).strip().lower()
            touches_left = touches_left or eye == "left"
            touches_right = touches_right or eye == "right"
            if touches_left and not touches_right:
                return "eyes:left"
            if touches_right and not touches_left:
                return "eyes:right"
            return "eyes:both"
        if self.op in ("temperature", "set_temperature"):
            return "temperature"
        return self.op


@dataclass
class LabStatePacket:
    ack: int | None = None
    ok: bool = True
    error: str | None = None
    state: dict = field(default_factory=dict)

    @staticmethod
    def from_dict(d: dict) -> "LabStatePacket":
        if not isinstance(d, dict):
            raise ValueError("lab state must be an object")
        ack = d.get("ack")
        if ack is not None:
            try:
                ack = max(0, min(2_147_483_647, int(ack)))
            except (TypeError, ValueError, OverflowError):
                ack = None
        state = d.get("state", {})
        return LabStatePacket(
            ack=ack,
            ok=bool(d.get("ok", True)),
            error=None if d.get("error") is None else str(d.get("error"))[:512],
            state=dict(state) if isinstance(state, dict) else {},
        )

    def to_dict(self) -> dict:
        d = {"type": LAB_STATE_TYPE, "ack": self.ack, "ok": self.ok, "state": self.state}
        if self.error is not None:
            d["error"] = self.error
        # Swift V1 deliberately decodes a small flat summary while the nested
        # state object retains the complete backend state for future clients.
        if isinstance(self.state, dict):
            d["t"] = clamp(self.state.get("t", 0.0), 0.0, 1e12)
            objects = self.state.get("objects")
            if isinstance(objects, list):
                d["object_count"] = len(objects)
            temperature = self.state.get("temperature")
            if isinstance(temperature, dict):
                d["temperature"] = clamp(temperature.get("celsius", 25.0), 0.0, 50.0)
            wind = self.state.get("wind")
            if isinstance(wind, dict):
                d["wind"] = clamp(wind.get("strength", 0.0), 0.0, 1.0)
            eyes = self.state.get("eyes")
            if isinstance(eyes, dict):
                d["left_eye_covered"] = (not bool(eyes.get("left_enabled", True)) or
                                         clamp(eyes.get("left_mask", 0.0), 0.0, 1.0) >= 0.999)
                d["right_eye_covered"] = (not bool(eyes.get("right_enabled", True)) or
                                          clamp(eyes.get("right_mask", 0.0), 0.0, 1.0) >= 0.999)
            if self.state.get("last_action") is not None:
                d["last_action"] = str(self.state.get("last_action"))[:64]
        return d


@dataclass
class LabEventPacket:
    event: str = ""
    data: dict = field(default_factory=dict)

    @staticmethod
    def from_dict(d: dict) -> "LabEventPacket":
        if not isinstance(d, dict):
            raise ValueError("lab event must be an object")
        event = str(d.get("event", ""))[:64]
        data = d.get("data", {})
        return LabEventPacket(event=event, data=dict(data) if isinstance(data, dict) else {})

    def to_dict(self) -> dict:
        return {"type": LAB_EVENT_TYPE, "event": self.event, "data": self.data}


class LabCommandQueue:
    """Thread-safe bounded FIFO for discrete ops + per-control latest slots."""

    def __init__(self, max_discrete=MAX_DISCRETE_LAB_COMMANDS,
                 max_continuous=MAX_CONTINUOUS_LAB_SLOTS):
        self.max_discrete = max(1, int(max_discrete))
        self.max_continuous = max(1, int(max_continuous))
        self._discrete = deque()
        self._continuous = OrderedDict()
        self._lock = threading.Lock()
        self.dropped = 0

    def push(self, command: LabCommand) -> bool:
        key = command.continuous_key()
        with self._lock:
            if key is None:
                if len(self._discrete) >= self.max_discrete:
                    self.dropped += 1
                    return False
                self._discrete.append(command)
                return True
            if key not in self._continuous and len(self._continuous) >= self.max_continuous:
                self.dropped += 1
                return False
            # Replacement is intentional latest-wins behavior.  Move to end so
            # drain order follows the most recent sequence as closely as possible.
            self._continuous.pop(key, None)
            self._continuous[key] = command
            return True

    def drain(self, max_discrete=None):
        with self._lock:
            n = len(self._discrete) if max_discrete is None else min(len(self._discrete), max(0, int(max_discrete)))
            discrete = [self._discrete.popleft() for _ in range(n)]
            # A pending lifecycle command may create/delete an object referenced
            # by a continuous slot. Keep latest-wins controls until the discrete
            # FIFO ahead of them has completely drained.
            if self._discrete:
                continuous = []
            else:
                continuous = list(self._continuous.values())
                self._continuous.clear()
        # Preserve wire intent when lifecycle and latest-state controls share a
        # tick (spawn->move, wind->reset, move->delete). Python's sort is stable,
        # so clients that omit sequence IDs (all seq=0) retain FIFO-then-slot
        # behavior while Swift's monotonic command IDs recover total order.
        return sorted(discrete + continuous, key=lambda command: command.seq)

    def stats(self):
        with self._lock:
            return {
                "discrete_pending": len(self._discrete),
                "continuous_pending": len(self._continuous),
                "dropped": self.dropped,
                "max_discrete": self.max_discrete,
                "max_continuous": self.max_continuous,
            }

def encode(obj) -> bytes:
    return (json.dumps(obj.to_dict(), separators=(",", ":"), allow_nan=False) + "\n").encode()

def decode_line(line: bytes):
    """Parse one newline-delimited line. Unknown/malformed packets return None."""
    try:
        text = line.decode("utf-8", errors="strict").strip()
    except Exception:
        return None
    if not text:
        return None
    try:
        d = json.loads(text)
    except Exception:
        return None
    if not isinstance(d, dict):
        return None
    kind = d.get("type", "")
    try:
        if kind == BRAIN_TYPE:
            return BrainPacket.from_dict(d)
        if kind == BODY_TYPE:
            return BodyPacket.from_dict(d)
        if kind == LAB_COMMAND_TYPE:
            return LabCommand.from_dict(d)
        if kind == LAB_STATE_TYPE:
            return LabStatePacket.from_dict(d)
        if kind == LAB_EVENT_TYPE:
            return LabEventPacket.from_dict(d)
    except Exception:
        return None
    return None
