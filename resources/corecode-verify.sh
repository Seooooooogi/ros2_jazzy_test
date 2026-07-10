#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# resources/corecode-verify.sh — 사용자가 ~/corecode 에 튜토리얼을 배치했는지 확인(install.sh step 10).
#
# corecode 튜토리얼(Calibration / DRL / OD / VoiceProcessing)은 이 레포가 더는 싣지 않는다 —
# 별도 배포본(corecode.zip)을 사용자가 받아 홈에 풀어 ${HOME}/corecode 를 만든다. 이 단계는 그
# 배치를 확인만 한다(obtain_cobot2 와 동일한 "외부 제공 콘텐츠 검증" 패턴). 배치돼 있으면 통과,
# 없으면 받는 방법을 안내하고 중단(exit 1) — 사용자가 배치 후 재실행하면 멱등하게 통과.
# 순수 설치 본문 — 단계 상태 관리(run_step)는 호출자(install.sh) 담당.
set -euo pipefail

DEST="${HOME}/corecode"

# 배치 확인: ~/corecode 아래에 노트북(.ipynb)이 하나라도 있으면 배치된 것으로 본다(튜토리얼 = 노트북).
# maxdepth 미지정 — 노트북은 ~/corecode/<Tutorial>/[sub]/x.ipynb 로 최대 3단(OD_Tutorial/YOLO/*.ipynb).
# -print -quit 로 첫 매치에서 즉시 종료하므로 트리 크기와 무관하게 빠름.
if [[ -d "${DEST}" ]] && find "${DEST}" -name '*.ipynb' -print -quit | grep -q .; then
    echo "corecode: tutorials found at ${DEST}"
    exit 0
fi

echo "corecode: tutorials not found at ${DEST}" >&2
echo "          This repo no longer ships corecode — obtain corecode.zip separately," >&2
echo "          extract it into your home so it becomes ${DEST}, then re-run:" >&2
echo "            unzip corecode.zip -d \"${HOME}\"    # yields ${DEST}" >&2
exit 1
