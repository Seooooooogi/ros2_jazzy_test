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
| ros-humble-* (DSR) | 15 패키지 | `backup/dsr-project-install.sh:9-23` | xacro, rclpy, std-msgs, joint-state-publisher-gui, launch-ros, rosgraph-msgs, ament-cmake, ament-pep257, ament-index-cpp, ament-lint-common, moveit-msgs, velocity-controllers, yaml-cpp-vendor, eigen3-cmake-module, ros2launch |
| ros-humble-* (ROS install) | 약 17 패키지 | `backup/ros2-install.sh:16,19-22,29` | control-msgs, realtime-tools, ros2-control, ros2-controllers, gazebo-msgs/gazebo-ros-pkgs, ros-gz-sim 등 |
| ros-humble-realsense2-* | apt 글로브 | `backup/a05-realsense02.sh:1` | |
| NVIDIA driver | 의도 570 → **실측 580.159.03** | `backup/nvidia-driver-install.sh` (`nvidia-driver-570 build-essential dkms`); 실측 출처: 노션 검증본 2026-05-22 | `apt upgrade -y` 가 핀 풀어 자동 상향. driver 측 CUDA 지원 13.0. reboot 필요 (a01 에서 처리). Phase 2: `apt-mark hold` 필요 |
| Docker CE | 의도 `5:23.0.6-1~ubuntu.22.04~jammy` → **실측 29.5.0** | `backup/docker-install.sh:22`; 실측 출처: 노션 검증본 | **jammy-pin** + `apt upgrade` 로 메이저 6단계 자동 점프. Phase 2: `apt-mark hold docker-ce docker-ce-cli` |
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
| Doosan DSR | `doosan-robotics/doosan-robot2 -b humble`, commit **ec92425** (2026-03-24, 노션), **33개 패키지 colcon 빌드 성공** | `backup/dsr-project-install.sh:4` | clone 위치 `~/cobot_ws/src/`. 주요 패키지: dsr-bringup2 0.1.2, dsr-msgs2 1.1.0, dsr-mujoco 0.1.0, dsr-visualservoing 0.0.0, dsr-example, dsr-tests. 지원 모델 10종 (A0509/A0912/E0509/H2017/H2515/M0609/M0617/M1013/M1509/P3020) |
| DSR Emulator (Docker image) | `doosanrobot/dsr_emulator:3.0.1` | upstream `install_emulator.sh:3` (`emulator_version="3.0.1"`), 본 레포 외부 자산 | a02 의 `backup/dsr-project-install.sh:35 (./install_emulator.sh)` 가 `docker pull` 수행. humble/jazzy 브랜치 모두 동일 3.0.1, distro-agnostic |
| RealSense SDK | **의도**: apt `librealsense2-{dkms,utils,dev,dbg}`<br>**실측**: 위 4개 패키지 22.04 공식 공급 중단으로 설치 실패. `ros-humble-librealsense2` vendored 패키지 (SDK 2.57.7) 로 대체 동작 | `backup/a04-realsense01.sh:11-15`; 실측 출처: 노션 검증본 | **Noble (24.04) 전환 시 Intel 공식 librealsense2 정식 지원 복귀 예정 → Phase 2-9 의 큰 호재**. 검증 카메라: D435I (firmware 5.17.0.10, USB 3.0) |
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
| VS Code | 1.120.0 (실측), 패키지 빌드 `1.120.0-1778619059` | `resources/base-install.sh vscode` (install.sh step 7) | `wget code.visualstudio.com/sboot/stable?platform=linux-deb-x64`. 설치 크기 약 645MB |
| Gazebo Classic | 11.10.2 (실측) | `backup/ros2-install.sh` (apt) | 기존 ROS2 예제 / MoveIt 데모용 |
| Ignition Gazebo (Fortress) | 6.17.1 (실측) | `backup/ros2-install.sh` (apt) | ROS2 Humble 공식 권장. `libignition-gazebo6-dev 6.17.1-1~jammy` |
| Gazebo apt repo key | gazebo-stable | `backup/ros2-install.sh:25-26` | **deprecated `apt-key add`** 로 키 등록 — Noble 에서 실패 |
| 시스템 라이브러리 (오디오/영상) | libportaudio2 / libportaudiocpp0 / portaudio19-dev 19.6.0, libsndfile1 1.0.31, libasound2-dev 1.2.6.1, ffmpeg + libavcodec/avformat/swscale-dev 4.4.2, libjpeg-dev 8c, libpng-dev 1.6.37, libtiff-dev 4.3.0, libpoco-dev 1.11.0, libyaml-cpp-dev 0.7.0 | `resources/python-dependency.sh` (apt) | Noble 대응 시 패키지명 동일 가능성 높음. 검증 필요 |
| Host 시스템 | Kernel 6.8.0-111-generic, GCC 11.4.0, GNU Make 4.3, Git 2.34.1 | OS 기본 (Ubuntu 22.04.x 갱신본) | 검증 환경 (노션, RTX 4060 Laptop) |
| Python 빌드 도구 (실측 노후) | `pip 22.0.2`, `setuptools 59.6.0`, `wheel 0.37.1` | Ubuntu 22.04 기본 (apt `python3-pip`) | **모두 2022년 빌드, 4년 이상 노후**. Py3.12 호환성에서 일부 wheel 빌드 실패 가능성. Phase 2-3 에서 `python3 -m pip install --upgrade pip setuptools wheel` 단계 권장 |
| ROS2 Python bindings (transitive, pip list 등록) | rclpy 3.3.21, ros2cli/pkg/topic/... 0.18.18, launch 1.0.14, launch-ros 0.19.13, tf2-*-py 0.25.20, rosidl-generator-py 0.14.6, ament-* 0.12.15, colcon-core 0.20.1 외 다수, rqt-* GUI 도구 일체 | apt `ros-humble-desktop` 가 `/opt/ros/humble/lib/python3.10/site-packages` 에 배치 → 셸 source 후 pip list 에 노출 | jazzy 전환 시 자동으로 해당 distro 의 동등 버전이 잡힘. 별도 핀 불필요. realsense2-camera-msgs 4.57.7 도 같은 경로로 등록 |

## Jazzy target (noble) — System layer 확정 (2026-05-28)

> System layer (a01: NVIDIA / Docker / ROS2 / Gazebo) 확정. Compute(CUDA/PyTorch — ADR-006 대기)
> / Robot(DSR) / Camera(RealSense) / Voice 레이어는 후속 마일스톤에서 추가.
> 드라이버·도커 실측 버전 숫자는 **핀하지 않고 설치 시점에 해소** → `bash install.sh`
> 실행 후 "_(a01 실행 후 기입)_" 칸을 실제 값으로 갱신할 것.

| Layer | Version | Source citation | Notes |
|-------|---------|-----------------|-------|
| Ubuntu | 24.04 LTS (noble) | `resources/config.sh` (`UBUNTU_CODENAME=noble`); `resources/base-install.sh ros2-desktop` OS 체크 | 다른 codename 이면 abort |
| Kernel | 6.17.0-35-generic (HWE) | `resources/base-install.sh kernel`; `resources/config.sh` (`KERNEL_META=linux-generic-hwe-24.04`) | HWE 트랙. `linux-generic-hwe-24.04` + `linux-headers-generic-hwe-24.04` 메타를 `--install-recommends` 로 명시 설치 → 커널 이미지 + 헤더 + `modules-extra`(wifi / 일부 USB 입력 드라이버) 를 함께 보장. 이 메타가 빠지면 다른 패키지가 커널 이미지만 끌어와 modules-extra 누락 → 부팅은 되나 wifi·USB 키보드가 사라지는 반쪽 커널이 됨. 실측 2026-06-01 |
| Python | 3.12 (noble 기본) | implicit (apt 기본 python3) | host 는 system Python 만 (ADR-008). application Python 은 Phase 4 컨테이너 |
| ROS2 | jazzy | `resources/config.sh` (`ROS_DISTRO=jazzy`) | `/opt/ros/jazzy/` |
| ROS apt key | `/etc/apt/keyrings/ros.gpg` (signed-by) | `resources/base-install.sh ros2-desktop` | humble 의 `/usr/share/keyrings/` 에서 이전 (Hard Rule #7 통일) |
| ros-jazzy-desktop | jazzy desktop 메타 (실측 `0.11.0-1noble.20260412`, pkg 374개) | `resources/base-install.sh ros2-desktop` | + ament-cmake, colcon-common-extensions/clean, rosdep, vcstool. 실측 2026-05-29 |
| ros-jazzy-* (robot/control) | control-msgs, realtime-tools, xacro, joint-state-publisher-gui, ros2-control, ros2-controllers, moveit-msgs, ament-lint-common, yaml-cpp-vendor, ros2launch, ament-pep257 | `resources/base-install.sh ros2-extras` | humble 의 `gazebo-msgs` 제거 (Classic 메시지는 `ros_gz_interfaces` 로 대체) |
| RMW (DDS) | **`rmw_cyclonedds_cpp` 표준** — `ros-jazzy-cyclonedds 0.10.5`, `ros-jazzy-rmw-cyclonedds-cpp 2.2.3` (실측 2026-06-05) | `resources/config.sh` (`RMW_IMPLEMENTATION`); `resources/app-install.sh colcon` (rmw 패키지 apt 설치); `resources/hostcfg.sh dds`; ADR-016 | fastrtps→cyclonedds 전환(ADR-016). **rmw 패키지(`ros-jazzy-rmw-cyclonedds-cpp`)는 `app-install.sh colcon` 이 colcon 빌드 직전 apt 설치(dpkg 가드로 멱등)** — ROS desktop 은 fastrtps 만 깔고 config.sh 가 기본 RMW 를 cyclonedds 로 고정하므로, 패키지가 없으면 colcon 이 dsr_msgs2 의 기본 RMW 를 해석하다 `Could not find ROS middleware implementation 'rmw_cyclonedds_cpp'` 로 CMake configure 실패(빌드 선행 조건). 대용량 토픽 수신엔 **커널 sysctl 버퍼 + XML(`CYCLONEDDS_URI`) 버퍼가 세트** 필요(`/etc/sysctl.d/60-cyclonedds.conf` rmem/wmem 2GB + `SocketReceive/SendBufferSize 64MB`). XML 은 **loopback 하나만** 화이트리스트한다(2026-07-23, ADR-039 — 물리 NIC 자동 고정 제거. 이 시스템 DDS 참여자는 전부 same-host 라 loopback 으로 붙고, 로봇·그리퍼는 DDS 가 아니라 TCP. 자동 탐지가 빈 NIC 이름을 렌더해 도메인 생성이 실패하던 사고 차단). cross-host 가 필요하면 `DDS_NETIF=<iface>` 로 명시 추가. host↔컨테이너는 동일 RMW + `ROS_DOMAIN_ID`(인스톨러가 묻지도 주입하지도 않는다 — 학생이 자기 `~/.bashrc` 에 직접 export 하는 연습 과제. 아무 데도 설정 안 하면 host·컨테이너 양쪽 다 ROS2 기본값 0 이라 한 머신 안에서는 여전히 매칭) + `network_mode: host`(커널버퍼·NIC 상속, 같은 netns 라 loopback 공유) |
| Gazebo | Harmonic (`ros-jazzy-ros-gz`) | `resources/base-install.sh ros2-extras` | packages.ros.org vendor 패키지. **별도 OSRF repo·apt-key 불필요**. humble 의 Classic 11 / Fortress 6 (`libignition-gazebo6-dev`) / `gazebo-ros-pkgs` 는 jazzy 빌드 없음(Classic EOL 2025-01) → 제거 |
| NVIDIA driver | **`nvidia-driver-595` (closed) 핀** (config: `NVIDIA_DRIVER_VERSION=595` / `NVIDIA_DRIVER_FLAVOR=""`) + 커널-모듈 메타 `linux-modules-nvidia-595-generic-hwe-24.04` + 드라이버 userspace `apt-mark hold` | `resources/base-install.sh nvidia` | 자동선택(`ubuntu-drivers install`) 폐기 — 머신/시점마다 다른 드라이버를 골라 비결정적이고, modules-extra 없는 반쪽 HWE 커널을 끌어와 재부팅 시 검은 화면(wifi/USB 입력 소실)을 유발했음. **open 변형은 Optimus(하이브리드) 노트북에서 디스플레이(gdm) 가 안 떠 closed 채택**(노트북 검증 2026-06-01). 커널-모듈 메타가 커널 업데이트 시 매칭 nvidia 모듈을 자동 추적(메타는 hold 안 함). 설치 후 **부팅 예정 커널에 nvidia.ko 존재를 재부팅 전 검증**, 없으면 중단. 드라이버 버전 595.71.05 / RTX 4060 Laptop |
| Docker CE | noble latest stable + `apt-mark hold docker-ce docker-ce-cli containerd.io` | `resources/base-install.sh docker` | jammy 핀(`5:23.0.6`) 폐기. keyring `/etc/apt/keyrings/docker.asc`. 설치 해소 버전: **29.5.2** (실측 2026-05-29) |
| containerd.io / docker-buildx-plugin / docker-compose-plugin | latest (containerd 는 hold) | `resources/base-install.sh docker` | 설치 해소 버전: **containerd v2.2.4 / buildx v0.34.1 / compose 5.1.4** (실측 2026-05-29) |
| NVIDIA Container Toolkit | `nvidia-container-toolkit` (NVIDIA libnvidia-container repo, noble; 실측 버전 클린설치 후 기재) | `resources/app-install.sh toolkit` — **`setup-app.sh` 의 `do_containers`** 가 호출(install.sh 소관 아님 — base 설치가 끝난 뒤 컨테이너 레이어에서). **`base-install.sh docker`(install.sh step 3) 시점 설치는 GPU 드라이버 커널 모듈 미로드로 실패** → install.sh step 6 의 reboot 이후로 밀어냈고, 지금은 아예 `setup-app.sh` 컨테이너 단계가 가져간다(그 시점이면 reboot 은 이미 지났다) | host GPU 를 컨테이너에 주입하는 런타임. compose `deploy.reservations.devices: nvidia` / `docker run --gpus` 가 의존 — 없으면 yolo 컨테이너가 GPU 로 못 떠 `compose up` 실패. keyring `/etc/apt/keyrings/nvidia-container-toolkit.gpg`(signed-by). `nvidia-ctk runtime configure --runtime=docker` 로 daemon.json 등록 후 docker 재시작(설치 흐름은 `ASSUME_YES=1` 자동). `SKIP_IF_NO_GPU=1` 면 nvidia-smi 부재를 정상 skip(GPU 없는 host 전용). 컨테이너 CUDA 는 PyTorch wheel 번들 — toolkit 은 드라이버 라이브러리 + `/dev/nvidia*` 주입만 |
| CUDA / CUDA toolkit | **host 미설치** — 12-8 (Phase 4 컨테이너) | ADR-006 (2026-05-29) | host colcon 패키지에 CUDA 소비자 없음(ADR-008). 12-8 은 Phase 4 yolo 컨테이너 base image 에서만. Noble repo 12-4 부재, cu130 PyTorch wheel 없음 → 12-8 채택 |
| PyTorch / torchvision | `cu128` — `application-containers`: 컨테이너만 · `application-shell`: **host venv** (ADR-014) | ADR-006 / ADR-008 / ADR-014 | 컨테이너 변종은 host `import torch`→ImportError 가 정상. shell 변종은 host venv 에 cu128 wheel(toolkit 불요) |
| Doosan DSR | `ROKEY-SPARK/doosan-robot2_jazzy` fork 의 `main` (= upstream `doosan-robotics/doosan-robot2` jazzy commit 816ecb5d 스냅샷 — fork 에 jazzy 브랜치 없이 핀이 main 에 있어 default 브랜치 clone), emulator `doosanrobot/dsr_emulator:3.0.1` 핀 | `resources/app-install.sh dsr` | clone 위치 `~/cobot2_ws/src/doosan-robot2`(setup-app.sh 가 호출). host 빌드(`app-install.sh colcon`) = doosan-robot2 + **사용자가 배치한 cobot2**(`robot_control`/`od_msg`/`rokey_cobot2`/`voice_processing`; `object_detection` 만 컨테이너(yolo) 전용이라 `--packages-skip`. `voice_processing` 은 host 직접 실행이라 host 에서 함께 빌드 — ADR-027). **cobot2 소스는 레포 미제공 — `~/cobot2_ws/src/cobot2` 에 사용자 배치**(setup-app.sh::obtain_cobot2 가 fail-loud 검증). DSR 전용 apt: `velocity-controllers`, `eigen3-cmake-module` (나머지는 rosdep 자동). 실측 2026-05-29: doosan-robot2 30개 패키지 colcon 빌드 성공, emulator 이미지 1.83GB |
| m0609_rg2_bringup (통합 bringup) | `Seooooooogi/M0609_RG2_Integration` 의 `jazzy` (`M0609_REF=jazzy` 기본 — **브랜치 추적, 커밋 핀 아님**. 레포는 distro 별 브랜치를 두며 `main` 은 `jazzy` 와 같은 내용을 유지) | `resources/config.sh` (`M0609_REPO_URL` / `M0609_REF` / `M0609_REPO_DIR`); `setup-app.sh::obtain_m0609` (workspace 단계 7개 중 cobot2 확인 직후 · doosan-robot2 직전) | clone 위치 `${M0609_REPO_DIR}=~/M0609_RG2_Integration`. **디렉토리가 이미 있으면 clone 을 건너뛴다** — 개발 중인 작업본을 덮어쓰지 않기 위함(cobot2 와 같은 원칙). 이때 `M0609_REF` 는 무시되므로 그 머신의 실제 리비전은 레포 현재 상태가 결정. 레포 전체가 아니라 `src/m0609_rg2_bringup` **패키지 하나만** `${DSR_WORKSPACE}/src` 로 심볼릭 링크(colcon 이 링크된 패키지를 인식하는 것 실측). 같은 레포의 `m0609_rg2_moveit` 은 moveit 스택을 통째로 끌어와 제외. 통합 bringup 진입점이 `cobot2_bringup bringup_all.launch.py` → `m0609_rg2_bringup bringup.launch.py` 로 교체됨(`containers/bringup.sh`). launch 인자: `mode`(virtual/real, 기본 virtual) / `host`(virtual 이면 127.0.0.1 강제) / `port` / `rt_host` / `camera` / `rviz` — 구 `gui` 인자 없음. 실측 2026-07-21: 심볼릭 링크 워크스페이스 colcon 5개 패키지 빌드 성공, virtual 모드 기동(DRCF 에뮬레이터 연결 + 컨트롤러 활성화 + 가상 그리퍼 노드). **실 로봇(`mode:=real`) · 실 RG2 그리퍼는 미검증**(하드웨어 필요) |
| onrobot-ros2 (RG2 그리퍼 패키지) | `ABC-iRobotics/onrobot-ros2` commit **c6e390313e831a2e54a0ad5894b2911cc360a16a** 핀 | `resources/config.sh` (`ONROBOT_REPO_URL` / `ONROBOT_COMMIT`); `setup-app.sh::obtain_m0609` | clone 위치 `${DSR_WORKSPACE}/src/onrobot-ros2`, clone 직후 해당 SHA 로 `git checkout`. **브랜치가 아니라 커밋으로 핀 — upstream 이 push 해도 이미 설치된 워크스페이스가 흔들리지 않게.** M0609 레포가 추적하지 않는 외부 패키지(description + msgs + Modbus 드라이버). `onrobot_rg_control/package.xml` 에 ROS1 잔재 키 `message_generation` / `message_runtime` 이 남아 jazzy rosdep 규칙이 없다 → `resources/app-install.sh colcon` 의 `--skip-keys` 가 기존 `librealsense2` 에 이 둘을 추가(`"librealsense2 message_generation message_runtime"`). 안 막으면 `set -e` 인 빌드 스크립트가 통째로 실패. `-r` 은 모든 해결 실패를 삼켜 미채택. `--reset` 은 이 clone 과 m0609 심볼릭 링크를 지운다(`${M0609_REPO_DIR}` 원본과 cobot2 는 보존) |
| librealsense2 SDK | `librealsense2-{dkms,utils,dev,dbg}` (RealSense AI apt repo, noble 정식) | `resources/app-install.sh realsense-sdk` | **humble 의 "22.04 공급 중단 → ROS vendored 폴백" 우회 불필요**. **2025-11 Intel→RealSense AI 분사**로 도메인/키 교체: repo `librealsense.realsenseai.com/Debian/apt-repo` (구 `librealsense.intel.com`), 서명 키 `…FB0B24895113F120` (2025-11 신 키, 구 intel `librealsense.pgp` 의 2018 키로는 NO_PUBKEY). keyring `/etc/apt/keyrings/librealsenseai.gpg` (`.asc` → dearmor). **DKMS 커널 모듈** — 빌드에 헤더 메타 `linux-headers-generic-hwe-24.04` + 현재 커널 헤더 동반(메타가 커널 업데이트 후 헤더를 자동 추적 → 재빌드 깨짐 방지). 커널 6.17.0-29/35 양쪽 DKMS 빌드 검증. 실측 2026-05-29: `librealsense2-utils 2.58.1-0~realsense.19174`, `librealsense2-dkms 1.3.31`, `ros-jazzy-realsense2-camera 4.57.7` |
| realsense-ros (래퍼) | `ros-jazzy-realsense2-camera` + `-description` (실측 candidate 4.57.7) | `resources/app-install.sh realsense-ros` | camera 가 realsense2-camera-msgs 동반. 원본 a05 의 `ros-humble-realsense2-*` glob 대신 명시 패키지 |
| RealSense 스트림 프로파일 (통합 bringup) | color `1280x720x30` / depth `848x480x30` + `align_depth.enable` / `enable_rgbd` / `enable_sync` / `pointcloud.enable` / `initial_reset` | `m0609_rg2_bringup/launch/bringup.launch.py:231-237` — **출처 이관**: 이전 기록 위치는 `cobot2_bringup/launch/bringup_all.launch.py:116-117`(값 자체는 변경 없이 그대로 옮김). 수동 실행 예시는 `README.md:107` / `docs/lecture-jazzy/협동로봇2_강의안_jazzy.md:84-86` 에도 동일 값 | **토픽 계약 변경(2026-07-21)**: 노드를 `namespace='/'` + `name='camera'` 로 띄운다 — 이전 `namespace='camera'` 조합이 내던 `/camera/camera/*` 의 중복 한 단계를 제거. namespace 인자를 지우는 것으로는 안 된다(드라이버 생성자 기본값이 `/camera` — `src/realsense_node_factory.cpp:34`). realsense2_camera 는 스트림 토픽을 private(`~/`)으로 만들어 최종 이름이 `/<node_namespace>/<node_name>/<stream>` 이 된다(근거: realsense-ros 4.58.1 `src/rs_node_setup.cpp:277-279`) → 이제 `/camera/color/image_raw`, `/camera/aligned_depth_to_color/image_raw`, `/camera/color/camera_info`. **TF 프레임은 별개 knob** — ROS 파라미터 `camera_name`(기본 `camera`)에서 나오므로 `camera_link` / `camera_color_optical_frame` 등은 **무변경**(근거: `src/parameters.cpp:24-28`, `include/base_realsense_node.h:86-90`), URDF 도 무변경. 소비자(yolo `object_detection` / `pick_and_place_text` / `pick_and_place_voice` 의 `realsense.py::ImgNode`)는 이 경로를 **절대 이름으로 구독**한다(2026-07-22 — 상대 이름 + remap 방식 폐기, 아래 yolo 컨테이너 note 참조). 프로파일 값 자체는 변경 없음. 새 launch 의 `camera` 인자 기본값은 **false**(standalone 개발 시 USB 카메라 미점유)이고 **`mode` 와 무관하다**(2026-07-22 — 그전에는 `mode:=real` 이 `camera` 값을 무시하고 강제 기동했다. 실기에서 카메라를 따로 띄우는 절차가 막히고 `camera:=false` 가 조용히 무시되어 제거). `containers/bringup.sh` 는 사용자가 `camera:=` 를 안 주면 `camera:=true` 를 덧붙인다(yolo 컨테이너 노드가 카메라 토픽 없으면 조용히 대기만 하므로). **실 RealSense 카메라 연결 검증은 미검증**(하드웨어 필요 — 기동 자체는 노드가 재시도 상태로 뜨는 것까지 확인). 위 이름 변경도 **이름 해석만 Jazzy 에서 실측**했고 실제 영상 수신은 미검증 |
| VS Code | `code` (Microsoft apt repo, codename 무관 stable main) | `resources/base-install.sh vscode` | 일회성 .deb 다운로드 → apt repo + keyring `/etc/apt/keyrings/packages.microsoft.gpg` (서명 키 `…EB3E94ADBE1229CF`). apt 관리 업데이트. `code` GUI 자동 실행 제거. 실측 버전: _(a03 실행 후 기입)_ |
| Voice (langchain/openai/sounddevice/numpy) | **host 직접 설치**(system pip `--break-system-packages`, ADR-027) — 컨테이너 아님 | `resources/app-install.sh voice` | 마이크 하드웨어 종속이라 host 실행. OPENAI 키 = 사용자가 `~/.config/cobot2/.env` 직접 생성(ADR-028 — `openai-key-setup.sh` 제거·인스톨러 자동생성 없음), `bringup.sh` 가 로드 |

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

## Phase 4 application Python 의존 (실측 빌드 2026-05-30, build gate)

두 애플리케이션 스택의 실측 버전. **yolo 는 컨테이너 안**, **voice 는 host system Python** — voice 는 마이크 하드웨어 종속 때문에 컨테이너를 폐기하고 host 직접 실행으로 이관했다 (ADR-027, 2026-07-08).
yolo 빌드 검증 = `containers/build-all.sh` (builder 스테이지 = `:dev-builder` 이미지 빌드 + 컨테이너 내부 import smoke). builder 엔 runtime entrypoint 가 없어 smoke 는 ROS + overlay 를 명시 source 후 import(pip 패키지는 system python 기본 sys.path 라 경로 주입 불요, ADR-034). 메이저 상한 핀은 Dockerfile 에 명시 (silent major drift 차단).
voice 설치 검증 = `resources/app-install.sh voice` 마지막의 `Model(.tflite)` 인스턴스화 + `predict` 1회 (import 만으론 모델 누락을 못 잡는다).

### yolo-detection (base `ros:jazzy-ros-base-noble`, Python 3.12)

| 패키지 | 실측 버전 | Dockerfile 핀 | 비고 |
|--------|----------|---------------|------|
| torch | 2.11.0+cu128 | cu128 index | CUDA 런타임 자체 번들 → host CUDA toolkit 불요 |
| torchvision | 0.26.0+cu128 | cu128 index | |
| ultralytics | 8.4.102 | `<9` | 메이저 상한 (2026-07-20 재빌드 실측 — 이전 8.4.56) |
| opencv-python | 4.9.0.80 | `<4.10` | 4.10+ 은 numpy>=2 메타 요구 → numpy<2 와 충돌. `<4.10` 으로 회피 (위 충돌표 1행 해소) |
| numpy | 1.26.4 | `<2` (선행 `--ignore-installed` + 마지막 재핀) | ultralytics 호환. apt numpy 는 pip RECORD 가 없어 제거 불가 → pip 소유 사본을 먼저 만들고 그 사본만 재핀 (ADR-034) |
| polars | 1.41.2 | (ultralytics 의존) | |

> 카메라는 **host 소유**(ADR-015, 2026-06-02): 이 컨테이너엔 realsense2_camera 드라이버를 두지 않는다. apt 런타임 ROS 의존은 `cv-bridge`/`sensor-msgs` 만(이미지 슬림화). host 가 카메라 토픽을 publish 하고 `object_detection` 노드는 subscribe — host 카메라 패키지는 위 시스템 표의 `ros-jazzy-realsense2-camera`(4.57.7) 행. host 측 카메라 노드를 띄우는 launch 는 `cobot2_bringup` 에서 `m0609_rg2_bringup` 으로 바뀌었고 스트림 프로파일도 그쪽으로 이관됐다(위 "RealSense 스트림 프로파일 (통합 bringup)" 행).
> **토픽 이름 변경 + remap 배선 (2026-07-21)**: host publish 경로가 `/camera/camera/*` → **`/camera/*`** 로 바뀌었다(중복 namespace 제거 — 위 프로파일 행). 종전의 "토픽 이름 동일 → 구독 경로 무변경" 서술은 이 변경으로 폐기. 컨테이너 `object_detection` 의 `ImgNode` 는 `/camera/color/image_raw`, `/camera/aligned_depth_to_color/image_raw`, `/camera/color/camera_info` 를 **절대 이름으로 구독**한다(2026-07-22 — 한때 상대 이름 + `-r img_node:__ns:=/camera` 였으나 인자 누락 시 조용한 무수신이라 되돌렸다). `containers/bringup.sh:140` 은 구 소스 머신을 위해 그 인자를 전환기 동안 유지한다.
> - **`img_node:` 접두사 필수** — 전역 `-r __ns:=/camera` 를 쓰면 같은 프로세스의 `object_detection_node` 까지 옮겨가 서비스가 `/camera/get_3d_position` 이 되고, `robot_control.py` 가 부르는 절대 경로 `/get_3d_position` 이 끊긴다(Jazzy 실측).
> - rcl 의 `**` 와일드카드 remap 은 **미구현**이다(Jazzy 실측: `Wildcard '**' is not implemented`) → 접두사 일괄 치환 불가. 네임스페이스 remap 또는 토픽 단위 remap 만 사용 가능.
> - `yolo-viz` 서비스(compose)와 `viz/live_detection.py` / `viz/viewer.py` 는 카메라 외 토픽(`/yolo/detections` 등)도 다루므로 `__ns` 통째 이동 대신 **토픽 단위 remap**(`-r color/image_raw:=/camera/color/image_raw`)을 쓴다.
> - 위험: remap 을 빠뜨려도 노드는 정상 기동하고 **에러 없이 토픽만 조용히 빈다**. 또한 소비자 소스(`~/cobot2_ws/src/cobot2`)는 이 레포도 다른 어떤 git 레포도 추적하지 않으므로, 프로듀서만 갱신되고 소비자 패치가 전달되지 않으면 파이프라인이 통째로 죽는다.
> DDS 통신: host↔컨테이너 동일 `RMW_IMPLEMENTATION`(표준 `rmw_cyclonedds_cpp`, ADR-016) + 동일 `ROS_DOMAIN_ID`(인스톨러가 묻지도 주입하지도 않는다 — 학생이 자기 `~/.bashrc` 에 직접 export 하는 연습 과제. 아무 데도 설정 안 하면 host·컨테이너 양쪽 다 ROS2 기본값 0 이라 한 머신 안에서는 여전히 매칭) + compose `network_mode: host` 필요(`resources/config.sh` 가 host 에, compose env 가 컨테이너에 주입). compose 가 host 의 `cyclonedds.xml` 을 컨테이너에 mount 하고, `network_mode: host` 라 커널 소켓 버퍼·NIC 화이트리스트(loopback-only, ADR-039)를 그대로 상속한다(같은 netns 라 host↔컨테이너는 loopback 으로 붙음, 컨테이너 내 별도 sysctl 불필요).

### voice_processing — host system Python 3.12 (컨테이너 폐기, ADR-027)

`resources/app-install.sh voice` 가 host 의 system Python 에 `pip --break-system-packages` 로 설치한다 (venv 아님 — 사용자 결정). 핀은 폐기된 컨테이너 레시피(`backup/voice-processing/Dockerfile`)와 `scripts/venv-demo/LAB.md` Part A4 의 검증본을 그대로 미러링한다. 아래 실측 버전은 컨테이너 빌드 게이트(2026-05-30) 측정치이며, 같은 핀으로 host 에 설치된다.

| 패키지 | 실측 버전 | 핀 (`app-install.sh voice`) | 비고 |
|--------|----------|---------------|------|
| langchain | 1.3.2 | `<2` | 메이저 사이 import 경로 변경 위험 (`langchain.prompts` → `langchain_core.prompts`) |
| langchain-core | 1.4.0 | (langchain 의존) | |
| langchain-openai | 1.2.2 | `<2` | |
| openai | 2.38.0 | `<3` | |
| openwakeword | 0.6.0 | `==0.6.0` (`--no-deps`) | wake-word. 모델이 `.tflite`. 0.6.0 은 tflite-runtime 의존 강제 → `--no-deps` 로 회피 |
| ai-edge-litert | 2.1.5 | `>=2.0.2,<3` | tflite-runtime(Py3.12 wheel 없음) 대체. `tflite_runtime→ai_edge_litert` shim 으로 openwakeword 의 `.tflite` 로드 |
| onnxruntime | 1.26.0 | `<2,>=1.10.0` (openwakeword 실제 의존, 명시 설치) | |
| scikit-learn / tqdm / requests | 1.8.0 / 4.67 / 2.34 | (openwakeword 실제 의존, 명시) | `--no-deps` 로 빠진 base 의존 보충 |
| scipy | 1.17.1 | `<1.18` | 1.18+ 은 런타임 numpy>=2.0 요구(np.long 사용) → numpy<2 재핀과 충돌. `<2` 면 1.18 로 drift |
| numpy | 1.26.4 | `<2` (**마지막에 재핀**) | scipy/scikit-learn 이 numpy>=2 를 끌어온다 → 설치 순서상 반드시 최후에 `--force-reinstall`. 설치 스크립트가 `numpy.__version__` 이 `1.` 로 시작하는지 단언 |
| python-dotenv | 1.2.2 | — | `.env` 의 `OPENAI_API_KEY` 로드 |
| sounddevice | 0.5.5 | — | |
| PyAudio | 0.2.14 | — | apt `portaudio19-dev` 빌드 의존 |

> openwakeword 검증: `import` 가 아닌 **`Model(.tflite)` 인스턴스화 + predict** 로 확인. `import openwakeword` 는 `.tflite` 를 열지 않아 모델이 없어도 통과한다(2026-07-09 실측). `app-install.sh voice` 와 `LAB.md` Part A4 검증 블록 양쪽이 이 게이트를 건다.
> feature 모델(melspectrogram/embedding/VAD)은 wheel 미동봉. 초기(ADR-014)엔 `download_models()` 로 받았으나, transient 504 시 에러 HTML 을 `.tflite` 로 저장해 런타임에 크래시했다 → 지금은 `resources/oww_models/` 동봉본을 복사하고 `TFL3` 식별자(offset 4)를 검증한다. 다운로드 경로 미사용.
> `tflite-runtime` 은 Python 3.12 wheel 이 없다(cp311 이 마지막). 그래서 openwakeword 를 `--no-deps` 로 깔고, 후속작 `ai-edge-litert`(cp312, 동일 `Interpreter` API)를 `tflite_runtime.interpreter` 이름으로 노출하는 shim 을 site-packages 에 만든다. Humble baseline 표의 `tflite-runtime 2.14.0` 행은 Python 3.10 환경이라 그대로 유효하다 — 혼동 주의.
> 이미지 크기 (build gate 측정, voice 컨테이너 폐기 전): yolo ≈ 13.6GB (nvidia CUDA 런타임 ≈4.2GB 가 지배), voice ≈ 1.9GB.
> `OPENAI_API_KEY` 는 host `.env` 에서 런타임 주입 (ADR-007). transitive 완전 잠금(lock 파일)은 추후 과제.

---

## application-shell host Python (venv) — 폐기된 브랜치 기록 (ADR-014, 2026-06-02)

> **폐기된 브랜치(`feat/application-shell`) 기록** — 아래 `${HOST_VENV}` 와 `resources/host-python-deps.sh` 는
> **현재 트리에 없다**(`grep -rn HOST_VENV resources/` = 0). 그 브랜치에만 존재했고, 핀 목록의 참고 가치 때문에
> 남겨 둔다. 현행 host Python 은 바로 위 voice 절(`app-install.sh voice`, system pip — 컨테이너 아님)이다.

`feat/application-shell` 은 컨테이너 없이 host 단독 실행이라, 위 컨테이너 핀을 host venv
(`${HOST_VENV}=~/cobot2_ws/.venv`, `--system-site-packages`)에 동일하게 설치**했다**(`resources/host-python-deps.sh`).
컨테이너 변종(`application-containers`)은 이 설치를 하지 않고 robot_control 용 thin client 만 뒀다.

| 묶음 | 핀 | 비고 |
|------|----|------|
| torch / torchvision | `--index-url .../cu128` | yolo 컨테이너와 동일. host CUDA toolkit 불요(wheel 번들) |
| ultralytics / opencv-python / supervision | `<9` / `<4.10` / — | yolo 컨테이너 미러링 |
| langchain / langchain-openai / openai | `<2` / `<2` / `<3` | voice 컨테이너 미러링 |
| openwakeword (+ ai-edge-litert, shim) | `==0.6.0 --no-deps` / `>=2.0.2,<3` | voice 컨테이너와 동일 레시피 (`tflite_runtime`→`ai_edge_litert`) |
| pymodbus | `<3.7` (3.x) | onrobot.py 가 3.x API(`slave=`)로 이관됨. 단 3.7 부터 client 잉여 kwargs 제거 → onrobot.py 의 `ModbusTcpClient(stopbits/bytesize/parity/baudrate)` 가 TypeError (3.13.1 실측) → `<3.7` 로 상한 고정 (3.6.9 실측 OK) |
| scipy / pyaudio / sounddevice / python-dotenv | `<2` / — / — / — | ⚠ scipy 1.18+ 은 런타임 numpy>=2.0 요구(np.long) → numpy<2 재핀과 충돌. 컨테이너는 `<1.18` 로 고정함. 이 shell 변종도 동일 수정 요망(미검증 — host-python-deps.sh 부재) |
| numpy | `<2` (마지막 `--force-reinstall`) | ultralytics 호환 (ADR-002) |

> 시스템 라이브러리(apt): `portaudio19-dev libportaudio2 libsndfile1 libasound2-dev ffmpeg libgl1` (+ python3-dev/venv/pip).
> 실측 버전은 host-python-deps.sh 최초 실행 후 기입(_TBD — 실기 noble/3.12_). 이 dev 머신은 jammy/3.10 이라 검증 불가.
> `ros2 run` 연동: colcon 빌드를 venv active 에서 수행 → ament_python entry_point shebang 이 venv python 을 가리킴.

---

## 데모 venv — uv 배포/복구 경로 (2026-07-20)

학생 배포/복구용 원커맨드 경로(`scripts/venv-demo/uv/setup.sh`)의 도구 핀. 스택 핀 자체는 위 Phase 4 절과 `scripts/venv-demo/requirements.txt` 의 검증본을 그대로 미러(원천 동일). 설계·실측 근거 = `docs/specs/2026-07-20-venv-uv-student-setup-design.md`.

| Layer | Version | Source citation | Notes |
|-------|---------|-----------------|-------|
| uv | 0.11.2 | `scripts/venv-demo/uv/setup.sh` (`UV_VERSION`, astral.sh 버전 핀 installer) | `dependency-metadata`(openwakeword·roboflow 의존 교체) + `override-dependencies`(numpy<2) + explicit index(torch cu128) 동작을 실측한 버전. 학생 머신은 `uv sync --frozen` 전용 |
| 스택 lock | `scripts/venv-demo/uv/uv.lock` | `uv lock` 산출물 (갱신: pyproject 수정 → `uv lock` → 커밋) | requirements.txt(LAB)와 수동 동기 — 한쪽 갱신 시 다른 쪽 확인 |

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
