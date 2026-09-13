# V4–V14 공통 구현·검증·인수인계 규칙

이 문서는 버전별 상세 계획과 함께 읽는다. 상태: 설계 문서. 기능 구현이나 테스트 완료 증거가 아니다.

## 1. 작업 시작 위치와 정본

실제 Git 저장소는 workspace 안의 `siliconfly/`다. 아래 명령은 그 저장소를 현재 디렉터리로 사용한다. 상위 workspace의 `flygym_bridge/` 복사본이나 `docs/workspace-legacy/`를 활성 소스로 오인하지 않는다. 실행 스크립트가 실제로 가리키는 경로는 현재 파일에서 확인한다.

```sh
pwd
git status --short
git log -3 --oneline
rg --files -g 'AGENTS.md' -g 'CLAUDE.md'
```

`CLAUDE.md`, 이 로드맵, 현재 버전 계획, 직전 완료 보고서 순서로 읽는다. 로컬 파일에 적힌 과거 모델/오케스트레이션 조건을 현재 모델과 혼동하지 않는다. 기존 dirty 변경의 파일/책임을 파악하고 덮어쓰거나 일괄 rollback하지 않는다.

## 2. 한 버전의 진행표

각 버전 착수 시 `docs/reports/VN_PROGRESS.md`를 만든다. N은 실제 버전 번호로 대체한다. 계획 수정 단계에서 미래 버전의 진행을 구현 중으로 표시하지 않는다.

| 단계 ID | 요구 | 상태 | 변경 파일 | 실행 검사/로그 | 실패/다음 조치 |
|---|---|---|---|---|---|
| VN.1 | 상세 계획의 첫 단계 | planned | 미정 | 미실행 | 선행 확인 |

허용 상태:

- `planned`: 아직 구현하지 않음.
- `implementing`: 코드/계약 작업 중이며 완료 검증 전.
- `automated_verified`: 해당 자동 검사가 실제 통과함. GUI를 대신하지 않음.
- `gui_verified`: 새 프로세스 실제 사용자 동선 확인.
- `complete`: 해당 단계의 필수 자동/실제/문서/성능 gate 충족.
- `blocked`: 구체적 선행 조건이 없어 진행 못 함. 원인/필요 입력/보존 상태 기록.

단계 종료마다 표를 갱신한다. 대화가 중단되어도 다음 구현자가 마지막 complete 다음 행에서 시작할 수 있어야 한다. context가 부족해지면 현재 파일/실패/재실행 명령을 남긴다. 처음부터 전부 재작성하지 않는다.

## 3. 모든 기능의 입력부터 출력까지

기능마다 아래 여섯 항목을 먼저 기록한다.

1. 사용자 행동: 어떤 모드에서 무엇을 누르는가.
2. 명령: 필요한 ID·단위·유효 범위·요청 tick은 무엇인가.
3. 상태 소유자: Swift session, Python world, neural backend 중 누가 실제 변경하는가.
4. 적용 경계: live tick, pause 편집 transaction, recompile 중 무엇인가.
5. 결과: actual_value/applied_tick/오류를 누가 반환하는가.
6. 화면/기록: pending과 applied를 어떻게 구별하고 어떤 event를 저장하는가.

이 중 하나라도 없다면 UI부터 만들지 않는다. 클릭 후 화면만 변하고 physics는 그대로인 구현을 막기 위한 규칙이다.

## 4. 시간·단위·소유권 불변식

- Neural 기본 tick은 현재 1 ms다. V4 quantum은 현재 20 ticks이며 협상한 physics step으로 정확히 나누어져야 한다.
- `sim_tick`과 wall time을 혼용하지 않는다. wall 시간은 성능/수신 freshness/사람용 시각에만 사용한다.
- deterministic mode에서 느려지면 simulated time 진행을 늦춘다. tick을 건너뛰거나 긴 wall stall을 실험 시간으로 보정하지 않는다.
- session/epoch가 다른 packet은 현재 상태를 바꾸지 못한다. reconnect transport generation은 session epoch와 별도다.
- geometry는 현재 world 단위 mm와 축 규약을 명시한다. texture/mesh/외부 모듈은 변환을 한 경계에서만 수행한다.
- UI는 immutable snapshot을 읽는다. Python MuJoCo 상태는 simulation-owner에서만 변경한다.
- 연속 입력은 coalesce 가능하나 discrete 사건은 무음 유실 금지다. 모든 queue에 크기와 overflow 정책이 있다.
- 물리 상태를 변경하는 사용자 avatar와 관찰 카메라를 구분한다. pause 중 카메라 탐색은 계속할 수 있다.
- 읽기 전용 뉴런 선택/상태 해석은 뇌 입력을 변경하지 않는다. direct neural 자극은 별도 경로다.

## 5. 새 계약을 추가하는 순서

1. 필수/optional 필드, 단위, 범위, lifecycle, 오류 코드를 작은 문서 또는 schema로 쓴다.
2. 유효 fixture와 최소 3종 불량 fixture(필수 누락/범위 오류/old epoch)를 만든다.
3. Swift encode/decode와 Python encode/decode를 대조한다. JSON의 64비트 neuron root ID는 문자열로 유지한다.
4. backend 적용 함수를 먼저 연결하고 무변경 실패를 검사한다.
5. UI를 명령/ACK에 연결한다. 낙관 preview는 pending으로 표시한다.
6. recorder에 요청/적용/실패 관계를 추가한다.
7. 동적 상태가 생겼으면 checkpoint inventory를 수정한다. V9 이전에는 future-state 목록에 기록하고 V9에서 모두 구현한다.
8. 테스트와 사용 동선을 기록하고 다음 기능으로 넘어간다.

새 타입 이름은 계약 제안이다. 기존 같은 책임 타입이 있으면 확장하며 이름만 다른 중복 상태 소유자를 만들지 않는다. 전체 신규 파일 목록을 버전 시작 시 빈 stub으로 일괄 생성하지 않는다.

## 6. 실험 데이터와 해석의 정확성

`physical`, `sensory_model`, `direct_neural`, `controller_model`, `observed`, `state_estimate` 출처를 구별한다. 예: 바람으로 몸이 밀림은 실제 물리 변화일 수 있지만 도피 뉴런이 움직임을 결정했다는 증거가 아니다.

뉴런 rate에는 집계 창/EMA tau, 뉴런 수, 뉴런당 평균인지 합계인지 기록한다. sampled animation에서 exact count를 만들지 않는다. 상태 분류에는 dataset membership/출처/version/validity가 있어야 한다. 미구현/미측정은 null 또는 unsupported다. 0은 실제 유효한 측정 0일 때만 사용한다.

새 생물학적 주장과 receptor/감정 mapping은 primary source/annotation을 직접 확인한 뒤 출처를 기록한다. 구현 계획의 후보 기능 이름은 과학적 입증이 아니다. 실제 생각을 문장으로 읽어냈다고 말하지 않는다.

## 7. 검사 실행법

아래는 현재 저장소의 기존 명령이다. 실행 전 `build.sh`와 `main.swift` dispatch, Python 파일 존재를 확인한다. future 버전의 test entry는 구현자가 작성 후 보고서에 정확한 명령을 추가한다.

```sh
./build.sh
./ThongpariFlyNeuronSim --bridgetest
./ThongpariFlyNeuronSim --labtest
./ThongpariFlyNeuronSim --v4test
./ThongpariFlyNeuronSim --v4timingtest
./flygym-venv/bin/python flygym_bridge/test_v4.py
./ThongpariFlyNeuronSim --simtest
./ThongpariFlyNeuronSim --behaviortest
./ThongpariFlyNeuronSim --gpucheck
./flygym-venv/bin/python tools/verify_data.py --no-parquet
./flygym-venv/bin/python flygym_bridge/test_bridge.py
./flygym-venv/bin/python flygym_bridge/test_lab.py
./flygym-venv/bin/python flygym_bridge/validate_experiment_presets.py
./flygym-venv/bin/python flygym_bridge/test_lab_real.py
./flygym-venv/bin/python flygym_bridge/test_vision_real.py
```

모든 명령을 무조건 매 문서 편집마다 실행하는 뜻은 아니다. 코드 변경 때 범위에 맞춰 실행한다:

| 변경 | 필수 검사 |
|---|---|
| 문서만 | 링크/버전 순서/정본/내용 정합성, 코드 무변경 확인 |
| UI만 | build, 해당 입력/focus/ACK 검사, 실제 GUI 동선 |
| protocol/session | bridge/lab/V4, mock/real TCP, epoch/duplicate/pause/timeout faults |
| neural/gain/ETL/shader | simtest+behaviortest+gpucheck, 데이터 변경 시 data verifier, 관련 감각 parity |
| physics/world/sensory | Python/real lab/vision, 실제 viewer, 시간/접촉/field 대조 |
| checkpoint/recording | 새 프로세스 continuation, 실패 저장/recovery, Quit lifecycle, 관련 회귀 |
| 버전 최종 완료 | 해당 버전 전체 gate와 기존 회귀, 실측 성능/실제 GUI 결과 |

GPU와 timing-sensitive 검사는 동시에 실행하지 않는다. timeout 자체를 합격으로 보지 않는다. stdout의 PASS와 process exit를 함께 확인한다. 간헐 실패는 재실행 결과와 원래 실패를 둘 다 보존한다.

TCP `--v4loop`/`--labloop`는 별도 backend가 필요하다. 현재 launcher와 argparse/CLI dispatch에서 실제 옵션을 먼저 확인한다. 시험 서버의 PID를 저장하고 준비 상태를 확인한 뒤 client를 실행한다. 이미 사용자 서버가 있으면 몰래 종료하지 않는다. 시험 후 자신의 PID만 종료하고 listener 잔존을 확인한다.

로그는 `notes/validation/vN-날짜/` 아래 명령별로 남긴다. 오래된 로그를 새 작업의 통과 결과로 복사하지 않는다. screenshot은 실제 수행 동선과 연결하고 사진 파일 존재만으로 기능을 통과 처리하지 않는다.

## 8. 실패를 처리하는 절차

1. 실패한 입력/seed/tick/schema/runtime과 로그를 남긴다.
2. 코드 결함인지 미지원 기능인지 모델 근거 부족인지 구분한다.
3. 재현 가능한 최소 fixture를 만든다. 검사 자체가 틀리면 원래 계약 기준으로 수정한다.
4. 해당 책임 파일만 고친다. 전체 engine 교체나 gain 조율로 증상을 숨기지 않는다.
5. 실패 fixture가 탐지→수정 후 통과하는지 확인한다. 정상 대조도 유지한다.
6. 관련 회귀를 실행하고 진행표/완료 보고서의 limitation을 갱신한다.

데이터/설정/설치/저장 형식을 교체할 때는 해당 범위 백업과 복원 방법을 먼저 만든다. `git reset --hard`, clean, 사용자 파일 삭제, 임의 force push는 작업 절차가 아니다.

## 9. 완료 보고서 형식

`docs/reports/VN_COMPLETION_REPORT.md`에 다음을 기록한다.

1. 구체적 사용자 결과와 버전 범위.
2. 기준 commit/dirty 상태, 수정 파일과 이유.
3. 추가 schema/capability/model 버전과 실제 state owner.
4. 검사 표: 명령, exit code, 로그, baseline/수정 후, 자동/real/GUI 구분.
5. 실제 새 프로세스 사용자 동선과 화면/기록 근거.
6. 성능 조건: 기기/runtime/해상도/scene/seed/sample rate와 측정값.
7. 실패/unsupported/연구 미검증 항목 및 disposition.
8. 백업/rollback/정리한 프로세스, 남긴 데이터 위치.
9. 다음 버전이 읽을 fixture/API와 정확한 재실행 명령.

완료 체크를 채우기 위해 미실행 검사를 PASS로 쓰지 않는다. 중요한 미해결 코드 실패가 있으면 버전 complete를 하지 않고 다음 버전에 착수하지 않는다.
