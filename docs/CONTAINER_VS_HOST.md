# 컨테이너 vs 호스트 배포 비교 (학습 노트)

## Scope

같은 cobot2 모놀리식 애플리케이션을 **두 배포 모델**로 운영했을 때의 *의존성 관리·운영* 차이를 대비한다.
두 모델은 이미 브랜치로 구현돼 있어 비교는 가설이 아니라 **branch vs branch** 다:

- **host 단독 (no container)** = `feat/application-shell` — 모든 노드를 host 에서 실행, application Python 은 host venv 한 곳.
- **분리 컨테이너 (container)** = `feat/application-containers` (현재) — host 는 thin `robot_control` 만, yolo/voice 는 각 이미지.
- **hybrid (voice 만 host)** = `feat/voice-host` (ADR-027, 2026-07-08) — yolo 는 컨테이너 유지, **voice 만 host 직접 실행**. 마이크가 하드웨어 종속(컨테이너 `asound.conf` 하드코딩 + raw ALSA passthrough 미검증)이라 voice 만 환원. voice application Python 은 host system pip(`--break-system-packages`). yolo 는 카메라 host 소유라 passthrough 문제 없어 컨테이너 유지.

근거(왜 컨테이너화했나)는 ADR 에 있고 여기서 재서술하지 않는다 → [Further reading](#further-reading) 참조.
본 문서는 *대비*와 *측정틀*에 집중한다.

> 서술 원칙: 구조적 사실(파일·핀·노드 import)은 인용처 코드에서 직접 확인된 것만 적는다.
> 이미지 크기·빌드 시간 같은 **측정값은 아직 미측정** — 표 자리만 두고 `미측정` 으로 남긴다(추정 금지).

---

## 두 모델 한눈에

| 축 | host 단독 (`application-shell`) | 분리 컨테이너 (`application-containers`) |
|---|---|---|
| application Python 위치 | **host venv 1곳** (`~/...venv`, `--system-site-packages`) | **이미지별 격리** (이미지 안 system python `/usr/local/lib/.../dist-packages`) |
| host 상태 | torch·langchain·openwakeword 로 **오염** | **apt-only 로 청결** (system Python + ROS bindings 만) |
| 실행 단위 | host 프로세스 (`ros2 run ...`) | 컨테이너 서비스 (`docker compose up`) + host `robot_control` |
| 단일 진실 소스 | `resources/host-python-deps.sh` | `containers/{yolo-detection,voice-processing}/Dockerfile` |
| numpy<2 재핀 위치 | host venv 끝단 | 각 Dockerfile 마지막 layer |
| ROS 통신 | CycloneDDS (host loopback) | CycloneDDS + `network_mode: host` (사실상 host loopback) |
| PEP 668 (noble) | `venv --system-site-packages` 로 우회 | 해당 없음 (host pip 자체 안 씀) |

핵심: **두 모델의 차이는 "노드가 어느 의존성/파일시스템 경계 안에 사는가"지, ROS 통신 방식이 아니다.** ([§5](#5-ros-통신-토폴로지-학습-핵심) 참조)

---

## 1. 의존성 관리 (핵심 축)

### numpy<2 — 결합 vs 격리

ultralytics(YOLO)는 numpy<2 를 요구한다. 두 스택 모두 이 제약 아래로 끌려 내려간다:

- **yolo**: `opencv-python<4.10` (4.10+ 은 numpy>=2 요구) → numpy<2 호환.
- **voice**: `scipy<1.18` (1.18+ 은 `np.long` 사용 = numpy>=2 전용) → numpy<2 호환.

두 모델이 이 제약을 **어디서** 푸느냐가 갈린다:

- **host 단독**: 한 venv 에 torch·ultralytics·opencv·langchain·openai·scipy·openwakeword 가 **전부 공존**.
  마지막에 `pip install --force-reinstall "numpy<2"` 1회로 전 스택을 한 핀에 묶는다.
  → 한 라이브러리가 numpy>=2 를 끌어오면 **전 스택 import 가 동시에 깨진다**. 검증도 합집합 import 게이트 1개
  (`host-python-deps.sh` step 6: numpy·torch·langchain·openwakeword 를 한 번에 import).
- **분리 컨테이너**: yolo 이미지에는 **langchain 이 없고**, voice 이미지에는 **torch 가 없다**.
  각 이미지가 자기 스택만 numpy<2 로 핀(각 Dockerfile 마지막 layer + 자체 smoke assert).
  → 한 이미지의 의존성 충돌이 **다른 이미지로 번지지 않는다**. 충돌 표면이 이미지 단위로 격리.

**voice(헤드라인)** 가 대비를 가장 잘 드러낸다: torch(YOLO) + langchain/openai(LLM) + openwakeword(tflite)
세 이질적 스택이 host 단독에선 한 venv 에 얹히지만, 컨테이너에선 애초에 두 이미지로 갈려 한곳에서 만나지 않는다.
**text** 는 스택이 단순(YOLO + DSR, 음성·LLM 없음)해 결합 압력 자체가 작다 — 대비 효과는 voice 보다 약하다.

### host 오염 / PEP 668

- **host 단독**: noble 의 externally-managed Python 때문에 전역 pip 이 막힌다. `venv --system-site-packages`
  로 우회(venv 안에서 rclpy/colcon 가시 유지). 대신 host 에 torch cu128·langchain 이 실재 →
  `import torch` 가 host 에서 성공(= ADR-008 의 "host 청결" 가정이 이 브랜치에선 무효).
- **분리 컨테이너**: host 는 application Python 을 *아예 설치하지 않는다*. PEP 668 우회 자체가 불필요.
  host `import torch` → ImportError 가 **의도된 정상**.

### 단일 진실 소스

- **host 단독**: `host-python-deps.sh` (6 step 절차적 스크립트). 재현 = 같은 host 에서 스크립트 재실행.
- **분리 컨테이너**: Dockerfile 2개. 재현 = 이미지 pull(또는 동일 Dockerfile build). 빌드 환경이 이미지에 박제.

---

## 2. 운영 (재빌드 blast radius / lifecycle / 관측성)

| 상황 | host 단독 | 분리 컨테이너 |
|---|---|---|
| voice 노드 코드 1줄 수정 | colcon ws 재빌드. venv 공유라 의존성 변경 시 전 스택 영향 가능 | **voice 이미지만** 재빌드·재기동. yolo 무관 |
| 의존성 1개 추가/충돌 | host venv 전체에 영향 (전 노드 공유 환경) | 해당 이미지에 국한 |
| 실패 격리 / 재시작 | 프로세스 단위지만 **env 공유** (한 venv) | 서비스 단위 (`restart: unless-stopped`), env 격리 |
| 관측성 | host 프로세스 로그 (각자 stdout) | `docker logs -f <service>` per-service |
| 이식성 / 재현성 | 타 host 에서 셋업 스크립트 재실행 (host 상태 의존) | 이미지 pull (빌드 결과 고정) |

**요지**: 컨테이너는 *재빌드·실패·관측의 단위를 서비스로 좁혀* blast radius 를 줄인다.
host 단독은 단위가 "host venv 1개"라 변경·고장의 영향 반경이 넓다.

---

## 3. ROS 통신 토폴로지 (학습 핵심)

**두 모델 모두 CycloneDDS 를 쓰고, 컨테이너 쪽도 `network_mode: host` 라 host 네트워크 네임스페이스를 공유한다.**
즉 컨테이너 노드와 host 노드는 **같은 host loopback DDS** 위에서 토픽/서비스를 주고받는다 — split 패키지든
모놀리식이든 와이어 계약(토픽 `/camera/...`, 서비스 `/get_3d_position`·`/get_keyword`, `od_msg`)이 동일하다.

따라서 **컨테이너가 바꾸는 것은 "ROS 통신 방식"이 아니라 "노드가 사는 의존성·파일시스템 경계"다.**
이 구분이 이 비교의 핵심 학습 포인트다:

- 컨테이너화의 이득(의존성 격리·host 청결·재빌드 국소화·관측성)은 **패키징/배포 경계**에서 온다.
- DDS 통신 자체는 두 모델에서 거의 동일하게 동작한다 (network_mode host 덕에 브리지/도메인 격리 없음).

(주의: `network_mode: host` 를 버리고 bridge 네트워크로 가면 그때부터 DDS discovery·멀티캐스트가 통신 변수로
등장한다. 현재 두 모델은 그 변수를 의도적으로 제거한 상태 — 통신이 아니라 의존성만 비교하기 위해.)

---

## 4. 트레이드오프 요약

| | host 단독 | 분리 컨테이너 |
|---|---|---|
| 셋업 단순성 | ✔ 스크립트 1개, 도커 불필요 | 이미지 build/pull + compose 필요 |
| 의존성 격리 | ✘ 전 스택 한 venv | ✔ 이미지별 |
| host 청결 | ✘ torch/langchain 오염 | ✔ apt-only |
| 재빌드 국소화 | ✘ ws/venv 단위 | ✔ 서비스 단위 |
| 관측성(per-service) | △ 프로세스별 stdout | ✔ `docker logs <svc>` |
| 재현성/이식성 | △ host 상태 의존 | ✔ 이미지 고정 |
| 디스크/이미지 비용 | △ venv 1개 | ✘ 이미지별 중복(torch 등) |
| 디버깅 즉시성 | ✔ host 에서 바로 | △ exec 진입 필요 |

한 줄: **host 단독은 시작이 싸고 디버깅이 즉각적이지만 결합·오염·넓은 blast radius 를 진다.
컨테이너는 셋업·디스크 비용을 내는 대신 격리·청결·국소 재빌드·관측성을 산다.**

---

## 5. 측정 대상 (미측정)

아래는 실측 머신(GPU/마이크/로봇)에서 채울 자리다. 현재 값은 전부 `미측정` — 추정값을 넣지 않는다.

| 지표 | host 단독 | 분리 컨테이너 | 수집 방법(참고) |
|---|---|---|---|
| 설치/이미지 크기 | 미측정 | 미측정 | venv `du -sh` / `docker image ls` |
| 초기 빌드·설치 시간 | 미측정 | 미측정 | `time host-python-deps.sh` / `time build-all.sh` |
| 코드 1줄 수정 후 재반영 시간 | 미측정 | 미측정 | colcon 증분 vs 이미지 재빌드 `time` |
| 노드 기동 시간 | 미측정 | 미측정 | 프로세스 start→ready / `up` →ready |
| (옵션) DDS round-trip | 미측정 | 미측정 | `ros2 topic delay` 등 |

---

## 6. (옵션) 3번째 점 — 단일 fat 컨테이너

본 비교는 2점(host 단독 ↔ 분리 컨테이너)이다. 학습을 더 정밀하게 하려면 중간점을 둘 수 있다:

- **단일 fat 컨테이너**: 모놀리식 전 노드 + 전 의존성(torch+langchain+DSR)을 **한 이미지**에 넣어 실행.
  기술적으로 가능하다 — numpy<2 가 두 스택 공통 제약이라 한 venv 에 공존하고, DSR 도 컨테이너 안에서
  colcon 빌드 후 에뮬레이터와 DDS 통신 가능.
- 이 중간점은 두 변수를 **분리**한다:
  - `host 단독 → fat 컨테이너`: "host 청결/재현성"만 바뀜 (둘 다 monolith, deps 한 곳).
  - `fat 컨테이너 → 분리 컨테이너`: "의존성 격리/재빌드 국소화"만 바뀜 (둘 다 컨테이너).

**이번엔 빌드하지 않는다**(분석 문서 범위). 2점 비교 실행 중 문제가 생기거나 변수 분리가 필요할 때 도입을 고려한다.

---

## Further reading

- ADR: `docs/decisions/README.md` — **ADR-008**(host venv 폐기), **ADR-014**(shell vs containers 브랜치 분기),
  **ADR-009**(Phase 4 base image/network/빌드게이트), **ADR-002**(numpy<2 핀), **ADR-006**(cu128, host 미설치).
- 컨테이너 실물: `containers/{yolo-detection,voice-processing}/Dockerfile`, `containers/entrypoint.sh`,
  `containers/docker-compose.yml`, `containers/README.md`.
- host 단독 실물: `feat/application-shell:resources/host-python-deps.sh` (`git show` 로 열람), 동 브랜치 `a02-robot-camera.sh`.
- 통신/튜닝: `resources/hostcfg.sh dds`, `docs/COMPATIBILITY.md`(Phase 4 핀 매트릭스).

> 업데이트 트리거: 실측 머신에서 §5 측정값을 채울 때, 단일 fat 컨테이너(§6)를 실제 구축할 때,
> 또는 두 브랜치의 배포 구조가 바뀔 때.
