# V3 독립 검증 — 2026-09-13

대상: `31bd106` (Complete Virtual Fly Lab V3 stabilization), 기준 V2 `447f7e2`.

## 판정

**기본 회귀와 이전 GPU/TCP 실패는 해결됐지만, 최종 완료 승인 전 2개 항목을 보완해야 한다.** 이번 검증은 구현 소스를 수정하지 않고 재빌드, 회귀 재실행, 소스 대조, 독립 fault injection으로 수행했다.

## 발견 사항

### [P1] 저장에 실패해도 정상 Quit을 그대로 승인

위치: `main.swift:1236–1242`, `LabWindow.swift:840–850`.

`applicationShouldTerminate`의 `.failed` 분기는 stderr 로그만 남긴다. 이후 결과와 관계없이 `reply(toApplicationShouldTerminate: true)`를 실행한다. 디스크 부족/I/O 실패 등으로 recorder가 실패를 돌려줘도 앱은 종료된다. LabWindow에 잠깐 넣는 실패 문자열도 종료되는 창과 함께 사라져, 사용자가 실패를 확인하거나 대응할 수 없다.

코드 경로에서 확인한 문제이며 이번에 실제 사용자 디스크를 가득 채우거나 기록 손실을 일으키지는 않았다. 현재 `--labtest`의 write failure 테스트는 recorder 결과만 확인하고, quit-drain 테스트는 `stop(reason: "application quit")`만 호출한다. AppDelegate의 terminateLater/reply와 실패 시 종료 여부는 테스트하지 않는다.

수정 권고: 실패면 종료를 취소하고 persistent 오류를 표시한다. 이미 쓴 파일은 보존하고 가능한 복구/내보내기와 명시적인 종료 선택을 제공한다. 성공과 실패를 모두 AppKit 종료 경로에서 검증한다. 이미 손실된 queued sample을 재시도만으로 복구할 수 있다고 주장하지 않는다.

### [P2] 만료 검사가 10배 늦은 자극 종료를 정상으로 통과시킴

위치: `FlyGymBridge.swift:1275–1290`.

검사는 목표 simulation time을 넘은 뒤에도 자극이 0이 될 때까지 12초 wall deadline 동안 기다린다. simulation-time 상한이 없어 지나치게 늦은 종료도 합격한다.

독립 mock server에서 `set_wind`/`apply_touch`의 `duration_ms`만 **10배**로 바꿨다. production repo는 수정하지 않고 임시 process wrapper로 주입했다. 요청 300ms가 실제 3000ms가 되었는데 `--labloop`는 **exit 0 / LABLOOP PASS**였다. 로그의 목표 `t=0.5086s`, 실제 통과 `t=3.1220s`다.

반대로 `pre_step(dt)`를 `pre_step(0)`으로 바꿔 timer를 완전히 멈춘 대조는 exit 1로 정상 탐지했다. 따라서 고장 탐지가 전혀 없는 것은 아니지만 “정확한 만료” 검증은 부족하다.

수정 권고: command 적용 simulation tick 또는 각 source 시작 tick과 duration에서 만료를 정하고, physics step/telemetry cadence에 근거한 제한된 오차만 허용한다. 타이머 정지·10배 지연·조기 종료를 각각 거부하고, 느린 wall-time 진행은 허용해야 한다.

[10배 지연을 놓친 로그](../../notes/validation/v3-independent-2026-09-13/labloop_tenfold_duration.txt), [타이머 정지 탐지 로그](../../notes/validation/v3-independent-2026-09-13/labloop_frozen.txt). 재현 스크립트는 같은 폴더의 `fault_server.py`, `fault_verify.py`다. 빈 17841 포트에서 저장소 루트 경로를 인자로 실행한다.

## 재실행한 검사

Apple M2에서 순차 수행했다. 이전 완료 보고서의 출력 재사용이 아닌 이번 실행이다.

| 검사 | 결과 |
|---|---|
| `./build.sh` | exit 0 |
| `git archive HEAD`의 깨끗한 사본 빌드 | exit 0; 옛 binary/venv 없이 새 executable 생성 |
| `--bridgetest` | exit 0 |
| `--labtest` | exit 0; 추출 전후 parity, recorder success/failure/tail 포함 |
| `--simtest` | exit 0; 16-step batch 111 µs/step 관측 |
| `--behaviortest` | exit 0 |
| `--gpucheck` | exit 0; 이전 C/H 통과, quantized weight mismatch 0 |
| `tools/verify_data.py --no-parquet` | exit 0; 원본 parquet 대조는 생략 |
| Python `test_bridge.py`, `test_lab.py` | 모두 exit 0 |
| preset validator | exit 0, 11 presets |
| `test_lab_real.py`, `test_vision_real.py` | 모두 exit 0 |
| mock TCP `--labloop` | exit 0 |
| real-headless TCP `--labloop` | exit 0 |
| 고장 주입: simulation timer 정지 | exit 1, 기대한 실패 탐지 |
| 고장 주입: 자극 duration 10배 | **exit 0, 잘못된 통과** |

각 로그: `notes/validation/v3-independent-2026-09-13/`.

## 범위 및 문서 대조

- `LIF.metal`, `MetalSim.swift`, `Sim.swift`, `data/`, `fly_body.py`, `neural_decoder.py`는 V2 기준 대비 변경이 없다. 감각/운동 수식 추출은 해당 parity 검사도 통과했다.
- `make -n run`은 `./build.sh` 다음 `./ThongpariFlyNeuronSim`을 실행한다. 옛 이름 문제는 수정됐다.
- 원격 `personal/master`는 조회 시 `447f7e2`, 로컬은 `31bd106`으로 1 commit 앞서 있다. V3 GitHub 업로드 완료 상태가 아니다. 이번에도 push하지 않았다.
- 완료 보고서의 rollback 절은 “V3 commit 미생성”이라고 하지만 현재 commit이 있으므로 현 상태와 다르다.
- V3 plan의 완료 체크와 별개로 위 두 사항을 먼저 보완하는 것이 적절하다. 단위 recorder 성공 검사를 AppKit 전체 Quit 검증으로 취급하지 않는다.
- 실제 GUI 메뉴의 기록→Quit, 새 venv dependency 설치는 이번 자동 재검증으로 대체되지 않는다. 전체 GUI 종료 검증이 남았다는 기존 보고서의 한계를 유지한다.

## 다음 작업

P1 실패 종료 처리 → P2 만료 판정 및 음성 대조 → 정상/실패 AppKit Quit E2E → 관련 회귀 및 완료 문서 정합성 확인 순서로 마무리한다. V4 기능 구현은 이 검증 보완과 분리한다.

## 후속 수정 결과

위 보고서 작성 후 같은 2026-09-13 작업 트리에서 P1/P2를 수정했다. 원래 발견 내용은 검증 이력으로 그대로 보존한다.

- **P1 수정:** recorder drain이 `.failed`이면 `applicationShouldTerminate`가 더 이상 자동으로 `true`를 reply하지 않는다. Lab 창을 다시 표시하고 실패 메시지와 부분 기록 경로를 유지한 채 `Keep App Open`(기본) / `Quit Anyway`를 명시적으로 선택하게 했다. 실제 AppDelegate가 사용하는 termination reply 정책을 순수 함수로 분리해 `--labtest`에서 성공 시 prompt 없이 terminate, 실패 시 keep-open=false reply, 명시적 override에서만 true reply가 나오는 것을 검증했다.
- **P2 수정:** `--labloop` expiry 검사를 단순 “목표 이후 언젠가 0”에서 **bounded simulation-time window**로 변경했다. 첫 active body packet의 `simTime`과 실제 `simDt`를 이용해 300 ms 요청의 허용 오차를 계산하며, source가 너무 빨리 0이 되거나 상한을 넘도록 계속 active면 즉시 실패한다. wall deadline은 여전히 hang guard일 뿐 합격 범위가 아니다.
- **fault injection 재검증:** 정상 mock 및 real-headless는 PASS. `pre_step(0)` timer freeze, duration 10×, duration 0.1×는 모두 `--labloop` exit 1로 탐지됐다. 10× 사례는 이전처럼 약 3 s까지 기다리지 않고 허용 simulation-time 상한을 넘는 즉시 실패한다.
- **전체 회귀:** `--bridgetest`, `--labtest`, `--simtest`, `--behaviortest`, `--gpucheck`, data verifier, Python bridge/lab/preset, real lab, real vision이 모두 다시 exit 0이었다.
- **문서 정합성:** `docs/reports/V3_COMPLETION_REPORT.md`의 “V3 commit 미생성” 문구를 실제 구현 커밋 `31bd106` 기준 rollback 절차로 수정했다.

남은 항목은 사용자가 별도로 수행하기로 한 **실제 GUI 메뉴에서 recording 중 Quit을 직접 누르는 수동 smoke**다. 자동 회귀는 성공/실패 termination reply 정책을 검증하지만, 이 보고서는 물리적 메뉴 클릭까지 수행했다고 주장하지 않는다.
