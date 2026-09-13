# Virtual Fly Lab V10 — 전체 지형·날씨·공간 환경 제어

작성: 2026-09-13 · 상태: **PLANNED / NOT IMPLEMENTED BY THIS DOCUMENT UPDATE**

선행: **V9 완료 후에만 착수**. 병렬로 다음 버전 기능을 구현하거나 버전 순서를 바꾸지 않는다.

[전체 순서](VIRTUAL_FLY_LAB_ROADMAP.md) · [공통 사용자 경험·계약](INTERACTIVE_FLY_SANDBOX_PLAN.md) · [공통 실행·검증 규칙](IMPLEMENTATION_PLAYBOOK.md)

## 1. 이번 버전의 단 하나의 결과

지형 mesh/heightfield와 국소 온습도·바람·날씨·냄새까지 Viewer에서 통제한다.

## 2. 시작 전 반드시 확인할 것

V9 rollback/checkpoint와 V6 descriptor가 검증되어야 한다. 범주별 효과를 동시에 구현하지 말고 아래 내부 단계를 순서대로 수행한다.

1. 저장소 루트에서 git status와 이전 버전 완료 보고서를 읽는다. 미커밋 사용자 변경을 보존한다.
2. 이전 보고서의 자동 검증/real backend/GUI 검증을 따로 확인한다. 실패를 무시하고 진행하지 않는다.
3. 아래 신규 파일은 설계 후보다. 같은 책임의 파일이 이미 있으면 그것을 확장하고 중복 구현하지 않는다.
4. API는 현재 설치 source로 확인한다. 아래 타입명은 새 계약 제안이며 이미 존재하는 심볼로 가정하지 않는다.

## 3. 수정할 파일과 책임

| 파일 | 책임 |
|---|---|
| `flygym_bridge/world_package.py (신규)` | 선언형 world/mesh import와 staged compile |
| `flygym_bridge/environment_fields.py (신규)` | 온도/RH/wind/odor의 권위 field sample |
| `flygym_bridge/weather.py (신규)` | seed/tick 기반 날씨 preset과 schedule |
| `TerrainEditor.swift (신규)` | heightfield brush, mesh preview, collision overlay |
| `WorldEditor.swift, EnvironmentProperty.swift` | 국소 source/zone·effect capability inspector |
| `SensoryModel.swift, flygym_bridge/lab_world.py` | 습도/접촉 미각·field 입력, 기존 모델과 출처 분리 |
| `CheckpointStore.swift, state_checkpoint.py` | field/날씨 동적 상태 저장 |

## 4. 데이터 계약 — UI보다 먼저 정의

공통 envelope의 session/epoch/seq/tick과 simulation-owner 규칙을 유지한다. 필수 값 누락/NaN/잘못된 배열 길이는 실패해야 한다. optional telemetry와 필수 control 필드의 허용 정책을 구분한다.

### WorldPackage

manifest/schema/hash, units/axes, static visual mesh/collision mesh, materials, terrain, sources, spawn. 임의 script/plugin 실행 없음.

### EnvironmentField

field_id/type/unit, global_value, local_sources, combine_policy, priority, clamp, sample_tick. 한 권위 sample을 renderer/sensory가 공유.

### WeatherPreset

seed, start_tick, transitions, constituent fields, visual/physical/sensory enabled effects. 이름만으로 미구현 효과를 켜지 않음.

### TasteContact

source_id/body_geom_id, start/end_tick, chemistry class/concentration, annotation provenance, receptor drive. 검증된 taste geometry 없으면 unsupported.

## 5. 구현 순서 — 위에서 아래로 실행

각 단계는 해당 출력과 검사 증거를 만든 후 다음 단계로 넘어간다. 전체 파일을 한 번에 새로 쓰는 방식은 피한다.

### 10.1. 자산 제한과 fixture

**할 일:** 정적 GLB subset/heightfield를 정하고 schema·단위·축·mesh budget을 정의한다. 작은 유효 fixture와 경로 탈출/과대/중복/손상 fixture를 만든다.

**완료 출력:** 자산 import 범위가 고정됨.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V10.1` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 10.2. 지형 편집/compile

**할 일:** brush stroke를 preview하고 pause 경계에서 staged collision compile한다. fly/player spawn 충돌 검사 후 swap한다. 실패하면 이전 world로 돌아간다.

**완료 출력:** visual/collision terrain 정합.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V10.2` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 10.3. 공간 field 기반

**할 일:** global+local zone/source 합성/우선순위/clamp를 field별로 구현한다. Viewer probe로 특정 위치 값과 source 기여를 확인한다.

**완료 출력:** 단위가 UI/physics/sensory/저장에 일치.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V10.3` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 10.4. 온습도 및 바람

**할 일:** 기존 global 모델을 field sample로 감싼다. 바람의 normalized force와 물리 풍속 모델을 구별한다. RH mapping은 실제 dataset annotation 확인 후 추가한다.

**완료 출력:** environment_only의 neural drive는 0.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V10.4` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 10.5. 냄새 수송

**할 일:** 현재 isotropic odor 모델과 새 wind transport를 mode/version으로 분리한다. 방향/확산/소멸을 fixture로 검사하고 원하는 행동을 만들려고 gain을 조절하지 않는다.

**완료 출력:** 바람 없는 대조와 풍하 sample 방향성 일치.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V10.5` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 10.6. 날씨 개별 효과

**할 일:** 맑음/흐림/안개/비/눈의 field 구성과 시각 효과를 하나씩 구현한다. 강수 접촉/젖음/열전달은 각각 물리 모델/단위/비용을 먼저 명시한다. 효과 미지원은 off+이유다.

**완료 출력:** 비 입자만으로 강수 물리 완료 표시 안 함.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V10.6` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 10.7. 미각과 source 접촉

**할 일:** 설치 anatomy와 primary annotation으로 taste-capable geometry/root IDs를 확인한다. 없으면 generic contact diagnostic만 제공하며 taste로 부르지 않는다.

**완료 출력:** 냄새만으로 taste drive가 생기지 않음.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V10.7` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

### 10.8. 저장/성능 통합

**할 일:** 날씨 seed/field timers/transport state를 checkpoint에 추가하고 재개 비교한다. 속성 전체가 Viewer에서 편집/저장되는지 inventory를 대조한다.

**완료 출력:** 코드 전용 숨은 환경 property 없음.

**다음 단계 진입 조건:** 이 출력의 정상 사례와 실패/무변경 사례를 확인하고 진행표의 `V10.8` 행에 증거를 남긴다. 검사 실패 시 같은 단계에서 원인을 수정한다.

## 6. 실패·취소·복구

지원하지 않는 자산/효과는 명시적 오류로 남긴다. 전체 환경 범주를 미지원 표시만 해두고 모두 구현 완료로 보고하지 않는다. 필요한 물리 모델이 미결이면 해당 세부 항목은 blocked로 문서화한다.

공통 규칙: 실패한 명령은 applied로 표시하지 않는다. 이전 정상 파일/세션을 먼저 삭제하지 않는다. timeout은 무한 재시도로 숨기지 않는다. UI는 오류 원인과 재시도 가능한 작업을 보여준다. queue drain/ACK가 완료되지 않으면 saved/paused/detached 성공을 추정하지 않는다.

## 7. 이번 버전에서 만들지 않는 것

완전한 CFD/기후/동물 생리 동등성은 이 버전의 암묵적 요구가 아니다. 선택 모델과 오차/지원 효과를 명시한다.

## 8. 검증 시나리오 — 실행과 예상 결과

| ID | 실행 방법 | 합격 조건 |
|---|---|
| V10-01 import 공격/손상 | 절대 경로/../symlink/zip bomb/과대 mesh fixture. | 실행/부분 import 없음, 기존 session 보존. |
| V10-02 field 합성 | 2개 겹치는 zone과 global baseline에 알려진 값을 넣는다. | 합성/우선순위/clamp가 정의값과 정확히 같음. |
| V10-03 시간 재현 | 같은 seed/tick weather를 wall stall 유무로 실행. | field sample 동일, pause에서 변화 없음. |
| V10-04 실제 효과 | rain visual-only와 물리 effect enabled를 따로 실행. | declared capability와 실제 contact/sensory 기록 일치. |
| V10-05 미각 | odor-only, 잘못된 body contact, 유효 contact, end/reset. | 유효 geometry 접촉에서만 nonzero, 종료 후 zero. |
| V10-06 GUI/restore | Viewer에서 terrain/온습도/바람/날씨/냄새 편집→checkpoint→재개. | 값/field/RNG 보존; 미지원 효과 정확히 표시. |

검사 코드는 이 표의 동작과 실패 조건을 검증해야 한다. 구현의 상수를 복사하여 항상 통과하는 테스트를 만들지 않는다. 실행 명령은 공통 playbook에 따라 구현 후 실제 존재하는 test entry를 기록한다. 아직 만들지 않은 테스트 명령을 이미 실행 가능한 것으로 보고하지 않는다.

## 9. 완료 체크리스트

- [ ] 위 구현 단계와 각 출력이 모두 존재한다.
- [ ] schema/단위/상태 소유권과 실제 코드가 일치한다.
- [ ] 버전별 정상·실패 검사와 필요한 기존 회귀가 실제 exit 0이다.
- [ ] 실제 backend와 새 GUI 프로세스의 사용자 동선을 확인했다. headless를 GUI 검증으로 표시하지 않았다.
- [ ] 저장/기록/큐/모듈 상태를 추가했다면 snapshot/cleanup inventory도 갱신했다.
- [ ] 성능 기준 및 실제 측정, unsupported/제약이 Viewer와 문서에 일치한다.
- [ ] 기존 사용자 변경을 보존했고 실행한 프로세스/시험 자원을 정리했다.
- [ ] `docs/reports/V10_COMPLETION_REPORT.md`에 명령/exit/로그/파일/한계/rollback을 남겼다.

## 10. 다음 버전에 넘길 내용

V11에 로컬 감각/체내 상태 입력 후보, 단위/효과 분리, annotation 근거와 미지원 목록을 넘긴다.

보고서의 마지막에는 완료한 세부 단계 ID, 남은 결함, 재실행 명령, schema 버전, fixture 경로, 실제 GUI 검증 여부를 적는다. V10의 실패가 있으면 다음 버전은 시작하지 않는다. 연구 근거 부족과 코드 결함을 구별하되, 사용자 목표의 미완료를 숨기지 않는다.
