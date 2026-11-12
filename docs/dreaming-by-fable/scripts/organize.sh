#!/bin/bash
# usage: organize.sh <run dir> <prompt file> [model]
run="$1"; prompt="$2"; model="${3:-haiku}"
cd "$run" || exit 1
n=$(ls transcripts | wc -l | tr -d ' ')
start=$(date +%s)
claude -p "Tidy the memory directory at $run/memory now. $n analyzers have finished adding facts from $n transcripts; no other agent is writing. Merge duplicates, fix links and frontmatter, resolve or mark conflicts, and complete _index.md, keeping every fact. Reply with the one-line JSON object your instructions describe." \
  --model "$model" --system-prompt "$(cat "$prompt")" --tools "Read,Write,Edit,Glob,Grep" --allowedTools "Read,Write,Edit,Glob,Grep" \
  --permission-mode acceptEdits --setting-sources project --strict-mcp-config --no-session-persistence \
  --max-budget-usd 3 --output-format json < /dev/null > logs/_organizer.json 2> logs/_organizer.err
echo "organizer $? $(( $(date +%s) - start ))s"
