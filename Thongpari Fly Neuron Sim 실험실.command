#!/bin/zsh

set -u
cd "$(dirname "$0")"

echo "🧪 Thongpari Fly Neuron Sim Virtual Fly Lab 시작"
echo "- FlyGym / MuJoCo 3D body"
echo "- Whole-brain Metal simulation"
echo "- Lab controls / telemetry / recording"
echo

./run_flygym.sh --flygym
STATUS=$?

echo
if [ "$STATUS" -ne 0 ]; then
  echo "실험실이 종료되었습니다. exit code: $STATUS"
  echo "위 오류를 확인한 뒤 아무 키나 누르면 창을 닫습니다."
  read -k 1
fi

exit "$STATUS"
