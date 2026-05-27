# Compatibility Matrix

본 프로젝트가 검증/지원하는 버전 조합. 어떤 스크립트라도 버전을 임의 변경하면 본 매트릭스를 동시에 갱신해야 한다. 매트릭스 없는 버전 변경은 "어제는 됐는데 오늘 안 돼"의 원인.

> **Phase 1 시점**: humble baseline 만 채워짐. jazzy 라인은 Phase 2 종료 시 추가.

---

## Humble baseline (현재 — 검증된 humble 셋업)

| Layer | Version | Source citation | Notes |
|-------|---------|-----------------|-------|
| Ubuntu | 22.04 LTS (jammy) | `resources/ros2-humble-desktop-main.sh:14` (`TARGET_OS=jammy` 검증 — 다른 OS면 abort) | 다른 distro 검증 분기는 silent skip |
| Python | 3.10 (Ubuntu 22.04 기본) | implicit (apt 기본 python3) | `numpy==1.24.4` 호환의 핵심 — 1.24 라인은 Py3.10 까지만 공식 지원 |
| ROS2 | humble | `resources/ros2-humble-desktop-main.sh:12` (`CHOOSE_ROS_DISTRO=humble`) | `/opt/ros/humble/` 에 설치 |
| ros-humble-* (DSR) | 15 패키지 | `resources/dsr-project-install.sh:9-23` | xacro, rclpy, std-msgs, joint-state-publisher-gui, launch-ros, rosgraph-msgs, ament-cmake, ament-pep257, ament-index-cpp, ament-lint-common, moveit-msgs, velocity-controllers, yaml-cpp-vendor, eigen3-cmake-module, ros2launch |
| ros-humble-* (ROS install) | 약 17 패키지 | `resources/ros2-install.sh:16,19-22,29` | control-msgs, realtime-tools, ros2-control, ros2-controllers, gazebo-msgs/gazebo-ros-pkgs, ros-gz-sim 등 |
| ros-humble-realsense2-* | apt 글로브 | `a05-realsense02.sh:1` | |
| NVIDIA driver | 의도 570 → **실측 580.159.03** | `resources/nvidia-driver-install.sh` (`nvidia-driver-570 build-essential dkms`); 실측 출처: 노션 검증본 2026-05-22 | `apt upgrade -y` 가 핀 풀어 자동 상향. driver 측 CUDA 지원 13.0. reboot 필요 (a01 에서 처리). Phase 2: `apt-mark hold` 필요 |
| Docker CE | 의도 `5:23.0.6-1~ubuntu.22.04~jammy` → **실측 29.5.0** | `resources/docker-install.sh:22`; 실측 출처: 노션 검증본 | **jammy-pin** + `apt upgrade` 로 메이저 6단계 자동 점프. Phase 2: `apt-mark hold docker-ce docker-ce-cli` |
| Docker Compose Plugin | 5.1.3 (실측) | apt 의존성으로 동반 설치 | 스크립트가 명시적으로 핀 안 함 |
| containerd.io | 2.2.3 (실측) | apt 의존성 | |
| docker-buildx-plugin | 0.34.0 (실측) | apt 의존성 | |
| CUDA | 12.4.1 (local installer) | `resources/cuda-pytorch-install.sh:5,7` (`cuda-repo-ubuntu2204-12-4-local_12.4.1-550.54.15-1_amd64.deb`) | nvcc 기준 12.4 확정 (노션). NVIDIA driver 550.54.15 동봉되나 위 drift 로 580 가 최종. ubuntu2204-pin |
| CUDA toolkit | `cuda-toolkit-12-4` | `resources/cuda-pytorch-install.sh` (apt install) | |
| PyTorch | 2.6.0 (`+cu124`) | `resources/cuda-pytorch-install.sh:13` (`--index-url https://download.pytorch.org/whl/cu124`) | GPU 가속 정상 동작 확인 (노션) |
| torchvision | 0.21.0 (`+cu124`) | `resources/cuda-pytorch-install.sh:13` | torch 와 동시 핀 |
| cuDNN (PyTorch 번들) | 9.1.0.70 | pip transitive (`nvidia-cudnn-cu12`) | 노션 검증본 |
| triton | 3.2.0 | pip transitive (PyTorch 의존) | PyTorch GPU 컴파일러 |
| PyTorch CUDA pip wheels (cu12 시리즈) | `nvidia-cublas-cu12 12.4.5.8`, `nvidia-cuda-cupti/nvrtc/runtime-cu12 12.4.127`, `nvidia-cufft 11.2.1.3`, `nvidia-curand 10.3.5.147`, `nvidia-cusolver 11.6.1.9`, `nvidia-cusparse 12.3.1.170`, `nvidia-cusparselt 0.6.2`, `nvidia-nccl-cu12 2.21.5`, `nvidia-nvjitlink/nvtx-cu12 12.4.127` (총 13개) | pip transitive (torch 2.6.0+cu124 의존, 노션 pip list 실측) | 시스템 CUDA toolkit 과는 별도 — torch wheel 안에 동봉된 GPU 런타임. CUDA 메이저 12.4 으로 시스템 설치와 일치. Phase 2-6 분기 영향 큼 (Noble 의 torch wheel 이 어떤 cu 시리즈 끌어오는지 검증 필요) |
| Doosan DSR | `doosan-robotics/doosan-robot2 -b humble`, commit **ec92425** (2026-03-24, 노션), **33개 패키지 colcon 빌드 성공** | `resources/dsr-project-install.sh:4` | clone 위치 `~/cobot_ws/src/`. 주요 패키지: dsr-bringup2 0.1.2, dsr-msgs2 1.1.0, dsr-mujoco 0.1.0, dsr-visualservoing 0.0.0, dsr-example, dsr-tests. 지원 모델 10종 (A0509/A0912/E0509/H2017/H2515/M0609/M0617/M1013/M1509/P3020) |
| DSR Emulator (Docker image) | `doosanrobot/dsr_emulator:3.0.1` | upstream `install_emulator.sh:3` (`emulator_version="3.0.1"`), 본 레포 외부 자산 | a02 의 `dsr-project-install.sh:35 (./install_emulator.sh)` 가 `docker pull` 수행. humble/jazzy 브랜치 모두 동일 3.0.1, distro-agnostic |
| RealSense SDK | **의도**: apt `librealsense2-{dkms,utils,dev,dbg}`<br>**실측**: 위 4개 패키지 22.04 공식 공급 중단으로 설치 실패. `ros-humble-librealsense2` vendored 패키지 (SDK 2.57.7) 로 대체 동작 | `a04-realsense01.sh:11-15`; 실측 출처: 노션 검증본 | **Noble (24.04) 전환 시 Intel 공식 librealsense2 정식 지원 복귀 예정 → Phase 2-9 의 큰 호재**. 검증 카메라: D435I (firmware 5.17.0.10, USB 3.0) |
| realsense-ros (래퍼) | 4.57.7 | apt `ros-humble-realsense2-*` | a05 단계 |
| langchain | 0.3.27 | `a06-Voice.sh:1` | ✅ 의도 일치 (노션) |
| langchain-core | 0.3.86 (transitive) | pip 의존성 | langchain 0.3.27 이 끌어옴 |
| langchain-openai | 0.3.28 | `a06-Voice.sh:2` | ✅ 의도 일치 |
| langchain-upstage | 0.7.7 (transitive 또는 별도) | pip | 🟡 선언적 충돌 (core/openai 메이저 불일치) 동작 OK — 노션 |
| langchain-text-splitters | 0.3.11 (transitive) | pip (langchain 의존) | |
| langchain-protocol | 0.0.15 (transitive) | pip | |
| langsmith | 0.8.4 (transitive) | pip (langchain 의존) | |
| openai | 1.98.0 | `a06-Voice.sh:3` | ✅ 의도 일치 |
| httpx | 0.28.1 (transitive) | pip | |
| huggingface_hub | 0.36.2 (transitive) | pip | |
| tokenizers | 0.20.3 (transitive) | pip | |
| tiktoken | 0.12.0 (transitive) | pip | |
| pydantic | 2.13.4 (transitive) | pip | |
| python-dotenv | 1.2.2 (transitive) | pip | |
| sounddevice | 0.5.5 (실측, unpinned) | `a06-Voice.sh:4` | |
| PyAudio | 0.2.14 (실측) | python-dependency 또는 transitive | |
| openwakeword | 0.6.0 (실측) | python-dependency 또는 transitive | 호출어 인식. 내부적으로 `tflite-runtime 2.14.0` 사용 |
| numpy | 1.24.4 (`--ignore-installed`) | `a06-Voice.sh:5-6` | `pip uninstall -y numpy` 후 강제 재설치. Py3.10 전용. 🟡 opencv-python 4.13 은 numpy≥2 요구 (선언적 충돌, 실제 동작 OK — 노션) |
| scipy | 1.15.3 (실측) | pip (unpinned) | |
| pandas | 2.3.3 (실측) | pip (unpinned) | |
| polars | 1.40.1 (실측) | pip (unpinned) | |
| scikit-learn | 1.7.2 (실측) | pip (unpinned) | |
| matplotlib | 3.10.9 (실측) | pip (unpinned) | |
| ultralytics | 8.4.50 (실측) | pip (unpinned), `resources/python-dependency.sh` | YOLO. numpy<2 강제의 원인 |
| ultralytics-thop | 2.0.19 (transitive) | pip (ultralytics 의존) | FLOP 계산용 |
| supervision | 0.28.0 (실측) | pip (unpinned) | |
| opencv-python | 4.13.0.92 (실측) | pip (unpinned) | 🟡 numpy<2 와 선언적 충돌. 동작 OK |
| pyrealsense2 | 2.57.7.10387 (실측) | pip | |
| onnxruntime | 1.23.2 (실측) | pip | YOLO ONNX 추론 |
| tflite-runtime | 2.14.0 (실측) | pip (openwakeword transitive) | |
| pymodbus | 2.5.3 | `resources/python-dependency.sh:31` | ✅ 정확히 핀 — Doosan Modbus 통신용 |
| VS Code | 1.120.0 (실측), 패키지 빌드 `1.120.0-1778619059` | `a03-vs-code-install.sh` | `wget code.visualstudio.com/sboot/stable?platform=linux-deb-x64`. 설치 크기 약 645MB |
| Gazebo Classic | 11.10.2 (실측) | `resources/ros2-install.sh` (apt) | 기존 ROS2 예제 / MoveIt 데모용 |
| Ignition Gazebo (Fortress) | 6.17.1 (실측) | `resources/ros2-install.sh` (apt) | ROS2 Humble 공식 권장. `libignition-gazebo6-dev 6.17.1-1~jammy` |
| Gazebo apt repo key | gazebo-stable | `resources/ros2-install.sh:25-26` | **deprecated `apt-key add`** 로 키 등록 — Noble 에서 실패 |
| 시스템 라이브러리 (오디오/영상) | libportaudio2 / libportaudiocpp0 / portaudio19-dev 19.6.0, libsndfile1 1.0.31, libasound2-dev 1.2.6.1, ffmpeg + libavcodec/avformat/swscale-dev 4.4.2, libjpeg-dev 8c, libpng-dev 1.6.37, libtiff-dev 4.3.0, libpoco-dev 1.11.0, libyaml-cpp-dev 0.7.0 | `resources/python-dependency.sh` (apt) | Noble 대응 시 패키지명 동일 가능성 높음. 검증 필요 |
| Host 시스템 | Kernel 6.8.0-111-generic, GCC 11.4.0, GNU Make 4.3, Git 2.34.1 | OS 기본 (Ubuntu 22.04.x 갱신본) | 검증 환경 (노션, RTX 4060 Laptop) |
| Python 빌드 도구 (실측 노후) | `pip 22.0.2`, `setuptools 59.6.0`, `wheel 0.37.1` | Ubuntu 22.04 기본 (apt `python3-pip`) | **모두 2022년 빌드, 4년 이상 노후**. Py3.12 호환성에서 일부 wheel 빌드 실패 가능성. Phase 2-3 에서 `python3 -m pip install --upgrade pip setuptools wheel` 단계 권장 |
| ROS2 Python bindings (transitive, pip list 등록) | rclpy 3.3.21, ros2cli/pkg/topic/... 0.18.18, launch 1.0.14, launch-ros 0.19.13, tf2-*-py 0.25.20, rosidl-generator-py 0.14.6, ament-* 0.12.15, colcon-core 0.20.1 외 다수, rqt-* GUI 도구 일체 | apt `ros-humble-desktop` 가 `/opt/ros/humble/lib/python3.10/site-packages` 에 배치 → 셸 source 후 pip list 에 노출 | jazzy 전환 시 자동으로 해당 distro 의 동등 버전이 잡힘. 별도 핀 불필요. realsense2-camera-msgs 4.57.7 도 같은 경로로 등록 |

## Jazzy target (Phase 2 종료 시 작성)

> 본 섹션은 Phase 2-1 ~ 2-14 종료 후 채움. 현재 비어 있음.

```
| Layer | Version | Source citation | Notes |
|-------|---------|-----------------|-------|
| Ubuntu | 24.04 LTS (noble) | (Phase 2-4) | |
| Python | 3.12 (Ubuntu 24.04 기본) | implicit | numpy 1.26.4 필수 (Py3.10용 1.24.x 호환 안 됨) |
| ROS2 | jazzy | (Phase 2-1 config.sh) | `/opt/ros/jazzy/` |
| numpy | 1.26.4 (`<2`, ultralytics 호환) | (Phase 2-10) | ADR-002 |
| ... | | | |
```

---

## Transitive dependency 함정 (Hard Rule #8 보강)

- **numpy<2 강제**: YOLO `ultralytics` 가 numpy<2 를 요구. 대부분 최신 ML 라이브러리는 numpy>=2 를 끌어옴 → `pip install` 순서에 따라 silent 업그레이드 발생, ultralytics import 시 런타임 실패.
- **핀 위치**: 모든 `pip install` 단계의 **마지막**에 `pip install "numpy<2" --upgrade --force-reinstall`. 그 후 `python -c "import numpy, ultralytics"` import 검증.
- **install 순서 원칙**: ultralytics 먼저 → langchain/openai 다음 → numpy 마지막 재핀. langchain 의존성이 numpy>=2 끌어오는지 catch.
- 자세한 결정 근거: `docs/decisions/README.md` ADR-002.

### 실측 검증된 선언적 의존성 충돌 (노션 2026-05-22, `pip check`)

`pip check` 경고가 뜨지만 **실제 import 및 인스턴스 생성은 모두 통과**한 3건. Phase 2-10 Py3.12 + numpy 1.26.4 환경에서 재검증 필요:

| 충돌 쌍 | 원인 | 실제 동작 |
|---------|------|----------|
| `opencv-python 4.13.0` vs `numpy 1.24.4` | OpenCV wheel 메타데이터가 `numpy>=2` 요구 | ✅ OK |
| `langchain-upstage 0.7.7` vs `langchain-core 0.3.86` | 메이저 버전 불일치 (0.7 vs 0.3) | ✅ OK |
| `langchain-upstage 0.7.7` vs `langchain-openai 0.3.28` | 메이저 버전 불일치 | ✅ OK |

---

## 실측 vs 스크립트 의도 — drift 패턴 (`apt upgrade -y` 부작용)

노션 검증본의 핵심 발견: 스크립트가 명시한 핀 버전을 `sudo apt upgrade -y` 가 풀어버려 실제 설치 버전이 의도와 다름.

| 컴포넌트 | 스크립트 의도 | 실측 설치 | 영향 |
|---------|---------------|-----------|------|
| NVIDIA Driver | `nvidia-driver-570` | **580.159.03** | driver-side CUDA 13.0 지원 — 결과적 문제 없음 |
| Docker CE | `5:23.0.6-1~ubuntu.22.04~jammy` | **29.5.0** | 메이저 6단계 점프, 동작 정상 |
| RealSense (`librealsense2-{dkms,utils,dev,dbg}`) | apt 설치 | **미설치** (22.04 공급 중단) | ROS2 vendored 패키지 (`ros-humble-librealsense2`, SDK 2.57.7) 로 대체 동작 |

**근본 원인**: `apt upgrade -y` 가 명시적 `=VERSION` 핀까지 풀어버림. 진정한 잠금은 `apt-mark hold` 필요.

```bash
sudo apt install docker-ce=5:23.0.6-1~ubuntu.22.04~jammy ...
sudo apt-mark hold docker-ce docker-ce-cli   # ← 실제 잠금
```

Phase 2 작업: a01 의 `apt upgrade -y` 단계 직후 또는 패키지 설치 직후 `apt-mark hold` 호출 추가. `MIGRATION_NOTES.md § 11` 참조.

---

## 출처

- **스크립트 의도 (script intent)**: 본 레포 `*.sh` 파일들의 명시적 버전 핀 / 변수
- **실측 설치 버전 (verified install)** — 둘 다 작성 이정현, 검증일 2026-05-22, 환경 RTX 4060 Laptop + Ubuntu 22.04 LTS + ROS2 Humble:
  - 시스템 요약: 노션 "Rokey 협동2 개발 환경 (Version@20260522)" — https://www.notion.so/teamsparkx/Rokey-2-Version-20260522-36c563918e59803cb719ca55e3e3369f
  - 전체 `pip list` 스냅샷: 노션 "pip list (Version@20260522)" — https://www.notion.so/teamsparkx/pip-list-Version-20260522-36c563918e5980c0af76f8b4332454fe

---

## 갱신 트리거

본 매트릭스는 다음 변경 시 동시 갱신:
- 새 라이브러리 도입 → 행 추가
- 기존 라이브러리 버전 핀 변경 → Version + Notes 갱신
- 새 Ubuntu / ROS distro 라인 → 새 baseline 섹션 추가 (humble 유지하면서)
- 호환 안 되는 조합 발견 → Notes 에 "incompatible with X" 명시

매트릭스 없이 버전 변경 → Phase 2/3 작업에서 BLOCK.
