# Virtual Fly Lab V12 — 행동·욕구 해석의 타당성 검증

작성: 2026-09-13 · 상태: **PLANNED / NOT IMPLEMENTED BY THIS DOCUMENT UPDATE**

선행: **V11 완료 후에만 착수**. 병렬로 다음 버전 기능을 구현하거나 버전 순서를 바꾸지 않는다.

[전체 순서](VIRTUAL_FLY_LAB_ROADMAP.md) · [공통 사용자 경험·계약](INTERACTIVE_FLY_SANDBOX_PLAN.md) · [공통 실행·검증 규칙](IMPLEMENTATION_PLAYBOOK.md)

## 1. 이번 버전의 단 하나의 결과

그럴듯한 화면을 넘어 실제 측정과 모델 해석의 근거·한계를 재현 가능한 대조 실험으로 검증한다.

## 2. 시작 전 반드시 확인할 것

V11 모델별 식과 annotation 출처가 존재해야 한다. 이 버전은 전신 신경계 교체 작업이 아니다.

1. 저장소 루트에서 git status와 이전 버전 완료 보고서를 읽는다. 미커밋 사용자 변경을 보존한다.
2. 이전 보고서의 자동 검증/real backend/GUI 검증을 따로 확인한다. 실패를 무시하고 진행하지 않는다.
3. 아래 신규 파일은 설계 후보다. 같은 책임의 파일이 이미 있으면 그것을 확장하고 중복 구현하지 않는다.
4. API는 현재 설치 source로 확인한다. 아래 타입명은 새 계약 제안이며 이미 존재하는 심볼로 가정하지 않는다.

## 3. 수정할 파일과 책임

| 파일 | 책임 |
|---|---|
| `benchmarks/manifest.json (신규)` | 사전 정의 조건/metric/허용오차/seed/source |
| `tools/run_benchmarks.py (신규)` | 고정 실험 실행과 관측 수집 |
| `tools/analyze_benchmarks.py (신규)` | latency/rate/행동 분포와 불확실성 |
| `fixtures/benchmarks/ (신규)` | 입력과 예상 contract, 데이터 라이선스 |
| `docs/reports/V12_VALIDITY_REPORT.md (신규)` | 실제 결과/대조/실패/미지원 |
| `StateDecoder.swift, functional_groups.json` | 근거에 따른 좁은 수정, 버전 변경 |

## 4. 데이터 계약 — UI보다 먼저 정의

공통 envelope의 session/epoch/seq/tick과 simulation-owner 규칙을 유지한다. 필수 값 누락/NaN/잘못된 배열 길이는 실패해야 한다. optional telemetry와 필수 control 필드의 허용 정책을 구분한다.

### BenchmarkCase

case_id/species/sex/condition, primary_source/data_license, initial checkpoint/config, tick inputs, seeds, measurements, acceptance bounds, tuning_or_holdout.

### ControlCase

baseline/no-input, same-seed perturbation, receptor/DN silence 또는 supported zero-weight control, controller-only comparison.

### Result

sample count, exclusions with reason, latency/rate/trajectory metrics, intervals, machine/model hashes, missingness, pass/fail/inconclusive.

### EvidenceDisposition

각 주장에 supported/limited/unsupported 및 GUI label 변경/미결 처리 연결.

## 5. 구현 순서 — 위에서 아래로 실행

각 단계는 해당 출력과 검사 증거를 만든 후 다음 단계로 넘어간다. 전체 파일을 한 번에 새로 쓰는 방식은 피한다.

### 12.1. 원자료 선택

**할 일:** looming/odor orientation/contact/gait와 V11 상태 관련 primary 데이터를 찾고 종/성별/조건을 기록한다. 유사한 논문 제목만으로 같은 실험으로 취급하지 않는다.

**완료 출력:** 출처·조건·라이선스·사용 가능 데이터 확인.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V12.1` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 12.2. 합격 기준 사전 고정

**할 일:** metric/창/표본 수/허용 오차를 결과를 보기 전에 정한다. 최소 5 고정 seed를 시작점으로 하되 충분성은 원자료 변동성 기준으로 결정한다.

**완료 출력:** benchmark manifest revision 동결.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V12.2` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 12.3. 대조 실험

**할 일:** no-input/같은 seed/제거 대조를 실행한다. 지원되지 않는 perturbation은 정식 API+단위 검사 후 실행하며 가짜 silence를 만들지 않는다.

**완료 출력:** connectome 기여와 controller-only 효과 비교.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V12.3` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 12.4. holdout 검증

**할 일:** 튜닝용과 평가용 조건/seed를 분리한다. 결과가 원하는 행동이 아니어도 보고하고 평가 데이터를 보고 gain을 조절하지 않는다.

**완료 출력:** 개선과 검증 데이터가 섞이지 않음.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V12.4` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 12.5. 분류 교정

**할 일:** 확률을 제시하려는 모델만 별도 calibration 지표를 계산한다. 교정 실패면 확률 UI를 제거하고 제한된 모델 지표로 표시한다.

**완료 출력:** 근거 수준과 UI 표현 일치.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V12.5` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 12.6. 실패 항목 처리

**할 일:** 코드 결함/모델 한계/증거 부족을 분류한다. 코드 결함은 좁게 수정 후 관련 회귀; 모델 한계는 수치/출처와 함께 남긴다.

**완료 출력:** 모든 실패에 disposition 존재.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V12.6` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 12.7. 보고서와 라벨 동기화

**할 일:** Viewer/문서/manifest의 지원 범위가 같은지 검사한다. 미해결 핵심 항목을 전체 검증 완료로 포장하지 않는다.

**완료 출력:** V13 이전 제품 claim 범위 확정.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V12.7` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

## 6. 실패·취소·복구

원자료 부족은 코드 성공으로 메우지 않는다. 완료 보고서에는 검증 수행 완료와 해당 생물학적 주장의 미검증을 별개로 적는다. 핵심 사용자 목표의 미달은 V14에서도 남겨야 한다.

공통 규칙: 실패한 명령은 applied로 표시하지 않는다. 이전 정상 파일/세션을 먼저 삭제하지 않는다. timeout은 무한 재시도로 숨기지 않는다. UI는 오류 원인과 재시도 가능한 작업을 보여준다. queue drain/ACK가 완료되지 않으면 saved/paused/detached 성공을 추정하지 않는다.

## 7. 이번 버전에서 만들지 않는 것

BANC/VNC backend 전면 교체, 학습/비행 새 연구는 V14 이후 별도 계획이다.

## 8. 검증 시나리오 — 실행과 예상 결과

| ID | 실행 방법 | 합격 조건 |
|---|---|
| V12-01 재현 | 같은 manifest로 새 프로세스 2회 실행. | 정해진 deterministic fields/오차 범위 일치. |
| V12-02 대조 유효 | 의도적으로 입력 연결을 끊은 fixture. | 검증기가 효과 상실을 탐지. |
| V12-03 데이터 분리 | seed/조건의 tuning-holdout 목록 비교. | 누수 없음, exclusion 근거 보존. |
| V12-04 지표 검증 | 알려진 작은 synthetic 결과로 latency/count 계산. | 계산 단위/통계 방법 정확. |
| V12-05 근거 UI | unsupported 판정된 category를 Viewer에서 열기. | 근거 부족/제한 표시, 허위 confidence 없음. |

검사 코드는 이 표의 동작과 실패 조건을 검증해야 한다. 구현의 상수를 복사하여 항상 통과하는 테스트를 만들지 않는다. 실행 명령은 공통 playbook에 따라 구현 후 실제 존재하는 test entry를 기록한다. 아직 만들지 않은 테스트 명령을 이미 실행 가능한 것으로 보고하지 않는다.

## 9. 완료 체크리스트

- [ ] 위 구현 단계와 각 출력이 모두 존재한다.
- [ ] schema/단위/상태 소유권과 실제 코드가 일치한다.
- [ ] 버전별 정상·실패 검사와 필요한 기존 회귀가 실제 exit 0이다.
- [ ] 실제 backend와 새 GUI 프로세스의 사용자 동선을 확인했다. headless를 GUI 검증으로 표시하지 않았다.
- [ ] 저장/기록/큐/모듈 상태를 추가했다면 snapshot/cleanup inventory도 갱신했다.
- [ ] 성능 기준 및 실제 측정, unsupported/제약이 Viewer와 문서에 일치한다.
- [ ] 기존 사용자 변경을 보존했고 실행한 프로세스/시험 자원을 정리했다.
- [ ] `docs/reports/V12_COMPLETION_REPORT.md`에 명령/exit/로그/파일/한계/rollback을 남겼다.

## 10. 다음 버전에 넘길 내용

V13에 검증된 claim 범위, benchmark 실행 비용/기준 workload, 허용 성능 저하 및 회귀 fixture를 전달한다.

보고서의 마지막에는 완료한 세부 단계 ID, 남은 결함, 재실행 명령, schema 버전, fixture 경로, 실제 GUI 검증 여부를 적는다. V12의 실패가 있으면 다음 버전은 시작하지 않는다. 연구 근거 부족과 코드 결함을 구별하되, 사용자 목표의 미완료를 숨기지 않는다.
