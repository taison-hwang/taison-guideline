# 에이전트 지침 — {{PROJECT}} (Codex·Claude 공통)

Codex는 이 파일을 직접 읽고, Claude Code는 `CLAUDE.md`의 `@AGENTS.md`로 같은 내용을 읽는다. 표시 사이의 내용은 `harness sync`가 덮어쓰므로 고치지 않는다.

<!-- harness:begin -->
<!-- harness:end -->

## 프로젝트 규칙

- 주업무: <이 프로젝트에서 가장 먼저 동작해야 하는 것. 상세는 docs/service-plan/index.md>
- 검사 명령: <전체 검사 명령과 영역별 명령. 타입 검사가 있으면 넣는다. 예: make check. `.agents/harness.env`의 `HERDR_CHECK_CMD`·`HERDR_CHECK_FILE_CMD`와 맞춘다>
- 실제 동작 확인: <앱을 띄워 사용자 경로를 실행하는 방법과 증거. 없으면 "없음">
- 코드 위치 찾기: <심볼 인덱스가 있으면 도구 이름>
