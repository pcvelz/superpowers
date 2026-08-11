#!/usr/bin/env bash
# PreToolUse hook: block git commit while a native task is in progress.
# Add this to your project's .claude/settings.json (see README).
#
# How it works:
# - Triggers on Bash tool calls containing "git commit"
# - Parses the session transcript for TaskCreate/TaskUpdate calls
# - Blocks only when a task has status "in_progress". Pending tasks pass
#   through so per-task commit flows (subagent-driven-development,
#   executing-plans) can commit one task at a time.

INPUT=$(cat)

ALLOW='{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' | tr -d '\r')
[[ "$TOOL_NAME" != "Bash" ]] && echo "$ALLOW" && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' | tr -d '\r')
# Match `git commit` only when it is an actual command — at the start of the
# line or after a shell separator (`;`, `&&`, `||`, `|`, `(`) — so embedded
# strings like `gh issue create --body "... git commit ..."` do not trigger.
echo "$COMMAND" | grep -qE '(^|[;&|(]|&&|\|\|)[[:space:]]*git[[:space:]]+commit([[:space:]]|[;&|)]|$)' || { echo "$ALLOW"; exit 0; }

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' | tr -d '\r')
[[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]] && echo "$ALLOW" && exit 0

# Transcript path passed as argv (not embedded in the source): MSYS path
# conversion on Windows rewrites argv only, so an inline '/...' string is
# unopenable for native Windows Python. tr strips the CRLF native Windows
# python3 emits (no-op elsewhere).
OPEN_TASKS=$({ python3 -c "
import json, sys
tasks = {}
next_id = 1
for line in open(sys.argv[1]):
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
" "$TRANSCRIPT_PATH" 2>/dev/null || echo "0"; } | tr -d '\r')

if [[ "$OPEN_TASKS" -gt 0 ]]; then
    echo "COMMIT BLOCKED: $OPEN_TASKS native task(s) still in progress. Finish the current task before committing." >&2
    exit 2
fi

echo "$ALLOW"
exit 0
