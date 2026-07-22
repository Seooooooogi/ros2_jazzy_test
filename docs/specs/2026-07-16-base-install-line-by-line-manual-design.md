# Base 설치 line-by-line 수동 매뉴얼 — 설계 (design spec)

- **작성일**: 2026-07-16
- **상태**: 승인됨 (구현 대기)
- **산출 브랜치**: `feat/application-containers` (docs 는 public main 제외 대상 → dev 에만 존재)
- **관련**: Notion "최초 빌드 수동화 명령어 정리" (`39c563918e59806cb235ed9c03f5c91a`, app 계층 A~G)

## 1. 목적 (motivation)

`install.sh` (base 환경, `[n/9]`) 를 자동화 스크립트가 아니라 **사람이 한 줄씩 이해하며 실행할 수 있는 명령어 매뉴얼**로 분해한다. 두 가지 가치:

1. **학습 효과** — 각 명령이 무엇을·왜 하는지 주석으로 드러내, 설치를 블랙박스가 아니라 학습 단위로 만든다.
2. **하드웨어 의존성 해소** — 상정한 실측 머신이 아닌 다른 노트북에서 설치할 때, 하드웨어/환경에 묶인 명령(특히 그래픽 드라이버)을 **개별적으로 대체**할 수 있게 표기한다.

최종 형태는 이 base 매뉴얼(1~9) 이 기존 Notion A~G **앞에 맞물려**, fresh Ubuntu 부터 시작하는 완결적 scratch line-by-line 설치 매뉴얼을 이룬다. (통합 자체는 사용자가 검토 후 Notion 에 반영 — 본 산출물은 레포 markdown 정본.)

## 2. 산출물 (deliverable)

- **파일**: `docs/BASE_INSTALL_MANUAL.md` (단일 markdown)
- **언어**: 한국어 설명/주석 + 영어 명령·식별자 (Notion A~G 와 동일 관례)
- **형식**: Notion A~G 미러 — `### N. 제목` 헤더 + ```bash 코드블록 + `# 1)`,`# 2)` 논리 단위 주석 + `# 검증:` 명령. 셸 line-continuation 은 단일 `\`.
- 자동 커밋 안 함 — 사용자 명시 요청 시에만 커밋.

## 3. 접근법 결정

**채택: install.sh 미러 (A안)** — install.sh 의 9단계를 1:1 로 섹션화. 학습의 "왜" 는 별도 산문 문단이 아니라 인라인 주석에 압축(Notion A~G 방식). 기각: 학습 심화(B, `TROUBLESHOOTING.md`/`COMPATIBILITY.md` 중복 위험 + 장황), 스크립트 대응표(C, 유지보수 부담).

## 4. 변수 해석 정책 (config.sh → 구체값)

`resources/config.sh` 의 핀 변수는 매뉴얼에서 **실측 기본값으로 해석**해 실제 명령을 보여준다:

| 변수 | 해석값 |
|---|---|
| `ROS_DISTRO` | `jazzy` |
| `UBUNTU_CODENAME` | `noble` |
| `KERNEL_META` / `KERNEL_HEADERS_META` | `linux-generic-hwe-24.04` / `linux-headers-generic-hwe-24.04` |
| `NVIDIA_DRIVER_VERSION` / `NVIDIA_DRIVER_FLAVOR` | `595` / `` (빈 값 = closed) |
| `KEYRING_DIR` | `/etc/apt/keyrings` |
| `HOST_ETH_IP`/`HOST_ETH_PREFIX` | `192.168.1.30`/`24` |
| `CYCLONEDDS_XML` | `~/.config/cyclonedds/cyclonedds.xml` |

**예외 — 그대로 유지** (이식성 있는 자가해석): `$(uname -r)`, `$(dpkg --print-architecture)`. 이들은 어느 머신에서도 옳으므로 명령 치환을 남긴다.

## 5. 무엇을 버리고 무엇을 남기나 (strip / keep)

install.sh 는 자동화 로버스트니스를 위한 배관(plumbing)을 많이 담는다. 매뉴얼은 사람이 한 번 실행하는 관점이므로 배관을 걷어내고 본질 명령만 남긴다.

**버림**: state/`run_step`/heartbeat/로그 라우팅(`LOG_FILE`)/`sudo_prime`/autostart·resume(`install-resume-launcher.sh`, `register/remove_resume_autostart`)/멱등 가드(`if grep -q ...`, `dpkg-query 설치확인`, `apt-mark showhold` 사전확인)/config 변수 간접참조.

**남김**: 실제 apt/curl/nmcli/docker 명령, `apt-mark hold`, `usermod -aG docker`, keyring 등록(install -d + curl + chmod + tee source list), 검증 게이트(nvidia.ko 존재 확인 / wireless 모듈 확인 / hello-world / static IP 확인).

**판단 기준**: "다른 머신에서 처음부터 설치하는 사람이 실제로 타이핑할 명령인가?" 예 → 남김. "재실행 안전을 위한 조건 분기인가?" 예 → 버림(단, 명령 자체가 의미 있으면 무조건 실행형으로 평문화).

## 6. 섹션 구조 (install.sh 순서)

각 섹션 = install.sh step, 원천 스크립트 명시. 최종 통합 시 Notion A 앞에 위치.

| # | 섹션 | 원천 | HW 의존 |
|---|---|---|---|
| 1 | 커널 기준선 (HWE meta + headers + modules-extra + wireless 검증) | `kernel-baseline.sh` | 커널메타 `-24.04` |
| 2 | NVIDIA 드라이버 (universe/multiverse + 빌드도구 + 595 pin + 모듈메타 + hold + nvidia.ko 검증) | `nvidia-driver-install.sh` | **GPU 모델** |
| 3 | Docker CE (keyring + repo + engine + hold + docker 그룹 + hello-world) | `docker-install.sh` (+`apt-repo.sh`) | — |
| 4 | ROS2 Jazzy desktop (OS/arch 확인 + repo + desktop meta + 개발도구 + rosdep init/update + bashrc source) | `ros2-packages.sh desktop` | — |
| 5 | ROS2 extras (기반 lib + control/robot 스택 + Gazebo Harmonic `ros-gz`) | `ros2-packages.sh extras` | — |
| 6 | **재부팅** (`sudo reboot`) — 드라이버/도커그룹 적용 경계. 이후 7부터 이어감 | install.sh 인라인 | — |
| 7 | VS Code (MS keyring dearmor + repo + `code`) | `vscode-install.sh` (+`apt-repo.sh`) | — |
| 8 | DDS 튜닝 (sysctl 설치+적용 + cyclonedds.xml 렌더 + bashrc export) | `dds-tuning.sh` | 유선 NIC |
| 9 | 정적 이더넷 IP (nmcli manual + never-default + 검증) | `network-static-ip.sh` | NIC + IP 대역 |

**섹션별 세부 유의**:
- **2 (NVIDIA)**: pin 경로만 제시(자동선택 폴백은 HW 태그 대체 레시피로만 언급). 모듈메타 = `linux-modules-nvidia-595-generic-hwe-24.04`. `nvidia.ko` 검증은 "부팅될 커널"(`find /lib/modules ... | sort -V | tail -1`) 기준 — 매뉴얼에선 간명화하되 검증 취지 유지.
- **6 (reboot)**: install.sh 의 autostart 자동재개는 자동화 전용이므로 **생략**. 매뉴얼은 "재부팅 → 로그인 → 7단계부터 계속" 안내만.
- **8 (DDS)**: `cyclonedds.xml` 은 템플릿(`resources/cyclonedds.xml.in`) + NIC 목록 렌더 결과물. 매뉴얼에선 (a) 완성 XML 예시를 직접 붙이거나 (b) 렌더 명령을 그대로 보여준다 — 구현 시 (b) 우선(원천과 drift 최소), NIC 감지 부분은 HW 태그.
- **9 (static IP)**: nmcli 자동감지 로직 대신 "NIC 이름 확인 → 그 NIC 에 manual IP 부여" 로 평문화. NIC 이름·IP 대역 둘 다 HW 태그.

## 7. 하드웨어 의존 표기 (핵심 요구)

**(a) 문서 상단 요약표** — 개별 대체를 한눈에:

| 항목 | 실측값 | 의존 원인 | 다른 머신이면 |
|---|---|---|---|
| NVIDIA 드라이버 | `nvidia-driver-595` (+ 모듈메타) | GPU 모델 | `ubuntu-drivers devices` → recommended 버전으로 `595` 교체. (자동 `sudo ubuntu-drivers install` 은 비결정적 + 반쪽 HWE 커널 위험) |
| HWE 커널 메타 / apt 코드네임 | `-24.04` / `noble` | Ubuntu 릴리스 | `lsb_release -sc` 로 코드네임 확인 → 해당 값으로 교체 (예 22.04=jammy) |
| 유선 NIC 이름 | 자동감지 | 머신 NIC | `ip -o link` 또는 `ls /sys/class/net` 로 실제 이름 확인 |
| 로봇 LAN IP | `192.168.1.30/24` (.1 그리퍼/.100 로봇/.30 host) | 배치 사이트 | 실제 로봇/그리퍼 IP 대역에 맞춰 host IP·prefix 조정 |
| CPU 아키텍처 | `amd64` | CPU arch | 대체 불필요 — `$(dpkg --print-architecture)` 자가해석 (arm64 등 자동) |
| (참고) CUDA `12.8` | — | GPU | base 무관 — 컨테이너 섹션 E~G 에서만 소비 |

**(b) 인라인 태그** — 해당 명령 위에 `# [하드웨어 의존]` (이모지 없이 grep 가능) + 바로 아래 대체 레시피 1줄. 요약표와 중복되지만 명령 지점에서 즉시 보이게 하는 것이 목적.

## 8. 전제/이음새 (Notion 통합)

- **상단 전제 callout**: `Ubuntu 24.04 (noble) 클린 설치 + sudo 권한 + 인터넷 연결`.
- **말미**: "여기까지 = install.sh 완료 상태. 이후 `~/cobot_ws/src` 에 cobot2 소스 배치 → 기존 A~G(DSR/RealSense/voice/colcon/컨테이너) 진행." → Notion 페이지의 기존 전제("`install.sh` 완료 + 소스 `~/cobot_ws/src` 배치")와 정확히 맞물림.

## 9. 범위 밖 (out of scope)

- 기존 A~G(app 계층) 재작성 — 중복 방지. base 만 산출.
- `setup-app.sh` 계층(DSR/RealSense/voice/colcon/컨테이너) — 이미 Notion A~G.
- install.sh 의 자동화 배관(state/resume/logging) 문서화 — 매뉴얼 관점 무관.
- Notion 에 직접 쓰기 — 사용자가 검토 후 반영.

## 10. 수용 기준 (acceptance criteria)

1. install.sh 9단계가 모두 섹션으로 존재하며, 각 섹션 명령이 원천 스크립트의 본질 명령과 일치(누락/오타 없음).
2. `${VAR}` 잔재 없이 실측 구체값으로 해석됨 (자가해석 `$(...)` 예외).
3. 하드웨어 의존 카탈로그(요약표)가 6행(대체 대상 4 + 참고 2: arch·CUDA)을 담고, 대체 대상 4종(NVIDIA/커널코드네임/NIC/IP)은 인라인 태그로도 명령 지점에 표기됨. 특히 NVIDIA 드라이버 대체법이 명확.
4. 각 섹션에 `# 검증:` 명령이 있어 성공 판정 가능(원천 스크립트의 검증 게이트 반영).
5. 상단 전제 + 말미 이음새가 Notion A 전제와 연속됨.
6. 셸 명령이 복붙 실행 가능(단일 `\` continuation, 잘못된 `\\` 없음).
