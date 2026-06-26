# pick & place 실습 — 컨테이너 없이 venv 로 실행하기

## 이게 뭔가
- 같은 pick & place 기능을 **두 가지 방식**으로 본다:
  - **컨테이너 방식(정식)**: `bash ~/ros2_jazzy_test/containers/bringup.sh` + `docker compose up -d` — 몇 줄로 끝.
  - **venv 방식(이 문서)**: 모놀리식 노드를 host venv 로 직접 — 의존성 설치·핀·네임스페이스·멀티터미널을 손으로.
- 목적: 컨테이너 이미지가 **대신 해주던 일**을 한 단계씩 체감.
- 모든 명령은 **한 줄씩 직접** 복사·실행하고 결과를 관찰한다.

## 주의
- 데모 산출물은 `~/.cobot2_venv_demo/` 에만 생성 → `rm -rf ~/.cobot2_venv_demo` 로 정리(Part C).
- `~/cobot_ws/src/cobot2` 원본을 in-place 수정한다(비추적). 되돌리려면 Part C 참고.
- 정식 설치 경로 아님 — 비교 학습용.

## Part 0 — 사전 점검

한 줄씩 실행해 전제를 확인한다(하나라도 실패하면 정식 설치 먼저).

```bash
# ROS2 jazzy 존재
command -v ros2                                  # 예상: /opt/ros/jazzy/bin/ros2 경로 출력 (없으면 ROS 미설치/미source)
# host colcon 빌드본에 DSR + od_msg (overlay 의존)
ls ~/cobot_ws/install/dsr_common2/lib/python3.12/site-packages/DSR_ROBOT2.py   # 예상: 경로 출력
ls ~/cobot_ws/install/od_msg                     # 예상: include lib share
# 두 원본 패키지 존재
ls ~/cobot_ws/src/cobot2/pick_and_place_text ~/cobot_ws/src/cobot2/pick_and_place_voice
# config.sh (RMW/도메인 소스) 존재
ls ~/ros2_jazzy_test/resources/config.sh
```

## Part A — 1회 환경 구성
### A1. 원본 패키지 활성화 (COLCON_IGNORE 제거)
### A2. voice 번들 rename + 마이크 fix
### A3. venv 생성
### A4. 의존성 설치 (pip)
### A4b. voice 에셋 스테이징
### A5. colcon 빌드 (격리 overlay)

## Part B — 실행
### text 데모 (터미널 3개)
### voice 데모 (터미널 4개)

## Part C — 정리 & 대비
