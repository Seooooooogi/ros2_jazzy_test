# 데모 venv 학생 배포/복구용 uv 설치 경로 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 학생이 원커맨드(`bash scripts/venv-demo/uv/setup.sh`)로 데모 venv(`~/cobot_demo_ws/.venv`)를 lock 기준 동일하게 구성/복구할 수 있게 한다.

**Architecture:** `scripts/venv-demo/uv/` 에 uv 프로젝트(pyproject.toml + uv.lock)를 두고, wrapper `setup.sh` 가 전제 확인 → apt 헤더 → venv 생성 → `uv sync --frozen` → post-install(tflite shim/oww 모델) → self-check 를 6단계로 수행한다. LAB.md one-by-one 경로(커리큘럼)는 불변, 포인터 1줄만 추가.

**Tech Stack:** bash, uv 0.11.2 (`dependency-metadata` / `override-dependencies` / explicit index), Python 3.12.

**Spec:** `docs/specs/2026-07-20-venv-uv-student-setup-design.md` (승인됨. 실측 근거 2026-07-20 포함)

## Global Constraints

- 실행 진입점 `.sh` 는 `#!/usr/bin/env bash` + `set -euo pipefail` (레포 공통 규약).
- `shellcheck` exit 0 없이 머지 금지.
- 버전 핀: uv `0.11.2`(astral.sh 버전 핀 installer), torch `2.11.0` / torchvision `0.26.0` (cu128 explicit index), numpy `<2` (override), 나머지 핀은 `scripts/venv-demo/requirements.txt` 활성 줄과 동일.
- venv 사양은 LAB 와 동일: `~/cobot_demo_ws/.venv`, `--system-site-packages`, `/usr/bin/python3.12` 기반.
- `scripts/venv-demo/LAB.md` 는 포인터 1줄 외 불변. `requirements.txt` 불변.
- 콘솔 메시지 prefix `venv-uv:`, 진행률 `[n/6]` (standalone 진입점 — orchestrate.sh 미경유).
- 커밋 단계는 **사용자 명시 승인 후에만** 실행. AI attribution / 내부 코드명(마일스톤·결정번호·룰번호) 커밋 메시지 금지.
- **배포 게이트**: Task 4 의 타깃(Ubuntu 24.04) 실측 3건 통과 전 학생 배포 금지.
- 이 레포 머신은 Ubuntu 22.04(system python 3.10) — setup.sh 전체 실행은 불가하고 정적 검증 + 플래그 스모크만 수행. 전체 실행 검증은 Task 4([실측] 머신).

---

### Task 1: uv 프로젝트 (pyproject.toml + uv.lock)

**Files:**
- Create: `scripts/venv-demo/uv/pyproject.toml`
- Create: `scripts/venv-demo/uv/uv.lock` (명령 산출물 — 손으로 쓰지 않음)

**Interfaces:**
- Consumes: `scripts/venv-demo/requirements.txt` 의 핀(참조용 — 값은 아래 코드에 이미 반영됨).
- Produces: `uv.lock` — Task 2 의 `setup.sh` 가 `uv sync --frozen --project <이 디렉토리>` 로 소비. pyproject 는 `requires-python = ">=3.12"`.

- [ ] **Step 1: pyproject.toml 작성**

`scripts/venv-demo/uv/pyproject.toml` 를 아래 내용 그대로 생성 (2026-07-20 실측 검증본 — resolution·서브셋 실설치·import 통과):

```toml
# 데모 venv 배포/복구용 의존 선언 — scripts/venv-demo/requirements.txt(LAB) 와 수동 동기.
# 원천은 동일(컨테이너 Dockerfile 미러). 한쪽 갱신 시 다른 쪽 확인.
# 갱신 절차: 이 파일 수정 → `uv lock` → uv.lock 커밋. 학생 머신은 setup.sh(--frozen) 전용.
[project]
name = "cobot-demo-venv"
version = "1.0.0"
requires-python = ">=3.12"
dependencies = [
    # torch — cu128 인덱스 (아래 tool.uv.sources 로 핀)
    "torch==2.11.0",
    "torchvision==0.26.0",
    # requirements.txt 활성 줄
    "ultralytics<9",
    "opencv-python<4.10",
    "langchain<2",
    "langchain-openai<2",
    "openai<3",
    "pyaudio",
    "sounddevice",
    "scipy<1.18",
    "python-dotenv",
    "pymodbus<3.7",
    "onnxruntime<2,>=1.10.0",
    "tqdm<5,>=4.0",
    "scikit-learn<2,>=1",
    "requests<3,>=2.0",
    "ai-edge-litert>=2.0.2,<3",
    "typer",
    "filetype",
    "pi-heif",
    "pillow-avif-plugin",
    # pip 에선 --no-deps 가 필요했던 2종 — dependency-metadata 로 의존 선언 교체
    "openwakeword==0.6.0",
    "roboflow<2",
    # numpy — 아래 override 로 <2 강제 (pip 의 '최후 재핀' 순서 함정 제거)
    "numpy",
]

# openwakeword 0.6.0 은 tflite-runtime(py3.12 wheel 없음)을 선언 — 실제 런타임 의존으로 교체.
# tflite_runtime import 호환은 setup.sh 의 shim 이 담당.
[[tool.uv.dependency-metadata]]
name = "openwakeword"
version = "0.6.0"
requires-dist = [
    "onnxruntime>=1.10.0,<2",
    "tqdm>=4.0,<5",
    "scikit-learn>=1,<2",
    "requests>=2.0,<3",
    "ai-edge-litert>=2.0.2,<3",
]

# roboflow 기본 의존이 opencv-python-headless 를 끌어와 opencv-python 과 cv2/ 디렉토리 충돌
# → headless 를 뺀 의존 선언으로 교체 (2026-07-20 실측: 이 목록으로 import roboflow 성공).
[[tool.uv.dependency-metadata]]
name = "roboflow"
requires-dist = [
    "certifi",
    "idna",
    "cycler",
    "kiwisolver",
    "matplotlib",
    "numpy",
    "pillow",
    "python-dateutil",
    "python-dotenv",
    "requests",
    "six",
    "urllib3",
    "tqdm",
    "PyYAML",
    "requests-toolbelt",
    "filetype",
]

# ultralytics 등이 numpy>=2 를 요구해도 resolver 수준에서 <2 강제 — 설치 순서 무관.
[tool.uv]
override-dependencies = ["numpy<2"]

# torch cu128 — torch/torchvision 만 이 인덱스에서 (explicit: 다른 패키지는 PyPI).
[[tool.uv.index]]
name = "pytorch-cu128"
url = "https://download.pytorch.org/whl/cu128"
explicit = true

[tool.uv.sources]
torch = { index = "pytorch-cu128" }
torchvision = { index = "pytorch-cu128" }
```

- [ ] **Step 2: uv.lock 생성**

Run: `cd ~/ros2_jazzy_test/scripts/venv-demo/uv && uv lock --python 3.12`
Expected: `Resolved 118 packages in ...` (±수 개 허용 — PyPI 신규 릴리스로 변동 가능), exit 0. `uv.lock` 파일 생성됨.

- [ ] **Step 3: lock 검증 (이 grep 세트가 이 Task 의 테스트)**

Run (모두 `scripts/venv-demo/uv/` 에서):

```bash
grep -c "tflite" uv.lock                 # 기대: 출력 0 (매치 0건이라 grep 자체는 exit 1 — 정상)
grep -c "opencv-python-headless" uv.lock # 기대: 출력 0 (동일 — exit 1 이 성공 조건)
grep -A1 '^name = "numpy"' uv.lock       # 기대: version = "1.26.4" (<2 override 성공)
grep -A2 '^name = "torch"' uv.lock       # 기대: version = "2.11.0+cu128", source 에 download.pytorch.org/whl/cu128
grep -A1 '^name = "openwakeword"' uv.lock # 기대: version = "0.6.0"
grep '^name = "roboflow"' uv.lock        # 기대: 1건 존재
```

하나라도 불일치 시: pyproject.toml 을 위 Step 1 내용과 대조(오탈자) 후 `uv lock` 재실행. 그래도 불일치면 **중단하고 사용자 보고** (upstream 메타데이터 변동 가능성 — 임의 핀 변경 금지).

- [ ] **Step 4: Commit (사용자 승인 후)**

```bash
git add scripts/venv-demo/uv/pyproject.toml scripts/venv-demo/uv/uv.lock
git commit -m "데모 venv 의존성을 uv lock 으로 고정 (배포/복구용 선언 프로젝트)"
```

---

### Task 2: setup.sh (wrapper 스크립트)

**Files:**
- Create: `scripts/venv-demo/uv/setup.sh`

**Interfaces:**
- Consumes: Task 1 의 `pyproject.toml`/`uv.lock` (같은 디렉토리, `--project "$SCRIPT_DIR"` 로 지정), 레포 동봉 `resources/oww_models/*.tflite`.
- Produces: `~/cobot_demo_ws/.venv` (system-site, python3.12) — LAB Part B 의 실행 절차가 그대로 소비.

- [ ] **Step 1: setup.sh 작성**

`scripts/venv-demo/uv/setup.sh` 를 아래 내용 그대로 생성:

```bash
#!/usr/bin/env bash
# scripts/venv-demo/uv/setup.sh — 데모 venv(~/cobot_demo_ws/.venv) 원커맨드 구성/복구.
# LAB.md A3+A4 와 동일 결과물을 uv.lock 기준으로 재현한다(순서 함정 없음).
# 학습용이 아니다 — 처음이면 LAB.md 를 한 줄씩(각 핀의 이유가 실습 내용).
set -euo pipefail

UV_VERSION="0.11.2"
VENV_DIR="$HOME/cobot_demo_ws/.venv"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TOTAL=6

step() { echo "[$1/${TOTAL}] $2"; }
fail() { echo "venv-uv: [FAIL] $*" >&2; exit 1; }

step 1 "전제 확인 (python3.12 / uv)"
command -v /usr/bin/python3.12 >/dev/null 2>&1 \
    || fail "/usr/bin/python3.12 없음 — Ubuntu 24.04 base 설치(install.sh) 선행 필요"
if ! command -v uv >/dev/null 2>&1; then
    read -rp "venv-uv: uv ${UV_VERSION} 을 설치합니다 (astral.sh installer). 진행? [y/N] " ans
    [[ "${ans}" == [yY]* ]] || fail "uv 미설치 — 중단"
    curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh
    export PATH="$HOME/.local/bin:$PATH"
    command -v uv >/dev/null 2>&1 || fail "uv 설치 후에도 PATH 에 없음 — 셸 재시작 후 재실행"
fi
if [[ "$(uv --version | awk '{print $2}')" != "${UV_VERSION}" ]]; then
    echo "venv-uv: [WARN] uv $(uv --version | awk '{print $2}') ≠ 검증 버전 ${UV_VERSION} — 계속 진행(lock 은 --frozen 이라 해석 고정)" >&2
fi

step 2 "apt 헤더 (portaudio19-dev libsndfile1 python3.12-venv)"
if ! dpkg -s portaudio19-dev libsndfile1 python3.12-venv >/dev/null 2>&1; then
    sudo apt-get install -y portaudio19-dev libsndfile1 python3.12-venv
else
    echo "venv-uv: apt 헤더 이미 설치됨 — skip"
fi

step 3 "venv 생성 (${VENV_DIR}, system-site-packages)"
if [[ -f "${VENV_DIR}/bin/python" ]]; then
    echo "venv-uv: venv 이미 존재 — 재사용"
else
    uv venv --python /usr/bin/python3.12 --system-site-packages "${VENV_DIR}"
fi

step 4 "의존성 설치 (uv sync --frozen — torch 포함, 최초 실행은 수 GB 다운로드)"
VIRTUAL_ENV="${VENV_DIR}" uv sync --frozen --active --project "${SCRIPT_DIR}"

PY="${VENV_DIR}/bin/python"

step 5 "post-install (tflite shim / oww feature 모델 / TFL3 검증)"
# tflite_runtime 호환 shim — openwakeword 가 tflite_runtime.interpreter 이름으로 import (LAB A4 (5) 동일)
"${PY}" - <<'EOF'
import os, ai_edge_litert as a
d = os.path.join(os.path.dirname(os.path.dirname(a.__file__)), 'tflite_runtime')
os.makedirs(d, exist_ok=True)
open(os.path.join(d, '__init__.py'), 'w').close()
open(os.path.join(d, 'interpreter.py'), 'w').write('from ai_edge_litert.interpreter import Interpreter  # noqa: F401\n')
EOF
OWW_DIR="$("${PY}" -c 'import os,openwakeword;print(os.path.join(os.path.dirname(openwakeword.__file__),"resources","models"))')"
mkdir -p "${OWW_DIR}"
cp "${REPO_ROOT}"/resources/oww_models/* "${OWW_DIR}"/
# TFL3 매직바이트 + 파일 0개 가드(LAB 명시 함정: 0개면 검사 자체가 공회전)
"${PY}" - "${OWW_DIR}" <<'EOF'
import os, sys
d = sys.argv[1]
files = [f for f in os.listdir(d) if f.endswith('.tflite')]
assert files, 'oww feature 모델 0개 — resources/oww_models/ 확인'
for f in files:
    assert open(os.path.join(d, f), 'rb').read(8)[4:8] == b'TFL3', 'corrupt tflite: ' + f
print('feature models TFL3 OK (%d)' % len(files))
EOF

step 6 "self-check (import 세트 + wakeword 실추론 게이트)"
# LAB A4 검증 블록과 동일 import 세트
"${PY}" - <<'EOF'
import numpy,torch,ultralytics,cv2,langchain,langchain_openai,openai
import pyaudio,sounddevice,scipy,openwakeword,ai_edge_litert
import tflite_runtime.interpreter,pymodbus,roboflow
assert numpy.__version__.startswith('1.'), numpy.__version__
print('deps OK', numpy.__version__)
EOF
# 진짜 게이트(LAB 동일): 의존성·shim·feature 모델·wakeword 모델을 실추론 1회로 한꺼번에 확증.
# ws 미구성(복구 전 단계)이면 skip — venv 자체는 완성.
WAKEWORD="$HOME/cobot_demo_ws/src/pick_and_place_voice/resource/hello_rokey_8332_32.tflite"
if [[ -f "${WAKEWORD}" ]]; then
    "${PY}" - "${WAKEWORD}" <<'EOF'
import sys
import numpy as np
from openwakeword.model import Model
m = Model(wakeword_models=[sys.argv[1]])
m.predict(np.zeros(1280, dtype=np.int16))
print('wakeword gate OK — Model(.tflite) load + predict')
EOF
else
    echo "venv-uv: [SKIP] wakeword gate — ${WAKEWORD} 없음(ws 미구성). venv 는 완성" >&2
fi

echo "venv-uv: success — source ${VENV_DIR}/bin/activate 후 LAB.md Part B 로"
```

- [ ] **Step 2: 정적 검증**

Run: `bash -n scripts/venv-demo/uv/setup.sh && shellcheck scripts/venv-demo/uv/setup.sh`
Expected: 출력 없이 exit 0. warning 이 나오면 해당 라인 수정 후 재실행 (`# shellcheck disable` 면제는 사유 주석 필수, 남발 금지).

- [ ] **Step 3: `--active` 플래그 메커니즘 스모크 (이 머신에서 가능한 유일한 동적 검증)**

setup.sh 의 핵심 조합(프로젝트 밖 venv + `VIRTUAL_ENV` + `--active` + `--frozen`)이 system-site 플래그를 보존하며 대상 venv 에 설치하는지 소형 프로젝트로 확인:

```bash
SMOKE=$(mktemp -d) && cd "$SMOKE"
cat > pyproject.toml <<'EOF'
[project]
name = "sync-active-smoke"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = ["python-dotenv"]
EOF
uv lock --python 3.12
uv venv --python 3.12 --system-site-packages "$SMOKE/target-venv"
VIRTUAL_ENV="$SMOKE/target-venv" uv sync --frozen --active --project "$SMOKE"
grep system-site "$SMOKE/target-venv/pyvenv.cfg"
"$SMOKE/target-venv/bin/python" -c "import dotenv; print('smoke OK')"
```

Expected: `include-system-site-packages = true` + `smoke OK`. 실패 시 setup.sh step 4 의 플래그 조합을 재검토하고 사용자 보고 (uv 동작 변경 가능성).
정리: `rm -rf "$SMOKE"`

- [ ] **Step 4: Commit (사용자 승인 후)**

```bash
git add scripts/venv-demo/uv/setup.sh
git commit -m "데모 venv 원커맨드 복구 스크립트 추가 (uv sync 기반 setup.sh)"
```

---

### Task 3: 문서 연결 (LAB.md 포인터 1줄 + COMPATIBILITY.md)

**Files:**
- Modify: `scripts/venv-demo/LAB.md` (A4-fast 도입 blockquote — 1줄 추가만)
- Modify: `docs/COMPATIBILITY.md` (`## 실측 vs 스크립트 의도` 섹션 직전에 신규 섹션 삽입)

**Interfaces:**
- Consumes: Task 1·2 의 파일 경로(`scripts/venv-demo/uv/setup.sh`, `uv.lock`).
- Produces: 없음 (문서만).

- [ ] **Step 1: LAB.md 포인터 추가**

`scripts/venv-demo/LAB.md` 의 A4-fast 도입 blockquote 에서, 아래 기존 텍스트를:

```
> 그래서 **`-r` 일괄 1콜 + 특수 3콜 + shim/모델 블록**으로 정리한다. 각 단계 의미는 위 A4 참조.
```

다음으로 교체(마지막 1줄 추가):

```
> 그래서 **`-r` 일괄 1콜 + 특수 3콜 + shim/모델 블록**으로 정리한다. 각 단계 의미는 위 A4 참조.
> 완전 원커맨드가 필요하면(복구/배포) → `bash ~/ros2_jazzy_test/scripts/venv-demo/uv/setup.sh` — lock 기반 동일 환경·순서 무관. 학습용이 아니라 재구성용.
```

- [ ] **Step 2: COMPATIBILITY.md 신규 섹션 추가**

`docs/COMPATIBILITY.md` 의 `## 실측 vs 스크립트 의도 — drift 패턴 (\`apt upgrade -y\` 부작용)` 헤딩 **바로 앞**에 삽입:

```markdown
## 데모 venv — uv 배포/복구 경로 (2026-07-20)

학생 배포/복구용 원커맨드 경로(`scripts/venv-demo/uv/setup.sh`)의 도구 핀. 스택 핀 자체는 위 Phase 4 절과 `scripts/venv-demo/requirements.txt` 의 검증본을 그대로 미러(원천 동일). 설계·실측 근거 = `docs/specs/2026-07-20-venv-uv-student-setup-design.md`.

| Layer | Version | Source citation | Notes |
|-------|---------|-----------------|-------|
| uv | 0.11.2 | `scripts/venv-demo/uv/setup.sh` (`UV_VERSION`, astral.sh 버전 핀 installer) | `dependency-metadata`(openwakeword·roboflow 의존 교체) + `override-dependencies`(numpy<2) + explicit index(torch cu128) 동작을 실측한 버전. 학생 머신은 `uv sync --frozen` 전용 |
| 스택 lock | `scripts/venv-demo/uv/uv.lock` | `uv lock` 산출물 (갱신: pyproject 수정 → `uv lock` → 커밋) | requirements.txt(LAB)와 수동 동기 — 한쪽 갱신 시 다른 쪽 확인 |

---
```

- [ ] **Step 3: 검증**

```bash
grep -c "uv/setup.sh" scripts/venv-demo/LAB.md      # 기대: 1
grep -c "데모 venv — uv 배포/복구 경로" docs/COMPATIBILITY.md  # 기대: 1
git diff --stat scripts/venv-demo/LAB.md             # 기대: 1 file changed, 1 insertion(+) — LAB 불변 원칙 확인
```

- [ ] **Step 4: Commit (사용자 승인 후)**

```bash
git add scripts/venv-demo/LAB.md docs/COMPATIBILITY.md
git commit -m "venv 실습 문서에 uv 복구 경로 안내 추가, 호환성 매트릭스에 uv 핀 기록"
```

---

### Task 4: 타깃(Ubuntu 24.04) 실측 — 배포 게이트 ([실측] 머신 전용 · 별도 세션)

**Files:** 없음 (검증만. 결과는 spec 의 게이트 항목에 기록)

이 레포 머신(22.04/py3.10)에서는 실행 불가. [실측] 머신에서 레포 pull 후:

- [ ] **Step 1: 전체 실행**

Run: `bash ~/ros2_jazzy_test/scripts/venv-demo/uv/setup.sh`
Expected: `[1/6]`…`[6/6]` 전부 통과, `deps OK 1.26.4`, (ws 구성 상태면) `wakeword gate OK`.

- [ ] **Step 2: 게이트 3건 개별 확인**

```bash
# ① system 3.12 venv 를 uv sync 가 재생성하지 않고 재사용했는지 (재실행 = 멱등 확인 겸)
readlink -f ~/cobot_demo_ws/.venv/bin/python   # 기대: /usr/bin/python3.12 계열 (uv-managed 경로 아님)
bash ~/ros2_jazzy_test/scripts/venv-demo/uv/setup.sh   # 재실행 — 기대: venv 재사용 메시지 + 빠른 완료
grep system-site ~/cobot_demo_ws/.venv/pyvenv.cfg      # 기대: include-system-site-packages = true

# ② torch cu128 실설치
~/cobot_demo_ws/.venv/bin/python -c "import torch; print(torch.__version__, torch.cuda.is_available())"
# 기대: 2.11.0+cu128 True

# ③ ROS 바인딩 (ROS 소스 후)
source /opt/ros/jazzy/setup.bash && ~/cobot_demo_ws/.venv/bin/python -c "import rclpy; print('rclpy OK')"
# 기대: rclpy OK
```

- [ ] **Step 3: 결과 기록**

3건 전부 통과 → spec(`docs/specs/2026-07-20-venv-uv-student-setup-design.md`)의 배포 게이트 절에 통과 일자 추가 후 커밋(사용자 승인). 1건이라도 실패 → **학생 배포 보류**, 실패 내용 그대로 사용자 보고 (임의 우회 금지).
