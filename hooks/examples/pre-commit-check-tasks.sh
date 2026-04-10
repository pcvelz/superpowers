#!/usr/bin/env bash
# PreToolUse hook: block git commit while a native task is in progress.
# Add this to your project's .claude/settings.local.json (see README).
#
# How it works:
# - Triggers on Bash tool calls containing "git commit"
# - Parses the session transcript for TaskCreate/TaskUpdate calls
# - Blocks only when a task has status "in_progress". Pending tasks pass
#   through so per-task commit flows (subagent-driven-development,
#   executing-plans) can commit one task at a time.

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[[ "$TOOL_NAME" != "Bash" ]] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
echo "$COMMAND" | grep -q 'git commit' || exit 0

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
[[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]] && exit 0

OPEN_TASKS=$(python3 -c "
import json
tasks = {}
next_id = 1
for line in open('$TRANSCRIPT_PATH'):
    try: entry = json.loads(line)
    except: continue
    if entry.get('type') != 'assistant': continue
    for c in entry.get('message', {}).get('content', []):
        if c.get('type') != 'tool_use': continue
        name, inp = c.get('name', ''), c.get('input', {})
        if name == 'TaskCreate':
            tasks[str(next_id)] = 'open'
            next_id += 1
        elif name == 'TaskUpdate':
            tid = str(inp.get('taskId', ''))
            status = inp.get('status', '')
            if tid and status:
                tasks[tid] = status
                try:
                    if int(tid) >= next_id: next_id = int(tid) + 1
                except ValueError: pass
print(sum(1 for s in tasks.values() if s == 'in_progress'))
" 2>/dev/null || echo "0")

if [[ "$OPEN_TASKS" -gt 0 ]]; then
    echo "COMMIT BLOCKED: $OPEN_TASKS native task(s) still in progress. Finish the current task before committing." >&2
    exit 2
fi
