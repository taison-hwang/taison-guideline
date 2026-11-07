# myharness

herdr로 개발을 자율주행하는 기본 동작만 담은 하네스다. 사용자가 목표를 주면 세션들이 계획·배정·구현·검증·병합을 이어 가고, 사용자 결정이 필요할 때만 멈춘다. Codex와 Claude Code에서 함께 쓴다.

## 담은 것

| 스킬 | 내용 |
| --- | --- |
| `running-herdr-autopilot` | Commander·Orchestrator·워커 역할, 의존성·맥락 연관도 기반 배정, 서브에이전트 사용 범위 |
| `managing-session-context` | 작업 경계의 `/clear`, 작업 중 auto-compact, 소프트 신호, compact 후 복구 |
| `writing-project-docs` | 방향 문서, 개발 과정 기록, 작업 계획·상태판, 문서 분할·색인 |

그 밖에 세션 실행기와 보고 명령(`core/bin/`), 역할 주입·컨텍스트·보고 누락 방지 hook(`core/hooks/`), 프로젝트 템플릿(`templates/`)이 있다. 린트·테스트 자동화, TDD 절차, 언어별 설정은 담지 않는다. 프로젝트가 `AGENTS.md`의 검사 명령과 전용 스킬로 더한다.

컨텍스트 정책의 근거와 검증 결과는 [docs/context-policy.md](docs/context-policy.md), 규칙별 강제 수단과 전제, 독립 검증 시험은 [docs/rules-and-enforcement.md](docs/rules-and-enforcement.md)에 있다.

## 시작

필요한 것: `hc`(herdr), `jq`, `git`, `rsync`, `claude` 또는 `codex`.

```bash
bin/harness init ~/CodeJobs/private/새-프로젝트
```

1. `intent.md`와 `AGENTS.md`의 "프로젝트 규칙"을 채운다.
2. `.agents/harness.env`를 확인한다. `HERDR_AUTONOMOUS=1`은 권한 확인 없이 도는 모드다. 운영 자원이나 비밀에 닿는 프로젝트는 0으로 둔다.
3. 첫 실행은 herdr 패널에서 직접 한다. 새 폴더는 신뢰 확인 창이 뜨므로 사람이 한 번 승인해야 한다. 이후 같은 폴더에 뜨는 세션은 묻지 않는다.

   ```bash
   .agents/bin/herdr-session --here commander claude
   ```

4. Commander에게 목표를 말한다. Orchestrator가 없으면 Commander가 띄운다.

## 갱신

```bash
bin/harness sync <프로젝트>
```

스킬 3개, 실행기, hook, `AGENTS.md`의 표시 블록만 덮어쓴다. 프로젝트 전용 스킬, `harness.env`, `intent.md`, 문서는 그대로 둔다. 파일은 전역이 아니라 프로젝트 안에 설치되므로, 커밋 전에 `git diff`로 바뀐 내용을 확인한다.

## 구조

```
core/                 프로젝트에 복사되는 원본
  AGENTS.core.md      AGENTS.md 표시 블록에 들어가는 규칙과 스킬 표
  skills/             스킬 3개
  bin/herdr-session   세션 실행기, 세션별 모델 표의 원본
  bin/herdr-report    보고 명령
  hooks/              역할 주입·compact 복구, 소프트 신호, compact 직전 스냅샷, 보고 누락 방지
  config/             Claude·Codex hook 설정
templates/            init 때 한 번만 넣는 파일
bin/harness           init, sync
tests/smoke.sh        설치·hook·실행기의 기계적 확인
```

## 전역 지침과의 관계

전역 `operating-herdr-sessions`와 전역 컨텍스트 hook은 진행 중인 다른 프로젝트가 쓰고 있어 바꾸지 않았다. 이 하네스를 설치한 프로젝트에서는 다음과 같이 대체한다.

- 세션이 시작되거나 `/clear`될 때마다 hook이 역할과 읽을 파일 경로를 주입한다. `AGENTS.md`의 안내만으로는 부족했다(시험에서 워커가 전역 스킬을 읽고 옛 규칙으로 일했다).
- 실행기가 `HERDR_CTX_GUARD_OFF=1`로 전역 hook의 알림을 끈다. 그래서 세션은 반드시 실행기로 띄운다.

스킬 이름은 전역 스킬과 겹치지 않게 지었다. Claude Code는 같은 이름이면 개인 스킬을 프로젝트 스킬보다 우선한다.

## 테스트

```bash
tests/smoke.sh
```

전역과 실제 세션을 건드리지 않는다. 실제 세션 동작은 [docs/context-policy.md](docs/context-policy.md)의 "검증 결과"처럼 도구 버전이 바뀔 때 다시 확인한다.
