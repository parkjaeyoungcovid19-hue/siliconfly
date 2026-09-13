# Virtual Fly Lab V9 — 같은 세션 이어하기·개체 이식·기록 재생

작성: 2026-09-13 · 상태: **PLANNED / NOT IMPLEMENTED BY THIS DOCUMENT UPDATE**

선행: **V8 완료 후에만 착수**. 병렬로 다음 버전 기능을 구현하거나 버전 순서를 바꾸지 않는다.

[전체 순서](VIRTUAL_FLY_LAB_ROADMAP.md) · [공통 사용자 경험·계약](INTERACTIVE_FLY_SANDBOX_PLAN.md) · [공통 실행·검증 규칙](IMPLEMENTATION_PLAYBOOK.md)

## 1. 이번 버전의 단 하나의 결과

파리와 세계의 전체 상태를 저장하고 새 앱에서 이어하며, 관찰 재생/재실행/분기를 명확히 구분한다.

## 2. 시작 전 반드시 확인할 것

V8까지 모든 state owner가 목록화되어야 한다. seed만 저장하는 방식은 불합격이다.

1. 저장소 루트에서 git status와 이전 버전 완료 보고서를 읽는다. 미커밋 사용자 변경을 보존한다.
2. 이전 보고서의 자동 검증/real backend/GUI 검증을 따로 확인한다. 실패를 무시하고 진행하지 않는다.
3. 아래 신규 파일은 설계 후보다. 같은 책임의 파일이 이미 있으면 그것을 확장하고 중복 구현하지 않는다.
4. API는 현재 설치 source로 확인한다. 아래 타입명은 새 계약 제안이며 이미 존재하는 심볼로 가정하지 않는다.

## 3. 수정할 파일과 책임

| 파일 | 책임 |
|---|---|
| `CheckpointStore.swift (신규)` | barrier/GPU drain/atomic 저장과 restore transaction |
| `IndividualManifest.swift (신규)` | individual/lineage/instance identity |
| `ExperimentReplay.swift (신규)` | observation playback/reexecute/branch 분리 |
| `flygym_bridge/state_checkpoint.py (신규)` | 설치된 MuJoCo state API 검증/직렬화 |
| `MetalSim.swift, SensoryModel.swift, MotorReadout.swift` | 동적 state snapshot/restore API |
| `ExperimentRecorder.swift, LabWindow.swift` | chunk commit/recovery 및 저장·열기 UI |

## 4. 데이터 계약 — UI보다 먼저 정의

공통 envelope의 session/epoch/seq/tick과 simulation-owner 규칙을 유지한다. 필수 값 누락/NaN/잘못된 배열 길이는 실패해야 한다. optional telemetry와 필수 control 필드의 허용 정책을 구분한다.

### CheckpointManifest

schema/runtime/device/config/dataset/asset/module hashes, session/individual/lineage/instance IDs, committed tick, complete flag, chunk hashes.

### NeuralState

membrane/refractory/excitation/inhibition ring/index, sim tick/seed, current/pending stim 잔여 tick, group EMA/GF latch/gate/arousal schedule.

### WorldControllerState

MuJoCo integration state, controller RNG/phase/adaptation, world timers/fields, player pose/input release policy, sensory frame/filter history, pending command disposition.

### RestoreMode

session_restore는 전체 동일 world 재개; transplant는 새 world에 뇌/개체 이식하고 환경 의존 current 제거; observation_only는 state 실행 없음.

## 5. 구현 순서 — 위에서 아래로 실행

각 단계는 해당 출력과 검사 증거를 만든 후 다음 단계로 넘어간다. 전체 파일을 한 번에 새로 쓰는 방식은 피한다.

### 9.1. state inventory

**할 일:** 각 owner의 변경되는 필드를 코드에서 수집하고 직렬화 대상/재생성 가능/버려야 함으로 분류한다. 근거 없이 재생성 가능 처리하지 않는다.

**완료 출력:** 필드→저장 위치→검사 대응표.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V9.1` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 9.2. 정체성 정의

**할 일:** 동일 checkpoint 재개는 individual 유지/new instance, clone은 new individual/parent lineage다. transplant 사건을 기록한다.

**완료 출력:** UI에 이어하기/복제/이식이 구별됨.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V9.2` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 9.3. 일관 snapshot

**할 일:** 양쪽 agreed tick pause→GPU 완료→immutable 복사→임시 저장→hash 검증→atomic rename. 실패 중에는 이전 checkpoint 삭제 금지.

**완료 출력:** half-written 파일은 complete가 아님.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V9.3` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 9.4. restore staging

**할 일:** 버전/배열/shape/dtype/hash/module 지원을 모두 확인 후 commit한다. raw neuron index가 dataset mismatch면 거부한다. epoch 증가로 이전 packet 폐기.

**완료 출력:** 실패 시 live session 보존.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V9.4` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 9.5. 재개 동등성

**할 일:** 고정 환경에서 uninterrupted 실행과 중간 저장/새 프로세스 재개를 비교한다. 누락 state가 드러나면 tolerance를 넓혀 숨기지 않는다.

**완료 출력:** 동일 runtime neural state/spike 일치; physics 허용오차 사전 정의.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V9.5` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 9.6. 기록 형식 분리

**할 일:** 보기는 저장 관측만 재생, 재실행은 초기 checkpoint+tick 입력, 분기는 checkpoint 이후 계산한다. 없는 상태를 보간 복원하지 않는다.

**완료 출력:** V2 CSV는 observation_only.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V9.6` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 9.7. 이식/모듈/실패 복구

**할 일:** 다른 built-in world에 이식할 때 world-relative sensory/held action을 해제한다. restore 미지원 외부 endpoint는 전체 continuation 불가 표시. disk full/부분 chunk recovery 제공.

**완료 출력:** 모듈 미지원에서 가짜 성공 없음.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V9.7` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

## 6. 실패·취소·복구

저장 상태는 recording/stopping/saved/failed를 구분한다. 디스크 가득 참/모듈 응답 없음/복원 불일치는 성공 표시 없이 현재 세션을 보존하고 재시도 경로를 제공한다.

공통 규칙: 실패한 명령은 applied로 표시하지 않는다. 이전 정상 파일/세션을 먼저 삭제하지 않는다. timeout은 무한 재시도로 숨기지 않는다. UI는 오류 원인과 재시도 가능한 작업을 보여준다. queue drain/ACK가 완료되지 않으면 saved/paused/detached 성공을 추정하지 않는다.

## 7. 이번 버전에서 만들지 않는 것

서로 다른 physics 버전/하드웨어에서 bit-exact를 무조건 약속하지 않는다. 클라우드 계정/마켓플레이스는 제외한다.

## 8. 검증 시나리오 — 실행과 예상 결과

| ID | 실행 방법 | 합격 조건 |
|---|---|
| V9-01 continuation | 고정 seed에서 A 연속 실행, B 중간 checkpoint→새 프로세스→동일 tick. | neural/필터 state 일치, physics 오차 기준 준수. |
| V9-02 음성 대조 | seed만 restore하거나 inhibition ring 누락 fixture. | continuation 검사가 반드시 실패. |
| V9-03 손상 파일 | hash/배열/버전 불일치 및 저장 중 종료. | 완전 저장으로 열지 않음, 기존 정상 파일 유지. |
| V9-04 이식 | 활성 바람/접촉 중 저장된 개체를 다른 arena로 이식. | identity/neural 보존, 옛 환경 current/packet 제거. |
| V9-05 기록 종류 | V2 CSV와 complete checkpoint를 각각 열기. | CSV에는 이어하기 제공 안 함. |
| V9-06 실제 GUI | 저장→앱 종료→다시 열기→이어하기→분기. | 명확한 메뉴 구분, 실제 새 프로세스 검증. |

검사 코드는 이 표의 동작과 실패 조건을 검증해야 한다. 구현의 상수를 복사하여 항상 통과하는 테스트를 만들지 않는다. 실행 명령은 공통 playbook에 따라 구현 후 실제 존재하는 test entry를 기록한다. 아직 만들지 않은 테스트 명령을 이미 실행 가능한 것으로 보고하지 않는다.

## 9. 완료 체크리스트

- [ ] 위 구현 단계와 각 출력이 모두 존재한다.
- [ ] schema/단위/상태 소유권과 실제 코드가 일치한다.
- [ ] 버전별 정상·실패 검사와 필요한 기존 회귀가 실제 exit 0이다.
- [ ] 실제 backend와 새 GUI 프로세스의 사용자 동선을 확인했다. headless를 GUI 검증으로 표시하지 않았다.
- [ ] 저장/기록/큐/모듈 상태를 추가했다면 snapshot/cleanup inventory도 갱신했다.
- [ ] 성능 기준 및 실제 측정, unsupported/제약이 Viewer와 문서에 일치한다.
- [ ] 기존 사용자 변경을 보존했고 실행한 프로세스/시험 자원을 정리했다.
- [ ] `docs/reports/V9_COMPLETION_REPORT.md`에 명령/exit/로그/파일/한계/rollback을 남겼다.

## 10. 다음 버전에 넘길 내용

V10에 새 환경 field/날씨 RNG가 추가될 때 checkpoint inventory를 확장하는 절차와 continuation fixture를 전달한다.

보고서의 마지막에는 완료한 세부 단계 ID, 남은 결함, 재실행 명령, schema 버전, fixture 경로, 실제 GUI 검증 여부를 적는다. V9의 실패가 있으면 다음 버전은 시작하지 않는다. 연구 근거 부족과 코드 결함을 구별하되, 사용자 목표의 미완료를 숨기지 않는다.
