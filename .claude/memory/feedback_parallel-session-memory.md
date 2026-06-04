---
name: feedback-parallel-session-memory
description: 병렬 세션 운영 중 공유 메모리(handoff / MEMORY.md index) 동시 쓰기 회피 규칙. standalone 파일 + merge 편집 선호.
metadata:
  type: feedback
---

# 병렬 세션 운영 시 공유 메모리 처리

여러 Claude Code 세션을 **동시에** 돌릴 때, 공유 파일에 대한 전체 덮어쓰기를 피하고 충돌을 최소화한다.

**Why**: 메모리 파일(`MEMORY.md`, `session-handoff-LATEST.md`)은 세션 시작 시 1회 로드되고 라이브 동기화가 없다. 두 세션이 같은 파일을 통째로 쓰면 lock 부재로 last-writer-wins → 한쪽 작업 소실. 사용자가 2026-05-28 병렬 작업 중 이를 명시적으로 우려했고, "신규 파일로 저장, 인덱스 안 건드림" → 이후 "merge 업데이트(index 제외)" 두 번 같은 방향으로 결정.

**How to apply**:
- 실질 산출(결정/분석)은 **신규 standalone 파일**로 저장 (예: `project_*.md`, `feedback_*.md`). 인덱스 충돌 구간을 피함.
- `MEMORY.md` (인덱스)는 병렬 세션 중 **수정하지 않음**. standalone 파일이 사실을 보유하고, 인덱스 등재는 단일 세션 정리 시점으로 미룸.
- `session-handoff-LATEST.md` 갱신이 필요하면 **전체 재작성 대신 merge 편집** — write 직전 현재 디스크 상태를 Read 하고, 기존 항목 보존한 채 이번 세션 delta 만 surgical 추가.
- 옆 세션이 이번 세션 산출을 알아야 하면, 그 세션이 standalone 파일을 직접 Read 하게 안내 (자동 전파 안 됨).
- 가능하면 **한 세션만 메모리 owner** 로 지정하고 나머지는 read-only.

관련: [[phase4-container-architecture]] (이 규칙 하에 standalone 으로 저장된 첫 사례).
