# 컨텍스트 정책의 근거

`managing-session-context` 스킬이 왜 그렇게 정해졌는지 기록한다. 규칙 자체는 스킬에 있다. 정책을 바꾸거나 새 모델로 다시 평가할 때 읽는다.

## 결론

작업 경계에서 리셋하고, 작업 중에는 compact에 맡기고, 상태는 항상 디스크에 둔다. 출발점은 자료 「Claude Code 컨텍스트 관리 전략 비교: 30% 핸드오프 + /clear vs Auto-compact」(2026-11-06)이다.

| 근거 | 내용 |
| --- | --- |
| 리셋 필요성은 모델에 따라 다르다 | 리셋이 필수였던 원인은 일부 모델의 context anxiety였다. 리셋을 모델의 약점이 아니라 작업 구조의 경계에 두면 모델이 바뀌어도 유효하다 |
| 고정 비율은 의미가 일정하지 않다 | 30%는 200K 창에서 60K, 1M 창에서 300K다. 그래서 토큰 수로 잰다 |
| 살아남는 것은 디스크뿐이다 | 리셋이든 compact든 대화는 사라지거나 요약된다. 작업 도중 쓴 핸드오프도 모델이 쓴 요약이다 |
| 신호가 마무리를 재촉하면 안 된다 | 공식 지침은 한도가 가까우면 모델이 일을 마무리하려 할 수 있으니 자동 compact를 미리 알리라고 한다. 그래서 워커 소프트 신호는 계속하라고 안내한다(2026-11-07 변경). 300k에 이른 세션이 없어 효과는 재지 못했다 |

## 자료와 다르게 정한 것

| 자료의 추천 | 이 하네스 | 이유 |
| --- | --- | --- |
| 기능 하나당 새 프로세스(`claude -p` 외부 루프) | 대화형 herdr 세션을 유지하고 연관 없는 작업으로 넘어갈 때 리셋 | 관련 작업을 맥락을 가진 세션에 주려면 세션이 남아 있어야 한다. `hc` 매뉴얼도 에이전트를 대화형으로 돌리도록 안내한다 |
| 작업 하나마다 리셋 | 다음 작업이 무관할 때만 리셋 | 같은 묶음이나 연관 작업에서 리셋하면 곧바로 다시 필요한 맥락을 버린다 |
| CLAUDE.md의 `# Compact instructions` 섹션 | `PreCompact` hook의 출력으로 요약을 지시 | 그 섹션은 공식 문서에서 확인하지 못했다. hook 출력이 요약 지시가 된다는 것은 문서에 있다 |
| 외부 루프의 watchdog | 자동 감시 없음. Orchestrator가 깨어날 때 확인 | 아래 "남은 한계" |

## 값

| 값 | 기본 | 이유 |
| --- | --- | --- |
| 소프트 신호 | 300k 토큰 | 자료의 30%를 1M 창 기준 토큰으로 옮겼다 |
| auto-compact | 400k 토큰 | 자료의 권장(1M 모델 300~400K)의 위쪽. 소프트 신호 뒤 Orchestrator·Commander가 상태를 정리할 여유를 둔다. 기본값 약 967K까지 두지 않는다 |
| 연관 작업 연장 | 맥락 크기와 무관하게 이어 간다 | 사용자 결정(2026-11-07): `/clear`는 다른 작업으로 넘어갈 때, compact는 진행 중인 세션을 이어 갈 때 쓴다. 전역 `operating-herdr-sessions` 절차는 임계 도달을 정리 조건으로 두어 이 점이 다르다. jobtailor 실측의 손익 분기(200k에서 약 40요청, 300k에서 약 19요청)와 1시간 넘게 쉰 세션의 첫 요청 cache write(중앙값이 맥락의 약 80%)로 보면, 큰 맥락에서 긴 작업을 이어 가거나 쉰 세션을 다시 쓰는 경우 정리하는 편이 쌌을 수 있다. 품질과 비용 효과는 재지 못했다 |

jobtailor 실측은 그 저장소의 `docs/optimization/07-clear-policy.md`에 있다(2026-11-04). 품질 저하는 재지 않았고 비용만 쟀다. 세션 간 메시지가 배정 1건당 약 1.35건이었고 받을 때마다 맥락 전체를 다시 읽었다는 수치가, 의존성 우선 배정과 답장 생략 규칙의 근거다.

## 검증 결과

Claude Code 2.1.318, Codex CLI 0.166.0, herdr 0.9.5에서 실제 세션으로 확인했다(2026-11-06).

| 항목 | Claude | Codex |
| --- | --- | --- |
| compact 임계 설정 | `CLAUDE_CODE_AUTO_COMPACT_WINDOW` 전달 확인, 공식 문서 확인. 임계까지 채워 자동 compact를 일으키지는 않음 | `-c model_auto_compact_token_limit` 낮춰서 자동 compact 발생 확인 |
| `PreCompact` 스냅샷 | 확인 | 확인 |
| `SessionStart(compact)` 복구 주입 | 수동 `/compact`로 확인 | 수동·자동 호출 확인, 주입은 수동 `/compact`로 확인 |
| `/clear`로 맥락 비움, 뒤이어 역할 주입 | 확인 | 확인 |
| 소프트 신호 알림 | 확인 | 연결하지 않음. 상태줄로 판단 |

전체 흐름 시험: 임시 프로젝트에서 Commander → Orchestrator → Claude 워커 + Codex 워커로 작업 3개를 사람 개입 없이 끝냈다. 의존 작업 A→B는 한 워커에, 독립 작업 C는 다른 워커에 배정했고, 앞선 시험에서 calc 후속 작업은 calc 맥락을 가진 워커로 갔다. 모델은 시험용으로 Sonnet·Haiku·Luna를 썼고 작업은 파일 한두 개 규모다.

시험에서 고친 결함:

- 워커가 `[완료]`를 화면에만 쓰고 보내지 않아 전체가 조용히 멈췄다 → `herdr-report`와 `Stop` hook
- 전역 지침을 따라 `operating-herdr-sessions`를 읽고 옛 규칙으로 일했다 → `SessionStart` hook으로 역할과 경로 주입
- 워커가 `ctx`를 알 수 없어 "측정 안 함"으로 보고했다 → hook이 기록하고 `herdr-report`가 자동으로 붙임

실측으로 알게 된 것:

- Codex 0.166은 `SessionStart(compact)` hook을 호출하지만 평문 출력을 컨텍스트에 넣지 않았다. `hookSpecificOutput.additionalContext` JSON은 들어간다. 문서에는 평문도 된다고 되어 있다.
- 작업 중에는 Codex가 `/compact`를 거부한다(`disabled while a task is in progress`). `/clear`에도 같은 일이 있다고 보고 실행 뒤 확인한다.
- 새 폴더는 두 도구 모두 첫 실행 때 신뢰 확인 창에서 멈춘다. `--yolo`·`--dangerously-skip-permissions`로도 건너뛰어지지 않는다.

## 남은 한계

- 실제 규모: 300k 소프트 신호와 400k compact에 실제로 이른 세션은 없다. 신호는 임계를 낮춰, Claude compact는 수동으로 확인했다. 큰 프로젝트의 장시간 주행은 아직 해 보지 않았다.
- 실제 세션으로 확인하지 못한 경로: `[미보고]` 전달(스모크 테스트만), 예외 정리, Orchestrator 자신의 정리, 워커 수 상한으로 세션을 정리하고 재사용하는 경우. Codex의 `Stop` 차단은 동작한 흔적만 있고 단정하지 못했다.
- 멈춤 감시: 막힘·오류·종료는 `hc`가 부모에게 알리고, 보고 없이 끝난 턴은 `Stop` hook이 잡는다. `working` 상태로 멈춘 세션만 남는다. Orchestrator가 다른 일로 깨어날 때만 찾아내므로, 모든 세션이 동시에 멈추면 사용자가 확인하기 전까지 알 수 없다.
- 품질 비교: 이 정책과 "30%에서 정리" 정책의 완료율·재작업·토큰 비용을 비교하지 않았다. 자료가 제안한 대로 같은 작업 세트를 두 방식으로 돌려 재야 한다. 모델이 바뀔 때마다 다시 잰다.
- 200K 창 모델: 소프트 신호와 compact 기본값은 1M 창 기준이다. 200K 창 모델을 쓰면 `.agents/harness.env`에서 낮춰야 한다.

## 출처

- [Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices): 한도 근처의 조기 마무리와 compact 안내
- [Context window](https://code.claude.com/docs/en/context-window.md): compact 후 남는 것
- [Model configuration](https://code.claude.com/docs/en/model-config.md#set-the-auto-compact-window): auto-compact 창, 기본 약 967K
- [Hooks](https://code.claude.com/docs/en/hooks.md): `SessionStart`의 `compact` matcher, `PreCompact`
- [Skills](https://code.claude.com/docs/en/skills.md): 같은 이름이면 개인 스킬이 프로젝트 스킬보다 우선
- [Codex hooks](https://learn.chatgpt.com/docs/hooks), [Codex config reference](https://learn.chatgpt.com/docs/config-file/config-reference)
