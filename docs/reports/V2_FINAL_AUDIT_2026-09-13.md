# V2 최종 점검 — 2026-09-13

## 판정

**GitHub 업로드 커밋은 일치한다. 현재 V2를 모든 검증이 끝난 최종 안정판으로 판정할 수는 없다.** GPU reference 검사와 실제 TCP labloop 검사가 실패했다. 코드를 고친 것으로 보고하지 않고, 원인과 수정/검증 순서를 V3 안정화 계획에 반영했다.

- 대상 저장소: [thongpari-fly-neuron-sim](https://github.com/parkjaeyoungcovid19-hue/thongpari-fly-neuron-sim)
- 로컬 `master`, tracking `personal/master`, 원격 `git ls-remote personal refs/heads/master` 모두 `447f7e234f91ec44da4e2e68ada50a00859f4375`.
- 최초 worktree는 clean. 이번 변경은 계획·점검 문서/검증 로그다. runtime source, shader, data, model gain은 수정하지 않았다. 검증용 executable은 `build.sh`로 재빌드했다.
- `origin`은 upstream `dawsonamf/siliconfly`, 사용자 저장소는 `personal`이다. 향후 push 대상 혼동에 유의한다. 이번에 commit/push는 하지 않았다.
- 개발 폴더가 중첩되어 있으며 실제 Git 루트는 상위 작업 폴더의 `siliconfly/`다. 상위 동명 V3 계획은 이번에 정본과 동기화했다.

## 재현된 문제 (우선순위 순)

### P1 — GPU reference의 그룹 정의가 V2 관측 그룹을 반영하지 않음

근거: [`GPUCheck.swift`](../../GPUCheck.swift)의 `RefSim` init은 Role 기반 1–8 그룹만 지정한다. [`MetalSim.swift`](../../MetalSim.swift)는 그 뒤 food/thermo/wind receptor를 추가 그룹에 배정한다. `compareStep`은 전체 16그룹을 비교하지만 오류 출력은 1–8만 보여줘 양쪽이 모두 0인 것처럼 보인다.

실행: `./ThongpariFlyNeuronSim --gpucheck` → **exit 1**. C (stim)와 H (arousal burst)에서 `groups X`, `max|Δv| 0`, spikes/refractory/rates는 일치했다. 15,091,983 quantized edges는 mismatch 0. 따라서 관측된 실패는 histogram/reference 계약 불일치와 일치하며, 이 로그만으로 신경 동역학이 틀렸다고 단정할 근거는 없다. 반대로 전체 GPU 검사가 통과했다고 할 수도 없다.

수정 계획: 독립 reference의 V2 그룹 기대값 갱신, 전체 그룹 진단, 음성 대조 포함 전체 재검증. 비교 자체를 제거하거나 GPU buffer를 기대값으로 사용하지 않는다. [로그](../../notes/validation/2026-09-13/gpucheck.txt)

### P1 — 실제 TCP 통합 검사의 자극 만료 실패

실행: real headless bridge + `./ThongpariFlyNeuronSim --labloop` → **exit 1**, 동일 실패 **2회**. 두 번째는 GPU 검사가 끝난 뒤 단독으로 수행했다. spawn/state/wind/flash/touch/source telemetry/reset ACK는 성공하고 `body source clears on backend timer expiry`만 실패했다.

근거: [`FlyGymBridge.swift`](../../FlyGymBridge.swift)의 `runLabLoopTest`는 0.40초 wall sleep 후 latest body source가 0인지 검사한다. [`flygym_bridge/lab_world.py`](../../flygym_bridge/lab_world.py)는 simulation dt로 source timer를 줄인다. 실제 몸체가 실시간보다 느리거나 packet이 stale이면 이 판정은 부정확할 수 있다.

**확인된 사실은 테스트 실패와 서로 다른 시간 기준이다.** 실패 순간 body tick/age/remaining timer를 아직 계측하지 않았으므로 이것이 테스트만의 문제인지 runtime 문제까지 포함하는지 확정하지 않았다. 실제 backend의 만료 자체는 `test_lab_real.py`의 reset/expiry 검사를 통과했다. 적용 tick·만료 tick·fresh packet을 기록하는 좁은 수정 후 다시 판단해야 한다.

[최초 로그](../../notes/validation/2026-09-13/labloop.txt), [단독 재실행 로그](../../notes/validation/2026-09-13/labloop_retry.txt)

### P1 — 기록의 저장 완료/앱 종료 계약 부족

[`ExperimentRecorder.swift`](../../ExperimentRecorder.swift)의 stop은 queued write/close를 예약한 뒤 반환한다. [`LabWindow.swift`](../../LabWindow.swift)의 stopRecording은 바로 `saved`로 표시한다. write/close error는 stderr에만 기록한다. [`main.swift`](../../main.swift)의 Quit은 `NSApplication.terminate`를 직접 호출하고 recorder drain을 기다리는 종료 hook은 없다.

따라서 사용자는 저장 중이거나 저장 오류가 발생해도 저장 완료 표시를 볼 수 있으며, 기록 직후 Quit에서 pending tail이 보존되는지 보장되지 않는다. 이번에 실제 사용자 기록 손실을 재현한 것은 아니다. labtest는 `flushForTesting()`을 호출하므로 실제 UI 종료 계약의 증거를 대신하지 않는다.

V3에서 stopping/saved/failed 상태, completion callback, 정상 Quit drain 및 빠른 stop/start 검증을 먼저 구현한다.

### P2 — Make 실행 이름과 빌드 산출물 불일치

[`build.sh`](../../build.sh)는 `ThongpariFlyNeuronSim`을 생성하고 [`Makefile`](../../Makefile)의 run/fly는 `./SiliconFly`를 실행한다. `make -n run`에서 확인했다. 개발 폴더에는 옛 `SiliconFly`가 남아 있어 문제를 가리지만 clean checkout에서는 해당 파일이 없고, 개발 폴더에서는 옛 프로그램이 실행될 수 있다. `run_flygym.sh`와 Finder launcher는 새 이름을 사용한다.

### P2 — 재현 가능한 배포/검증 설명 보완 필요

README의 validated 표시는 이번 결과와 구분해야 한다. `.github` workflow는 tracked tree에 없고 `requirements.txt`는 FlyGym만 고정하며 numpy는 범위, transitive dependency 전체는 고정되어 있지 않다. 현재 venv는 `../flygym-venv` symlink를 사용한다. 이는 현재 로컬 실행을 무효로 만들지 않지만 새 사용자의 clean setup 증거는 아니다.

V3에서 fresh checkout/venv, launcher/실제 viewer smoke, dependency inventory와 날짜·커밋이 있는 검증표를 남긴다. 지금 README의 과거 성능 수치를 새로 측정한 값으로 취급하지 않는다.

## 이번에 직접 실행한 검증

모든 명령은 Git 저장소 루트에서 실행했다. Mac의 GPU는 검사 로그 기준 Apple M2다. 테스트 중 일부 Python/Swift 작업은 병행했으므로 이 실행의 시간 수치를 독립 성능 benchmark로 쓰지 않는다. 실패한 real labloop는 단독으로 다시 수행했다.

| 명령 | 결과 | 근거 |
|---|---|---|
| `./build.sh` | exit 0 | 새 executable 빌드 성공 |
| `./ThongpariFlyNeuronSim --bridgetest` | exit 0, PASS 26항목 | [로그](../../notes/validation/2026-09-13/bridgetest.txt) |
| `./ThongpariFlyNeuronSim --labtest` | exit 0, PASS 26항목 | [로그](../../notes/validation/2026-09-13/labtest.txt) |
| `./ThongpariFlyNeuronSim --simtest` | exit 0 | [로그](../../notes/validation/2026-09-13/simtest.txt) |
| `./ThongpariFlyNeuronSim --behaviortest` | exit 0, PASS 17항목 | [로그](../../notes/validation/2026-09-13/behaviortest.txt) |
| `./ThongpariFlyNeuronSim --gpucheck` | **exit 1, C/H groups** | [로그](../../notes/validation/2026-09-13/gpucheck.txt) |
| `./flygym-venv/bin/python tools/verify_data.py --no-parquet` | exit 0, PASS 63항목 | [로그](../../notes/validation/2026-09-13/data.txt) |
| `./flygym-venv/bin/python flygym_bridge/test_bridge.py` | exit 0, PASS 44항목 | [로그](../../notes/validation/2026-09-13/bridge.txt) |
| `./flygym-venv/bin/python flygym_bridge/test_lab.py` | exit 0, PASS 53항목 | [로그](../../notes/validation/2026-09-13/lab.txt) |
| `./flygym-venv/bin/python flygym_bridge/validate_experiment_presets.py` | exit 0, 11 presets | [로그](../../notes/validation/2026-09-13/presets.txt) |
| `./flygym-venv/bin/python flygym_bridge/test_lab_real.py` | exit 0, PASS 34항목 | [로그](../../notes/validation/2026-09-13/lab_real.txt) |
| `./flygym-venv/bin/python flygym_bridge/test_vision_real.py` | exit 0, PASS 12항목 | [로그](../../notes/validation/2026-09-13/vision_real.txt) |
| real `bridge.py --flygym-headless` + `--labloop` | **exit 1, 만료 검사, 2회** | 위 최초/재실행 로그 |

`PASS 항목`은 출력의 PASS 행 수이며 별도 테스트 framework case 수를 뜻하지 않는다. GPU arithmetic probe에는 의도적으로 잘못된 산술 후보의 FAIL 출력도 있으므로 최종 exit/status와 C/H 결과를 기준으로 판정했다.

데이터 검사는 파일 크기·SHA256·CSR 구조·배열 등을 확인했다. **원본 parquet spot-check는 `--no-parquet`로 생략했다.** full GUI/real viewer의 새 런처 smoke, clean install, 장기 녹화 종료, 생물학적 동등성 검증은 이번 수행 범위에서 완료하지 않았다. headless real eye/body 통과와 이를 혼동하지 않는다.

실제 TCP 검사는 17841 포트가 비어 있을 때만 별도 bridge를 시작했고, 종료 시 해당 PID만 정리했다. 기존 사용자 프로세스와 기록은 변경하지 않았다.

## 목표 대비 계획 수정

- **V3**: 위 실패/기록/배포 문제 해결 및 작은 모듈 경계 분리. 실제 구현은 아직 하지 않았다.
- **V4–V6**: simulation time/epoch → session checkpoint → 동일 가상 개체의 import/export/이식.
- **V7–V9**: 선언형 월드 → 외부 GLB → 도구·동적 물체. visual mesh만 표시해 환경 상호작용이 된 것으로 부르지 않는다.
- **V10–V11**: 정확 뉴런 탐색 → 기록 재생/재실행. 현재 sampled flash와 정확 계측을 분리한다. 기본 클릭은 관찰로 바꾸고 direct stimulation은 별도 모드로 둔다.
- **V12–V13**: 습도 → 검증된 접촉 미각. anatomy가 없으면 generic 전신 접촉을 자연 미각으로 대체하지 않는다.
- **V14–V16+**: 실제 데이터와의 비교, BANC/VNC 등 후속 신경계, 생리·가소성·섭식/비행 등을 개별 연구로 분리한다.

seed는 개체의 동적 상태가 아니다. 실제 “같은 개체 이어하기”에는 neural state/delay buffers/filter/controller/physics/timebase를 포함한 checkpoint가 필요하다. 현재의 점군+표본 반짝임 역시 정확한 모든 뉴런 spike 기록이 아니다. 이러한 차이를 장기 계약과 단계별 완료 조건에 반영했다.

현 기준 데이터셋에서 HRN_VP4 29, HRN_VP5 16, claw_tpGRN 60, dorsal_tpGRN 11, BM_Taste 72를 binary cellType 배열에서 재확인했다. 세포 이름/개수만으로 생리적 기능이나 신체 부위의 정확한 mapping을 확정하지 않는다.

문서: [V3 실행 계획](../plans/VIRTUAL_FLY_LAB_V3_PLAN.md), [V3–V16+ 장기 로드맵](../plans/VIRTUAL_FLY_LAB_ROADMAP.md). 로드맵의 각 버전은 이전 버전 실패가 해소된 뒤 시작하며 필요하면 더 분할한다.
