# Migration Notes — humble → jazzy

Phase 2 작업에서 빠짐없이 처리해야 할 모든 지점. 본 문서가 Phase 2 의 task checklist 역할.

**검증 명령** (본 문서의 카운트가 실제 grep 결과와 일치하는지 확인):
```bash
grep -RInE 'humble|jammy|22\.04|ubuntu2204' *.sh resources/*.sh | wc -l   # 약 56 라인
grep -L 'set -e' *.sh resources/*.sh                                      # 11개 파일
grep -RIn 'apt-key add' *.sh resources/*.sh                               # 1 (ros2-install.sh:26)
```

---

## 1. Execution graph (Phase 1-1)

```
a01-prerequirements.sh                              [ENTRY — has `set -e`]
├── resources/nvidia-driver-install.sh              [apt upgrade + nvidia-driver-570 + dkms]
├── resources/docker-install.sh                     [Docker CE 23.0.6 jammy-pinned]
└── resources/ros2-install.sh                       [ROS2 Humble + Gazebo (deprecated apt-key add)]
    └── resources/ros2-humble-desktop-main.sh       [has `set -eu`, TARGET_OS=jammy validation]
[sudo reboot]                                       [a01:13 — state-changing, no confirm]

a02-about-project.sh                                [has `set -e`]
├── resources/cuda-pytorch-install.sh               [CUDA 12.4 + PyTorch 2.6.0 cu124, ubuntu2204-pinned]
├── resources/python-dependency.sh                  [apt + pip mixed, pymodbus==2.5.3]
└── resources/dsr-project-install.sh                [doosan-robot2 -b humble clone]

a03-vs-code-install.sh                              [standalone, no shebang, no set -e]
a04-realsense01.sh                                  [standalone, no set -e, libgtk-3-dev purge]
a05-realsense02.sh                                  [standalone, no set -e, assumes ROS2 humble sourced]
a06-Voice.sh                                        [standalone, no set -e, numpy 1.24.4 force-reinstall]

[ORPHANED]
resources/dsr-project-install_25.sh                 [not called by any a0X — dead Ubuntu 24.04 흔적]
```

Docker layer (Phase 1-3 시점): 본 레포에 **Dockerfile 없음** (host installer 범위 안). `docker pull/run hello-world` 는 install verification 용 1회 호출 (`resources/docker-install.sh:29,32`).

**Phase 4 (2026-05-27 사용자 결정) 에서 변경 예정**: `containers/yolo-detection/` + `containers/voice-processing/` 두 Dockerfile 신설. `containers/docker-compose.yml` 로 동시 운영. Phase 2-3 (host installer) 작업 자체는 영향 없음 — Phase 4 진입 시 별도 추가.

**단, 외부 Docker 이미지 1개가 설치 흐름 중 pull 됨** (참고용):
- 이미지: `doosanrobot/dsr_emulator:3.0.1` — Doosan 공식 emulator 이미지 (Docker Hub)
- Pull 위치: `a02 → resources/dsr-project-install.sh:35 (sudo ./install_emulator.sh)` → upstream 의 `install_emulator.sh` 가 `docker pull` 수행
- 핀 위치: `doosan-robot2` upstream repo 의 `install_emulator.sh:3` (`emulator_version="3.0.1"`) — 본 레포 직접 통제 바깥
- humble / jazzy 브랜치 양쪽 동일한 3.0.1 사용 → distro-agnostic, 마이그레이션 시 이미지 변경 불필요
- Hard Rule #6 (태그 핀 고정) 충족 (`latest` 아님)
- 컨테이너 명명 규칙: name 에 `emulator` suffix (upstream `run_drcf.sh` 가 사용)
- **Phase 2 검증 항목**: 이미지 자체는 ROS distro 비종속이나 publish 메시지 / DDS 프로토콜이 ROS2 Jazzy 와 호환되는지 실제 통신 테스트 필요 (Phase 2-8 / Phase 3 TROUBLESHOOTING 검토)

참고로 doosan-robot2 repo 에는 `.devcontainer/` (VS Code dev container 설정 — installer 흐름과 무관) 와 `dsr_mujoco/` (Mujoco 시뮬레이션 패키지 — installer 흐름과 무관) 도 존재. 본 프로젝트의 마이그레이션 대상 아님.

---

## 2. 하드코딩 distro / Ubuntu 인벤토리 (총 56 라인, Hard Rule #1 위반)

### 2.1 ROS2 distro (`humble`)

| File:line | Content | Phase 2 변경안 |
|-----------|---------|----------------|
| a05-realsense02.sh:1 | `sudo apt install ros-humble-realsense2-* -y` | `ros-${ROS_DISTRO}-realsense2-*` |
| a05-realsense02.sh:11 | `ROS_DISTRO=humble  # set your ROS_DISTRO: iron, humble, foxy` | `ROS_DISTRO=${ROS_DISTRO:-jazzy}` (또는 `source config.sh`) — 주석의 distro 목록도 `jazzy, kilted` 로 갱신 |
| resources/ros2-humble-desktop-main.sh:12 | `CHOOSE_ROS_DISTRO=humble` | `CHOOSE_ROS_DISTRO=${ROS_DISTRO}` |
| resources/ros2-humble-desktop-main.sh:54 | `... ros-humble-ament-cmake libzmq3-dev -y` | `ros-${ROS_DISTRO}-ament-cmake` |
| resources/ros2-install.sh:5 | `chmod +x ./resources/ros2-humble-desktop-main.sh` | 파일명 자체 변경 → `ros2-desktop-main.sh` (distro-agnostic) |
| resources/ros2-install.sh:8 | `./resources/ros2-humble-desktop-main.sh` | 위와 동일 (distro-agnostic 호출) |
| resources/ros2-install.sh:10 | `export CMAKE_PREFIX_PATH=/opt/ros/humble:${CMAKE_PREFIX_PATH}` | `/opt/ros/${ROS_DISTRO}` |
| resources/ros2-install.sh:16 | 8 `ros-humble-*` 패키지 (control-msgs, realtime-tools, xacro, joint-state-publisher-gui, ros2-control, ros2-controllers, gazebo-msgs, moveit-msgs) | `ros-${ROS_DISTRO}-*` |
| resources/ros2-install.sh:19-22 | 4 `ros-humble-*` 패키지 (ament-lint-common, yaml-cpp-vendor, ros2launch, ament-pep257) | `ros-${ROS_DISTRO}-*` |
| resources/ros2-install.sh:29 | 3 `ros-humble-*` 패키지 (gazebo-ros-pkgs, moveit-msgs, ros-gz-sim) | `ros-${ROS_DISTRO}-*` |
| resources/dsr-project-install.sh:4 | `git clone -b humble https://github.com/doosan-robotics/doosan-robot2.git` | `-b ${ROS_DISTRO}` — **단, doosan-robot2 upstream 에 jazzy 브랜치 존재 여부 사전 검증 필수** (§ 7 참조) |
| resources/dsr-project-install.sh:9-23 | 15 `ros-humble-*` 패키지 (xacro, rclpy, std-msgs, joint-state-publisher-gui, launch-ros, rosgraph-msgs, ament-cmake, ament-pep257, ament-index-cpp, ament-lint-common, moveit-msgs, velocity-controllers, yaml-cpp-vendor, eigen3-cmake-module, ros2launch) | `ros-${ROS_DISTRO}-*` |
| resources/dsr-project-install.sh:38 | `source /opt/ros/humble/setup.bash` | `/opt/ros/${ROS_DISTRO}/` |
| resources/dsr-project-install.sh:39 | `export ROS_DISTRO=humble` | `${ROS_DISTRO}` (또는 config.sh 참조로 통일) |

### 2.2 Ubuntu version (`jammy` / `22.04` / `ubuntu2204`)

| File:line | Content | Phase 2 변경안 |
|-----------|---------|----------------|
| resources/ros2-humble-desktop-main.sh:14 | `TARGET_OS=jammy` | `TARGET_OS=noble` (또는 `${UBUNTU_CODENAME}`) |
| resources/docker-install.sh:22 | `VERSION_STRING=5:23.0.6-1~ubuntu.22.04~jammy` | Noble 호환 Docker CE 버전을 별도 확인 후 `5:X.Y.Z-1~ubuntu.24.04~noble` |
| resources/cuda-pytorch-install.sh:3 | `wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin` | `ubuntu2404` URL (NVIDIA CUDA Noble repo 활성 시점 사전 검증, § 7) |
| resources/cuda-pytorch-install.sh:4 | `sudo mv cuda-ubuntu2204.pin ...` | `cuda-ubuntu2404.pin` |
| resources/cuda-pytorch-install.sh:5 | `wget .../cuda-repo-ubuntu2204-12-4-local_12.4.1-550.54.15-1_amd64.deb` | Noble 용 CUDA 12.x local installer 확인 (12.4 가 Noble 지원 안 하면 12.6+) |
| resources/cuda-pytorch-install.sh:6 | `sudo dpkg -i cuda-repo-ubuntu2204-12-4-local_*` | 위와 동일 |
| resources/cuda-pytorch-install.sh:7 | `sudo cp /var/cuda-repo-ubuntu2204-12-4-local/cuda-*-keyring.gpg /usr/share/keyrings/` | 위와 동일. **keyring 경로를 `/etc/apt/keyrings/` 로 통일** 검토 (§ 5 참조) |

### 2.3 `noble` / `24.04` 현재 등장 횟수: **0** (Phase 2 의 모든 변경은 신규 도입)

---

## 3. Deprecated patterns (Phase 2)

### 3.1 `apt-key add` (Hard Rule #7 위반)

| File:line | Content | Phase 2 변경안 |
|-----------|---------|----------------|
| resources/ros2-install.sh:26 | `wget http://packages.osrfoundation.org/gazebo.key -O - \| sudo apt-key add -` | `curl -fsSL http://packages.osrfoundation.org/gazebo.key \| sudo gpg --dearmor -o /etc/apt/keyrings/gazebo.gpg` + sources.list 의 `deb` 라인을 `signed-by=/etc/apt/keyrings/gazebo.gpg` 로 갱신 (Ubuntu 24.04 에선 apt-key 호출 시 경고/실패) |

### 3.2 Keyring 경로 일관성 (Hard Rule #7)

현재 외부 repo 키링 경로 분포:
- `/etc/apt/keyrings/librealsense.pgp` — `a04-realsense01.sh:2`
- `/etc/apt/keyrings/docker.asc` — `resources/docker-install.sh:7`
- `/usr/share/keyrings/ros-archive-keyring.gpg` — `resources/ros2-humble-desktop-main.sh:51`
- `/usr/share/keyrings/cuda-*-keyring.gpg` — `resources/cuda-pytorch-install.sh:7` (`cp` 로 복사)

**불일치**: ROS + CUDA 는 `/usr/share/keyrings/`, RealSense + Docker 는 `/etc/apt/keyrings/`. Ubuntu 24.04 권장은 `/etc/apt/keyrings/` 로 통일. Phase 2-11 작업 시 4개 경로 통일 + `signed-by=` 도 동일 경로로 갱신.

---

## 4. `set -euo pipefail` 누락 인벤토리 (Hard Rule #5)

11/14 파일에 누락. Phase 2 에서 모두 강화.

| File | 현재 | Phase 2 변경안 |
|------|------|----------------|
| a01-prerequirements.sh | `set -e` (line 2) | `set -euo pipefail` |
| a02-about-project.sh | `set -e` (line 2) | `set -euo pipefail` |
| resources/ros2-humble-desktop-main.sh | `set -eu` (line 2) | `set -euo pipefail` |
| a03-vs-code-install.sh | **없음** (shebang 도 없음) | `#!/bin/bash` + `set -euo pipefail` |
| a04-realsense01.sh | **없음** (shebang 도 없음) | `#!/bin/bash` + `set -euo pipefail` |
| a05-realsense02.sh | **없음** (shebang 도 없음) | `#!/bin/bash` + `set -euo pipefail` |
| a06-Voice.sh | **없음** (shebang 도 없음) | `#!/bin/bash` + `set -euo pipefail` |
| resources/cuda-pytorch-install.sh | **없음** | `#!/bin/bash` + `set -euo pipefail` |
| resources/docker-install.sh | **없음** | `#!/bin/bash` + `set -euo pipefail` |
| resources/dsr-project-install.sh | **없음** | `#!/bin/bash` + `set -euo pipefail` |
| resources/dsr-project-install_25.sh | **없음** | (orphaned — § 6 참조) |
| resources/nvidia-driver-install.sh | **없음** | `#!/bin/bash` + `set -euo pipefail` |
| resources/python-dependency.sh | **없음** | `#!/bin/bash` + `set -euo pipefail` |
| resources/ros2-install.sh | **없음** | `#!/bin/bash` + `set -euo pipefail` |

---

## 5. Idempotency 결함 (Hard Rule #2)

명시적 가드 없는 재실행-위험 작업:

| File:line | Issue | Phase 2 가드 |
|-----------|-------|--------------|
| a04-realsense01.sh:6 | `tee /etc/apt/sources.list.d/librealsense.list` 무조건 덮어쓰기 | `[[ -f $TARGET ]] || tee ...` 또는 항상 idempotent 한 tee (현재 동작도 사실상 idempotent 하나 명시 권장) |
| a04-realsense01.sh:11-15 | `apt install librealsense2-*` 재실행 시 DKMS 재빌드 위험 | `dpkg -s` 사전 체크 후 install |
| a04-realsense01.sh:17 | `realsense-viewer` 자동 실행 (GUI) | install 종료 후 자동 launch 제거 — 사용자 결정 |
| resources/docker-install.sh | Docker 사전 설치 여부 미체크 | `command -v docker` 사전 체크, 이미 있으면 skip |
| resources/docker-install.sh:29,32 | `docker pull hello-world` + `docker run hello-world` 재실행 시 무해하나 출력 노이즈 | 첫 실행 시만 검증, 이후 skip |
| resources/dsr-project-install.sh:1 | `mkdir -p ~/cobot_ws/src` (idempotent) | OK |
| resources/dsr-project-install.sh:4 | `git clone -b humble ... doosan-robot2.git` 재실행 시 실패 (already exists) | `[[ -d doosan-robot2 ]] && git -C doosan-robot2 pull \|\| git clone ...` |
| resources/dsr-project-install.sh:30 | `rosdep init` (이미 init 됐으면 실패) | `[[ -f /etc/ros/rosdep/sources.list.d/20-default.list ]] \|\| sudo rosdep init` |
| a06-Voice.sh:5 | `pip uninstall -y numpy` 무조건 실행 | numpy 버전 확인 후 분기 또는 `pip install "numpy<2" --upgrade --force-reinstall` 한 줄로 통합 (ADR-002) |
| resources/python-dependency.sh:11 | `pip uninstall -y numpy` 추정 (확인 필요) | a06 과 동일 패턴 |
| resources/ros2-install.sh:25-26 | sources.list 덮어쓰기 + `apt-key add` (deprecated) | 위 § 3.1 + 가드 |

---

## 6. Orphaned / dead 스크립트

`resources/dsr-project-install_25.sh` — a0X 어느 곳에서도 호출되지 않음. dsr-project-install.sh 의 변형으로, 다음 차이:
- 워크스페이스 생성 / DoosanBootcamp / gz_ros2_control clone 모두 주석 처리 (line 1, 4, 5)
- `install_emulator.sh` 호출에서 sudo 제거 (line 38, 추정)
- PYTHONPATH export 활성 (line 47)
- 동일하게 `ros-humble-*` 패키지 15개 + `/opt/ros/humble/` + `ROS_DISTRO=humble`

**해석**: Ubuntu 24.04 또는 sudo-less 환경에서 dsr-project-install 을 재현하려는 미완성 시도. `_25` 접미사는 "v2.5" 또는 "Ubuntu 25.x 실험" 둘 다 가능 (확인 불가). 2026-05-27 사용자 결정: 본 파일 포함 humble 시절 resources/ 8개 모두 `backup/` 으로 이동 완료.

---

## 7. External dependencies — Phase 2 진입 전 사전 검증 (CRITICAL)

다음 4건은 Phase 2 설계 자체를 좌우. ADR-003 후보:

| 의존성 | 검증 질문 | 검증 방법 | 부재 시 |
|--------|-----------|-----------|---------|
| doosan-robot2 upstream `jazzy` 브랜치 | `https://github.com/doosan-robotics/doosan-robot2` 에 `jazzy` 브랜치 또는 태그 존재? | `git ls-remote https://github.com/doosan-robotics/doosan-robot2.git \| grep -E 'jazzy\|refs/tags'` | Phase 3 TROUBLESHOOTING 카탈로그에 회피 절차 (humble 브랜치 cross-build 또는 fork) 기록. Phase 2 설계 분기 |
| NVIDIA CUDA Noble repo | `developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/` 활성? | `curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/ \| head` | Phase 2-6 보류 — Ubuntu 22.04 환경 유지 검토 |
| librealsense2 Noble apt repo | `librealsense.intel.com/Debian/apt-repo` 의 `noble` 코드네임 활성? | `apt-cache madison librealsense2` 또는 release notes | Phase 2-9 보류 — 소스 빌드 또는 humble 환경 유지 |
| ROS2 Jazzy Noble packages | `packages.ros.org/ros2/ubuntu noble main` 가용? | `apt-cache search ros-jazzy-` (apt source 추가 후) 또는 ROS2 release docs | Phase 2 전체 보류 |

**위 4건 검증 결과를 Phase 2 시작 전에 ADR-003 으로 기록**. 1건이라도 부재면 Phase 2 설계 변경 필요.

---

## 8. State-changing / 비가역 명령 인벤토리 (Hard Rule #9)

| File:line | Command | 위험도 | Phase 2 보강 |
|-----------|---------|--------|--------------|
| a01-prerequirements.sh:13 | `sudo reboot` | HIGH — 진행 중 작업 손실 | confirm prompt (`read -p "Reboot now? (y/N): " ans; [[ $ans = y ]] \|\| exit 0`) |
| a04-realsense01.sh:9 | `sudo apt-get remove --purge libgtk-3-dev -y` | MEDIUM — 다른 패키지 의존성 깨질 가능성 | `-y` 제거하고 사용자 확인 + 영향받는 패키지 목록 출력 |
| resources/nvidia-driver-install.sh | NVIDIA 드라이버 교체 | HIGH — 기존 드라이버 강제 제거 | 현재 드라이버 버전 확인 + 사용자 confirm |
| resources/docker-install.sh | usermod docker group | MEDIUM — 재로그인 필요 | 사용자에게 재로그인 안내 출력 |

---

## 9. Pip 의존성 — Python 3.12 호환성 재핀 필요 (Phase 2-10)

| Package | 현재 핀 | Py3.12 호환 후보 | 검증 필요 |
|---------|---------|------------------|-----------|
| numpy | 1.24.4 | **1.26.4** (ADR-002 결정) | ultralytics 호환 — numpy<2 강제 |
| langchain | 0.3.27 | upstream 최신 (numpy>=2 끌어오는지 catch) | ultralytics 와 동시 사용 시 충돌 |
| langchain-openai | 0.3.28 | upstream | |
| openai | 1.98.0 | upstream | |
| pymodbus | 2.5.3 | upstream Py3.12 지원 시점 확인 | 2.5.3 이 Py3.12 호환 안 되면 3.x 필요 |
| torch | 2.6.0 cu124 | CUDA 12.x Noble 지원 매트릭스 확인 | torch 2.6 이 cu124 Noble wheel 제공? |
| torchvision | 0.21.0 cu124 | torch 와 페어 | |
| sounddevice, opencv-* 등 unpinned | — | unpinned 유지 vs 핀 결정 | numpy 충돌 발생 시 핀 강제 |

**Install 순서 원칙 (ADR-002)**: ultralytics 먼저 → langchain/openai → 마지막에 `pip install "numpy<2" --upgrade --force-reinstall` + import 검증.

---

## 10. 비-소재 파일

- `Installfile_2026_A_v2.zip` — 사용자 백업 패키지 (installer 소스 아님). Phase 1/2 작업 대상 제외. `.gitignore` 에 `*.zip` 추가하여 실수 커밋 차단.

---

## 11. `apt upgrade -y` drift — 실측 검증 결과 (노션 2026-05-22, 이정현)

**증상**: 스크립트가 명시적으로 핀(`=VERSION`)한 패키지가 `sudo apt upgrade -y` 단계에서 silent 상향됨.

| 패키지 | 스크립트 의도 | 실측 | Drift 크기 |
|--------|---------------|------|-----------|
| `nvidia-driver-*` | 570 | 580.159.03 | 메이저 10 |
| `docker-ce` | `5:23.0.6-1~ubuntu.22.04~jammy` | 29.5.0 | 메이저 6 |

**근본 원인**: `apt upgrade -y` 는 핀을 풀고 latest stable 로 끌어올림. `apt install pkg=X.Y.Z` 만으로는 후속 `upgrade` 를 막지 못함.

**Phase 2 변경안**: 패키지 설치 직후 `apt-mark hold` 호출 삽입.

```bash
# resources/nvidia-driver-install.sh
sudo apt install -y nvidia-driver-${NVIDIA_DRIVER_VERSION} build-essential dkms
sudo apt-mark hold nvidia-driver-${NVIDIA_DRIVER_VERSION}

# resources/docker-install.sh
sudo apt install -y docker-ce=${DOCKER_VERSION} docker-ce-cli=${DOCKER_VERSION} ...
sudo apt-mark hold docker-ce docker-ce-cli containerd.io
```

**검증**: 설치 후 `apt-mark showhold` 출력이 핀한 패키지 목록과 일치해야 함.

**부수 검토**: a01 의 `apt upgrade -y` 단계 자체가 필요한지 재검토 — 의도하지 않은 부작용의 원천. 필요하다면 `apt upgrade --no-install-recommends` 또는 특정 패키지 제외 옵션 사용.

---

## 12. RealSense 22.04 공급 중단 → Noble 정식 복귀 기대 (Phase 2-9 호재)

**현재 humble 상태 (노션 실측)**:
- Intel 공식 `librealsense2-{dkms,utils,dev,dbg}` 패키지가 **Ubuntu 22.04 (Jammy) 용 공급 중단**. `a04-realsense01.sh:11-15` 의 `apt install` 은 실제로 설치 실패.
- 대체 동작: ROS2 vendored 패키지 `ros-humble-librealsense2` (SDK 버전 2.57.7) 가 `librealsense2` 의 역할 대행. realsense-ros 래퍼 4.57.7 과 함께 동작 확인 (D435I, firmware 5.17.0.10, USB 3.0).

**Noble 전환 시 기대**:
- Intel 가 Ubuntu 24.04 (Noble) 용 `librealsense2` apt repo 를 **정식 지원 재개 예정** (노션 검증본 주석). 이 경우 vendored 패키지 의존도가 사라지고 SDK 업데이트 주기가 distro 와 분리됨.

**Phase 2-9 분기 결정 (사전 검증 필요)**:
1. Noble 용 Intel 공식 repo 가 **활성** (Phase 2 진입 전 § 7 검증): `a04-realsense01.sh` 의 `librealsense2-*` apt install 흐름을 그대로 살리고, `signed-by=/etc/apt/keyrings/librealsense.pgp` 만 유지.
2. **미활성** 또는 시점 불확실: vendored 의존 유지 — `a04-realsense01.sh` 의 11-15 라인을 주석/skip 처리하고 a05 의 `ros-${ROS_DISTRO}-realsense2-*` 만 사용.

**검증 명령**:
```bash
curl -fsSL https://librealsense.intel.com/Debian/apt-repo/dists/ | grep -i noble
# 또는
apt-cache madison librealsense2-utils  # apt source 추가 후
```

**Phase 2-9 의 가장 큰 변경 가능성**: 분기 1 채택 시 `a04-realsense01.sh` 가 의도대로 동작하는 첫 환경이 됨 (humble 에선 한 번도 의도대로 안 됐던 단계). 분기 2 채택 시 Phase 3 TROUBLESHOOTING 에 "vendored 우회" 절차 영구 기록.

---

## 13. 선언적 의존성 충돌 (`pip check` 경고, 실측 동작 OK)

`pip check` 경고 3건이 humble 환경에서 확인되나 **실제 import / 인스턴스 생성은 모두 통과** (노션):

| 충돌 쌍 | 메타데이터 요구 | 실측 |
|---------|----------------|------|
| `opencv-python 4.13.0.92` vs `numpy 1.24.4` | OpenCV: `numpy>=2` | ✅ 동작 OK |
| `langchain-upstage 0.7.7` vs `langchain-core 0.3.86` | upstage: core 메이저 일치 기대 | ✅ 동작 OK |
| `langchain-upstage 0.7.7` vs `langchain-openai 0.3.28` | upstage: openai 메이저 일치 기대 | ✅ 동작 OK |

**Phase 2-10 재검증 필요**: jazzy 의 Py3.12 + numpy 1.26.4 환경에서:
- opencv-python 의 어느 마이너 버전이 numpy<2 와 메타데이터까지 호환되는지 (또는 그대로 경고만 무시할지) — 결정 필요.
- langchain-upstage 가 메이저 0.x 라인 안에서 core/openai 0.3 와 호환되는 minor 버전이 있는지 확인.
- 노션 결과를 그대로 신뢰하지 말고 jazzy 환경에서 `pip check` + `python -c "import cv2, numpy; cv2.imread('x')"` 등 smoke test 재실행.

**중요**: 이 충돌들은 **선언적 메타데이터** 수준이므로 핀을 무시하고 silent 업그레이드 트리거하지 않음. Phase 2-10 에서는 경고를 받아들이고 `--no-deps` 등으로 우회 가능.

---

## 14. 노션 검증본에서 발견된 누락 의존성 (Phase 2-10 추가 핀 후보)

humble 실측에 존재하지만 본 레포 스크립트가 명시 핀 / 명시 install 하지 않은 패키지들. Phase 2 에서 본 레포가 직접 install 하지 않더라도 **호환 매트릭스에는 기록** (`docs/COMPATIBILITY.md` 갱신 완료):

- **PyTorch GPU 스택 (pip transitive)**: `nvidia-cudnn-cu12 9.1.0.70`, `triton 3.2.0`
- **Python ML (`python-dependency.sh` 안에 있을 가능성)**: `scipy 1.15.3`, `pandas 2.3.3`, `polars 1.40.1`, `scikit-learn 1.7.2`, `matplotlib 3.10.9`, `ultralytics 8.4.50`, `supervision 0.28.0`, `opencv-python 4.13.0.92`, `pyrealsense2 2.57.7.10387`
- **추론 엔진**: `onnxruntime 1.23.2`, `tflite-runtime 2.14.0`
- **음성**: `PyAudio 0.2.14`, `openwakeword 0.6.0`, `sounddevice 0.5.5`
- **LangChain transitive**: `langchain-core 0.3.86`, `langchain-upstage 0.7.7`, `httpx 0.28.1`, `huggingface_hub 0.36.2`, `tokenizers 0.20.3`, `tiktoken 0.12.0`, `pydantic 2.13.4`, `python-dotenv 1.2.2`
- **시스템 라이브러리 (apt)**: `libportaudio2 / libportaudiocpp0 / portaudio19-dev 19.6.0`, `libsndfile1 1.0.31`, `libasound2-dev`, `ffmpeg + libavcodec/avformat/swscale-dev 4.4.2`, `libjpeg/png/tiff-dev`, `libpoco-dev 1.11.0`, `libyaml-cpp-dev 0.7.0`

**Phase 2 액션**: `resources/python-dependency.sh` 의 실제 내용을 다시 확인하여 어떤 게 명시 install 이고 어떤 게 transitive 인지 분류. 핵심 (`scipy`, `ultralytics`, `opencv-python`, `pyrealsense2`, `openwakeword`) 은 명시 핀 후보.

---

## 15. Python 빌드 도구 노후 — Phase 2-3 동반 작업

humble 실측 (노션 pip list, 2026-05-22):
- `pip 22.0.2` (2022-01, 4년 노후)
- `setuptools 59.6.0` (2021-11)
- `wheel 0.37.1` (2021-12)

**Py3.12 (Ubuntu 24.04 기본) 호환성 위험**:
- 일부 source wheel 이 Py3.12 + 신규 wheel 메타데이터 (PEP 660 editable 등) 를 요구. `pip 22` 은 PEP 660 지원 부분적.
- 노후 setuptools 는 `pkg_resources` deprecation 경로에서 Py3.12 가 발생시키는 경고와 충돌.

**Phase 2-3 변경안**: a01 또는 Python 의존성 설치 직전 단계에 빌드 도구 upgrade 1줄 추가.

```bash
# resources/python-dependency.sh 시작부 또는 a02 진입 직후
python3 -m pip install --upgrade pip setuptools wheel
```

**주의**: Ubuntu 24.04 는 PEP 668 (`externally-managed-environment`) 로 system Python 의 pip install 을 막음. **결정 완료 (ADR-004)**: `python3 -m venv --system-site-packages ~/cobot_ws/.venv` + `~/.bashrc` 자동 source. 위 upgrade 명령도 venv active 상태에서 수행 → system Python 안전.

```bash
# resources/python-dependency.sh 시작부 (venv 가 active 한 셸에서만 호출 가정)
python3 -m pip install --upgrade pip setuptools wheel  # venv 안에서 동작
```

---

## 16. PyTorch CUDA pip wheels — Phase 2-6 분기 영향

humble pip list (노션) 실측: torch 2.6.0+cu124 가 **13개의 `nvidia-*-cu12` wheel** 을 transitive 로 끌어옴 (`cublas`, `cuda-cupti/nvrtc/runtime`, `cudnn 9.1.0.70`, `cufft`, `curand`, `cusolver`, `cusparse`, `cusparselt`, `nccl 2.21.5`, `nvjitlink`, `nvtx`). 모두 CUDA **메이저 12.4** 와 일치.

**의미**: 시스템 CUDA toolkit 설치 (`cuda-toolkit-12-4`, 1.4GB local installer) 는 사실상 nvcc 와 CUDA samples 용. **PyTorch 가속 자체는 wheel 안의 13개 nvidia-* 라이브러리로 동작**. 시스템 CUDA 와 wheel CUDA 의 메이저가 어긋나면 fallback 동작 (느려짐 또는 import 에러).

**Phase 2-6 결정 영향**:
- CUDA modernize 시 (system CUDA 12.4 → 12.6 또는 13.x), PyTorch wheel 도 동시에 변경 (`+cu126` 또는 `+cu130` 으로). 메이저 어긋남 방지.
- 또는: 시스템 CUDA 설치 자체를 생략하고 PyTorch wheel 만으로 운영 (단, nvcc 가 필요한 다른 빌드 작업이 없을 때 한정).

**검증 명령** (Phase 2 진입 후 jazzy 환경에서):
```bash
python3 -c "import torch; print(torch.version.cuda, torch.backends.cudnn.version())"
# 출력의 CUDA 메이저가 시스템 nvcc 메이저와 일치하는지 확인
```

---

## 출처 — 실측 검증

§ 11, 12, 13, 14, 15, 16 의 실측 데이터는 노션 두 페이지 (작성 이정현, 검증일 2026-05-22, 환경 Ubuntu 22.04 LTS + ROS2 Humble + RTX 4060 Laptop) 에서 인용:
- 시스템 요약: https://www.notion.so/teamsparkx/Rokey-2-Version-20260522-36c563918e59803cb719ca55e3e3369f
- 전체 `pip list` 스냅샷: https://www.notion.so/teamsparkx/pip-list-Version-20260522-36c563918e5980c0af76f8b4332454fe
- 본 레포 스크립트와 별도 작성된 외부 사실 — Phase 2 시작 전 사용자 별도 검증 권장 (특히 RealSense Noble repo 활성 시점, PEP 668 대응)

---

## Phase 2 task 매핑 요약

본 문서의 § 가 Phase 2 task 와 어떻게 대응되는지:

| MIGRATION_NOTES § | ROADMAP Phase 2 task |
|-------------------|----------------------|
| § 2 (distro/Ubuntu 변수화) | 2-1 (config.sh) + 2-4 ~ 2-10 (스크립트별 변수화) |
| § 3.1 (apt-key add) | 2-11 (keyring 일관성) |
| § 3.2 (keyring 경로) | 2-11 |
| § 4 (`set -euo pipefail`) | 2-3 |
| § 5 (idempotency) | 2-2 + 각 스크립트별 가드 (2-4 ~ 2-10) |
| § 6 (`_25` orphaned) | resolved 2026-05-27 — `backup/` 으로 이동 완료 |
| § 7 (external dependencies) | **Phase 2 진입 전** 별도 검증 → ADR-003 |
| § 8 (state-changing) | 2-12 |
| § 9 (pip pins) | 2-10 |
| § 10 (비-소재) | .gitignore (Phase 1 완료 시) |
| § 11 (`apt upgrade` drift, `apt-mark hold`) | 2-5 (nvidia) + 2-7 (docker) — `apt-mark hold` 패턴 일괄 도입 |
| § 12 (RealSense Noble 복귀) | 2-9 (사전 검증 § 7 결과에 분기 의존) |
| § 13 (선언적 충돌 재검증) | 2-10 (Py3.12 환경에서 `pip check` smoke test) |
| § 14 (누락 의존성 핀 후보) | 2-10 (python-dependency.sh 분류 + 핵심 패키지 명시 핀) |
| § 15 (pip/setuptools/wheel 노후) | 2-3 (`pip install --upgrade pip setuptools wheel`) + § 7 추가 검증 (PEP 668 대응) |
| § 16 (PyTorch CUDA wheel 메이저 일치) | 2-6 (CUDA modernize 와 PyTorch wheel 동시 결정) |
