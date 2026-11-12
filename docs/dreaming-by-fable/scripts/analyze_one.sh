#!/bin/bash
# usage: analyze_one.sh <run dir> <prompt file> <transcript file name> [model]
run="$1"; prompt="$2"; f="$3"; model="${4:-haiku}"
cd "$run" || exit 1
start=$(date +%s)
claude -p "Please read the transcript at $run/transcripts/$f and add the durable, verified facts it shows to the long-term memory directory at $run/memory. Other analyzers are working on other transcripts into the same directory at the same time, so check what is already there before writing and add to or update existing files rather than overwrite them. Write only inside that directory, and do not modify the transcript. When done, submit a short summary of what you added." \
  --model "$model" --system-prompt "$(cat "$prompt")" --tools "Read,Write,Edit,Glob,Grep" --allowedTools "Read,Write,Edit,Glob,Grep" \
  --permission-mode acceptEdits --setting-sources project --strict-mcp-config --no-session-persistence \
  --max-budget-usd 0.8 --output-format json < /dev/null > "logs/$f.json" 2> "logs/$f.err"
echo "$f $? $(( $(date +%s) - start ))s" >> logs/done.txt
