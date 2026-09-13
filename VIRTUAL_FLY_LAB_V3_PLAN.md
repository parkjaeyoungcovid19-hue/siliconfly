# Virtual Fly Lab V3 — 안정화와 최소 모듈 경계

상태: **IMPLEMENTATION COMPLETE / USER VALIDATION PENDING** · 완료: 2026-09-13
기준 커밋: `447f7e234f91ec44da4e2e68ada50a00859f4375`

현재 진행: A–E 구현과 자동/real-headless 회귀는 완료했다. 커밋 `31bd106`에 대한 독립 검증에서 발견된 recorder 실패 시 Quit 승인(P1)과 10× 늦은 source expiry 허용(P2)도 후속 수정 및 fault-injection 재검증을 완료했다. 실제 viewer+GUI 시작/연결 smoke도 완료했다. 기록 중 정상 메뉴 Quit의 마지막 물리적 메뉴 조작은 사용자가 별도로 검증하기로 했으므로 구현 완료와 외부 검증을 분리한다. 정확한 결과와 한계는 `V3_COMPLETION_REPORT.md`와 `V3_VERIFICATION_REPORT_2026-09-13.md`에 기록한다.

## 1. 이번 버전의 목표

**V2에서 확인된 실패와 배포·기록 문제를 해결하고, 현재 동작을 유지한 채 감각/운동 코드의 최소 경계를 분리한다.** 새 기능을 한꺼번에 만들지 않는다.

사용자의 궁극적 목표는 실제 초파리에 가까운 감각–신경계–몸–환경 폐루프, 뉴런 활동 탐색, 외부 world/tool/record/individual 교환이다. 그 목표는 [장기 로드맵](VIRTUAL_FLY_LAB_ROADMAP.md)의 V3–V16+로 나눴다. **외부 파일 가져오기, 개체 저장·복원, 새 뉴런 UI, 습도·미각은 V3 완료 조건이 아니다.**

이전 습도·미각 중심 V3 계획은 각각 V12/V13의 기능 계획으로 이동했다. 그 전에 모듈/시간/상태/관측 기반을 검증한다. 필요한 경우 버전 수를 더 늘린다.

## 2. 착수 전 확인된 문제

2026-09-13 원본 커밋에서 검증했다. 자세한 명령/한계는 [최종 점검 보고서](V2_FINAL_AUDIT_2026-09-13.md)를 따른다.

| 우선순위 | 근거 | V3에서 처리할 일 |
|---|---|---|
| P1 | `--gpucheck` exit 1, scenario C/H의 group mismatch. 막전위·spikes·refractory는 일치. `RefSim`은 기존 1–8 그룹만 지정하고 Metal은 V2 감각 그룹도 지정 | 독립 CPU 기준에 정확한 V2 receptor group 규칙/집계 반영; 전체 그룹 차이를 출력; 기존 비교를 삭제해서 통과시키지 않기 |
| P1 | real TCP `--labloop` 자극 만료 검사 실패. 테스트는 400 ms wall sleep 후 판정, backend는 simulation dt로 source timer 감소 | source command의 적용 simulation time/만료와 fresh body를 확인하는 테스트로 변경; runtime 누락 여부도 함께 확인; 무조건 timeout만 늘리지 않기 |
| P1 | `ExperimentRecorder.stop()`은 비동기 close, `LabWindow`는 바로 `saved` 표시, 앱 Quit은 `NSApplication.terminate` 직접 호출 | stopping/saved/failed completion과 정상 앱 종료 drain 구현; 파일 쓰기 오류를 UI에 전달 |
| P2 | `build.sh`는 `ThongpariFlyNeuronSim`, `Makefile`은 `SiliconFly` 실행 | Make target/문서 executable 정합성; 옛 로컬 바이너리가 있어도 신버전을 실행하도록 검증 |
| P2 | README는 full validated로 설명하지만 이번 검사에 실패가 있고 dependency 전체 lock/clean setup 증거가 없음 | 검증 상태를 커밋/일자/기기로 구분, 개인 venv symlink 없이 clean setup 확인, dependency 버전 기록 |

## 3. 변경하지 않을 모델 계약

- FlyWire v783 binary, 뉴런 수, Role ID, connectome weight/model gain, `LIF.metal` 계산은 그대로 둔다. 오류 증거가 있어 수정이 필요해지면 별도 작은 수정 단계와 GPU reference 검증을 먼저 정의한다.
- 실험 중인 사용자 데이터와 로컬 환경을 보존한다. test recording은 임시 폴더를 사용한다.
- preset을 원하는 행동이 나오도록 조율하지 않는다. 자연 감각, modeled drive, direct-neural의 구분을 유지한다.
- CPU 검증기는 GPU의 group buffer를 그대로 읽어 자신의 기대값으로 사용하지 않는다. 데이터와 독립 규칙에서 기대값을 계산한다.
- V3에서 새 package format, lockstep runtime, checkpoint serializer, 자산 converter, plugin loader를 구현하지 않는다.

## 4. 작은 변경 단위와 순서

각 단계는 독립 검증 후 다음으로 넘어간다. 안정화와 리팩터링은 서로 다른 변경 단위다. 필요하면 V3.0 안정화 / V3.1 경계 분리로 출시한다.

### A. GPU 검증 기준 수리

대상: `GPUCheck.swift`; 실제 오류 증거가 없으면 `MetalSim.swift`/shader는 수정하지 않는다.

1. `MetalSim.Group` 및 exact cell-type + side + outgoing row 필터를 목록화한다.
2. CPU 기준에 누락된 food/thermo/wind histogram 정의를 독립적으로 구현한다.
3. 진단 출력에서 1–8뿐 아니라 실제로 비교하는 0–15 그룹의 차이와 이름을 표시한다.
4. 같은 seed로 C/H와 전체 `--gpucheck`를 통과시킨다. weights 0 mismatch, 기존 spike/membrane/refractory 검사도 유지한다.
5. 감각 group histogram 기대값을 의도적으로 틀린 fixture/음성 대조로 검사기가 실패함을 확인한다.

### B. 실제 bridge 만료 확인

대상: `FlyGymBridge.swift`의 `runLabLoopTest`; 원인이 runtime이면 해당 `bridge.py`/`lab_world.py` 경로만 좁게 수정한다.

1. command ack, body packet `t`, source strength, packet generation/age를 실패 로그에 남긴다.
2. natural source timer가 사용하는 simulation-time 기준으로 만료를 관찰한다. wall deadline은 test hang 방지용이다.
3. 느린 backend·일시 지연에서도 만료 이전 false failure가 없어야 한다. backend가 timer를 갱신하지 않는 경우에는 여전히 실패해야 한다.
4. mock와 real headless TCP loop를 순차 실행한다. 실제 viewer/GUI smoke는 별도 수행한다.
5. 자신이 시작한 bridge만 종료하고 기존 사용자 listener에 연결해 world를 reset하지 않는다.

### C. 기록 종료의 완료 보장

대상: `ExperimentRecorder.swift`, `LabWindow.swift`, `main.swift` 종료 lifecycle, 관련 lab tests.

1. recorder의 append/stop/start/close 순서를 하나의 소유 queue 또는 원자적 상태 전이로 관리한다.
2. `stop(completion:)` 또는 동등 API를 제공하고 마지막 event·write·close가 끝난 뒤 결과를 반환한다.
3. UI는 `stopping`을 표시한 뒤 성공 시 `saved`, 실패 시 파일 경로와 오류를 표시한다.
4. 정상 Quit 요청 시 기록 종료 완료 후 앱 종료를 재개한다. UI thread를 무기한 block하지 않는다.
5. 빠른 stop→start, pending append와 stop, 쓰기 실패, 기록 중 정상 Quit을 테스트한다. 성공 처리 전에 손실된 tail이 없어야 한다.
6. full checkpoint/crash replay 포맷은 V5/V11에서 다룬다. V3는 기존 CSV/event 파일 lifecycle만 고친다.

### D. 배포 경로와 검증 문서

대상: `Makefile`, `README.md`, `LAUNCHERS.md`, 필요한 launcher 좁은 수정.

1. 신 executable 경로로 맞추고 `make -n run` 및 실제 실행을 검증한다.
2. `git archive` 등 별도 깨끗한 임시 checkout에서 빌드·경로 검사를 수행한다. 기존 `SiliconFly`나 상위 venv symlink가 성공을 가리지 않게 한다.
3. Python 3.12 dependency 버전과 실제 설치 목록을 기록하고 fresh venv로 README 절차를 검증한다. 개인 Homebrew 경로는 필수값으로 강제하지 않는다.
4. full GUI/real viewer 시작·연결·자극·종료 smoke 결과를 날짜/기기와 함께 기록한다.
5. 자동 회귀는 stdlib/mock/문서 계약을 우선 구성하고 Metal/MuJoCo 검사는 검증 가능한 Mac 환경에서 실행한다. GPU 없는 CI를 GPU 통과로 표시하지 않는다.

### E. 기존 동작의 최소 모듈 경계

A–D가 통과한 뒤에만 진행한다. 대상은 `main.swift`의 modeled sensory transform과 `SignalBuilder`, 기존 `neural_decoder.py`다.

1. 현재 source→drive와 rate→command 함수/상태의 소유자를 문서화한다.
2. 감각 변환을 작은 `SensoryModel.swift`로 옮기고, 필요할 때만 motor readout을 별도 파일로 추출한다. 상수/계산 순서/시간/gate를 동시에 바꾸지 않는다.
3. 입력/출력 타입과 `clear/reset` 경계만 정의한다. 범용 플러그인 framework나 미래 backend loader를 만들지 않는다.
4. `build.sh`에 새 Swift 파일을 추가한다. same seed + same input sequence로 분리 전후 drive/command/neural 결과의 parity를 확인한다.
5. 추출 규모가 커지면 E를 V3.1로 분리한다. 실패한 상태에서 checkpoint/world 기능을 시작하지 않는다.

## 5. 검증 및 완료 기준

[장기 로드맵 §12](VIRTUAL_FLY_LAB_ROADMAP.md#12-검증-매트릭스와-성능)의 기존 회귀 전체를 실행한다. GPU와 timing-sensitive 검사는 부하를 겹치지 않게 순차 실행한다.

- [x] A: `--gpucheck` C/H 포함 전체 exit 0, 비교의 독립성 유지.
- [x] B: mock/real TCP loop 정상 만료 확인, 느린 wall-time simulation 허용, bounded simulation-time window 적용. timer 정지·10× 지연·0.1× 조기 종료 음성 대조는 모두 실패 탐지.
- [x] C: 저장 완료 이후에만 saved, recorder quit-drain tail 유지. 저장 실패 시 자동 Quit을 취소하고 오류/경로를 유지하며 `Quit Anyway`의 명시적 선택만 종료를 허용. 성공/실패 reply 정책 회귀 통과. 실제 메뉴 조작 E2E는 사용자 수동 검증으로 분리.
- [x] D: clean checkout 실행 경로 및 fresh venv setup 검증, 실제 GUI/real viewer 시작·연결 smoke, 검증 문서 갱신. 정상 메뉴 조작은 사용자 수동 검증으로 분리.
- [x] E: `SensoryModel.swift` / `MotorReadout.swift` 최소 추출, V2 formula parity + same-seed downstream neural parity, 기존 회귀 전체 통과.
- [x] 사용 데이터와 gain/shader 의미에 의도하지 않은 변경 없음.
- [x] `V3_COMPLETION_REPORT.md`에 파일·기준 SHA·명령·exit code·기기·한계·rollback 절차를 남김.

완료 보고서는 실제 구현 때 생성한다. **이 계획 파일을 수정했다는 사실은 V3 구현 완료가 아니다.** 확인된 실패가 남아 있으면 다음 기능 버전으로 넘어가지 않는다.

## 6. 다음 버전 인계

V4에서는 시간/epoch/lockstep만 다룬다. V5는 session checkpoint, V6는 개체 교환·이식, V7/V8은 외부 world/mesh, V9는 도구, V10은 정확 뉴런 탐색, V11은 기록 교환·재생, V12/V13은 감각, V14 이후는 생물학 검증·전신 신경계 연구다. 자세한 계약은 장기 로드맵에서 해당 버전 착수 시 필요한 부분만 꺼내 구체화한다.
