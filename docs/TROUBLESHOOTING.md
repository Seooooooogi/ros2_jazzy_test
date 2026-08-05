# TROUBLESHOOTING

설치/실행 중 마주친 증상과 복구 절차 카탈로그. 증상 → 원인 → 복구 → 예방 순.

---

## 재부팅 후 검은 화면 + 깜빡이는 `_` 로 부팅 정지

**증상**: NVIDIA 드라이버 설치 후 재부팅하면 화면이 검은색이고 좌상단에 `_` 커서만 깜빡이며 부팅이 진행되지 않음. `nomodeset` 커널 파라미터를 줘도 동일.

**원인** (한 가지 이상 중첩 가능):
1. **반쪽 HWE 커널 — `modules-extra` 누락**: 드라이버 자동선택(`ubuntu-drivers install`)이 HWE 커널 이미지를 의존성으로 끌어오지만 `linux-modules-extra-<kernel>`(wifi / 일부 USB 입력 드라이버 수록)는 함께 오지 않아, 그 커널로 부팅하면 wifi·USB 키보드가 사라진다. 그래픽이 아니라 입력/네트워크가 죽는 형태로도 나타남.
2. **드라이버 커널 모듈 부재**: 부팅하는 커널에 nvidia 커널 모듈(`nvidia.ko`)이 빌드/설치되지 않아 디스플레이 드라이버가 없음. nouveau 는 nvidia 패키지가 블랙리스트하므로 폴백도 없어 검은 화면.

**복구**:
1. **이전(정상) 커널로 부팅** — 부팅 시 `Shift`/`Esc` 로 GRUB → `Advanced options for Ubuntu` → 모듈이 온전한 이전 커널 선택. wifi·키보드가 돌아오면 현재 커널만 깨진 것.
2. **드라이버 제거로 디스플레이 복구** (그래픽이 검은 화면일 때) — GRUB → recovery mode → root shell:
   ```bash
   mount -o remount,rw /
   apt-mark unhold 'nvidia-driver-*' 2>/dev/null || true
   apt-get purge -y '^nvidia-.*'
   apt-get autoremove -y
   reboot
   ```
   nouveau 로 정상 부팅됨. (주의: `autoremove` 가 지우는 목록을 확인 — 의도치 않은 커널/모듈 제거 방지.)
3. **깨진 커널에 모듈 채우기** — 정상 커널로 부팅한 뒤(네트워크 필요: wifi 죽었으면 휴대폰 USB 테더링/유선), 대상 커널용 모듈을 설치:
   ```bash
   sudo apt-get install -y \
     linux-image-<kernel> linux-modules-<kernel> linux-modules-extra-<kernel>
   sudo update-initramfs -u -k <kernel>
   ```
   커널 모듈은 버전별로 따로 설치되므로, 현재 실행 커널이 달라도 대상 커널용 패키지를 설치하면 그 커널로 부팅했을 때 적용된다.

**예방** (현재 installer 에 반영됨):
- 커널 베이스라인 단계(`resources/base-install.sh kernel`)가 nvidia 보다 먼저 실행돼 `linux-generic-hwe-24.04` + 헤더 메타를 `--install-recommends` 로 설치 → 이미지 + 헤더 + `modules-extra` 를 항상 함께 보장.
- nvidia 드라이버를 자동선택 대신 명시 핀(`nvidia-driver-595` closed)으로 설치하고, 커널-모듈 메타로 커널 업데이트를 자동 추적. (Optimus 노트북 디스플레이 안정성 위해 open 대신 closed 채택.)
- nvidia 설치 직후 **부팅 예정 커널에 `nvidia.ko` 가 실제로 있는지 검증**하고 없으면 재부팅 단계로 넘어가기 전에 중단(silent brick → 재부팅 전 시끄러운 실패).

**참고 — Secure Boot 가 켜진 환경** (이 프로젝트 타깃은 disabled): 서명 안 된 nvidia DKMS 모듈을 커널이 거부해 같은 검은 화면이 날 수 있다. `mokutil --sb-state` 로 확인, BIOS 에서 Secure Boot 비활성 또는 MOK 등록(`sudo mokutil --import /var/lib/dkms/mok.pub` 후 재부팅 시 파란 화면에서 enroll) 필요.

---

## 왜 커널이 여러 개 설치되나 (정상 동작)

설치 후 `/lib/modules` 에 커널이 2개 이상 보이는 것은 정상이다.
- **이전 커널 보존(안전망)**: 커널 업데이트 시 apt 가 직전 커널을 지우지 않아, 새 커널이 부팅을 깨면 GRUB 에서 되돌릴 수 있다.
- **GA vs HWE 트랙**: 24.04 는 출시 커널 라인(GA, 6.8.x)과 신형 하드웨어 지원용 롤링 트랙(HWE, 6.11→6.14→6.17…)이 별개 패키지로 공존한다. 본 installer 는 HWE 트랙으로 통일(`linux-generic-hwe-24.04`).

---

## `ros2 run <pkg> <node>` → ModuleNotFoundError (scipy / pymodbus / openwakeword 등) — application-shell (폐기된 브랜치 기록)

**증상**: `colcon build` 는 성공했는데 `ros2 run robot_control robot_control` 실행 시 `ModuleNotFoundError`. host venv 에는 패키지가 분명히 설치돼 있다.

**원인**: ament_python 패키지는 **빌드 시 third-party 를 import 하지 않아** 빌드는 통과하지만, 런타임에 import 한다. host venv(`--system-site-packages`)는 venv→system 단방향만 열려, system Python 으로 실행되는 `ros2 run` 이 venv 의 app Python 을 못 본다.

**복구 / 예방** (application-shell):
- 핵심은 **colcon 빌드를 venv active 에서 수행**하는 것 — 그래야 entry_point console_script 의 shebang 이 venv python 으로 박혀 `ros2 run` 이 venv 를 본다. **활성화 자동화는 없다** — `HOST_VENV` 를 보고 자동 activate 하는 로직은 현행 `resources/app-install.sh colcon` 에 없고(`grep -rn HOST_VENV resources/` = 0) 폐기된 `feat/application-shell` 브랜치에만 있었다. venv 를 쓴다면 손으로 activate 한 뒤 빌드한다.
- 이미 빌드했는데 깨졌다면 venv active 상태에서 재빌드: `source ~/cobot_ws/.venv/bin/activate && cd ~/cobot_ws && colcon build`.
- 직접 `python3 ...` 실행/디버깅은 `source resources/activate.sh` (ROS + 워크스페이스 overlay + venv 함께 활성화).
- 설치된 스크립트 shebang 확인: `head -1 ~/cobot_ws/install/robot_control/lib/robot_control/robot_control` → venv python 경로여야 함.

---

## openwakeword `Model(.tflite)` 로드 실패 / tflite-runtime Python 3.12 wheel 없음

**증상**: `import openwakeword` 는 되는데 `Model(wakeword_models=["...tflite"])` 에서 실패. 또는 `pip install openwakeword` 가 `Could not find a version that satisfies tflite-runtime` 로 실패.

**원인**: wakeword 모델이 `.tflite` 라 tflite 백엔드가 필요한데, openwakeword 0.6.0 이 의존으로 강제하는 `tflite-runtime` 은 **Python 3.12 wheel 이 없다**(최대 3.11). noble=3.12. (import smoke 만으론 안 잡힘 — `.tflite` 로드는 런타임에만 일어남.)

**복구 / 예방**: 후속작 `ai-edge-litert`(cp312 wheel, 동일 `Interpreter` API)로 대체. `resources/app-install.sh voice` 가 이미 적용 — (1) `openwakeword==0.6.0 --no-deps` (불가능한 tflite-runtime 의존 회피), (2) 실제 의존 명시 + `ai-edge-litert`, (3) `tflite_runtime → ai_edge_litert` shim 을 site-packages 에 생성, (4) 모델 채우기 3단계 — `resources/oww_models/` 동봉본(melspectrogram/embedding/silero_vad)을 설치 경로에 먼저 복사하고, 그 다음 `download_models()` 로 나머지 stock 모델만 받은 뒤(이미 있는 것은 존재-가드로 skip), 모든 `.tflite` 의 offset 4 `TFL3` 매직을 검증해 손상본은 삭제하고 fail-loud(재실행 시 재다운로드). 검증은 `import` 가 아닌 **`Model(.tflite)` 인스턴스화 + predict**. 상세 = ADR-014.

---

## pymodbus 3.x gripper — `unit=`/`slave=`, 통신 실패 시 cryptic 에러

**증상**: gripper 코드에서 `ModuleNotFoundError: pymodbus.client.sync`(2.x import), 또는 통신 실패 시 `AttributeError: ... has no attribute 'registers'`.

**원인**: noble apt / 최신 pip 의 pymodbus 는 3.x 라 `pymodbus.client.sync` 모듈이 없고(→`pymodbus.client`), 메서드 인자가 `unit=`→`slave=` 로 바뀌었다. 3.x 는 통신 실패 시 예외 대신 에러 응답 객체를 반환해 `result.registers[0]` 직접 접근이 AttributeError 가 된다.

**복구 / 예방**: onrobot.py 3개를 3.x API 로 이관 완료(`from pymodbus.client import ...`, `slave=`, read·write 후 `isError()` 가드 — write 실패 silent 진행 차단). ⚠️ **안전**: register write 의미는 import smoke 로 검증 안 됨 — 실 RG gripper 에서 open/close/move 하드웨어 재검증 없이 실로봇 운용 금지. 설치되는 3.x minor 에 따라 `slave=`→`device_id=` 일 수 있어 실기에서 인자명 확인. 상세 = ADR-014.

---

## yolo 컨테이너가 카메라를 못 봄 / `/get_3d_position` 좌표가 비거나 depth 가 None

**증상**: yolo 컨테이너(`object_detection`)는 떠 있는데 `/get_3d_position` 서비스 호출이 응답을 안 주거나, 응답 좌표의 depth(z)가 0/None. `ros2 topic list` 에 `/camera/aligned_depth_to_color/image_raw` 가 없다.

**원인**: 카메라는 **host 소유**다(2026-06-02 토폴로지 변경). yolo 컨테이너 안엔 realsense2_camera 드라이버가 없고, `object_detection` 노드는 host 가 publish 하는 `/camera/*` 토픽을 DDS 로 subscribe 만 한다. host 에서 카메라 노드를 안 띄웠거나, `align_depth` 없이 띄워 `aligned_depth_to_color` 토픽이 없으면 노드의 `depth_frame` 이 채워지지 않아 좌표 계산이 실패한다.

카메라 노드 기동 주체는 통합 bringup 이다 — 진입점이 `m0609_rg2_bringup` 의 `bringup.launch.py` 로 바뀌었고, 이 launch 가 로봇 드라이버·그리퍼와 함께 realsense 노드도 띄운다. 따라서 예전 절차였던 `ros2 launch realsense2_camera rs_launch.py align_depth.enable:=true` 수동 기동은 더 이상 쓰지 않는다(같은 장치를 두 노드가 동시에 여는 상태는 검증한 적 없음).

**복구 / 예방**:
- host 에서 카메라 노드가 떠 있어야 한다(`object_detection` 은 그 토픽을 subscribe 만 한다). 래퍼를 쓰면 자동 — 래퍼는 yolo 컨테이너를 먼저 올리고 카메라를 마지막에 띄우지만, 구독자가 먼저 떠 있어도 DDS discovery 로 붙는다:
  ```bash
  bash containers/bringup.sh
  ```
  래퍼는 사용자가 `camera:=` 를 명시하지 않은 경우에만 `camera:=true` 를 덧붙인다(launch 의 camera 기본값은 false).
- launch 를 직접 쓸 때는 `camera:=true` 를 반드시 준다:
  ```bash
  ros2 launch m0609_rg2_bringup bringup.launch.py camera:=true
  ```
  `align_depth.enable` 을 비롯한 프로파일(color 1280x720x30, depth 848x480x30, `initial_reset`, `enable_rgbd`, `enable_sync`, `pointcloud.enable`)은 launch 안에 이미 박혀 있어 따로 넘기지 않는다.
- 토픽 확인: `ros2 topic list | grep '^/camera/'` → `/camera/color/image_raw`, `/camera/aligned_depth_to_color/image_raw`, `/camera/color/camera_info` 3개가 보여야 한다. (**경로가 바뀌었다** — 예전 문서의 `/camera/camera/*` 이중 namespace 는 더 이상 나오지 않는다. realsense2_camera 4.58.1 은 스트림 토픽을 private(`~/`)으로 만들어 최종 이름이 `/<node_namespace>/<node_name>/<stream>` 이 되는데, upstream `rs_launch.py` 가 `camera_namespace` 와 `camera_name` 을 **둘 다 `camera`** 로 두는 바람에 아무 정보도 없는 한 단계가 더 붙었던 것이다. 새 `bringup.launch.py` 는 realsense 노드를 `namespace='/'` + `name='camera'` 로 띄워 `/camera/*` 한 단계로 낸다(인자를 지우기만 하면 드라이버 생성자 기본값 `/camera` 가 살아나 그대로다 — `src/realsense_node_factory.cpp:34`).)
  - TF 프레임은 **무변경**이다(`camera_link`, `camera_color_optical_frame`, …). frame_id 는 토픽 이름과 별개로 ROS 파라미터 `camera_name`(기본 `camera`)에서 나오고, 그 파라미터는 건드리지 않았다. URDF 도 그대로. 즉 "토픽이 안 보인다"와 "TF 가 안 붙는다"는 서로 다른 문제다.
  - 소비자(`ImgNode`)는 이 3개 경로를 **절대 경로로** 구독한다(2026-07-22 기준). 한때 상대 이름 + 기동 시 remap 이었으나 인자를 빠뜨리면 조용히 무수신이 되어 되돌렸다 — 구 소스가 깔린 머신의 증상은 아래 "카메라 토픽 구독자가 0" 항목 참조.
- host 와 컨테이너가 서로의 토픽을 보는지: 같은 `ROS_DOMAIN_ID` + 같은 `RMW_IMPLEMENTATION`(둘 다 `resources/config.sh` 가 host 에 싣고 compose 가 컨테이너에 주입, 현행 표준 `rmw_cyclonedds_cpp`) + compose `network_mode: host`. 하나라도 어긋나면 같은 topic 도 discovery 안 됨. 상세 = ADR-015 / ADR-016.

**변형 — 카메라 노드가 아예 안 뜸(`camera:=false` / launch 를 인자 없이 직접 실행)**

**증상**: 위와 달리 `/camera/*` 가 **하나도** 없다(`aligned_depth_to_color` 만 빠진 게 아니라 `color/image_raw` 도 없음). 로봇 드라이버·그리퍼·RViz 는 정상이고 yolo 컨테이너도 살아 있지만 아무 로그도 안 남기며 조용하다. `ros2 node list` 에 카메라 노드(`/camera`)가 없다. — 이것은 **publisher 부재**다. 토픽 이름이 어긋난 게 아니라 토픽을 내는 노드 자체가 없는 상태이며, 이름 불일치 쪽은 아래 별도 항목이다.

**원인**: 새 launch 의 `camera` 인자 기본값이 **false** 다(그리퍼/URDF standalone 개발 시 USB 카메라를 잡지 않기 위함). `ros2 launch m0609_rg2_bringup bringup.launch.py` 를 인자 없이 실행하거나 `camera:=false` 를 명시하면 realsense 노드 자체가 생성되지 않는다. `object_detection` 노드는 토픽이 없으면 에러 없이 대기만 하므로 "노드는 살아 있는데 조용함" 으로 보인다 — 카메라 하드웨어 고장/USB 문제와 헷갈리기 쉽다.

**구분법**: 노드 부재(`ros2 node list | grep camera` 가 빈 결과) = launch 인자 문제. 노드는 있는데 로그에 재시도/장치 못 찾음 = 하드웨어·USB 문제.

**복구**: `camera:=true` 로 다시 띄운다(또는 `bash containers/bringup.sh` 사용 — 명시 안 하면 자동으로 붙는다).

---

## 카메라 토픽 구독자가 0 — remap 배선 누락(노드는 정상, 이름만 어긋남)

> **적용 범위**: 소비자 소스가 **구본**(상대 이름 구독)인 머신에만 해당한다. 2026-07-22 이후의
> `cobot2.zip` 을 배치했다면 `ImgNode` 가 절대 경로를 구독하므로 이 실패 자체가 생기지 않는다.
> 판별: `grep -n "create_subscription" -A1 ~/cobot2_ws/src/cobot2/yolo_container/object_detection/object_detection/realsense.py`
> → `'/camera/color/image_raw'` (절대) 면 신본, `'color/image_raw'` (상대) 면 구본이라 아래가 적용된다.

**증상**: 앞 항목과 정반대로 **publisher 는 멀쩡하다**. `/camera/color/image_raw` 가 topic list 에 있고 hz 도 나오는데, 소비자만 아무것도 못 받는다. 노드는 에러 없이 정상 기동하고 로그도 깨끗하다.
- `ros2 topic info /camera/color/image_raw` → `Publisher count: 1`, **`Subscription count: 0`**.
- 대신 `/color/image_raw`, `/aligned_depth_to_color/image_raw`, `/color/camera_info` 같은 **루트 토픽**이 topic list 에 나타나고, 거기엔 구독자만 있고 publisher 가 없다.

**원인**: 소비자 `ImgNode`(cobot2 의 `realsense.py` 3벌 — `yolo_container/object_detection`, `pick_and_place_text`, `pick_and_place_voice`)가 절대 경로 대신 **상대 이름**을 구독하도록 바뀌었다. 상대 이름은 그 노드의 네임스페이스 아래로 해석되므로, remap 없이 띄우면 네임스페이스가 `/` 라 `/color/image_raw` 로 붙는다. 이름이 존재하지 않는 게 아니라 **다른 이름에 정상적으로 붙은 것**이라 ROS 는 경고조차 내지 않는다 — 조용히 빈 토픽을 구독한다.

**진단**:
```bash
ros2 topic info /camera/color/image_raw          # Subscription count 가 0 이면 배선 누락
ros2 topic list | grep -E '^/(color|aligned_depth_to_color)/'   # 루트에 새 토픽이 생겼는지
ros2 node info /camera/img_node                  # remap 이 먹었으면 이 이름으로 존재
ros2 node info /img_node                         # 배선 누락 시 여기로 뜨고, 구독 목록이 루트 경로
```
`ros2 node info` 의 Subscribers 섹션에 찍힌 경로가 `/camera/...` 인지 `/...` 인지가 결정적 단서다.

**근본 복구** — `cobot2.zip` 신본을 재배치해 소비자를 절대 경로 판으로 바꾼다. 그러면 기동 인자가 필요 없어진다.

**임시 복구** — 구 소스 그대로 쓰려면 소비자 실행줄에 remap 인자를 넣는다.
- yolo 노드(`containers/bringup.sh`): 카메라 토픽만 다루므로 노드 스코프 네임스페이스 remap 한 줄.
  ```bash
  ros2 run object_detection object_detection --ros-args -r img_node:__ns:=/camera
  ```
- viz 스크립트(`viz/live_detection.py`, `viz/viewer.py`, compose 의 `yolo-viz`): `/yolo/detections` 등 카메라 밖 토픽도 함께 쓰므로 네임스페이스 통째 이동 대신 **토픽 단위 remap**.
  ```bash
  python3 /opt/viz/live_detection.py --ros-args -r color/image_raw:=/camera/color/image_raw
  ```

**전역 `__ns` 를 쓰면 안 되는 이유** (Jazzy 실측):

| remap | ImgNode 구독 | `/get_3d_position` 서비스 |
|---|---|---|
| 없음 | `/color/image_raw` (무수신) | `/get_3d_position` |
| `-r img_node:__ns:=/camera` (채택) | `/camera/color/image_raw` | `/get_3d_position` 유지 |
| 전역 `-r __ns:=/camera` (금지) | `/camera/color/image_raw` | `/camera/get_3d_position` 으로 이동 |

`img_node:` 접두사를 빼면 같은 프로세스의 `object_detection_node` 까지 함께 옮겨져, `robot_control.py` 가 절대 경로로 부르는 `/get_3d_position` 이 끊긴다 — 카메라는 고쳐지고 서비스가 죽는 교환이라 더 나쁘다. 접두사 일괄 치환으로 우회할 수도 없다: rcl 의 `**` 와일드카드 remap 은 **미구현**이다(Jazzy 실측 시 `Wildcard '**' is not implemented`). 네임스페이스 remap 또는 토픽 단위 remap 둘 중 하나만 쓸 수 있다.

**남은 위험 / 미검증**:
- 소비자 소스(`~/cobot2_ws/src/cobot2`)는 **어떤 git 저장소에도 추적되지 않는다**(이 레포도 `.gitignore` 로 배제). 프로듀서만 새 이름으로 바뀌고 소비자 패치가 다른 머신에 전달되지 않으면 파이프라인이 통째로 죽는다 — 새 머신 세팅 시 위 진단 명령을 먼저 돌릴 것.
- 실 RealSense 하드웨어가 없어 **실제 영상 수신은 미검증**이다. 위 표는 이름 해석(어떤 토픽/서비스 이름으로 붙는지)만 Jazzy 컨테이너에서 실측한 결과다.

---

## CycloneDDS 로 RealSense raw 토픽이 0Hz / `SocketSendBufferSize` 지정 후 노드가 SIGABRT 로 죽음

**증상**: `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` 로 바꾸자 (1) `color/image_raw` 등 대용량 토픽이 `ros2 topic hz` 에서 0Hz, 또는 (2) `CYCLONEDDS_URI` 의 `SocketSendBufferSize` 를 키운 뒤 노드 기동이 `failed to increase socket send buffer size to at least N bytes` → `rmw_create_node: failed to create domain` → `failed to initialize rcl node` 로 즉사(exit -6). 같은 fastrtps 환경에선 멀쩡했다.

**원인**: 대용량 프레임(color 1280x720 RGB8 ≈ 2.6MB)은 UDP fragment 로 쪼개져 전송된다. CycloneDDS 가 소켓 수신 버퍼(`SocketReceiveBufferSize`)·송신 버퍼(`SocketSendBufferSize`)를 요청해도 **실효치는 커널 `net.core.rmem_max` / `net.core.wmem_max` 에 캡**된다. 둘의 기본값은 ~208KB 라 한 프레임보다 작아 fragment 재조립이 실패 → 수신측은 전량 유실(0Hz). 게다가 `SocketSendBufferSize` 는 **하드 최소값**이라 커널 `wmem_max` 가 요청치를 못 주면 CycloneDDS 가 도메인 생성을 거부하고 노드가 죽는다(`SocketReceiveBufferSize` 도 같은 캡을 받지만 `rmem_max` 만 올려두면 통과해 증상이 송신쪽에서만 즉사로 드러날 수 있다).

**복구 / 예방**:
- 커널 소켓 버퍼를 먼저 올리고 영속화(재부팅 유지). DDS XML 의 버퍼 요청은 이 한도 안에서만 성립하므로 **sysctl 과 XML 은 세트** — XML 만 다른 머신에 복사하면 `wmem_max` 부족으로 노드가 죽는다.
  ```bash
  # /etc/sysctl.d/60-cyclonedds.conf (root). 적용: sudo sysctl --system
  net.core.rmem_max = 2147483647
  net.core.wmem_max = 2147483647
  net.core.rmem_default = 268435456
  net.core.wmem_default = 67108864
  net.ipv4.ipfrag_time = 3
  net.ipv4.ipfrag_high_thresh = 134217728
  net.ipv4.ipfrag_low_thresh = 98304000
  net.core.netdev_max_backlog = 30000
  ```
- DDS 버퍼 요청은 `CYCLONEDDS_URI` 가 가리키는 XML 의 `Domain/Internal` 에:
  ```xml
  <SocketReceiveBufferSize min="64MB"/>
  <SocketSendBufferSize min="64MB"/>
  ```
- 노드·측정 셸 **모두** 같은 RMW + 같은 `CYCLONEDDS_URI` 를 export 해야 한다(쉘별 환경변수라 한 터미널의 export 가 다른 터미널로 전파 안 됨). 한쪽만 cyclonedds 면 topic 자체가 discovery 안 됨.
- 검증: 노드 기동 로그에 `failed to increase socket ... buffer` 경고가 없어야 하고, 대용량 토픽 hz 는 작은 동반 토픽(`camera_info`)과 일치해야 한다(예: `color/image_raw` 30Hz ↔ `color/camera_info` 30Hz). `ros2 topic hz` 가 SIGTERM 으로 죽으면 파이프 버퍼가 유실되니 `stdbuf -oL ... | grep -m4 'average rate'` 로 받는다.
- 주의: 대용량 토픽의 낮은 hz 가 항상 버퍼 문제는 아니다 — fastrtps + `ros2 topic hz`(rclpy 단일 스레드) 조합은 역직렬화가 publish 를 못 따라가 실제 30fps 여도 15Hz 안팎으로 출렁인다(측정 artifact). 작은 동반 토픽 hz 로 실제 프레임레이트를 교차검증할 것.

---

## `colcon build` 끝에 "2 packages had stderr output: dsr_controller2 dsr_hardware2" (정상 동작)

**증상**: 빌드가 `Summary: 34 packages finished` 로 끝났는데 위 두 패키지에서 stderr 가 쏟아진다. CMake deprecation, `-Wdeprecated-declarations`, `-Wunused-variable` 등.

**결론: 실패가 아니다.** colcon 은 stderr 로 나간 모든 것을 — 경고 포함 — 저 줄에 집계한다. 실패는 `N packages failed` 로 따로 표시된다. 이 목록이 없으면 빌드는 성공한 것이다.

**경고 출처별 분류** (전부 우리 레포 밖):

| 경고 | 출처 | 조치 |
|---|---|---|
| `tl_expected` CMake Deprecation | **ROS Jazzy 자체** (`/opt/ros/jazzy/share/tl_expected/`), `controller_manager`→`parameter_traits` 경유 | 없음. upstream ROS 가 다음 distro 전에 정리 |
| `boost/bind.hpp` global placeholders | doosan `dsr_hw_interface2.cpp` 가 `<boost/thread/thread.hpp>` 를 include | 없음 |
| `on_init(const HardwareInfo&)` deprecated | ros2_control 이 `on_init(HardwareComponentInterfaceParams&)` 로 이전 | **없음 — 단 다음 distro 마이그레이션 때 빌드 실패로 승격될 항목** |
| `ManageAccessControl` / `GetRobotState` / `SetRobotMode` / `GetCurrentPose` / `PlayDrlPause` 등 deprecated | Doosan SDK(`DRFLEx.h`)가 자기 camelCase API 를 snake_case 로 이전 중인데 doosan 코드가 구 API 를 계속 호출 | 없음 |
| `realtime_buffer.h` → `.hpp` | ros2_control `realtime_tools` 헤더 이름 변경 | 없음 |
| `unused variable` / `set but not used` | doosan 소스 위생 | 없음 |

**왜 고치지 않나**: clone 대상은 doosan 본가가 아니라 우리 쪽 fork(`ROKEY-SPARK/doosan-robot2_jazzy`)라 **고치는 것 자체는 가능하다**. 로컬 작업본 패치는 재clone·`--reset` 때 날아가지만 fork 에 커밋하면 남는다. 그럼에도 안 고치는 이유는 이득이 없어서다:

- 위 표에서 기능에 영향 있는 항목이 **하나도 없다**. 전부 표시상의 노이즈.
- `on_init` 만 미래 가치가 있는데, 새 시그니처(`HardwareComponentInterfaceParams`)는 ros2_control 의 **특정 버전 이후**에만 존재한다. 지금 갈아타면 apt `ros-jazzy-ros2-control` 이 더 오래된 머신에서 **빌드가 깨진다** — 경고보다 나쁜 실패 모드. 버전 분기(`#if`)로 양쪽을 지탱하는 건 경고 하나에 치르기엔 과한 값.
- 컴파일러 플래그(`-Wno-deprecated-declarations`) 억제는 나중에 생길 **진짜** 경고까지 같이 가린다.

(fork 커밋 `f1118a1` 의 `DSR_ROBOT2.py` 수정은 성격이 다르다 — 빌드/런타임이 실제로 깨지는 이름 불일치다.)

**fork 을 고치기로 한다면**: 리비전 핀은 이미 걸려 있다 — `DSR_COMMIT`(`resources/config.sh`)이 clone 직후 detach 하는 SHA다. fork main 에 커밋을 얹은 뒤에는 **이 핀도 함께 올려야** 새 리비전이 설치에 반영된다. 핀을 안 올리면 fork 만 앞서가고 설치는 옛 커밋에 머문다(그게 의도된 기본값 — 설치 재현성이 fork 의 최신 상태보다 우선).

**예방/모니터링**: `on_init` deprecation 만 추적 대상. jazzy → 다음 distro 마이그레이션 시 이 시그니처가 제거되면 `dsr_hardware2` 가 빌드 실패한다 — 그 시점에 fork 갱신이 선결 조건이 된다.
