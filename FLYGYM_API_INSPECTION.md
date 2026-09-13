# Installed FlyGym API inspection

Inspected locally on 2026-09-12. The installed package, not remembered 1.x
examples, is authoritative for this implementation.

- Python: 3.12.14 (`flygym-venv`)
- FlyGym: 2.1.0
- MuJoCo: 3.9.0
- Installed extra: `flygym[examples]` (no RL/Warp/Torch/TensorFlow)

Relevant installed signatures:

```text
Simulation(world, *, timestep=None)
FlatGroundWorld(name='flat_ground_world', *, half_size=1000)
BaseWorld.add_fly(fly, spawn_position, spawn_rotation, *args, **kwargs)
make_locomotion_fly(name='nmf', *, ..., add_adhesion=True, ..., colorize=False)
make_tripod_cpg_network(timestep, *, intrinsic_frequency=12.0,
    intrinsic_amplitude=1.0, coupling_strength=10.0,
    convergence_coef=20.0, seed=0)
HybridTurningController(timestep, cpg_network=None, ..., enable_adhesion=True,
    legs=('lf','lm','lh','rf','rm','rh'))
HybridTurningController.step(descending_signal, obs) -> LocomotionAction
HybridControllerObservation.from_sim(sim, fly_name, *, legs=..., stumbling_links=...)
apply_locomotion_action(sim, fly_name, action, *, actuator_type=POSITION)
```

Installed `HybridTurningController.step` requires a `(2,)` left/right descending
signal. It assigns absolute signal magnitudes to the six CPG amplitudes and uses
the sign of each side to reverse that side's intrinsic frequencies. Therefore:

- forward and steering are supported through left/right differential drive;
- backward is supported cleanly by two negative channels;
- grooming, wing movement, and flight are not exposed by this locomotion
  controller and remain display/log state only.

The first world uses `FlatGroundWorld`, an actual `NeuroMechFly` produced by
`make_locomotion_fly`, a fixed MJCF box geom, and MuJoCo's passive interactive
viewer. The viewer is launched through `mjpython` on macOS.
