# Base 환경 수동 설치 (line-by-line)

작성일 : 2026/7/16

`install.sh` (base 환경, 9단계)를 한 줄씩 수동으로 실행하는 매뉴얼. 각 명령의 목적을 주석으로 설명하며, 하드웨어/환경에 묶인 명령은 `# [하드웨어 의존]` 으로 표기해 다른 머신에서 개별 대체할 수 있게 한다.

> **전제**
> 1. Ubuntu 24.04 (noble) 클린 설치
> 2. sudo 권한 + 인터넷 연결
> 3. 레포 배치: `~/ros2_jazzy_test`

---

## 하드웨어 의존 명령어 요약

다른 노트북/GPU 에서 설치할 때 아래 값만 개별 교체하면 된다. 각 항목은 해당 섹션에도 `# [하드웨어 의존]` 으로 다시 표기돼 있다.

| 항목 | 실측값 | 의존 원인 | 다른 머신이면 |
|---|---|---|---|
| NVIDIA 드라이버 (§2) | `nvidia-driver-595` (+ 커널모듈 메타) | GPU 모델 | `ubuntu-drivers devices` → recommended 버전으로 `595` 교체. 자동 `sudo ubuntu-drivers install` 은 비결정적 + 반쪽 HWE 커널 위험 |
| HWE 커널 메타 / apt 코드네임 (§1,§3,§4) | `-24.04` / `noble` | Ubuntu 릴리스 | `lsb_release -sc` 로 코드네임 확인 → 해당 값으로 교체 (예: 22.04 = jammy). VS Code(§7)는 `stable main` 채널이라 코드네임 무관 |
| 유선 NIC 이름 (§8,§9) | 머신마다 다름 | 물리 NIC | `ip -o link show` 또는 `ls /sys/class/net` 로 실제 이름 확인 |
| 로봇 LAN IP (§9) | `192.168.1.30/24` (.1 그리퍼 / .100 로봇 / .30 host) | 배치 사이트 | 실제 로봇/그리퍼 IP 대역에 맞춰 host IP·prefix 조정 |
| CPU 아키텍처 | `amd64` | CPU arch | 대체 불필요 — `$(dpkg --print-architecture)` 자가해석 (arm64 등 자동) |
| (참고) CUDA `12.8` | — | GPU | base 무관 — 컨테이너 섹션(Notion E~G)에서만 소비 |

---

### 1. 커널 기준선 (HWE 커널 + headers + modules-extra)

nvidia 드라이버와 RealSense DKMS 는 커널에 묶인 모듈이다. 커널 image 만 깔고 modules-extra(wifi / 일부 USB 입력 드라이버)가 빠지면 부팅은 되지만 wifi/USB 키보드를 잃는 반쪽 커널이 된다. 그래서 nvidia 보다 커널부터 보장한다.

```bash
# 1) HWE 커널 meta + headers 설치. --install-recommends 로 modules-extra 까지 유입.
# [하드웨어 의존] '-24.04' = noble(Ubuntu 24.04) HWE 트랙. 다른 릴리스면 lsb_release -sc 로 확인 후 교체.
sudo apt-get update
sudo apt-get install -y --install-recommends \
  linux-generic-hwe-24.04 linux-headers-generic-hwe-24.04

# 2) 지금 부팅된 커널에도 modules-extra / headers 보강 ($(uname -r) = 현재 커널, 자가해석).
sudo apt-get install -y "linux-modules-extra-$(uname -r)" "linux-headers-$(uname -r)"

# 검증: wireless 드라이버 디렉토리 존재 확인 (없으면 반쪽 커널 — 재부팅 후 새 커널에서 재확인).
ls -d "/lib/modules/$(uname -r)/kernel/drivers/net/wireless"
```

### 2. NVIDIA 드라이버

드라이버를 버전 + flavor 로 콕 집어(핀) 설치한다. 자동 선택은 머신·시점마다 다른 드라이버를 뽑고, modules-extra 없는 반쪽 HWE 커널을 끌어와 재부팅 시 검은 화면을 유발할 수 있다.

```bash
# 1) apt 컴포넌트 활성화 (nvidia-modprobe 는 multiverse 에 있음).
sudo apt-get update
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y universe
sudo add-apt-repository -y multiverse

# 2) 빌드 도구 + ubuntu-drivers.
sudo apt-get update
sudo apt-get install -y build-essential gcc ubuntu-drivers-common dkms nvidia-modprobe

# 3) 드라이버 유저스페이스 + HWE 커널모듈 메타를 함께 설치 (커널 업데이트 시 모듈 자동 추적).
# [하드웨어 의존] 이 머신 GPU 기준 595 closed 로 핀. 다른 GPU 면:
#   ubuntu-drivers devices     # → recommended 버전 확인 후 아래 595 두 곳을 그 버전으로 교체
#   (자동 sudo ubuntu-drivers install 은 비결정적 + 반쪽 HWE 커널 위험 → 비권장)
sudo apt-get install -y \
  nvidia-driver-595 linux-modules-nvidia-595-generic-hwe-24.04

# 4) 드라이버 유저스페이스만 hold (apt upgrade 로 핀 풀림 방지). 커널모듈 메타는 hold 금지.
sudo apt-mark hold nvidia-driver-595

# 검증: 부팅될 커널에 nvidia 커널 모듈이 실제로 있는지 확인. 없으면 재부팅 시 검은 화면.
find /lib/modules -name 'nvidia.ko*'
```

### 3. Docker CE (도커 엔진)

noble 용 docker-ce 최신 stable 을 설치하고 엔진 패키지를 hold 로 고정한다. 키링은 signed-by 방식(구식 apt-key 미사용).

```bash
# 1) 사전 도구.
sudo apt-get update
sudo apt-get install -y ca-certificates curl

# 2) Docker keyring (armored .asc 그대로 저장).
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# 3) apt 소스 등록 (arch = $(dpkg --print-architecture) 자가해석, 'noble' 은 [하드웨어 의존] 릴리스 코드네임).
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list

# 4) 엔진 설치.
sudo apt-get update
sudo apt-get install -y \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5) 엔진 패키지 버전 고정 (hold).
sudo apt-mark hold docker-ce docker-ce-cli containerd.io

# 6) 현재 사용자를 docker 그룹에 추가 (재부팅/재로그인 후 반영).
sudo usermod -aG docker "$USER"

# 검증: 그룹 변경이 이 셸엔 아직 미반영 → sudo 로 실행.
sudo docker run --rm hello-world

# 설치 확정 버전 확인 (COMPATIBILITY 기록용).
docker --version
docker compose version
```

### 4. ROS2 Jazzy desktop

ROS2 jazzy desktop 핵심 + 개발 도구 + rosdep 초기화 + ~/.bashrc 자동 source.

```bash
# 1) OS / 아키텍처 확인 (noble + 64-bit 여야 함).
lsb_release -sc                    # → noble
dpkg --print-architecture          # → amd64 (arm64 등도 가능)

# 2) repo 도구 + universe.
sudo apt-get update
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y universe
sudo apt-get install -y curl gnupg2 lsb-release build-essential

# 3) ROS2 apt key + 소스 ('noble' 은 [하드웨어 의존] 릴리스 코드네임).
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
  -o /etc/apt/keyrings/ros.gpg
sudo chmod a+r /etc/apt/keyrings/ros.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/ros.gpg] http://packages.ros.org/ros2/ubuntu noble main" \
  | sudo tee /etc/apt/sources.list.d/ros2.list
sudo apt-get update

# 4) ROS2 desktop + 개발 도구.
sudo apt-get install -y \
  ros-jazzy-ament-package python3-pyqt5 ros-jazzy-ament-cmake libzmq3-dev
sudo apt-get install -y ros-jazzy-desktop
sudo apt-get install -y \
  python3-argcomplete python3-colcon-clean python3-colcon-common-extensions \
  python3-rosdep python3-vcstool

# 5) rosdep 초기화 (init 은 최초 1회).
sudo rosdep init
rosdep update

# 6) ~/.bashrc 자동 source 등록.
echo "source /opt/ros/jazzy/setup.bash" >> ~/.bashrc
echo "source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash" >> ~/.bashrc

# 검증: 새 셸에서 ROS2 CLI 동작.
source /opt/ros/jazzy/setup.bash && ros2 pkg list >/dev/null && echo "ROS2 desktop OK"
```

### 5. ROS2 extras (robot/control 스택 + Gazebo Harmonic)

DSR/robot 빌드에 필요한 control 스택과 Gazebo Harmonic(`ros-gz`)을 설치한다. (Classic/Fortress 는 jazzy 빌드 없음 → Harmonic.)

```bash
sudo apt-get update

# 1) 기반 라이브러리.
sudo apt-get install -y git libpoco-dev libyaml-cpp-dev dbus-x11

# 2) robot / control 스택.
sudo apt-get install -y \
  ros-jazzy-control-msgs ros-jazzy-realtime-tools ros-jazzy-xacro \
  ros-jazzy-joint-state-publisher-gui ros-jazzy-ros2-control \
  ros-jazzy-ros2-controllers ros-jazzy-moveit-msgs

# 3) lint / launch 유틸리티.
sudo apt-get install -y \
  ros-jazzy-ament-lint-common ros-jazzy-yaml-cpp-vendor \
  ros-jazzy-ros2launch ros-jazzy-ament-pep257

# 4) Gazebo Harmonic (ros_gz 메타).
sudo apt-get install -y ros-jazzy-ros-gz
```

### 6. 재부팅 (드라이버 + docker 그룹 적용 경계)

여기까지가 재부팅 전 단계다. NVIDIA 드라이버 커널 모듈과 docker 그룹 소속을 실제로 적용하려면 재부팅이 필요하다.

```bash
sudo reboot
# → 재부팅 후 로그인하면 아래 7단계부터 이어서 진행.
#   (install.sh 는 자동 재개하지만, 수동 매뉴얼에서는 로그인 후 직접 이어감.)
```

### 7. VS Code

Microsoft apt 저장소로 설치 → 이후 apt 가 업데이트까지 관리. 저장소는 Ubuntu 코드네임 무관 stable main 채널.

```bash
# 1) 사전 도구.
sudo apt-get update
sudo apt-get install -y wget gpg apt-transport-https ca-certificates

# 2) MS keyring (armored 키를 dearmor 로 바이너리 변환) + apt 소스.
sudo install -m 0755 -d /etc/apt/keyrings
wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor | sudo tee /etc/apt/keyrings/packages.microsoft.gpg >/dev/null
sudo chmod a+r /etc/apt/keyrings/packages.microsoft.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
  | sudo tee /etc/apt/sources.list.d/vscode.list

# 3) 설치.
sudo apt-get update
sudo apt-get install -y code

# 검증.
code --version
```

### 8. DDS 튜닝 (CycloneDDS 대용량 토픽 버퍼 + 인터페이스)

RealSense raw 이미지(color ≈ 2.6MB)는 UDP fragment 로 쪼개진다. 안정 수신을 위해 커널 소켓 버퍼(sysctl)와 CycloneDDS XML 버퍼를 세트로 올린다. 순서 중요 — sysctl 이 cyclonedds 노드 시작보다 먼저.

```bash
# 1) 커널 소켓/fragment 버퍼 설치 (재부팅해도 유지). sysctl 은 값 뒤 inline 주석 금지.
sudo tee /etc/sysctl.d/60-cyclonedds.conf >/dev/null <<'EOF'
# IP fragment 재조립 (대용량 프레임은 UDP fragment 로 분할)
net.ipv4.ipfrag_time = 3
net.ipv4.ipfrag_high_thresh = 134217728
net.ipv4.ipfrag_low_thresh = 98304000
# UDP 수신 버퍼 (DDS SocketReceiveBufferSize 요청이 rmem_max 에 캡됨)
net.core.rmem_max = 2147483647
net.core.rmem_default = 268435456
# UDP 송신 버퍼 (SocketSendBufferSize 하드 최소값 — 부족하면 도메인 생성 거부)
net.core.wmem_max = 2147483647
net.core.wmem_default = 67108864
# NIC 수신 큐 (버스트 드랍 완화)
net.core.netdev_max_backlog = 30000
EOF
sudo sysctl --system >/dev/null
echo "rmem_max=$(sysctl -n net.core.rmem_max) wmem_max=$(sysctl -n net.core.wmem_max)"

# 2) CycloneDDS XML 렌더 (loopback 우선 + 물리 외부 NIC).
# [하드웨어 의존] __NIC__ 를 실제 유선/무선 인터페이스 이름으로 교체 (ip -o link show 로 확인).
#   loopback(lo) 은 같은 호스트(host↔container) 경로라 항상 맨 앞에 둔다.
mkdir -p ~/.config/cyclonedds
tee ~/.config/cyclonedds/cyclonedds.xml >/dev/null <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<CycloneDDS xmlns="https://cdds.io/config"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xsi:schemaLocation="https://cdds.io/config https://raw.githubusercontent.com/eclipse-cyclonedds/cyclonedds/master/etc/cyclonedds.xsd">
  <Domain id="any">
    <General>
      <Interfaces>
        <NetworkInterface name="lo" priority="default" multicast="true"/>
        <NetworkInterface name="__NIC__" presence_required="false"/>
      </Interfaces>
      <AllowMulticast>true</AllowMulticast>
    </General>
    <Internal>
      <SocketReceiveBufferSize min="64MB"/>
      <SocketSendBufferSize min="64MB"/>
    </Internal>
  </Domain>
</CycloneDDS>
EOF
# 위 __NIC__ 를 실제 이름으로 치환 (예: enp0s31f6). 여러 NIC 면 <NetworkInterface> 줄을 추가.
sed -i "s/__NIC__/$(ip -o link show | awk -F': ' '$2!="lo"{print $2; exit}')/" \
  ~/.config/cyclonedds/cyclonedds.xml

# 3) ~/.bashrc 에 RMW / URI export (새 셸부터 적용).
echo 'export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp' >> ~/.bashrc
echo 'export CYCLONEDDS_URI="file://$HOME/.config/cyclonedds/cyclonedds.xml"' >> ~/.bashrc

# 검증.
cat ~/.config/cyclonedds/cyclonedds.xml
```

### 9. 정적 이더넷 IP (로봇 장비 LAN)

로봇/그리퍼와 같은 서브넷에 있으려면 host 유선 NIC 에 고정 IP 가 필요하다. gateway/DNS 는 비우고 never-default 로 두어 인터넷 기본 경로는 wifi 에 유지한다.

```bash
# 1) 유선 NIC 이름 확인.
# [하드웨어 의존] 아래 명령으로 실제 이름을 찾아 이후 <NIC> 를 교체.
ip -o link show | awk -F': ' '{print $2}'      # 또는: ls /sys/class/net

# 2) 정적 IP 부여 (nmcli). <NIC> = 위에서 확인한 이름.
# [하드웨어 의존] 로봇 LAN 대역이 다르면 192.168.1.30/24 조정 (.1 그리퍼 / .100 로봇 / .30 host).
sudo nmcli con add type ethernet ifname <NIC> con-name <NIC>-static
sudo nmcli con modify <NIC>-static \
  connection.interface-name <NIC> \
  connection.autoconnect yes \
  ipv4.method manual \
  ipv4.addresses 192.168.1.30/24 \
  ipv4.gateway "" \
  ipv4.dns "" \
  ipv4.never-default yes
sudo nmcli con up <NIC>-static      # 케이블 없으면 실패할 수 있으나 설정은 저장됨.

# 검증: 적용된 주소 확인.
nmcli -g IP4.ADDRESS device show <NIC>
```

---

여기까지 = `install.sh` 완료 상태(base 환경 준비 완료). 이후:
1. `~/cobot2_ws/src` 에 cobot2 소스 배치
2. app 계층(voice OPENAI 키 → DSR 드라이버 / RealSense / voice / colcon 빌드 / 컨테이너) — Notion "최초 빌드 수동화 명령어 정리"의 §10-17 진행.
