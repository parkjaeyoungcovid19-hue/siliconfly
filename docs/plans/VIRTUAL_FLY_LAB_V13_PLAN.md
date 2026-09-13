# Virtual Fly Lab V13 — 게임형 상호작용 성능·사용성·복구

작성: 2026-09-13 · 상태: **PLANNED / NOT IMPLEMENTED BY THIS DOCUMENT UPDATE**

선행: **V12 완료 후에만 착수**. 병렬로 다음 버전 기능을 구현하거나 버전 순서를 바꾸지 않는다.

[전체 순서](VIRTUAL_FLY_LAB_ROADMAP.md) · [공통 사용자 경험·계약](INTERACTIVE_FLY_SANDBOX_PLAN.md) · [공통 실행·검증 규칙](IMPLEMENTATION_PLAYBOOK.md)

## 1. 이번 버전의 단 하나의 결과

통합 기능을 장시간 사용할 수 있고 조작이 즉시 이해되며 느린 backend에서도 상태를 정확히 보여준다.

## 2. 시작 전 반드시 확인할 것

V12의 기능/해석 claim 범위가 고정되어야 한다. 최적화 전에 같은 장면/seed/기기의 baseline을 측정한다.

1. 저장소 루트에서 git status와 이전 버전 완료 보고서를 읽는다. 미커밋 사용자 변경을 보존한다.
2. 이전 보고서의 자동 검증/real backend/GUI 검증을 따로 확인한다. 실패를 무시하고 진행하지 않는다.
3. 아래 신규 파일은 설계 후보다. 같은 책임의 파일이 이미 있으면 그것을 확장하고 중복 구현하지 않는다.
4. API는 현재 설치 source로 확인한다. 아래 타입명은 새 계약 제안이며 이미 존재하는 심볼로 가정하지 않는다.

## 3. 수정할 파일과 책임

| 파일 | 책임 |
|---|---|
| `tools/profile_interactive.py (신규)` | 반복 가능한 workload/latency/queue 측정 |
| `WorldViewer.swift, LabWindow.swift` | 입력 피드백·접이식 패널·키보드/접근성 |
| `NeuralObservation.swift, FlyGymBridge.swift` | sampling/backpressure/resource budget |
| `ExperimentRecorder.swift, CheckpointStore.swift` | 장시간 기록/디스크 오류 복구 |
| `docs/reports/V13_PERFORMANCE_UX_REPORT.md (신규)` | 기준/최적화/실제 동선/실패 증거 |

## 4. 데이터 계약 — UI보다 먼저 정의

공통 envelope의 session/epoch/seq/tick과 simulation-owner 규칙을 유지한다. 필수 값 누락/NaN/잘못된 배열 길이는 실패해야 한다. optional telemetry와 필수 control 필드의 허용 정책을 구분한다.

### PerformanceSample

machine/runtime/resolution, wall+sim duration, viewport FPS, input acknowledgement/applied latency p50/p95, body sim/wall ratio, sensory Hz, queue occupancy/drop, RSS.

### QualityPolicy

graphics/observations/recording budget는 독립. deterministic tick 생략 금지; degradation 상태와 원인을 UI에 표시.

### RecoveryCase

trigger/failure_state/preserved_data/retry/expected neutral action/log location.

### UXChecklist

keyboard focus, drag 대체, labels/units, contrast, reduced motion, menu discoverability, no hidden terminal step.

## 5. 구현 순서 — 위에서 아래로 실행

각 단계는 해당 출력과 검사 증거를 만든 후 다음 단계로 넘어간다. 전체 파일을 한 번에 새로 쓰는 방식은 피한다.

### 13.1. 기준 workload 측정

**할 일:** 작은 arena, 복잡 terrain/weather, 뇌 inspector, 기록+module fixture 조건을 각각 측정한다. idle만 측정해 전체 성능으로 보고하지 않는다.

**완료 출력:** 재현 가능한 profile manifest.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V13.1` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 13.2. 목표 확정

**할 일:** 초기 목표 viewport≥30FPS, 입력 접수 p95≤100ms, 카드10Hz를 기준 장비에서 검토한다. body 실시간 비율과 별도로 보고한다. 미달 시 원인/개선안을 기록한다.

**완료 출력:** 목표를 조용히 낮추지 않음.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V13.2` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 13.3. 병목만 최적화

**할 일:** GPU 관측 복사/eye rendering/UI layout/socket/recording 비용을 분리한다. 효과 확인된 부분만 batch/aggregate/backpressure로 수정한다.

**완료 출력:** 전후 동일 실험 state/결과 parity.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V13.3` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 13.4. 긴 실행 검사

**할 일:** 10분 단계 후 30분 soak를 실행한다. memory slope/queue max/drop/입력 latency를 저장한다.

**완료 출력:** 무제한 backlog/메모리 증가 없음.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V13.4` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 13.5. 실제 사용성 점검

**할 일:** 새 프로세스에서 참여/편집/사건 선택/저장/모듈 분리까지 GUI로 수행한다. 드래그 대체 수치/버튼, 키보드 focus, reduced motion을 확인한다.

**완료 출력:** 문서나 터미널 없이 핵심 동선 완료.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V13.5` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 13.6. 고장 복구

**할 일:** backend crash, stuck module, disk full, corrupt scene, focus loss, pause 중 reconnect를 주입한다. 정상 데이터 보존/held action 해제/명확한 오류를 확인한다.

**완료 출력:** 실패 후 안전한 재시도 또는 종료 가능.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V13.6` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 13.7. 회귀와 문서

**할 일:** 최적화 변경에 맞는 neural/GPU/physics 회귀를 순차 수행하고 현재 지원 범위/성능 설정을 사용자 가이드에 반영한다.

**완료 출력:** 성능 개선이 의미 변경을 숨기지 않음.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V13.7` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

## 6. 실패·취소·복구

느려지면 표시 품질을 조절하거나 simulated time을 늦추며 정확도를 유지한다. 줄어든 sensor/관측 빈도를 숨기지 않는다. 성능 목표 미달을 GUI smoke 성공으로 대체하지 않는다.

공통 규칙: 실패한 명령은 applied로 표시하지 않는다. 이전 정상 파일/세션을 먼저 삭제하지 않는다. timeout은 무한 재시도로 숨기지 않는다. UI는 오류 원인과 재시도 가능한 작업을 보여준다. queue drain/ACK가 완료되지 않으면 saved/paused/detached 성공을 추정하지 않는다.

## 7. 이번 버전에서 만들지 않는 것

새 게임 모듈/감정 모델/새 물리 모델을 최적화 작업에 섞지 않는다.

## 8. 검증 시나리오 — 실행과 예상 결과

| ID | 실행 방법 | 합격 조건 |
|---|---|
| V13-01 부하 비교 | 정해진 모든 workload의 baseline/수정 후 실행. | p50/p95/FPS/ratio와 기기 기록, 선택적 결과 누락 없음. |
| V13-02 bounded | 느린 consumer와 high-rate input을 장시간 입력. | queue/memory 상한, 손실 명시, discreet 사건 조용한 유실 없음. |
| V13-03 결정론 유지 | 렌더 품질/창 크기를 바꿔 같은 tick 실험 실행. | 신경/실험 결과 parity. |
| V13-04 접근성 | 키보드만으로 선택/편집/취소/저장. | focus가 보이고 drag-only 조작 없음. |
| V13-05 장애 | 기록 중 disk 오류와 endpoint crash. | 잘못된 saved/connected 표시 없음, 기존 파일 유지. |
| V13-06 soak | 30분 통합 실행. | 기준 내 지연/메모리/queue; 실패하면 완료 아님. |

검사 코드는 이 표의 동작과 실패 조건을 검증해야 한다. 구현의 상수를 복사하여 항상 통과하는 테스트를 만들지 않는다. 실행 명령은 공통 playbook에 따라 구현 후 실제 존재하는 test entry를 기록한다. 아직 만들지 않은 테스트 명령을 이미 실행 가능한 것으로 보고하지 않는다.

## 9. 완료 체크리스트

- [ ] 위 구현 단계와 각 출력이 모두 존재한다.
- [ ] schema/단위/상태 소유권과 실제 코드가 일치한다.
- [ ] 버전별 정상·실패 검사와 필요한 기존 회귀가 실제 exit 0이다.
- [ ] 실제 backend와 새 GUI 프로세스의 사용자 동선을 확인했다. headless를 GUI 검증으로 표시하지 않았다.
- [ ] 저장/기록/큐/모듈 상태를 추가했다면 snapshot/cleanup inventory도 갱신했다.
- [ ] 성능 기준 및 실제 측정, unsupported/제약이 Viewer와 문서에 일치한다.
- [ ] 기존 사용자 변경을 보존했고 실행한 프로세스/시험 자원을 정리했다.
- [ ] `docs/reports/V13_COMPLETION_REPORT.md`에 명령/exit/로그/파일/한계/rollback을 남겼다.

## 10. 다음 버전에 넘길 내용

V14에 정확한 테스트 기기/실행 옵션/회귀 결과/지원 효과/알려진 한계와 복구 runbook을 전달한다.

보고서의 마지막에는 완료한 세부 단계 ID, 남은 결함, 재실행 명령, schema 버전, fixture 경로, 실제 GUI 검증 여부를 적는다. V13의 실패가 있으면 다음 버전은 시작하지 않는다. 연구 근거 부족과 코드 결함을 구별하되, 사용자 목표의 미완료를 숨기지 않는다.
