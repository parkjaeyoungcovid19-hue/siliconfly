# V5.1 미커밋 변경 독립 점검 — 2026-09-13

기준 HEAD: `3faf942`. 기존 미커밋 구현을 보존했고 제품 코드 수정·커밋은 하지 않았다.
판정: **수정 후 재검증 필요. V5.1 완료 판정 보류.**

## 확인된 결함

### 1. [P2] 물체가 움직이는 동안 전역 revision 비교로 picking이 거부됨

위치: `flygym_bridge/bridge.py:249-251`, `lab_world.py:646-649`.
`serve_once`는 view snapshot 생성 이후 body를 step하고 응답을 보낸다. 접근 중인 물체는 step마다 world revision을 올리므로 클라이언트가 받은 snapshot은 이미 이전 revision이다. `_validate_ray_source`는 현재 revision과 다르면 ray를 평가하지 않는다. 움직이는 물체 하나 때문에 정지 물체·바닥을 향한 ray까지 막힌다.

재현: Mock Bridge의 실제 `serve_once`를 socketpair로 실행. X=500의 box를 1 mm/s로 접근시키고 snapshot 수신 직후 하향 ray를 5회 전송. source/current revision이 2/3, 4/5, 6/7, 8/9, 10/11로 모두 `stale source world revision` 실패. `v51-audit-transport.log` 참고.

수정 방향: snapshot 출처·session·epoch 검사는 유지하되 pose 갱신과 객체 수명/형상 변경을 구분하거나, 현재 owner state에서 평가한다는 계약에 맞게 움직임을 허용한다. UI도 오류 ACK를 현재 화면 revision 일치 조건 때문에 숨기지 않아야 한다 (`LabWindow.swift:1444-1455`).

### 2. [P2] 새 연결이 이전 클라이언트의 view 결과 캐시를 재사용함

위치: `flygym_bridge/bridge.py:270-275`, `serve_once`의 연결 초기화 부분.
view 결과 키는 kind/session/epoch/seq뿐이고 새 연결에서 `recent_view_results`와 `snapshot_sources`를 비우지 않는다. 새 Swift bridge는 seq=1로 시작한다. sessionless 상태에서 앱만 재시작하면 새 요청이 이전 앱의 중복 요청으로 취급된다.

재현: 위 socket 연결을 종료하고 물체 X를 100으로 변경한 뒤 새 연결에서 snapshot seq=1 전송. 현재 X=99.995, tick=177인데 응답은 X=499.995, tick=5였다. 클라이언트는 새 연결의 신선한 패킷으로 취급한다. `v51-audit-transport.log` 참고.

수정 방향: viewer request identity를 연결 단위로 분리하거나 reconnect에서 viewer 캐시와 관련 응답 큐를 정리한다. V4 logical session 지속 규칙은 별도로 유지한다.

### 3. [P2] atomic snapshot의 파리 pose가 현재 tick보다 이전 파생 좌표일 수 있음

위치: `flygym_bridge/fly_body.py:458-464`, `ray_pick:494`.
`world_render_state`는 `mj_data.xpos/xquat`를 바로 복사하지만 ray query는 `mj_forward`를 먼저 실행한다. 실제 body step 직후 파생 좌표가 아직 최신 qpos로 갱신되지 않아 같은 tick의 두 snapshot이 picking 유무에 따라 달라진다.

재현: 실제 RealFlyBody에서 200 substeps 후 snapshot → ray_pick → snapshot 비교. simulation time=0.12340000000000251이 동일한 상태에서 thorax X=0.5446871932 → 0.5450056314, Y=-0.0020944129 → -0.0019255971로 바뀌고 quaternion도 달라졌다. 전체 xpos 최대 변화는 0.0005191377 mm. `v51-audit-observation.log` 참고.

영향은 한 physics substep 수준이지만 현재 tick의 atomic pose 및 동일 geometry picking 계약을 만족하지 않는다. owner boundary에서 snapshot과 ray에 필요한 파생 좌표를 일관되게 갱신해야 한다.

추가 대조: qpos/qvel/qacc_warmstart는 query 전후 동일했고, 복사한 MjData와 다음 `mj_step`을 비교했을 때 qpos/qvel 차이는 0이었다. 따라서 이 결과를 물리 궤적 변경으로 확대 해석하지 않는다.

## 독립 재검증

- build.sh: PASS.
- Swift bridgetest, labtest, v4test, v4timingtest, simtest, behaviortest: PASS.
- Python test_v5, test_v4, test_lab, test_bridge, test_lab_real, test_vision_real: PASS.
- git diff --check: PASS.
- GPUCHECK: PASS — 12,200 simulated ms, 538 comparison points, max|Δv|=0, 117.2 s.
- 실제 headless FlyGym과 새 GUI 프로세스 연결/실행 로그 확인. 검사 전 기존 listener가 없음을 확인하고 검사 전용 프로세스만 종료했다.

## 검증 한계 / 남은 gate

화면 제어 도구가 standalone `ThongpariFlyNeuronSim` 실행 파일을 앱 이름과 절대 경로 모두에서 `Invalid app`으로 거부했고 앱 inventory에도 노출하지 않았다. 따라서 이번 검사는 GUI 시각 대조, 실제 focus, click-to-ACK, viewport FPS를 확인했다고 주장하지 않는다. 기존 보고서의 GUI acceptance pending을 유지한다. 기존 이미지도 새 실행 증거로 사용하지 않았다.

검증 로그는 이 디렉터리에 저장했다. 전체 V5.2~V5.7 기능은 이번 V5.1 점검 범위에 포함하지 않았다.
