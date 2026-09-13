# Thongpari Fly Neuron Sim + FlyGym measured performance

Measured on the user's Apple M2 Air (8 GB), 2026-09-12. These are observations,
not targets or estimates.

## Closed-loop bridge

- Mock round trip: 200 brain packets sent; 279 body packets received; measured
  feedback 56 Hz before the final 60 Hz pacer.
- Real FlyGym 2.1.0, viewer enabled, after explicit prewarm: 193 brain packets
  received at 59.9 Hz; 253 body packets returned at 60 Hz; Swift loop PASS.
- During tuning, a headless closed-loop run with 128x112 eye rendering at 10 Hz
  returned 253 body packets for 200 brain packets and held 60 Hz feedback, but a
  later hot/loaded run fell to ~31 Hz. The final configuration therefore uses a
  more conservative 96x84 Retina at 5 Hz and a 20-substep physics cap. Final
  validation: 200 brain packets, 258 body packets, measured body feedback 60 Hz,
  Python-side brain receive rate 62.0 Hz; Swift `--bridgeloop` PASS.
- Queues are bounded: one latest-state slot and one protected escape-pulse slot
  in Swift; one latest command under a lock in Python.
- The viewer/body pipeline can take about 30 seconds to prewarm on a cold launch.
  The server does not listen until this one-time JIT/graphics work is complete;
  Thongpari Fly Neuron Sim reconnects automatically meanwhile.

## Simulation rates

- Preserved standalone Thongpari Fly Neuron Sim `--simtest`: 157 us per simulated ms for
  16-step batches (about 6.4x realtime capacity); 416 us for 1-step batches.
- Full `run_flygym.sh --flygym` after the Python body-loop pacing fix:
  observed Metal windows of 655, 433, and 363 us per simulated ms. All are
  inside the 1,000 us realtime budget.
- FlyGym physics intentionally caps at 20 x 0.1 ms MuJoCo steps per 60 Hz body
  tick in the final vision-enabled configuration. Simulation time therefore
  runs well below wall time; this is deliberate so the brain/body exchange does
  not accumulate an unbounded physics backlog on the 8 GB M2.
- Viewer state sync is limited to every sixth body tick (about 10 FPS), with
  shadows, reflections, skybox, fog, haze, and side UIs disabled.
- FlyGym's default 512x450 eye Retina reduced body feedback to about 38 Hz on
  this machine. The current 96x84 Retina preserves the eye cameras/FOV while
  leaving substantially more headroom for the 60 Hz bridge loop. At the final
  96x84 setting, the visual stimulus expansion probe measured mean stereo target
  occupancy rising from about 0.52% at 60 mm to 2.85% at 30 mm, 7.38% at 18 mm,
  and 15.50% at 12 mm; the corresponding decoder looming rose
  from 0 to ~0.75, ~0.94, and ~0.98.

## Memory and CPU

During the full viewer-enabled launch:

```text
FlyGym bridge: 195216 KiB RSS, nice 15, about 62.5% CPU
ThongpariFlyNeuronSim: 162816 KiB RSS, nice  0, about 10.0% CPU
Combined:      358032 KiB RSS (about 350 MiB)
```

The bridge is launched at niceness +10 so the 1 kHz Metal brain remains the
priority under contention.
