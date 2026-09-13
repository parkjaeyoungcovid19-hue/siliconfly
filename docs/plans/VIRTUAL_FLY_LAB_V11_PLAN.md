# Virtual Fly Lab V11 — 욕구·정서·각성 해석 모델

작성: 2026-09-13 · 상태: **PLANNED / NOT IMPLEMENTED BY THIS DOCUMENT UPDATE**

선행: **V10 완료 후에만 착수**. 병렬로 다음 버전 기능을 구현하거나 버전 순서를 바꾸지 않는다.

[전체 순서](VIRTUAL_FLY_LAB_ROADMAP.md) · [공통 사용자 경험·계약](INTERACTIVE_FLY_SANDBOX_PLAN.md) · [공통 실행·검증 규칙](IMPLEMENTATION_PLAYBOOK.md)

## 1. 이번 버전의 단 하나의 결과

뉴런 활동을 욕구·정서 관련·각성 범주로 해석하여 상호작용마다 이해 가능한 상태를 보여준다.

## 2. 시작 전 반드시 확인할 것

V7 정확 관측 및 V10 환경 입력과 annotation 증거가 있어야 한다. 새 생물학적 mapping은 primary source 검증 없이는 구현하지 않는다.

1. 저장소 루트에서 git status와 이전 버전 완료 보고서를 읽는다. 미커밋 사용자 변경을 보존한다.
2. 이전 보고서의 자동 검증/real backend/GUI 검증을 따로 확인한다. 실패를 무시하고 진행하지 않는다.
3. 아래 신규 파일은 설계 후보다. 같은 책임의 파일이 이미 있으면 그것을 확장하고 중복 구현하지 않는다.
4. API는 현재 설치 source로 확인한다. 아래 타입명은 새 계약 제안이며 이미 존재하는 심볼로 가정하지 않는다.

## 3. 수정할 파일과 책임

| 파일 | 책임 |
|---|---|
| `StateDecoder.swift (신규)` | 관측→해석, 읽기 전용, versioned 계산 |
| `InternalStateModel.swift (신규)` | 에너지/수분/휴식 관련 모델 state |
| `data/annotations/functional_groups.json (신규)` | 근거 있는 membership/출처/unknown |
| `NeuralGroupRegistry.swift` | overlap/unknown 및 dataset 검증 |
| `BrainInspector.swift, LabWindow.swift` | 욕구/정서/각성 카드·근거 상세 |
| `CheckpointStore.swift, ExperimentRecorder.swift` | decoder/filter/내부상태 저장 및 재현 |

## 4. 데이터 계약 — UI보다 먼저 정의

공통 envelope의 session/epoch/seq/tick과 simulation-owner 규칙을 유지한다. 필수 값 누락/NaN/잘못된 배열 길이는 실패해야 한다. optional telemetry와 필수 control 필드의 허용 정책을 구분한다.

### InternalState

model_version, tick, energy/hydration/rest 관련 typed value와 단위, update inputs, provenance. 실제 생체 측정이 아닌 모델 상태.

### StateEstimate

category, value 또는 null, unit, valid/unsupported/insufficient_data/stale, evidence_tier, contributing_groups, window, decoder_version.

### FunctionalAnnotation

dataset/root IDs, role tags, primary source URL/annotation revision, 종/조건, mapping rationale. 이름만 보고 감정 group 지정 금지.

### InterpretationEvidence

event_id, observed delta, normalized index, source/baseline, alternative causes, confidence_policy. 교정하지 않은 확률 표시 금지.

## 5. 구현 순서 — 위에서 아래로 실행

각 단계는 해당 출력과 검사 증거를 만든 후 다음 단계로 넘어간다. 전체 파일을 한 번에 새로 쓰는 방식은 피한다.

### 11.1. 분류 목록과 근거 표

**할 일:** 각성, 위협/회피, 운동/감각은 기존 코드부터 조사한다. 배고픔/갈증/피로/보상/혐오는 primary evidence와 dataset membership을 검증한다.

**완료 출력:** 지원/후보/근거 부족을 분리한 registry.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V11.1` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 11.2. 체내 상태와 neural 추정 분리

**할 일:** energy와 hunger estimate를 서로 다른 필드로 만든다. 단순 odor proximity를 hunger로 쓰지 않는다. body 소모/섭취가 미지원이면 모델 가정을 명시하거나 계산을 비활성화한다.

**완료 출력:** 환경 자극과 욕구 수치가 동의어가 아님.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V11.2` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 11.3. 모델 하나씩 구현

**할 일:** 먼저 각성/위협 관련 지표를 정규화하고 다음 욕구를 하나씩 추가한다. update equation/단위/시간상수/initial condition을 명시한다.

**완료 출력:** 각 모델에 고정 fixture 및 known baseline.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V11.3` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 11.4. 읽기 전용 해석 경로

**할 일:** decoder output을 neural input으로 다시 보내지 않는다. 생리 feedback은 별도 명시 모델로 구현하고 대조를 추가한다.

**완료 출력:** 카드 표시만 켜고 꺼도 neural state 동일.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V11.4` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 11.5. 불확실성 규칙

**할 일:** evidence tier와 valid state를 구현한다. overlap/unclassified를 허용하고 모든 뉴런을 강제 감정 분할하지 않는다. calibration 안 된 80% 행복 같은 값은 금지한다.

**완료 출력:** unknown은 null/이유, 0으로 가장하지 않음.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V11.5` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 11.6. 사건별 설명 연결

**할 일:** V7 event analysis에 관련 욕구 지표 변화와 근거를 붙인다. 직접 행동/감정 원인 단정은 개입 대조가 있는 경우에만 제한적으로 표시한다.

**완료 출력:** 설명 문장에서 관측과 모델 추정이 구분됨.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V11.6` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 11.7. 상태 저장/카드 UI

**할 일:** decoder baseline/filters와 내부state를 checkpoint에 추가한다. 카드→그룹→root ID→근거까지 펼쳐 볼 수 있게 한다.

**완료 출력:** 새 프로세스 이어하기에서 해석 불연속 없음.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V11.7` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

## 6. 실패·취소·복구

근거 없는 범주는 추정치를 꾸미지 않고 미완료로 유지한다. 기술 구현 완료와 생물학적 검증 완료를 별도 표기하고 V12 검증 대상으로 넘긴다.

공통 규칙: 실패한 명령은 applied로 표시하지 않는다. 이전 정상 파일/세션을 먼저 삭제하지 않는다. timeout은 무한 재시도로 숨기지 않는다. UI는 오류 원인과 재시도 가능한 작업을 보여준다. queue drain/ACK가 완료되지 않으면 saved/paused/detached 성공을 추정하지 않는다.

## 7. 이번 버전에서 만들지 않는 것

파리의 주관적 생각/의식 읽기, 인간 감정 분류를 전뇌에 억지 적용, 설명용 LLM의 사실 없는 내면 독백은 제외한다.

## 8. 검증 시나리오 — 실행과 예상 결과

| ID | 실행 방법 | 합격 조건 |
|---|---|
| V11-01 식/단위 | 각 decoder 고정 fixture/경계/NaN 입력. | 명시한 식과 일치, 불량값은 invalid. |
| V11-02 source 누락 | 미지원 hunger와 annotation mismatch. | 숫자 0/확률 대신 미지원 이유 표시. |
| V11-03 feedback 대조 | 카드/decoder 켬·끔 동일 seed 실행. | 읽기 전용이면 neural trajectory 동일. |
| V11-04 감각/욕구 분리 | 냄새만 올리고 체내 입력 고정. | hunger를 냄새값 복사로 계산하지 않음. |
| V11-05 기록 동등성 | checkpoint에서 decoder EMA/baseline 재개. | 연속 실행의 해석값과 일치. |
| V11-06 GUI 설명 | 접근/온도/먹이 사건을 각각 선택. | 측정/추정/미지원, contributing groups/근거가 조회됨. |

검사 코드는 이 표의 동작과 실패 조건을 검증해야 한다. 구현의 상수를 복사하여 항상 통과하는 테스트를 만들지 않는다. 실행 명령은 공통 playbook에 따라 구현 후 실제 존재하는 test entry를 기록한다. 아직 만들지 않은 테스트 명령을 이미 실행 가능한 것으로 보고하지 않는다.

## 9. 완료 체크리스트

- [ ] 위 구현 단계와 각 출력이 모두 존재한다.
- [ ] schema/단위/상태 소유권과 실제 코드가 일치한다.
- [ ] 버전별 정상·실패 검사와 필요한 기존 회귀가 실제 exit 0이다.
- [ ] 실제 backend와 새 GUI 프로세스의 사용자 동선을 확인했다. headless를 GUI 검증으로 표시하지 않았다.
- [ ] 저장/기록/큐/모듈 상태를 추가했다면 snapshot/cleanup inventory도 갱신했다.
- [ ] 성능 기준 및 실제 측정, unsupported/제약이 Viewer와 문서에 일치한다.
- [ ] 기존 사용자 변경을 보존했고 실행한 프로세스/시험 자원을 정리했다.
- [ ] `docs/reports/V11_COMPLETION_REPORT.md`에 명령/exit/로그/파일/한계/rollback을 남겼다.

## 10. 다음 버전에 넘길 내용

V12에 모델별 식/가정/dataset/primary 출처/calibration 여부/미결 항목과 고정 실험 fixture를 전달한다.

보고서의 마지막에는 완료한 세부 단계 ID, 남은 결함, 재실행 명령, schema 버전, fixture 경로, 실제 GUI 검증 여부를 적는다. V11의 실패가 있으면 다음 버전은 시작하지 않는다. 연구 근거 부족과 코드 결함을 구별하되, 사용자 목표의 미완료를 숨기지 않는다.
