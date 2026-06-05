# Session Handoff — LATEST

> 매 세션 종료 전 갱신. 글로벌 `SessionStart` hook 이 자동 로드.
> Forward-looking only — 본 세션에서 한 일이 아니라 다음 세션이 할 일.
> 두 머신 공유 — **[실측]** 머신(로봇/카메라 실기) + **[문서]** 머신(git/문서/lessons). 항목에 담당 표기.

## Last updated
2026-06-05 — **[문서]** 연속 2작업: (1) **CycloneDDS 프로젝트 표준 전환 + 유선 NIC/커널버퍼 설치 자동화** (`resources/dds-tuning.sh`, install.sh step 13, config.sh 기본 RMW=cyclonedds) push 완료. (2) **Phase 4 — 통신 토폴로지 = robot_control 중심 star 확정**(cobot2_ws 코드가 이미 전부 ROS2 service 기반, socket 없음) + 통합 bringup launch `cobot2_ws/launch/bringup_all.launch.py` 골격(로봇 드라이버 dsr_bringup2 + host 카메라 realsense + yolo/voice 컨테이너 `docker compose up -d` 를 한 번에; robot_control 실모션은 `start_robot_control:=true` 옵트인, `mode` 기본 virtual) + 결정기록(통신 토폴로지 star)·로드맵 Phase 4·Notion 2번 항목을 **카메라 host 소유**로 정합. **(2)는 미커밋** — launch + 신규 ADR + roadmap 편집. 직전 2026-06-04: origin 동기화 + lessons 푸시(`55a7890`), RealSense 미인식(케이블 부재).

---

## Next Actions (priority order)

1. **[실측] RealSense 재연결 + USB 3.x 검증** (케이블 확보 후 — 현재 데이터 케이블 없음):
   - 현 상태: 카메라 OS 미인식 (`/dev/video*` 없음, `lsusb -t` 트리에 없음, `rs-enumerate-devices` = no device).
   - 절차: `sudo dmesg -wH` 켜고 재연결 → `new SuperSpeed`(USB3 OK) / `new high-speed`(USB2로 떨어짐) / 무반응(케이블·포트·전원) 구분 → `rs-enumerate-devices` 의 `Usb Type Descriptor`(3.2 vs 2.1) 로 최종 확인.
   - 머신 USB3 포트는 정상(`lsusb -t` 에 10000M/20000M 다수). 1순위 의심 = 데이터+USB3 지원 케이블(충전 전용 의심).
2. **[실측] DSR jog 모션 검증** (위치 읽기만 확인됨, movej/movel 미실행):
   - 터미널1: `ros2 launch dsr_bringup2 dsr_bringup2_rviz.launch.py mode:=real host:=192.168.1.100 port:=12345 model:=m0609 name:=dsr01 gui:=false`
   - 터미널2: `python3 ~/ros2_jazzy_test/jog_complete.py` → +/- 버튼 소폭 이동. **실기 — 비상정지 대기.**
3. **[실측] fleet 머신에 DSR 패치 전파** — 메모 `~/dsr_patch_command.txt`(+USB 사본). 이미 설치된 머신은 state DONE 이라 install.sh skip → 직접 sed.
4. **[실측, 2026-06-08(월) 예정] Phase 4 통합 E2E**: ① `bash containers/build-all.sh` 이미지 빌드 — **yolo 이미지는 host 소유 카메라 전제로 realsense 드라이버 제거 반영 필요**(잔존 시 정리). ② 셸에 `config.sh`+`/opt/ros/jazzy`+`~/cobot2_ws/install` overlay 3개 source + `.env`·`cyclonedds.xml` 준비 후 `ros2 launch <repo>/cobot2_ws/launch/bringup_all.launch.py mode:=real host:=192.168.1.100`. ③ 검증: 컨테이너에서 `/camera/camera/*` 가시 + host `robot_control` 이 `/get_keyword`·`/get_3d_position` 왕복(star). voice 마이크 passthrough + OPENAI_API_KEY 런타임 주입. 미빌드 점검은 `containers:=false`.
5. **[문서] 미정리 git 항목 결정**:
   - `backup/pre-github-sync-2026-05-29` 브랜치: origin 미push(로컬 전용) — 삭제/보존/push 결정.
   - 태그 `v0.1.0`: origin 미push — push 여부 결정.
   - `.gitignore` 에이전트 산출물 4줄(`.agents/`, `.claude/skills/`, `.understand-anything/`, `skills-lock.json`): 실측·문서 머신이 쓰는 에이전트 도구가 달라 **보류 중**. 머신별 처리 vs repo 통합 결정.
6. **[문서/실측] RealSense udev rule 명시화 패치** (보류 — 사용자 검토 대기): `resources/realsense-sdk-install.sh` SDK 설치 줄에 `librealsense2-udev-rules` 명시 추가 + rule 파일 존재 검증 게이트 + `udevadm control --reload-rules && udevadm trigger`. 현재는 `librealsense2-dkms` 의 **Recommends** 로만 유입 → apt 기본값(Install-Recommends ON)일 때만 자동, `--no-install-recommends` 환경/타 머신 전파 시 silent 누락(카메라 비-root 접근 실패) 가능. 적용 시 `docs/COMPATIBILITY.md` 동반 갱신. 최종 확정은 [실측]에서 `dpkg -l librealsense2-udev-rules` + `ls /lib/udev/rules.d/*realsense*`.
7. **[공통] 브랜치 canonical 선택**: `feat/application-containers`(현재) vs `feat/application-shell` → main 병합 시점.

---

## Open Decisions

- **브랜치 canonical**: containers vs shell — main 병합 대상.
- **Phase 4 컨테이너 design 잔여**: GPU passthrough 활성화 + 마이크 passthrough + yolo 이미지 realsense 드라이버 제거. (해결됨: DDS=cyclonedds/`network_mode: host`, 통신 토폴로지=star, compose 자동 up=통합 bringup launch.)
- **미push git 객체**: backup 브랜치 / `v0.1.0` 태그 origin 반영 여부.
- **.gitignore 에이전트 산출물**: 머신마다 도구가 달라 통합 보류 — 머신별 .gitignore vs repo 통합.
- **RealSense udev 명시화**: `librealsense2-dkms` Recommends 의존 유지 vs `librealsense2-udev-rules` 명시설치+검증 패치 — silent 누락 위험 대비 (Next Actions #6).

---

## Remaining Issues

- RealSense **미인식** — 케이블 부재로 진단 중단. 내일 케이블 확보 후 재개.
- DSR jog **모션(movej/movel)** 미검증 — 위치 읽기(get_current_posj)만 실기 응답 확인.
- DSR 패치: 이 머신 라이브본 + 설치 스크립트 + **origin 반영 완료**. 다른 fleet 머신은 미적용.

---

## Context Notes

### git 동기화 상태 (2026-06-04 문서 머신)
- origin `feat/application-containers` 와 완전 동기화 (HEAD `55a7890`). main / feat/application-shell 도 동기화.
- 2026-06-02 실측 커밋 5건 fast-forward pull: DSR 패치 `c6cd645`, jog gitignore `9f0f243`, a04 음성 `1524617`, heartbeat `6152a3b`, 핸드오프/메모리 `25184e4`.
- pull 시 로컬 `.gitignore` 의 에이전트 산출물 4줄은 버리고 origin 버전 채택 → 4개 디렉토리 다시 untracked 노출(noise, 커밋 대상 아님).
- lessons **L-009** 추가·푸시(`55a7890`).

### DSR_ROBOT2 jazzy 패치 2종 (재발/타 머신 시 필수 — origin 반영 완료)
doosan-robot2 `-b jazzy` clone 의 `dsr_common2/imp/DSR_ROBOT2.py` 이름 불일치 2개. `from DSR_ROBOT2 import` 쓰는 모든 스크립트 공통:
1. **import NameError**: `SetSingularityHandlingForce`(코드) ↔ `SetSingularHandlingForce`(빌드 클래스). 이름 치환.
2. **서비스 무한 대기**: `_srv_name_prefix=''` → 죽은 이름 `/dsr01/aux_control/...` 호출. 실서버는 `/dsr01/dsr_controller2/...`. prefix `''`→`'dsr_controller2/'`(모듈 레벨).
- `resources/dsr-project-install.sh` 가 clone 직후 멱등 sed patch. 이미 설치된 머신은 state DONE → skip → `~/dsr_patch_command.txt` 직접 sed.

### 실기 로봇 환경 (검증된 값)
- 모델 `m0609`, 네임스페이스 `dsr01`.
- 컨트롤러(DRCF) `192.168.1.100:12345`. 그리퍼 `192.168.1.1`. host `enp4s0 192.168.1.30/24`(로봇망), `wlo1 192.168.10.61`.
- 실서버 전부 `/dsr01/dsr_controller2/...`. joint_states 는 `/dsr01/joint_states`.

### RealSense / DDS 수신 튜닝 (L-008 / L-009)
- 대용량 토픽 `ros2 topic hz` 저수치 = 측정/전송 계층 artifact, 카메라 성능 아님. 작은 동반 토픽(`camera_info`)으로 교차검증.
- CycloneDDS(UDP) raw 0Hz → `net.core.rmem_max`(커널 천장) + `SocketReceiveBufferSize`(rcvbuf, 실제 SO_RCVBUF) **둘 다** 상향(clamp 관계). 버퍼 하한 = 수신 최대 토픽 1프레임: color 2.76MB / depth Z16 1.84MB / **pointcloud ≈14.7MB**(>rcvbuf 10MB면 pointcloud만 0Hz). Fast-DDS 기본(같은 호스트=SHM)엔 socket 버퍼 무효 — SHM segment/QoS depth 가 노브.
- `RMW_IMPLEMENTATION`·`CYCLONEDDS_URI` 는 **쉘별 환경변수** — 측정/노드 터미널 양쪽 export.

### 함정 (다음 세션 피하기)
- python stdout 파이프 시 block-buffered → hang 오인. `python3 -u` + `flush=True`.
- DSR 서비스 "있는데 응답 없음" → short name(클라이언트) vs `dsr_controller2/` prefix(실서버) 갈림. `ros2 node info` 로 서버 노드 확인.

### USB / export / 음성 (참고)
- host-only USB export: `/media/rokey/Rokey/ros2_jazzy_test_host`. DSR 패치 메모: `~/dsr_patch_command.txt`(+USB 사본).
- a04 음성: 키 없으면 그 자리 입력(`read -rs`) 후 `.env` 기록, 비대화형은 경고+exit0. install.sh: 비-verbose heartbeat, `--verbose`/`VERBOSE=1` 시 step stdout 노출.

---

## Current Focus
- **[실측] Top priority**: RealSense 케이블 확보 후 재연결+USB3 검증 → DSR jog 모션 검증. **2026-06-08(월) Phase 4 통합 E2E 예정**(bringup launch + 컨테이너 빌드/왕복).
- **[문서] Friction**: 미push git 객체(backup 브랜치 / `v0.1.0` 태그) + `.gitignore` 에이전트 산출물 + RealSense udev 명시화 패치 결정 대기.
