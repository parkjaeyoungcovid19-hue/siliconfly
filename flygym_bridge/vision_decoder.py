"""Vision -> looming decoder for the FlyGym body.

This module is a MODELING ASSUMPTION, not a measured Drosophila visual circuit
and not a claim of biological retinotopy.  Its input is genuinely visual:
signals are computed only from FlyGym's two eye-camera frames
(`Simulation.get_raw_vision`), never from obstacle coordinates or object IDs.

V2 adds a generic image-motion path.  It measures outward movement of visual
edges after compensating a small whole-frame translation, so arbitrary visible
objects can create optic expansion without being a configured color.  The
pooling, translation search, edge-motion statistic, gains, thresholds and
temporal smoothing are engineering choices.  They are only a compact sensory
proxy suitable for feeding the existing looming-sensitive neural inputs.

The original target-chromaticity area path remains as a compatibility signal
for existing experiments/tests.  It is combined with, rather than required by,
the generic optic-expansion estimate.
"""
from __future__ import annotations

import math


class VisionLoomDetector:
    """Turn stereo eye frames into compact looming/brightness/bearing signals."""

    CHROMA_TOL = 0.105
    MIN_AREA = 2e-4
    LOOM_GAIN = 8.0

    # Generic raw-frame motion path.  FlyGym runs this on 96x84 eye images; 4x
    # pooling gives a small 24x21 motion grid without adding dependencies.
    MOTION_POOL = 4
    MAX_GLOBAL_SHIFT = 3
    MOTION_EPS = 0.025
    RADIAL_DEADBAND = 0.007
    GENERIC_GAIN = 1.8
    FLASH_DELTA = 0.10
    FLASH_FRACTION = 0.70

    def __init__(self, target_rgb=(0.55, 0.32, 0.12)):
        import numpy as np

        self.np = np
        target = np.asarray(target_rgb, dtype=float)[:3]
        target = np.clip(target, 0.0, None)
        self.target_chroma = target / max(1e-9, float(target.sum()))
        self.prev_radius = [None, None]
        self.prev_motion = [None, None]
        self.prev_luminance = [None, None]
        self.loom = [0.0, 0.0]
        self.brightness = 0.0
        self.brightness_eye = [0.0, 0.0]
        self.bearing = 0.0
        self.last_area = [0.0, 0.0]
        self.optic_expansion = [0.0, 0.0]

    def _rgb01(self, frame):
        np = self.np
        a = np.asarray(frame, dtype=float)
        if a.size == 0:
            return a
        if float(a.max()) > 1.5:
            a = a / 255.0
        return np.clip(a[..., :3], 0.0, 1.0)

    def _mask(self, rgb):
        """Legacy configured-color occupancy plus ordinary luminance."""
        np = self.np
        if rgb.size == 0:
            return np.zeros(rgb.shape[:2], dtype=bool), np.zeros(rgb.shape[:2], dtype=float)
        rgb_sum = rgb.sum(axis=2)
        chroma = rgb / np.maximum(rgb_sum[..., None], 1e-6)
        dist = np.linalg.norm(chroma - self.target_chroma, axis=2)
        lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
        # Reject near-black renderer background and near-white floor/highlights.
        mask = (dist < self.CHROMA_TOL) & (lum > 0.04) & (lum < 0.78)
        return mask, lum

    def _motion_features(self, rgb):
        """Return low-resolution normalized RGB and unsigned edge energy.

        Per-channel centering/scaling makes uniform illumination or color flashes
        mostly disappear from the motion representation.  This is image-processing
        engineering, not a model of individual ommatidia or motion neurons.
        """
        np = self.np
        h, w = rgb.shape[:2]
        pool = self.MOTION_POOL if min(h, w) >= self.MOTION_POOL * 2 else 1
        hh = (h // pool) * pool
        ww = (w // pool) * pool
        cropped = rgb[:hh, :ww]
        if pool > 1:
            pooled = cropped.reshape(hh // pool, pool, ww // pool, pool, 3).mean(axis=(1, 3))
        else:
            pooled = cropped

        mean = pooled.mean(axis=(0, 1), keepdims=True)
        std = pooled.std(axis=(0, 1), keepdims=True)
        normalized = (pooled - mean) / (std + 0.05)

        gx = np.zeros(normalized.shape[:2], dtype=float)
        gy = np.zeros(normalized.shape[:2], dtype=float)
        gx[:, 1:] = np.mean(np.abs(normalized[:, 1:] - normalized[:, :-1]), axis=2)
        gy[1:, :] = np.mean(np.abs(normalized[1:, :] - normalized[:-1, :]), axis=2)
        return normalized, gx + gy

    def _global_shift(self, previous, current):
        """Estimate small whole-eye translation in pooled pixels by SSD."""
        np = self.np
        h, w = current.shape[:2]
        margin = min(self.MAX_GLOBAL_SHIFT, max(0, (min(h, w) - 3) // 2))
        if margin < 1:
            return 0, 0
        core = (slice(margin, h - margin), slice(margin, w - margin))
        best = (float("inf"), 0, 0)
        for dy in range(-margin, margin + 1):
            for dx in range(-margin, margin + 1):
                shifted = np.roll(previous, shift=(dy, dx), axis=(0, 1))
                err = shifted[core] - current[core]
                # Small tie-breaker keeps a static image at zero shift.
                cost = float(np.mean(err * err)) + 5e-4 * (dx * dx + dy * dy)
                if cost < best[0]:
                    best = (cost, dy, dx)
        return best[1], best[2]

    def _generic_expansion(self, previous, current, dt):
        """Estimate positive radial edge expansion after whole-frame alignment."""
        np = self.np
        prev_features, prev_edge = previous
        curr_features, curr_edge = current
        dy, dx = self._global_shift(prev_features, curr_features)
        aligned_prev_edge = np.roll(prev_edge, shift=(dy, dx), axis=(0, 1))
        delta = curr_edge - aligned_prev_edge

        # Rolled pixels at the perimeter are not real correspondences.  Ignoring a
        # fixed narrow rim also reduces false looming from eye-camera pan.
        border = min(self.MAX_GLOBAL_SHIFT, max(0, (min(delta.shape) - 3) // 2))
        if border > 0:
            delta[:border, :] = 0.0
            delta[-border:, :] = 0.0
            delta[:, :border] = 0.0
            delta[:, -border:] = 0.0

        motion = np.abs(delta)
        motion[motion < self.MOTION_EPS] = 0.0
        total = float(motion.sum())
        if total <= 1e-9:
            return 0.0

        # A real scale change has disappearing inner edges and appearing outer
        # edges.  Requiring both signs rejects many one-sided translations/onsets.
        positive = float(np.maximum(delta, 0.0).sum())
        negative = float(np.maximum(-delta, 0.0).sum())
        if min(positive, negative) < 0.08 * total:
            return 0.0

        yy, xx = np.indices(delta.shape, dtype=float)
        cx = float((motion * xx).sum() / total)
        cy = float((motion * yy).sum() / total)
        rx = (xx - cx) / max(1.0, float(delta.shape[1]))
        ry = (yy - cy) / max(1.0, float(delta.shape[0]))
        radius = np.sqrt(rx * rx + ry * ry)
        radial = float((delta * radius).sum() / total)
        outward = max(0.0, radial - self.RADIAL_DEADBAND)
        return min(1.0, (outward / dt) * self.GENERIC_GAIN)

    def analyze(self, frames, dt: float) -> dict:
        """Analyze one stereo frame pair. `dt` is time since the previous pair."""
        np = self.np
        arr = np.asarray(frames)
        if arr.ndim != 4 or arr.shape[0] != 2 or arr.shape[-1] < 3:
            raise ValueError(f"expected eye frames shape (2,H,W,3), got {arr.shape}")
        dt = max(1e-3, min(1.0, float(dt)))
        areas = []
        lums = []
        radii = []
        generic = []
        flash_like = []
        motion_now = []
        luminance_now = []

        for eye in range(2):
            rgb = self._rgb01(arr[eye, ..., :3])
            mask, lum = self._mask(rgb)
            area = float(mask.mean())
            if area < self.MIN_AREA:
                area = 0.0
            areas.append(area)
            radii.append(math.sqrt(area))
            lums.append(float(lum.mean()))

            features = self._motion_features(rgb)
            motion_now.append(features)
            prev = self.prev_motion[eye]
            generic.append(0.0 if prev is None else self._generic_expansion(prev, features, dt))

            old_lum = self.prev_luminance[eye]
            if old_lum is None or old_lum.shape != lum.shape:
                widespread = False
            else:
                widespread = float(np.mean(np.abs(lum - old_lum) > self.FLASH_DELTA)) >= self.FLASH_FRACTION
            # Widespread pixel change with no coherent expansion is treated as a
            # flash/illumination transient, not looming.
            flash_like.append(widespread and generic[-1] < 0.05)
            luminance_now.append(lum.copy())

        for eye in range(2):
            prev_radius = self.prev_radius[eye]
            legacy = 0.0 if prev_radius is None else max(0.0, (radii[eye] - prev_radius) / dt) * self.LOOM_GAIN
            if flash_like[eye]:
                legacy = 0.0
                generic[eye] = 0.0
            raw = min(1.0, max(legacy, generic[eye]))
            self.optic_expansion[eye] = raw
            # Attack quickly, release more slowly so a 5-10 Hz camera stream is
            # not reduced to one-frame impulses before 60 Hz body packets carry it.
            if raw >= self.loom[eye]:
                self.loom[eye] += (raw - self.loom[eye]) * 0.75
            else:
                self.loom[eye] += (raw - self.loom[eye]) * 0.35
            self.prev_radius[eye] = radii[eye]
            self.prev_motion[eye] = motion_now[eye]
            self.prev_luminance[eye] = luminance_now[eye]

        self.last_area = areas
        self.brightness_eye = [max(0.0, min(1.0, v)) for v in lums]
        self.brightness = max(0.0, min(1.0, sum(lums) / 2.0))
        total = areas[0] + areas[1]
        # Compatibility bearing: positive means configured-color occupancy is
        # larger in the left eye; negative means right.
        self.bearing = 0.0 if total < self.MIN_AREA else max(-1.0, min(1.0, (areas[0] - areas[1]) / total))
        return self.state()

    def decay(self, dt: float) -> dict:
        """Decay sample-derived motion telemetry between expensive eye renders.

        Brightness/occupancy/bearing describe the last rendered frame and are
        intentionally sample-held.  Looming is a filtered state, while raw optic
        expansion is an instantaneous motion estimate; holding the latter at its
        last 5 Hz sample made the diagnostics claim expansion was still present
        after the neural loom signal had already begun to release.
        """
        elapsed = max(0.0, float(dt))
        loom_k = math.exp(-3.0 * elapsed)
        raw_k = math.exp(-8.0 * elapsed)
        self.loom[0] *= loom_k
        self.loom[1] *= loom_k
        self.optic_expansion[0] *= raw_k
        self.optic_expansion[1] *= raw_k
        return self.state()

    def state(self) -> dict:
        return {
            "loom_left": max(0.0, min(1.0, float(self.loom[0]))),
            "loom_right": max(0.0, min(1.0, float(self.loom[1]))),
            "brightness": self.brightness,
            "brightness_left": self.brightness_eye[0],
            "brightness_right": self.brightness_eye[1],
            "occupancy_left": self.last_area[0],
            "occupancy_right": self.last_area[1],
            "optic_expansion_left": self.optic_expansion[0],
            "optic_expansion_right": self.optic_expansion[1],
            "bearing": self.bearing,
        }
