# tasks/lessons.md — AI 행동 교정 규칙

> 반복 실수가 발생하면 여기에 기록 → 다음 세션 SessionStart hook이 자동 노출.
> 작성 패턴:
> - **Symptom**: 어떤 잘못된 행동이 반복되었는가
> - **Why it happened**: 모델이 그 행동을 한 추정 원인
> - **Correction**: 다음부터 어떻게 행동해야 하는가
> - **Trigger**: 이 교정이 발동되어야 하는 상황 (키워드 / 작업 종류)

---

## L-001: Notion `insert_content` 큰 페이로드 → Cloudflare 차단

- **Symptom**: 한 번에 ~10KB+ 크기의 markdown 을 `mcp__claude_ai_Notion__notion-update-page` `insert_content` 로 보내면 Cloudflare 가 차단 응답 (HTML "Sorry, you have been blocked", Ray ID 동반).
- **Why it happened**: 페이로드 크기 + 일부 WAF 트리거 패턴 (shell 명령 라인 / `<script>` 유사 토큰 등) 의심.
- **Correction**: 5-7개 섹션으로 분할하여 `insert_content` 를 순차 호출 (각 청크 ~50줄 이하 권장). 첫 청크가 통과하면 나머지도 같은 호출 패턴으로 안전.
- **Trigger**: "노션에 보고서 만들어줘", "notion 페이지에 정리", "notion 페이지에 넣어줘", `mcp__claude_ai_Notion__notion-update-page` 의 `insert_content` 호출.

---

## L-002: Mermaid edge label 안의 `--` → 화살표 토큰으로 오인 → 구문 오류

- **Symptom**: 노션 / GitHub 의 mermaid 렌더러가 다음 같은 라인에서 "syntax error" 표시:
  ```
  SRC -- docker compose build --pull --> BUILD
  ```
  사용자 의도: `--` 사이의 문자열 ("docker compose build --pull") 이 edge label. 그러나 라벨 안의 `--pull` 의 `--` 가 mermaid parser 에게 화살표 시작 토큰으로 보임 → edge 정의가 깨짐.
- **Why it happened**: Mermaid 의 `A -- text --> B` 문법은 양쪽 `--` 를 edge 경계로 인식. 라벨 자체에 `--` 가 들어가면 parser 가 어디서 라벨이 끝나는지 헷갈림. CLI flag (`--pull`, `--force`, `--no-deps` 등) 이 흔한 trigger.
- **Correction**: **pipe 문법으로 작성**: `A -->|text with --| B`. pipe `|` 가 명시적 경계라 라벨 안에 `--` 가 자유롭게 들어감. 또는 라벨에서 `--` 를 단일 `-` / em-dash (`—`) 로 변경해 회피 (단 의미 손실 가능).
- **Trigger**: Mermaid flowchart 의 edge label 에 shell 명령 / CLI flag / 옵션 (`--pull`, `--force`, `--no-deps`, `--system-site-packages`) 을 넣을 때. 노션에 mermaid 다이어그램 작성 / GitHub README 의 flowchart 작성 시.

---

## 예상 후보 (발생 시 정식 항목으로 승격)

본 프로젝트가 Phase 2 마이그레이션 단계에서 실제 작업이 진행되면, 발견되는 반복 실수를 이 파일에 누적.
- distro 문자열을 하드코딩으로 다시 박는 경우 (Hard Rule #1 위반)
- `pip install` 을 numpy 재핀 단계 **앞**에 추가하는 경우 (ADR-002 위반)
- Docker 이미지를 무태그 또는 `latest` 로 두는 경우 (Hard Rule #6 위반)
- bash 스크립트 최상단에 `set -euo pipefail` 누락 (Hard Rule #5 위반)
