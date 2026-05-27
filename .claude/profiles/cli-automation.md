# Profile marker: CLI-automation

이 파일의 **존재** 자체가 활성화 신호. 내용은 무관.

활성화되는 검증 (글로벌 `~/.claude/agents/code-reviewer.md` + `orchestrator.md` 참조):
- destructive ops gated (`--force` / `--confirm` 강제)
- idempotent operations (재실행 결과 동일)
- help text coverage (모든 flag/command에 help)
- exit code 규율 (0/1/2)
- stdout vs stderr 분리
- `--dry-run` preview mode 강제 (destructive 명령)

본 프로젝트는 bash installer 도메인이므로 위 규율을 모두 적용.
