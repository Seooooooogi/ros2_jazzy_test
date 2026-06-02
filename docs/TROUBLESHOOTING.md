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
- 커널 베이스라인 단계(`resources/kernel-baseline.sh`)가 nvidia 보다 먼저 실행돼 `linux-generic-hwe-24.04` + 헤더 메타를 `--install-recommends` 로 설치 → 이미지 + 헤더 + `modules-extra` 를 항상 함께 보장.
- nvidia 드라이버를 자동선택 대신 명시 핀(`nvidia-driver-595` closed)으로 설치하고, 커널-모듈 메타로 커널 업데이트를 자동 추적. (Optimus 노트북 디스플레이 안정성 위해 open 대신 closed 채택.)
- nvidia 설치 직후 **부팅 예정 커널에 `nvidia.ko` 가 실제로 있는지 검증**하고 없으면 재부팅 단계로 넘어가기 전에 중단(silent brick → 재부팅 전 시끄러운 실패).

**참고 — Secure Boot 가 켜진 환경** (이 프로젝트 타깃은 disabled): 서명 안 된 nvidia DKMS 모듈을 커널이 거부해 같은 검은 화면이 날 수 있다. `mokutil --sb-state` 로 확인, BIOS 에서 Secure Boot 비활성 또는 MOK 등록(`sudo mokutil --import /var/lib/dkms/mok.pub` 후 재부팅 시 파란 화면에서 enroll) 필요.

---

## 왜 커널이 여러 개 설치되나 (정상 동작)

설치 후 `/lib/modules` 에 커널이 2개 이상 보이는 것은 정상이다.
- **이전 커널 보존(안전망)**: 커널 업데이트 시 apt 가 직전 커널을 지우지 않아, 새 커널이 부팅을 깨면 GRUB 에서 되돌릴 수 있다.
- **GA vs HWE 트랙**: 24.04 는 출시 커널 라인(GA, 6.8.x)과 신형 하드웨어 지원용 롤링 트랙(HWE, 6.11→6.14→6.17…)이 별개 패키지로 공존한다. 본 installer 는 HWE 트랙으로 통일(`linux-generic-hwe-24.04`).

---

## `ros2 run <pkg> <node>` → ModuleNotFoundError (scipy / pymodbus / openwakeword 등) — application-shell

**증상**: `colcon build` 는 성공했는데 `ros2 run robot_control robot_control` 실행 시 `ModuleNotFoundError`. host venv 에는 패키지가 분명히 설치돼 있다.

**원인**: ament_python 패키지는 **빌드 시 third-party 를 import 하지 않아** 빌드는 통과하지만, 런타임에 import 한다. host venv(`--system-site-packages`)는 venv→system 단방향만 열려, system Python 으로 실행되는 `ros2 run` 이 venv 의 app Python 을 못 본다.

**복구 / 예방** (application-shell):
- 핵심은 **colcon 빌드를 venv active 에서 수행**하는 것 — 그래야 entry_point console_script 의 shebang 이 venv python 으로 박혀 `ros2 run` 이 venv 를 본다(`resources/colcon-build.sh` 가 `HOST_VENV` 있으면 자동 activate).
- 이미 빌드했는데 깨졌다면 venv active 상태에서 재빌드: `source ~/cobot2_ws/.venv/bin/activate && cd ~/cobot2_ws && colcon build`.
- 직접 `python3 ...` 실행/디버깅은 `source resources/activate.sh` (ROS + 워크스페이스 overlay + venv 함께 활성화).
- 설치된 스크립트 shebang 확인: `head -1 ~/cobot2_ws/install/robot_control/lib/robot_control/robot_control` → venv python 경로여야 함.

---

## openwakeword `Model(.tflite)` 로드 실패 / tflite-runtime Python 3.12 wheel 없음

**증상**: `import openwakeword` 는 되는데 `Model(wakeword_models=["...tflite"])` 에서 실패. 또는 `pip install openwakeword` 가 `Could not find a version that satisfies tflite-runtime` 로 실패.

**원인**: wakeword 모델이 `.tflite` 라 tflite 백엔드가 필요한데, openwakeword 0.6.0 이 의존으로 강제하는 `tflite-runtime` 은 **Python 3.12 wheel 이 없다**(최대 3.11). noble=3.12. (import smoke 만으론 안 잡힘 — `.tflite` 로드는 런타임에만 일어남.)

**복구 / 예방**: 후속작 `ai-edge-litert`(cp312 wheel, 동일 `Interpreter` API)로 대체. `host-python-deps.sh` / voice Dockerfile 이 이미 적용 — (1) `openwakeword==0.6.0 --no-deps` (불가능한 tflite-runtime 의존 회피), (2) 실제 의존 명시 + `ai-edge-litert`, (3) `tflite_runtime → ai_edge_litert` shim 을 site-packages 에 생성, (4) feature 모델은 `download_models()`. 검증은 `import` 가 아닌 **`Model(.tflite)` 인스턴스화 + predict**. 상세 = ADR-014.

---

## pymodbus 3.x gripper — `unit=`/`slave=`, 통신 실패 시 cryptic 에러

**증상**: gripper 코드에서 `ModuleNotFoundError: pymodbus.client.sync`(2.x import), 또는 통신 실패 시 `AttributeError: ... has no attribute 'registers'`.

**원인**: noble apt / 최신 pip 의 pymodbus 는 3.x 라 `pymodbus.client.sync` 모듈이 없고(→`pymodbus.client`), 메서드 인자가 `unit=`→`slave=` 로 바뀌었다. 3.x 는 통신 실패 시 예외 대신 에러 응답 객체를 반환해 `result.registers[0]` 직접 접근이 AttributeError 가 된다.

**복구 / 예방**: onrobot.py 3개를 3.x API 로 이관 완료(`from pymodbus.client import ...`, `slave=`, read·write 후 `isError()` 가드 — write 실패 silent 진행 차단). ⚠️ **안전**: register write 의미는 import smoke 로 검증 안 됨 — 실 RG gripper 에서 open/close/move 하드웨어 재검증 없이 실로봇 운용 금지. 설치되는 3.x minor 에 따라 `slave=`→`device_id=` 일 수 있어 실기에서 인자명 확인. 상세 = ADR-014.

---

## yolo 컨테이너가 카메라를 못 봄 / `/get_3d_position` 좌표가 비거나 depth 가 None

**증상**: yolo 컨테이너(`object_detection`)는 떠 있는데 `/get_3d_position` 서비스 호출이 응답을 안 주거나, 응답 좌표의 depth(z)가 0/None. `ros2 topic list` 에 `/camera/camera/aligned_depth_to_color/image_raw` 가 없다.

**원인**: 카메라는 **host 소유**다(2026-06-02 토폴로지 변경). yolo 컨테이너 안엔 realsense2_camera 드라이버가 없고, `object_detection` 노드는 host 가 publish 하는 `/camera/camera/*` 토픽을 DDS 로 subscribe 만 한다. host 에서 카메라 노드를 안 띄웠거나, `align_depth` 없이 띄워 `aligned_depth_to_color` 토픽이 없으면 노드의 `depth_frame` 이 채워지지 않아 좌표 계산이 실패한다.

**복구 / 예방**:
- yolo 컨테이너를 올리기 **전에** host 에서 카메라 노드 기동(align_depth 필수):
  ```bash
  ros2 launch realsense2_camera rs_launch.py align_depth.enable:=true
  ```
- 토픽 확인: `ros2 topic list | grep /camera/camera` → `color/image_raw`, `aligned_depth_to_color/image_raw`, `color/camera_info` 3개가 보여야 한다. (노드 구독 경로가 `/camera/camera/*` 이중 namespace 라 `camera_name`/namespace 를 바꿔 띄우면 토픽이 안 맞는다 — 기본 launch 사용.)
- host 와 컨테이너가 서로의 토픽을 보는지: 같은 `ROS_DOMAIN_ID` + 같은 `RMW_IMPLEMENTATION`(둘 다 `resources/config.sh` 가 host 에 싣고 compose 가 컨테이너에 주입, 기본 fastrtps) + compose `network_mode: host`. 하나라도 어긋나면 같은 topic 도 discovery 안 됨. 상세 = ADR-015.
