#!/bin/zsh
# One-script launch: venv bridge (mock or real) + Thongpari Fly Neuron Sim --flygym.
# Usage: ./run_flygym.sh [--mock|--flygym]   (default: --flygym)
cd "$(dirname "$0")"
MODE="${1:---flygym}"
if [ ! -x flygym-venv/bin/python ]; then
  echo "no flygym-venv — create it first (see flygym_bridge/README.md)" >&2
  exit 1
fi
if [ "$MODE" = "--flygym" ]; then
  # The venv path contains spaces, so mjpython's shebang cannot be executed
  # directly by macOS. Run the trampoline through the venv interpreter.
  ./flygym-venv/bin/python ./flygym-venv/bin/mjpython flygym_bridge/bridge.py "$MODE" &
else
  ./flygym-venv/bin/python flygym_bridge/bridge.py "$MODE" &
fi
BRIDGE_PID=$!
cleanup() { kill $BRIDGE_PID 2>/dev/null; }
trap cleanup EXIT INT TERM
sleep 2
./ThongpariFlyNeuronSim --flygym
