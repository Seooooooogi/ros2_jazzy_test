# 개발환경 설치 (Jazzy)

> 상위 페이지 **[7기] 협동로봇2 — Jazzy/24.04 개정판** 의 §1~2 상세.
> 구 강의안의 2경로(A. Ubuntu 초기화 MSI / B. 협동1 유지)와 `Installfile_2026_{A,B}.zip` 의 `a0X`/`b0X` 스크립트를 **`install.sh` → `setup-app.sh` 2단계로 통합**. 경로 분기 없음.

---

## 전체 흐름

```
bash install.sh      →   (자동 reboot·복귀)   →   bash setup-app.sh
  base 환경 10 step                                 워크스페이스 + 컨테이너 + OPENAI key
```

- **전제**: Ubuntu **24.04(noble)** 설치 완료 + 인터넷. NVIDIA GPU 없으면 드라이버 step skip(그 외 진행).

---

## Step 1. 레포 취득

```bash
git clone <repo-url> ~/ros2_jazzy_test
cd ~/ros2_jazzy_test
```

## Step 2. base 환경 설치 — `install.sh`

```bash
bash install.sh
```

- **내용(10 step)**: kernel/NVIDIA → Docker → ROS2 **Jazzy** → **자동 reboot** → VS Code → DDS 튜닝 → 정적 IP → corecode.
- **진행**: 시작 시 confirm 1회 → 자동. **step 6 에서 자동 reboot** → 재로그인하면 GUI autostart 로 이어서 재개(복귀 후 sudo 비번 1회).
- **NVIDIA 재부팅 후 MOK(파란 화면)**: `Enroll MOK → View key → Continue → YES → Reboot`. 이후 `nvidia-smi` 로 드라이버 확인.
- **진행률**: 콘솔 `[n/10] <step>` 만. 상세 로그 = 레포 루트 `install_log`.
- **재실행 안전**: 실패/재부팅 후 `bash install.sh` 재실행 → 완료 step 자동 skip, 끊긴 지점부터.

> 🔄 재촬영: 구 `Installfile` 압축해제·개별 `bash a0X` 화면 → `install.sh [n/10]` 진행률 콘솔 + MOK 화면.

#### install.sh 옵션

```bash
bash install.sh --status    # 어디까지 끝났는지
bash install.sh --reset     # 설치 상태 초기화 (처음부터)
bash install.sh --verbose   # 상세 출력 콘솔 표시
bash install.sh --help
```

## Step 3. cobot2 소스 배치

- cobot2 애플리케이션 소스는 **레포에 없음**(추적 제외). 직접 배치:

```bash
mkdir -p ~/cobot_ws/src
cp -a <cobot2 소스> ~/cobot_ws/src/cobot2
```

## Step 4. 애플리케이션 설치 — `setup-app.sh`

```bash
bash setup-app.sh
```

- **워크스페이스**: cobot2 소스 검증 → DSR 드라이버(doosan-robot2) → RealSense(SDK + ROS 래퍼) → colcon build.
- **컨테이너 / host voice**: NVIDIA Container Toolkit → **`:dev-builder` 이미지 빌드**(`build-all.sh`, yolo) → **host voice Python 설치**(`voice-host-install.sh` — voice 는 컨테이너 아님, 마이크 하드웨어 종속이라 host 실행, ADR-027). OPENAI 키는 사용자가 `~/.config/cobot2/.env` 직접 생성(ADR-028) — 인스톨러 자동생성 없음.
- **ROS_DOMAIN_ID**: 설치가 prompt/주입 안 함 — 학생이 직접 `~/.bashrc` 에 `export ROS_DOMAIN_ID=<n>` 삽입(학습). 미설정 시 host·컨테이너 모두 0(ROS2 기본).

#### setup-app.sh 옵션

```bash
bash setup-app.sh --workspace-only    # 워크스페이스만
bash setup-app.sh --containers-only   # 컨테이너/voice만 (toolkit + yolo 이미지 + host voice 설치)
bash setup-app.sh --reset             # doosan 재클론 + 빌드산출물 wipe 후 재빌드 (cobot2 보존)
bash setup-app.sh --verbose
bash setup-app.sh -y                  # --reset confirm 생략
bash setup-app.sh --help
```

---

## 폐기된 것 (구 강의안 대비)

- ❌ `Installfile_2026_{A,B}_v2.zip` · `a01~a06` / `b01~b04` 개별 스크립트
- ❌ 설치 2경로 분기(MSI 초기화 / 협동1 유지) — 단일 흐름
- ❌ `.bashrc` 수동 편집(source/CUDA/PYTHONPATH/alias/`ROS_DOMAIN_ID=99`) — 자동화
- ❌ host 음성 라이브러리 설치(`a06/b04-Voice`) · host CUDA 12.4 — 컨테이너로 이동(CUDA 12.8, 컨테이너 내부)

> 🔄 재촬영: 구 numpy 1.24.4 설치 출력 → 해당 절차 자체 없음(컨테이너 `numpy<2` 핀).
