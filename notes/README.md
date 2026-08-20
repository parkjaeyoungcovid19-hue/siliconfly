# notes/ — the whole-brain port's working reports

Working notes from porting DesktopFly's sim from a 668-neuron CPU circuit to the
full FlyWire v783 connectome (139,255 neurons) on the GPU. They were written
during the port, while the project was still called DesktopFly, and are left
verbatim: the transcripts here are captured terminal output, so `./DesktopFly`
in them is today's `./SiliconFly`. They record what was
measured and why each number is what it is; they are not user documentation
(that is `README.md`) and not agent instructions (that is `CLAUDE.md`).

| file | contents |
|---|---|
| `01-recon.md` | recon: candidate edge sets, neuron inventory, degree structure, GPU footprint, webgpu-fly + fly-brain design summaries, port recommendations |
| `02-etl.md` | the ETL: binary layout (the loader's contract), run output, every count reconciled, in-degree onto each command population, `verify_data.py` results |
| `03-metal-sim.md` | the Metal sim: loading, fixed point, per-step semantics, RNG, buffers, batching, test hooks, first measurements, open risks |
| `04-gpucheck.md` | GPU vs an independent CPU reference: bit-exactness results, batch/stim invariance, synaptic-delay and gait probes, the fma finding |
| `05-tuning.md` | first tuning pass: the diagnosis, the per-super-class resting-drive table, iterations, final numbers, what stayed fragile |
| `06-tuning-2.md` | re-tuning after the antennal-lobe sign fix: noise granularity as the lever, the giant fiber's three input gains, the shipped parameter table, SignalBuilder mapping |
| `07-brainview.md` | the brain window at full scale: 139,255-point cloud, spike sampling, bounded click clusters, cost |
| `08-fixpass.md` | code-quality fix pass on the finished port, zero behavior change (bit-exactness re-verified after each item) |
| `09-docs.md` | this docs pass: what `README.md` / `CLAUDE.md` now claim and where every number came from |
| `docs-runs.txt` | the diagnostic capture behind the current README/CLAUDE numbers (`--simtest`, `--brainstats 4`, `--gpucheck`, `--behaviortest`, `verify_data.py`) |
| `brainshot*.png` | brain-window renders from the tuning and BrainView passes (`before`/`after`, `tuned`/`tuned2`) |
| `tuning-runs/` | raw `--brainstats` / `--simtest` captures from every tuning iteration |

See also `../WRITEUP.md` — the full narrative writeup of the port (state before, what was done, state now, future directions).
