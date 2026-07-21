# install.sh `--no-nvidia-driver` 플래그 — 설계 (design spec)

- **작성일**: 2026-07-21
- **상태**: 승인됨 (구현 대기)
- **산출 브랜치**: `feat/application-containers` (docs 는 public main 제외 대상 → dev 에만 존재)
- **변경 파일**: `install.sh`, `resources/orchestrate.sh` (2개)

## 1. 목적 (motivation)

`install.sh` 는 검증된 타겟 워크스테이션 재현을 위해 `nvidia-driver-595` 를 핀 고정 설치하고, reboot 전 "nvidia 커널 모듈 존재" 게이트에서 `exit 1` 한다. **타겟이 아닌 머신**(설치 스크립트 개발/테스트용, 또는 이미 다른 방식으로 드라이버를 깔아둔 워크스테이션)에서는 이 단계가 불필요하거나 실패한다.

`--no-nvidia-driver` 플래그로 **드라이버 설치 단계(step 2, `a01_nvidia_driver`)만** 건너뛴다. 나머지 base 설치(kernel/docker/ROS2/reboot/vscode/dds/static-IP)는 그대로 진행.

**전제**: 플래그를 준 사용자는 **그래픽 드라이버를 이미 별도로 설치했다고 상정**한다. 따라서 이 플래그는 "GPU 없음" 감지가 아니라 "드라이버는 외부에서 관리됨" 선언이며, 드라이버 존재 여부를 검증하지 않는다(사용자 책임).

## 2. 스코프

**포함**: step 2 `a01_nvidia_driver` 단계 skip + 그 결정의 영속화.

**비포함 (non-goal)**:
- reboot(step 6) — docker 그룹 적용에 여전히 필요하므로 유지.
- static-IP(step 9), nvidia-container-toolkit(setup-app.sh 소관) — 무관.
- GPU 자동 감지 / 드라이버 존재 검증 게이트 — 넣지 않음(사용자 상정 책임).
- 별도 env 변수 surface — 플래그 하나로 충분(YAGNI).

## 3. 핵심 제약 — reboot-resume 영속성

install.sh 는 step 6 에서 reboot 하고, 복귀 시 GUI autostart 가 **`bash install.sh` 를 인자 없이** 재실행한다(`resources/install-resume-launcher.sh:15`). 이때 `run_stage_a01 0` 이 다시 호출되어 nvidia 단계를 재평가한다.

→ **플래그만으로는 부족**하다. reboot 후 플래그가 사라지므로, opt-out 결정은 **state 파일에 영속화**해야 한다. state 파일은 reboot 를 넘어 살아남는다.

기존 `SKIPPED` 상태 + `step_end_skip` 는 정의돼 있으나 **현재 어디서도 호출되지 않는다**(dead machinery). 이를 활성화해 재사용한다.

## 4. 파일별 변경

### 4.1 `install.sh`

- `NO_NVIDIA_DRIVER=0` 선언.
- `--verbose` 를 분리하는 pre-parse 루프(88–100줄)에 `--no-nvidia-driver` 케이스 추가 → `NO_NVIDIA_DRIVER=1`. (subcommand 와 직교하는 modifier → 스트립 후 `--status`/`--reset`/빈 subcommand 판정 그대로 유지.)
- `run_stage_a01 0` → `run_stage_a01 0 "$NO_NVIDIA_DRIVER"` (162줄).
- `usage()` 에 플래그 1줄 + "assumes the NVIDIA driver is already installed by other means" 설명 추가.

### 4.2 `resources/orchestrate.sh`

- **`step_should_skip` (71줄)**: 정규식 `^step_${name}=DONE$` → `^step_${name}=(DONE|SKIPPED)$`. DONE 뿐 아니라 SKIPPED 도 skip 으로 인정 → reboot 후 인자 없는 재실행에서도 opt-out 유지. (`a01_reboot` 는 SKIPPED 로 기록되는 경로가 없어 install.sh:148/170 의 기존 동작 불변.)
- **`run_step_skip()` 신설**: `[n/total] skip: <name> (<reason>)` 출력 + `_state_set <name> SKIPPED`. run_step 과 같은 콘솔 스타일.
- **`run_stage_a01` (315줄)**: 2번째 인자 `skip_nvidia="${2:-0}"` 추가. nvidia 줄을 분기:
  ```bash
  if [[ "$skip_nvidia" == 1 ]]; then
      run_step_skip $((off + 2)) a01_nvidia_driver "nvidia driver assumed pre-installed (--no-nvidia-driver)"
  else
      run_step $((off + 2)) a01_nvidia_driver bash "${RESOURCE_DIR}/nvidia-driver-install.sh"
  fi
  ```
- **run_step 의 skip 메시지 (228줄)**: `(already DONE)` 하드코딩 → 실제 상태 반영(`already done` vs `already skipped`). SKIPPED 단계를 DONE 이라 잘못 표기하지 않도록(정직성). `_state_get` 소형 헬퍼 또는 인라인 grep 로 상태 조회.

**total 은 9 불변** — 단계를 제거하는 게 아니라 SKIPPED 로 표시하므로 번호 재정렬 없음.

## 5. 엣지 케이스

- **`--status`**: nvidia 단계가 `step_a01_nvidia_driver=SKIPPED` 로 정직하게 표시(DONE 위장 안 함).
- **`--reset`**: state 파일 삭제 → opt-out 도 초기화. 재실행 시 플래그를 다시 줘야 skip(의도된 동작).
- **플래그 + 다른 subcommand**: `install.sh --no-nvidia-driver --status` 등 — 플래그는 modifier 로 스트립되고 subcommand 정상 처리. 무해.
- **타겟 머신에서 실수로 플래그 사용**: 드라이버 미설치 상태로 진행될 수 있음 — 하지만 "이미 설치했다고 상정" 전제이므로 사용자 책임 범위. 검증 게이트는 의도적으로 없음.

## 6. 검증 (Tier 1)

- `shellcheck install.sh resources/orchestrate.sh` 통과.
- 시나리오 ① `bash install.sh --no-nvidia-driver` → 콘솔에 `[2/9] skip: a01_nvidia_driver (...)`, state 에 `step_a01_nvidia_driver=SKIPPED`.
- 시나리오 ② ①의 SKIPPED state 에서 `bash install.sh`(인자 없음) 재실행 → nvidia 단계 여전히 skip(reboot-resume 모사, 실제 reboot 없이 state 로 검증).
- 시나리오 ③ 플래그 없이 실행 → nvidia 단계 정상 진입(회귀 없음). (드라이버 실제 설치는 타겟 머신 실측 몫 — 문서 머신에서는 state 흐름만 검증.)
