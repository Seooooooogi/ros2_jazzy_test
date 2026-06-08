# ros2_jazzy_test

Ubuntu 워크스테이션을 **ROS2 Jazzy 로봇 개발 환경**으로 일관되게 셋업하는 bash 설치 스크립트 모음.
NVIDIA 드라이버 + Docker + ROS2 Jazzy + Doosan DSR + RealSense + 음성(LangChain) 까지 한 번에 구성한다.

대상: Ubuntu 24.04 (noble) + NVIDIA GPU 워크스테이션. 동일 모델 머신에 반복 설치/검증하는 것을 전제로 한다.

## 설치 순서

권장 진입점은 `install.sh` 하나다. 내부적으로 `a01 → reboot → a02 → a03 → a04` 를 단일 시퀀스(`[n/total]` 진행률)로 실행하고, 이미 끝난 단계는 자동 skip 한다.

```bash
# 1) 저장소 클론 후 디렉토리 진입
git clone <repo-url> ros2_jazzy_test
cd ros2_jazzy_test

# 2) 전체 설치 시작 (a01 단계에서 시스템 준비 후 reboot 가 필요할 수 있음)
bash install.sh

# 3) reboot 가 발생하면, 부팅 후 같은 명령을 다시 실행 → 멈춘 다음 단계부터 이어서 진행
bash install.sh
```

설치는 **재개 가능(resumable)** 하다. 중간에 실패하거나 reboot 로 끊겨도 마지막 성공 단계를 기록해두므로, 다시 `bash install.sh` 를 실행하면 처음이 아니라 그 다음 단계부터 진행한다.

### 단계 구성

| 단계 | 스크립트 | 내용 |
|------|----------|------|
| a01 | `a01-prerequirements.sh` | 시스템 준비 — 커널 베이스라인, NVIDIA 드라이버, Docker, ROS2 Jazzy. **reboot 포함** |
| a02 | `a02-robot-camera.sh` | Doosan DSR 로봇 + RealSense 카메라 설치 |
| a03 | `a03-vs-code-install.sh` | VS Code 설치 |
| a04 | `a04-voice-precheck.sh` | 음성 처리 사전 점검 (API 키 입력 포함) |

각 단계는 단독으로도 실행할 수 있다. `install.sh` 와 같은 상태 파일을 공유하므로 어느 쪽으로 실행하든 skip 판정이 일관된다.

```bash
bash a01-prerequirements.sh   # 시스템 (reboot 포함)
bash a02-robot-camera.sh      # 로봇 + 카메라
bash a03-vs-code-install.sh   # VS Code
bash a04-voice-precheck.sh    # 음성 점검
```

## 자주 쓰는 옵션

```bash
bash install.sh --status   # 어느 단계까지 끝났는지 상태 출력
bash install.sh --reset    # 설치 상태 초기화 (처음부터 다시)
bash install.sh --help     # 도움말
```

- 콘솔에는 `[n/total]` 진행률과 경고/에러만 표시된다. 각 단계의 상세 출력(apt/pip/colcon)은 `~/.ros2_jazzy_test/install.log` 에 append 된다.
- 상세 출력을 콘솔에서 실시간으로 보려면 `VERBOSE=1 bash install.sh`.

## 환경 변수 / 시크릿

- 음성 처리에 필요한 API 키 등은 `.env` 로 관리한다. `.env.example` 이 템플릿이며, 복사해서 값을 채운다.
- `.env` 는 절대 커밋하지 않는다.

```bash
cp .env.example .env
# .env 를 편집해 실제 키 입력
```

## 개발 / 검증

```bash
shellcheck *.sh resources/*.sh   # 스크립트 정적 검증
```

설정의 단일 진실 소스는 `resources/config.sh` 다 — ROS distro, 드라이버/CUDA 버전, DDS(RMW) 설정 등을 한 곳에서 정의하고 모든 스크립트가 참조한다.
