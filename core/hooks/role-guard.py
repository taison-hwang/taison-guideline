#!/usr/bin/env python3
"""Orchestrator가 워커의 일(코드·문서 편집, 검사·테스트·빌드 실행, 병합·이력 변경)을 하지 못하게 막는다.

PreToolUse hook(Claude: Edit·Write·MultiEdit·NotebookEdit·Bash, Codex: apply_patch·셸). HERDR_ROLE=orchestrator일 때만 본다.
막으면 끝 코드 2와 stderr로 이유와 맡길 곳을 돌려준다. 읽지 못하는 명령은 막지 않는다.
herdr-usage --audit가 같은 규칙(classify_*)으로 지난 대화 기록을 센다. 규칙은 이 파일 한 곳에만 둔다.

Orchestrator가 직접 써도 되는 곳(references/orchestrator.md 첫 문단):
  <저장소>/docs/status/ (작업 계획·상태판·결정 기록, 그 커밋), docs/progress/ (개발 과정 기록),
  ~/.claude/herdr/ (세션 장부·배정 원문), ~/.claude/projects/*/memory/ (세션 자신의 메모리), /tmp, /dev
HERDR_ROLE_GUARD=0(harness.env)이면 막지 않는다.
"""
import json
import os
import re
import shlex
import subprocess
import sys

SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "|&", ";;", "{", "}", "!"}
REDIRECTS = {">", ">>", "&>", ">|", "&>>", ">&"}
WRAPPERS = {"timeout", "env", "nohup", "nice", "time", "command", "exec", "sudo", "stdbuf", "ionice"}
EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
CODE_EXT = re.compile(r"\.(go|ts|tsx|js|jsx|mjs|cjs|py|rs|java|kt|kts|swift|dart|rb|php|c|cc|cpp|h|hpp|cs|sql|css|scss|vue|svelte)$")

# 검사·테스트·빌드: (명령 이름, 그 뒤 첫 인자가 이 중 하나일 때만. None이면 언제나)
RUNNERS = {
    "go": {"test", "build", "vet", "run", "generate", "install"},
    "npm": {"test", "t", "run", "run-script", "ci", "install", "i", "exec", "x"},
    "pnpm": {"test", "t", "run", "install", "i", "exec", "dlx", "build", "lint"},
    "yarn": {"test", "run", "install", "build", "lint", "exec", "dlx"},
    "bun": {"test", "run", "install", "x"},
    "cargo": {"test", "build", "check", "clippy", "run", "nextest"},
    "flutter": {"test", "analyze", "build", "run"},
    "dart": {"test", "analyze", "run"},
    "deno": {"test", "task", "run", "lint", "check"},
    "docker": {"build", "compose", "run"},
    "uv": {"run"},
    "poetry": {"run"},
    "npx": None, "pnpx": None, "bunx": None, "make": None, "pytest": None, "tox": None, "nox": None,
    "vitest": None, "jest": None, "playwright": None, "tsc": None, "eslint": None, "prettier": None,
    "golangci-lint": None, "ruff": None, "mypy": None, "gradle": None, "gradlew": None, "mvn": None,
}
GIT_WRITE = {"merge", "rebase", "cherry-pick", "revert", "am", "apply", "reset", "push", "pull", "checkout",
             "switch", "restore", "stash", "worktree", "rm", "mv", "clean", "branch", "tag"}
GIT_READ_SUB = {"worktree": {"list"}, "branch": {"--list", "-l", "-a", "-r", "--show-current", "-v", "-vv", "--contains", "--merged"},
                "stash": {"list", "show"}, "tag": {"-l", "--list"}}


def home():
    return os.path.expanduser("~")


def repo_root(cwd):
    d = os.path.abspath(cwd) if cwd else None
    while d and d != "/":
        if os.path.exists(os.path.join(d, ".git")):
            return d
        d = os.path.dirname(d)
    return None


STATE_DOCS = re.compile(r"/docs/(status|progress)(/|$)")


def allowed_path(path, cwd=None):
    """Orchestrator가 써도 되는 경로인가. 정할 수 없으면(변수가 남음) None."""
    if not path or "$" in path or "`" in path:
        return None
    p = os.path.expanduser(path)
    if not os.path.isabs(p):
        if re.match(r"^(\./)?docs/(status|progress)(/|$)", p):
            return True
        if not cwd:
            return None
        p = os.path.join(cwd, p)
    p = os.path.normpath(p)
    root = repo_root(cwd)
    if root and (p + "/").startswith(root + "/"):  # 저장소 안은 그 위치(/tmp 등)와 상관없이 상태 문서만
        return bool(STATE_DOCS.search(p[len(root):])) and "/.worktrees/" not in p
    tmp = os.environ.get("TMPDIR", "/tmp").rstrip("/") or "/tmp"
    if p.startswith(("/dev/", "/proc/", "/tmp/", tmp + "/")) or p in ("/dev/null",):
        return True
    if p.startswith(os.path.join(home(), ".claude", "herdr") + "/"):
        return True
    if re.match(re.escape(os.path.join(home(), ".claude", "projects")) + r"/[^/]+/memory(/|$)", p):
        return True
    return bool(STATE_DOCS.search(p)) and "/.worktrees/" not in p and "/worktrees/" not in p


def strip_heredocs(cmd):
    """히어독 본문을 떼어 낸다. (본문 없는 명령, 본문 목록)"""
    bodies = []
    out, lines, i = [], cmd.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        tags = re.findall(r"<<-?\s*['\"]?([A-Za-z_]\w*)['\"]?", line)
        i += 1
        for tag in tags:
            body = []
            while i < len(lines) and lines[i].strip() != tag:
                body.append(lines[i])
                i += 1
            i += 1
            bodies.append("\n".join(body))
    return "\n".join(out), bodies


def tokens_of(cmd):
    cmd = cmd.replace("\\\n", " ")
    cmd = re.sub(r"\n", " ; ", cmd)
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=";&|()<>{}!")
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)


def segments(tokens):
    seg = []
    for t in tokens:
        if t in SEPARATORS or (set(t) <= set(";&|(){}!") and t):
            if seg:
                yield seg
            seg = []
        else:
            seg.append(t)
    if seg:
        yield seg


def expand(word, env):
    def sub(m):
        name = m.group(1) or m.group(2)
        return env.get(name, m.group(0))
    w = re.sub(r"\$\{(\w+)\}|\$(\w+)", sub, word)
    return w


def py_writes(text):
    """파이썬 코드(히어독·-c)에서 문자열로 적힌 쓰기 대상을 찾는다."""
    found = re.findall(r"open\(\s*['\"]([^'\"]+)['\"]\s*,\s*['\"][wax]", text)
    found += re.findall(r"Path\(\s*['\"]([^'\"]+)['\"]\s*\)\.write_(?:text|bytes)", text)
    return found


def classify_command(cmd, cwd=None, staged=None, depth=0, changed=None):
    """셸 명령 → [(종류, 내용)]. 종류: edit(범위 밖 쓰기), check(검사·테스트·빌드), git(병합·이력 변경).
    staged·changed: git commit 때 스테이징된 파일과 바뀐 모든 파일(hook만 안다). None이면(지난 기록) 같은 명령의
    git add에 적힌 경로만 보고, 전체를 넣는 커밋(add -A, commit -a)은 무엇이 들어갔는지 모르므로 세지 않는다."""
    found = []
    body_cmd, bodies = strip_heredocs(cmd)
    try:
        toks = tokens_of(body_cmd)
    except ValueError:
        return found
    env = {"HOME": home()}
    for t in toks:
        m = re.match(r"^([A-Za-z_]\w*)=(.*)$", t)
        if m:
            env[m.group(1)] = expand(m.group(2), env)
    added, py_checked = [], False
    for seg in segments(toks):
        # 쓰기 리다이렉트
        for i, t in enumerate(seg):
            if t in REDIRECTS and i + 1 < len(seg):
                target = expand(seg[i + 1], env)
                if not re.fullmatch(r"&?\d", target) and allowed_path(target, cwd) is False:
                    found.append(("edit", f"> {seg[i + 1]}"))
        words = [w for i, w in enumerate(seg) if w not in REDIRECTS and (i == 0 or seg[i - 1] not in REDIRECTS)
                 and not (re.fullmatch(r"\d", w) and i + 1 < len(seg) and seg[i + 1] in REDIRECTS)]
        while words and re.match(r"^[A-Za-z_]\w*=", words[0]):
            words.pop(0)
        while words and os.path.basename(words[0]) in WRAPPERS:
            name = os.path.basename(words.pop(0))
            while words and (words[0].startswith("-") or re.match(r"^[A-Za-z_]\w*=", words[0])
                             or (name == "timeout" and re.fullmatch(r"[\d.]+[smhd]?", words[0]))):
                words.pop(0)
        if not words:
            continue
        name, args = os.path.basename(words[0]), words[1:]
        if any(a in ("-h", "--help", "help") for a in args[:2]):
            continue
        if name in ("python", "python3") and "-c" not in args and not py_checked:
            py_checked = True
            for b in bodies:
                for target in py_writes(b):
                    if allowed_path(expand(target, env), cwd) is False:
                        found.append(("edit", f"python 쓰기 {target}"))
        if name == "cd" and args:
            new = os.path.expanduser(expand(args[0], env))
            cwd = new if os.path.isabs(new) else (os.path.join(cwd, new) if cwd and "$" not in new else None)
            continue
        if name in ("bash", "sh", "zsh") and "-c" in args:
            i = args.index("-c")
            if i + 1 < len(args):
                found += classify_command(args[i + 1], cwd, staged, depth + 1, changed)
            continue
        if name == "herdr-scope" and "--" in args:
            rest = args[args.index("--") + 1:]
            found += classify_command(shlex.join(rest), cwd, staged, depth + 1, changed)
            continue
        if name in ("python", "python3") and "-c" in args:
            i = args.index("-c")
            for target in py_writes(args[i + 1] if i + 1 < len(args) else ""):
                if allowed_path(expand(target, env), cwd) is False:
                    found.append(("edit", f"python 쓰기 {target}"))
            continue
        if name == "herdr-check" and not any(a in ("--status", "--status-of") for a in args):
            found.append(("check", "herdr-check " + " ".join(args)))
        elif name == "herdr-verify" and "--status" not in args and any(not a.startswith("-") for a in args):
            found.append(("check", "herdr-verify " + " ".join(args)))
        elif name == "herdr-queue" and args[:1] == ["run"]:
            found.append(("check", "herdr-queue run"))
        elif name in RUNNERS:
            subs = RUNNERS[name]
            first = next((a for a in args if not a.startswith("-")), "")
            if subs is None or first in subs:
                if not (name == "make" and first in ("-n", "--dry-run")) and not (name == "docker" and first == "compose" and not set(args) & {"up", "build", "run", "exec"}):
                    found.append(("check", " ".join([name] + args[:3])))
        elif name in ("python", "python3") and args[:2] == ["-m", "pytest"]:
            found.append(("check", "python -m pytest"))
        elif name == "git":
            a = list(args)
            while a and a[0] in ("-C", "-c"):
                a = a[2:]
            if not a:
                continue
            sub, rest = a[0], a[1:]
            if sub == "add":
                paths = [x for x in rest if not x.startswith("-")]
                added += [x for x in paths if x not in (".", ":/")]
                if "." in paths or ":/" in paths or (not paths and set(rest) & {"-A", "--all", "-u", "--update"}):
                    added.append("<전체>")
            elif sub == "commit":
                if any(x == "--all" or re.fullmatch(r"-[a-zA-Z]*a[a-zA-Z]*", x) for x in rest):
                    added.append("<전체>")
                files = added + (staged or [])
                if "<전체>" in files:
                    files = [f for f in files if f != "<전체>"] + (changed or [])
                bad = [f for f in files if allowed_path(f, cwd) is False]
                if bad:
                    found.append(("git", "git commit (상태 문서 밖: " + ", ".join(bad[:3]) + ")"))
            elif sub in GIT_WRITE:
                reads = GIT_READ_SUB.get(sub)
                if reads is not None and (not rest or rest[0] in reads):
                    continue
                if sub == "checkout" and rest and rest[0] in ("--help",):
                    continue
                found.append(("git", "git " + " ".join([sub] + rest[:2])))
        elif name == "sed" and any(x.startswith("-i") or x == "--in-place" for x in args):
            files, scripted, skip = [], False, False
            for x in args:
                if skip:
                    skip = False
                elif x in ("-e", "-f", "--expression", "--file"):
                    scripted = skip = True
                elif not x.startswith("-"):
                    files.append(x)
            if not scripted:
                files = files[1:]
            for f in files:
                if allowed_path(expand(f, env), cwd) is False:
                    found.append(("edit", f"sed -i {f}"))
        elif name == "perl" and any(re.match(r"^-\w*i", x) for x in args):
            for f in [x for x in args if not x.startswith("-")][1:]:
                if allowed_path(expand(f, env), cwd) is False:
                    found.append(("edit", f"perl -i {f}"))
        elif name in ("tee", "cp", "mv", "rm", "truncate", "install", "ln"):
            files = [x for x in args if not x.startswith("-")]
            targets = files[-1:] if name in ("cp", "mv", "install", "ln") else files
            for f in targets:
                if allowed_path(expand(f, env), cwd) is False:
                    found.append(("edit", f"{name} {f}"))
        elif name == "gofmt" and "-w" in args:
            found.append(("edit", "gofmt -w"))
    return found


def patch_files(text):
    return re.findall(r"\*\*\* (?:Update|Add|Delete) File: ([^\n\\]+)", text)


def classify_edit(tool, tool_input, cwd=None):
    """편집 도구 호출 → [(edit, 경로)]. Claude 편집 도구와 Codex apply_patch."""
    if tool in EDIT_TOOLS:
        paths = [tool_input.get("file_path") or tool_input.get("notebook_path") or ""]
    elif tool == "apply_patch":
        paths = patch_files(tool_input.get("command") or tool_input.get("input") or tool_input.get("patch") or "")
    else:
        return []
    return [("edit", p.strip()) for p in paths if allowed_path(p.strip(), cwd) is False]


def is_code_read(tool, tool_input):
    """코드 파일을 직접 읽었나(측정용, 막지 않는다)."""
    if tool == "Read":
        return bool(CODE_EXT.search(tool_input.get("file_path", "")))
    cmd = tool_input.get("command") if tool in ("Bash", "shell") else None
    if not isinstance(cmd, str):
        return False
    try:
        segs = list(segments(tokens_of(strip_heredocs(cmd)[0])))
    except ValueError:
        return False
    for seg in segs:
        if seg and os.path.basename(seg[0]) in ("cat", "sed", "head", "tail", "nl", "less", "bat") \
                and any(CODE_EXT.search(x) for x in seg[1:]):
            return True
    return False


HINT = {
    "edit": "Orchestrator는 작업 계획·상태판·결정 기록(docs/status/)과 세션 장부(~/.claude/herdr/)만 고친다. 코드·문서 수정은 [배정]으로 워커에게 맡긴다.",
    "check": "Orchestrator는 검사·테스트·빌드를 돌리지 않는다. 근거가 부족하면 같은 세션에 보완을 배정하고, 기록은 herdr-check --status-of <SHA>, herdr-verify --status <작업 ID>로 읽는다.",
    "git": "Orchestrator는 병합·rebase·push 같은 이력 변경을 하지 않는다(상태 문서 커밋만). 병합은 [병합]으로 워커에게 지시한다.",
}


def git_files(cwd, *args):
    try:
        out = subprocess.run(["git", *args], cwd=cwd or None, capture_output=True, text=True, timeout=5)
        return [f for f in out.stdout.splitlines() if f]
    except (OSError, subprocess.SubprocessError):
        return []


def guard_off():
    if os.environ.get("HERDR_ROLE_GUARD") is not None:
        return os.environ["HERDR_ROLE_GUARD"] == "0"
    env = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "harness.env")
    try:
        with open(env, encoding="utf-8") as f:
            return any(re.match(r"^HERDR_ROLE_GUARD=['\"]?0['\"]?\s*$", line) for line in f)
    except OSError:
        return False


def main():
    if os.environ.get("HERDR_ROLE") != "orchestrator" or guard_off():
        return 0
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    tool = data.get("tool_name") or ""
    ti = data.get("tool_input") or {}
    cwd = data.get("cwd") or os.getcwd()
    found = classify_edit(tool, ti, cwd)
    if not found and tool not in EDIT_TOOLS and tool != "apply_patch":
        cmd = ti.get("command")
        if isinstance(cmd, list):
            cmd = " ".join(cmd)
        if isinstance(cmd, str) and cmd:
            staged = changed = None
            if re.search(r"\bgit\b.*\bcommit\b", cmd):
                staged = git_files(cwd, "diff", "--cached", "--name-only")
                changed = git_files(cwd, "ls-files", "--modified", "--others", "--exclude-standard") + staged
            found = classify_command(cmd, cwd, staged, changed=changed)
    if not found:
        return 0
    kind, what = found[0]
    print(f"role-guard: {what} — {HINT[kind]} 정말 필요하면 [차단]으로 Commander에 올린다.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
