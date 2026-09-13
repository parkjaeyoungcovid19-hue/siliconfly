# SiliconFly 실행 파일 안내

Virtual Fly Lab을 사용할 때는 **`SiliconFly 실험실.command`를 기본 런처로 사용한다.** Finder에서 더블클릭하면 실제 FlyGym/MuJoCo bridge와 `SiliconFly --flygym`을 함께 실행하며 Lab 창도 자동으로 열린다.

## 1. 권장: `SiliconFly 실험실.command`

사용 순서:

1. Finder에서 저장소 루트의 `SiliconFly 실험실.command`를 더블클릭한다.
2. 열린 Terminal 창을 유지한다.
3. FlyGym/MuJoCo viewer와 SiliconFly가 시작되고 Virtual Fly Lab 창이 자동으로 열리면 실험을 진행한다.

이 경로에서 World / Stimuli / Brain / Live Data / Experiments 전체 기능, built-in presets, replay, recording을 사용할 수 있다. 자세한 조작법은 [`VIRTUAL_FLY_LAB_GUIDE.md`](VIRTUAL_FLY_LAB_GUIDE.md)를 본다.

## 2. `SiliconFly 바로 실행.command`

일반 SiliconFly + 실제 FlyGym/MuJoCo body를 실행하는 보조 바로가기다. 내부 실행 경로는 역시 `./run_flygym.sh --flygym`이다. Lab 작업 목적이라면 이름이 명확한 `SiliconFly 실험실.command`를 우선 사용한다.

## 3. CLI launch

실제 body + interactive viewer:

```sh
./run_flygym.sh --flygym
```

mock body:

```sh
./run_flygym.sh --mock
```

실제 body를 viewer 없이 실행:

```sh
./run_flygym.sh --flygym-headless
```

`run_flygym.sh`는 bridge를 먼저 띄우고 `./SiliconFly --flygym`을 실행한 뒤 앱 종료 시 bridge 프로세스를 정리한다.

## 4. Lab test modes

socket 없이 Swift lab command queue/state parsing/direct-neural role mapping을 검사:

```sh
./SiliconFly --labtest
```

실제 TCP lab protocol loop를 검사하려면 bridge를 별도 Terminal에서 먼저 띄운다.

```sh
./flygym-venv/bin/python flygym_bridge/bridge.py --mock
```

다른 Terminal에서:

```sh
./SiliconFly --labloop
```

`--labloop`는 실제 `lab_command`/ack/state/event 경로를 통해 sphere spawn, wind, flash, touch, `reset_body`, `reset_world`를 검사한다. real bridge를 이미 띄운 상태에서도 사용할 수 있다.

기존 bridge 진단도 그대로 사용할 수 있다.

```sh
./SiliconFly --bridgetest
./SiliconFly --bridgeloop   # bridge.py --mock 필요
```

Python Lab 검사:

```sh
python3 flygym_bridge/test_lab.py
./flygym-venv/bin/python flygym_bridge/test_lab_real.py
```

## 5. Preset JSON validation

내장 UI preset과 동기화해 둔 독립 참조 사양은 `flygym_bridge/experiment_presets.json`이다. UI는 현재 JSON을 읽지 않고 `LabWindow.runPreset`의 built-in 값을 직접 실행한다.

JSON 검증:

```sh
python3 flygym_bridge/validate_experiment_presets.py
```

## 6. 빌드가 오래된 경우

Swift 소스를 수정한 뒤 실행 파일이 갱신되지 않았다면:

```sh
./build.sh
```

그 다음 `SiliconFly 실험실.command`를 다시 실행한다.

## 7. 첫 실제 실행에서 연결이 늦을 때

FlyGym viewer는 첫 시작에서 JIT/그래픽 준비를 먼저 할 수 있다. 그동안 SiliconFly brain simulation은 계속 돌고 bridge 연결은 재시도된다. Terminal에 실제 오류가 없다면 같은 실행을 유지하면 준비 완료 후 연결된다.
