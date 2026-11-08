# myharness

herdr로 개발을 자율주행하는 기본 동작만 담은 하네스다. 사용자가 목표를 주면 세션들이 계획·배정·구현·검증·병합을 이어 가고, 사용자 결정이 필요할 때만 멈춘다. Codex와 Claude Code에서 함께 쓴다.

## 담은 것

| 스킬 | 내용 |
| --- | --- |
| `running-herdr-autopilot` | Commander·Orchestrator·워커 역할, 의존성·맥락 연관도 기반 배정, 서브에이전트 사용 범위 |
| `managing-session-context` | 작업 경계의 `/clear`, 작업 중 auto-compact, 소프트 신호, compact 후 복구 |
| `writing-project-docs` | 방향 문서, 개발 과정 기록, 작업 계획·상태판, 문서 분할·색인 |

그 밖에 세션 실행기·보고 명령·검사 실행기(`core/bin/`), 역할 주입·컨텍스트·보고 누락 방지·편집 직후 검사 hook(`core/hooks/`), 프로젝트 템플릿(`templates/`)이 있다. 검사를 돌리는 관문은 담지만 검사 명령 자체(린트 도구, 테스트 러너), TDD 절차, 언어별 설정은 담지 않는다. 프로젝트가 `harness.env`의 검사 명령과 전용 스킬로 더한다.

컨텍스트 정책의 근거와 검증 결과는 [docs/context-policy.md](docs/context-policy.md), 규칙별 강제 수단과 전제, 독립 검증 시험은 [docs/rules-and-enforcement.md](docs/rules-and-enforcement.md)에 있다.

## 시작

### 1. 필요한 도구 설치

필요한 것: `hc`(herdr-core), `jq`, `git`, `rsync`, `claude` 또는 `codex`.

`hc`는 herdr 앱과 따로 설치한다. herdr 앱은 hc(herdr-core) 위의 클라이언트 중 하나일 뿐이라, herdr 앱만 있으면 `hc` 명령이 없다. 실행기·보고 명령·스킬의 세션 띄우기, 라벨, 메시지가 모두 `hc`를 쓴다.

```bash
curl -fsSL https://releases.herdr.dev/core/install.sh | sh   # ~/.local/bin/hc 에 설치된다
hc --version                                                  # 예: hc 0.1.18. 안 나오면 ~/.local/bin 을 PATH에 넣는다
```

### 2. 프로젝트에 하네스 설치

새 프로젝트는 `init`, 이미 설치한 프로젝트는 `sync`로 실행기를 최신으로 맞춘다. 예전 실행기는 herdr 패널에서 `--here`를 거부한다.

```bash
bin/harness init <프로젝트 경로>    # 처음 설치
bin/harness sync <프로젝트 경로>    # 이미 설치한 프로젝트 갱신
```

설치한 뒤 다음을 채운다.

- `intent.md`와 `AGENTS.md`의 "프로젝트 규칙"
- `.agents/harness.env`: `HERDR_AUTONOMOUS=1`은 권한 확인 없이 도는 모드다. 운영 자원이나 비밀에 닿는 프로젝트는 0으로 둔다.
- `.agents/harness.env`의 역할별 에이전트·모델(아래)

#### 검사 명령

워커가 고친 코드는 두 관문에서 검사한다. 명령은 프로젝트가 `.agents/harness.env`에 정한다(`AGENTS.md`의 "검사 명령"과 맞춘다).

```bash
HERDR_CHECK_CMD="npm run lint && npm run typecheck && npm test"   # 전체 검사
HERDR_CHECK_FILE_CMD="npx eslint --no-warn-ignored {files}"        # 고친 파일만 빠르게. {files}에 목록이 들어간다
HERDR_CHECK_TIMEOUT=900                                            # 한 번의 시간 제한(초)
```

| 관문 | 언제 | 무엇을 | 실패하면 |
| --- | --- | --- | --- |
| 편집 직후 (`check-edit.sh` hook) | Claude가 `Edit`·`Write`·`MultiEdit`·`NotebookEdit`, Codex가 `apply_patch`로 파일을 고칠 때마다 | `HERDR_CHECK_FILE_CMD`로 고친 파일만 | 출력 끝부분을 에이전트에게 돌려줘 그 자리에서 고치게 한다. 편집은 되돌리지 않는다 |
| `[완료]` 보고 (`herdr-report`) | 워커가 `herdr-report "[완료] …"`를 실행할 때 | worktree면 커밋 안 된 변경이 없는지 확인하고, `HERDR_CHECK_CMD`로 전체 검사. 병합 뒤 메인 체크아웃에서 보내면 다른 세션의 변경이 섞일 수 있어 변경 확인은 건너뛰고 병합된 결과를 검사한다 | 보고를 보내지 않는다. 통과하면 보고 끝에 `검사 PASS <SHA>`를 붙인다 |

- Orchestrator는 `검사 PASS <SHA>`나 `검사 미설정`이 붙지 않은 `[완료]`를 받지 않는다. 워커가 쓴 설명이 아니라 이 기록으로 통과를 판단한다.
- 전체 검사 결과는 HEAD SHA에 묶여 기록된다. 워커가 먼저 `herdr-check`를 돌려 통과했으면 보고 때 다시 돌리지 않는다. 검사가 오래 걸리면 이렇게 나눠 돌린다.
- `HERDR_CHECK_CMD`가 비어 있으면 막지 않고 보고에 `검사 미설정`을 붙인다. `HERDR_CHECK_FILE_CMD`가 비어 있으면 편집 hook은 아무것도 하지 않는다.
- 테스트는 편집마다 돌지 않도록 `HERDR_CHECK_FILE_CMD`에 넣지 않는다.
- worktree에는 `node_modules` 같은 설치물이 없을 수 있다. 검사는 고친 파일이 있는 작업 트리에서 돌므로, 검사 명령이 거기서 돌 수 있게 준비하는 것은 프로젝트 몫이다.
- 직접 돌려 보기: `.agents/bin/herdr-check`(전체), `.agents/bin/herdr-check --files <파일>`(빠른 검사), `.agents/bin/herdr-check --status`(지금 HEAD의 기록).
- Codex의 편집 hook은 hook 신뢰가 필요하다. 자율 모드(`HERDR_AUTONOMOUS=1`)는 실행기가 신뢰 확인을 건너뛰고, 아니면 Codex에서 `/hooks`로 한 번 신뢰한다.

#### 역할별 에이전트·모델

Commander, Orchestrator, 워커, 검증자가 쓸 에이전트(codex | claude)와 모델·effort를 `.agents/harness.env`에 정한다. Commander와 Orchestrator는 세션을 띄울 때 도구를 적지 않고 이 값을 따른다. 정하지 않으면 띄우는 세션이 자기와 같은 에이전트를 고르기 쉽다.

```bash
HERDR_COMMANDER_TOOL=codex          # --here commander 에서 도구를 생략하면 쓴다
HERDR_ORCHESTRATOR_TOOL=claude
HERDR_ORCHESTRATOR_MODEL=opus       # 비우면 실행기 기본 표
HERDR_ORCHESTRATOR_EFFORT=high
HERDR_WORKER_TOOL=codex
HERDR_WORKER_MODEL=gpt-6.1-sol
HERDR_WORKER_EFFORT=high
HERDR_VERIFIER_TOOL=claude          # 독립 검증자(verifier-*). 작성자와 다른 도구를 권한다
HERDR_VERIFIER_MODEL=opus
HERDR_VERIFIER_EFFORT=high
```

| 값 | 정하는 순서 |
| --- | --- |
| 에이전트 | 실행기 인자(`codex`·`claude`) > `HERDR_<역할>_TOOL`. 둘 다 없으면 실행기가 거부한다 |
| 모델 | `--model` 인자 > `HERDR_<역할>_MODEL` > 기본 표 |
| effort | effort 인자 > `HERDR_<역할>_EFFORT` > 기본 표 |

- 역할은 `COMMANDER`, `ORCHESTRATOR`, `WORKER`, `VERIFIER`다. `verifier-<n>` 역할은 `VERIFIER` 설정을 쓰고, `HERDR_VERIFIER_TOOL`이 비어 있으면 `WORKER` 설정을 쓴다. 기본 표와 워커 수 상한은 검증자도 워커와 같다.
- 검증자는 작성자의 맥락에 묶이지 않게 워커와 다른 도구, 상위 모델과 high effort로 두기를 권한다. 비워 두면 Orchestrator가 작성자와 다른 도구를 인자로 적어 띄운다.
- `*_MODEL`·`*_EFFORT`는 실제 도구가 `*_TOOL`과 같을 때만 쓴다. 검증자를 작성자와 다른 도구로 띄우면 그 도구의 기본 표를 쓴다(codex 모델 이름이 claude에 넘어가지 않게).
- 기본 표: codex는 Commander·Orchestrator `gpt-6.1-terra`/medium, 워커 `gpt-6.1-sol`/high. claude는 Commander `sonnet`/medium, Orchestrator `opus`/high, 워커 `opus`/medium.
- 이미 떠 있는 세션에는 적용되지 않는다. 바꾼 뒤 새로 띄우는 세션부터 쓴다.
- 어떤 명령이 나가는지는 `.agents/bin/herdr-session --dry-run worker-1`처럼 확인한다.

### 3. herdr 패널에서 Commander 띄우기

herdr 화면에서 패널을 하나 열고, 프로젝트 폴더로 가서 실행한다.

```bash
cd <프로젝트 경로>
.agents/bin/herdr-session --here commander          # HERDR_COMMANDER_TOOL을 정해 둔 경우
.agents/bin/herdr-session --here commander codex    # 직접 고를 때(claude도 된다)
```

실행하면 다음이 일어난다.

1. herdr 패널은 hc 터미널이 아니므로 실행기가 `hc run --bg`로 hc 터미널을 새로 열어 `role=commander`, `project=<프로젝트 폴더 이름>` 라벨을 붙이고, 이 패널을 `hc attach`로 거기에 붙인다. 이미 hc 터미널 안에서 실행했다면 새로 열지 않고 지금 터미널에 라벨을 붙인다.
2. 그 안에서 codex(또는 claude)가 프로젝트 폴더를 작업 위치로 해서 뜬다.
3. 새 폴더에서 처음 띄우면 폴더 신뢰 확인 창이 뜬다. codex는 `1. Trust and continue`, claude는 `Yes, I trust this folder`를 골라 한 번 승인한다. 이후 같은 폴더에 뜨는 세션은 묻지 않는다. codex는 이보다 먼저 업데이트 안내를 띄울 수 있다.
4. 이 패널이 보기 패널의 기준이 되고, 패널 이름이 `commander`로 바뀐다.

### 4. 목표 말하기

Commander에게 목표를 말한다. Orchestrator가 없으면 Commander가 띄우고, 워커는 Orchestrator가 띄운다. 둘 다 실행기로 띄우므로 사용자가 직접 띄울 필요는 없다.

### 보기 패널

`HERDR_VIEW_PANES=1`(기본)이면 Orchestrator·워커·검증자가 뜰 때마다 실행기가 Commander 패널이 있는 탭을 나눠 그 세션을 보여 준다.

```
┌──────────────┬───────────────────┐
│              │ hc:orchestrator   │
│  commander   ├───────────────────┤
│              │ hc:worker-1       │
│              ├───────────────────┤
│              │ hc:worker-2       │
└──────────────┴───────────────────┘
```

- 첫 세션은 Commander 패널 오른쪽에, 다음부터는 보기 패널 중 가장 높은 것을 아래로 나눈다. 패널 이름은 `hc:<role>`이다.
- 패널은 `hc attach <주소>`로 붙어 세션 크기를 패널에 맞춘다. 보기 전용(`--observe`)은 크기를 바꾸지 않아 화면이 겹쳐 깨지므로 쓰지 않는다. 패널을 클릭해 포커스를 주면 그 세션에 직접 입력할 수 있다. 떨어지려면 `ctrl+\`(패널도 닫힌다).
- 세션이 끝나면 패널도 닫힌다. 같은 역할의 세션을 다시 쓰면(`/clear` 재사용) 패널을 새로 만들지 않는다.
- 보기 패널을 닫아도 세션은 계속 돈다. 다시 보려면 아무 패널에서 `hc attach <주소>`를 실행한다. 같은 세션에 두 곳이 붙으면 크기가 마지막에 바꾼 쪽에 맞춰져 다른 쪽 화면이 깨질 수 있다.
- 기준은 `--here`를 실행한 herdr 패널이다. 그 패널을 닫았거나 herdr 밖에서 띄웠으면 보기 패널 없이 백그라운드로만 뜬다.
- 화면이 작으면 `HERDR_MAX_WORKERS`를 줄이거나 `HERDR_VIEW_PANES=0`으로 끈다.

### 떠나기, 다시 붙기, 끝내기

Commander는 herdr 패널이 아니라 hc 터미널에서 돈다. 그래서 패널을 닫거나 `ctrl+\`로 떨어져도 세션은 계속 돈다.

```bash
hc ls --label "project=<프로젝트 폴더 이름>"                       # 이 프로젝트의 세션 목록. 맨 앞이 주소(예: t3)
hc ls --label "project=<프로젝트 폴더 이름>" --label role=commander  # Commander만
hc attach t3                                                       # 다시 붙기. ctrl+\ 로 떨어진다
hc kill t3                                                         # 세션 끝내기
```

## 갱신

```bash
bin/harness sync <프로젝트>
```

스킬 3개, 실행기, hook, `AGENTS.md`의 표시 블록만 덮어쓴다. 프로젝트 전용 스킬, `harness.env`, `intent.md`, 문서는 그대로 둔다. 파일은 전역이 아니라 프로젝트 안에 설치되므로, 커밋 전에 `git diff`로 바뀐 내용을 확인한다.

## 문제 해결

| 증상 | 원인과 조치 |
| --- | --- |
| `--here 는 herdr 터미널 안에서만 쓴다` | 예전 실행기다. herdr 패널은 hc 터미널이 아니라서 거부했다. `bin/harness sync <프로젝트 경로>`로 실행기를 갱신한다 |
| `hc(herdr-core)가 없다` | `hc`가 설치되지 않았거나 PATH에 없다. 위 설치 명령을 실행하고 `hc --version`으로 확인한다 |
| `command not found: hc` | 위와 같다. 설치 위치 `~/.local/bin`을 PATH에 넣는다 |
| `--here`로 띄웠는데 화면이 멈춘 채 아무것도 안 나온다 | `--bg` 없는 `hc run`으로 띄우던 이전 실행기다(끝날 때까지 기다렸다가 출력만 보여 준다). `bin/harness sync`로 갱신한 뒤 다시 띄운다. 이미 뜬 세션은 `hc attach <주소>`로 붙거나 `hc kill <주소>`로 끝낸다 |
| `커밋 안 된 변경이 있어 [완료]를 보내지 않았다` | 워커가 커밋하지 않았거나 작업 트리 밖에서 보고했다. 작업한 worktree에서 커밋한 뒤 다시 보낸다 |
| `검사가 실패해 [완료]를 보내지 않았다` | `HERDR_CHECK_CMD`가 실패했다. 전체 출력은 `~/.claude/herdr/handoff/<프로젝트>/.<role>.check.log`에 있다 |
| 편집 hook이 돌지 않는다 | `HERDR_CHECK_FILE_CMD`가 비었거나, 프로젝트의 `.claude/settings.json`·`.codex/hooks.json`에 hook이 없다. `sync`는 이 두 파일을 덮어쓰지 않으므로 `core/config/`의 내용을 직접 합친다 |
| 보기 패널이 생기지 않는다 | Commander를 `--here`로 herdr 패널에서 띄워야 기준 패널이 생긴다. 이전 실행기로 띄운 Commander는 기준이 없으니 `bin/harness sync` 뒤 다시 띄운다. 그 패널을 닫았어도 생기지 않는다. `HERDR_VIEW_PANES=1`인지 확인한다 |
| 보기 패널의 화면이 겹치거나 줄이 엉켜 나온다 | 보기 전용(`--observe`)으로 붙던 이전 실행기다. hc 세션은 200x120으로 그리는데 패널이 작아 깨진다. `bin/harness sync` 뒤 그 패널에서 `ctrl+\`로 떨어지고 `hc attach <주소>`로 다시 붙는다 |
| `Transcript saving is off — inherited CLAUDE_CODE_CHILD_SESSION marker` | hc 서버를 Claude Code 안에서 띄워 그 세션의 표지가 물려졌다. 실행기가 띄울 때 지우므로 `bin/harness sync` 뒤 새로 띄운 세션에는 없다. 이미 뜬 세션은 기록이 저장되지 않으니 작업 경계에서 다시 띄운다 |
| 패널을 닫았더니 Commander가 사라진 것 같다 | 세션은 hc 터미널에 남아 있다. `hc ls --label "project=<프로젝트 폴더 이름>"`로 찾아 `hc attach`로 붙는다 |
| `도구를 정하지 못했다` | 도구 인자가 없고 `.agents/harness.env`의 `HERDR_<역할>_TOOL`도 비어 있다. 값을 채우거나 인자로 `codex`·`claude`를 준다. 예전 `harness.env`에는 이 줄이 없으니 위 예시를 더한다 |
| codex가 띄운 명령이 hc 밖에서 돈다 | 실행기가 codex에 `--no-daemon`을 붙인다. 예전 실행기면 `bin/harness sync`로 갱신한다 |

## 구조

```
core/                 프로젝트에 복사되는 원본
  AGENTS.core.md      AGENTS.md 표시 블록에 들어가는 규칙과 스킬 표
  skills/             스킬 3개
  bin/herdr-session   세션 실행기, 세션별 모델 표의 원본
  bin/herdr-report    보고 명령
  bin/herdr-view      보기 패널(herdr 탭을 나눠 세션에 보기 전용으로 붙인다)
  bin/herdr-check     검사 실행기(전체 검사·빠른 파일 검사, HEAD별 결과 기록)
  hooks/              역할 주입·compact 복구, 소프트 신호, compact 직전 스냅샷, 보고 누락 방지, 편집 직후 검사
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

전역과 실제 세션을 건드리지 않는다. Linux(GNU)와 macOS(BSD) 도구 모두에서 돈다. `hc`는 가짜로 대신하므로 설치하지 않아도 된다. 실제 세션 동작은 [docs/context-policy.md](docs/context-policy.md)의 "검증 결과"처럼 도구 버전이 바뀔 때 다시 확인한다.
