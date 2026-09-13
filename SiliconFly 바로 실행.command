#!/bin/zsh

set -u
cd "$(dirname "$0")"

echo "🪰 SiliconFly + FlyGym 실행 중..."
echo "- MuJoCo/FlyGym 실제 몸"
echo "- 양안 시각 looming → LC4/LPLC2"
echo "- Metal whole-brain sim"
echo

./run_flygym.sh --flygym
STATUS=$?

echo
if [ "$STATUS" -ne 0 ]; then
  echo "실행이 종료되었습니다. exit code: $STATUS"
  echo "에러 내용을 확인한 뒤 아무 키나 누르면 창을 닫습니다."
  read -k 1
fi

exit "$STATUS"
