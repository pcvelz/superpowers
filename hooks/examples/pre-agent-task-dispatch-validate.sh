#!/usr/bin/env bash
# PreToolUse hook on Agent: enforce per-task LLM/dispatch requirements.
#
# Plans can now encode dispatch requirements in a task's json:metadata fence:
#   {
#     "subagentType": "general-purpose",
#     "model": "haiku",
#     "dispatchBrief": "required prompt substring"
#   }
#
# When a task is in_progress and the coordinator calls Agent, this hook:
#   1. Finds the most recent in_progress task.
#   2. Reads its metadata.subagentType / .model / .dispatchBrief.
#   3. Compares against the Agent tool_input.subagent_type / .model / .prompt.
#   4. Blocks on mismatch; passes when metadata is absent or matches.
#
# Rationale: coordinators frequently dispatch the wrong tier (e.g. Sonnet
# where the plan spec'd Haiku for empirical measurement). Skill prose is not
# enforcement; this hook is. Opt-in — most projects do not need it.
#
# Escape hatch: SUPERPOWERS_DISPATCH_GUARD=0 to disable.

TRACE_LOG="${SUPERPOWERS_USERGATE_TRACE_LOG:-/tmp/claude-hooks/user-gate-trace.log}"
mkdir -p "$(dirname "$TRACE_LOG")" 2>/dev/null || true
trace() {
    local tid="${1:-?}" event="${2:-?}" reason="${3:-}"
    printf '%s | pre-dispatch | task=%s | %s%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$tid" "$event" \
        "${reason:+ | $reason}" >> "$TRACE_LOG" 2>/dev/null || true
}

ALLOW='{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'

if [[ "${SUPERPOWERS_DISPATCH_GUARD:-1}" == "0" ]]; then
    trace "?" "skip" "guard=0"
    echo "$ALLOW"; exit 0
fi

trap 'trace "?" "error" "trap-ERR"; echo "$ALLOW"; exit 0' ERR

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[[ "$TOOL_NAME" != "Agent" ]] && { trace "?" "skip" "tool=$TOOL_NAME"; echo "$ALLOW"; exit 0; }

AGENT_SUBTYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
AGENT_MODEL=$(echo "$INPUT" | jq -r '.tool_input.model // empty' 2>/dev/null)
AGENT_PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]] && { trace "?" "skip" "no-transcript"; echo "$ALLOW"; exit 0; }

# Walk the transcript: find the most recent in_progress task + its metadata.
PY_SCAN='
import json, re, sys
path = sys.argv[1]

tasks = {}         # tid -> {"subject", "description"}
next_id = 1
current_inprogress = None  # most recent in_progress tid

try:
    with open(path) as f:
        lines = f.readlines()
except Exception:
    print(json.dumps({}))
    sys.exit(0)

for line in lines:
    try:
        e = json.loads(line)
    except Exception:
        continue
    if e.get("type") != "assistant":
        continue
    for c in (e.get("message") or {}).get("content") or []:
        if not isinstance(c, dict) or c.get("type") != "tool_use":
            continue
        name = c.get("name", "")
        inp = c.get("input") or {}
        if name == "TaskCreate":
            tid = str(next_id)
            tasks[tid] = {
                "subject": inp.get("subject", "") or "",
                "description": inp.get("description", "") or "",
            }
            next_id += 1
        elif name == "TaskUpdate":
            tid = str(inp.get("taskId", ""))
            if not tid:
                continue
            if tid not in tasks:
                tasks[tid] = {"subject": "", "description": ""}
            if inp.get("description"):
                tasks[tid]["description"] = inp["description"]
            status = inp.get("status")
            if status == "in_progress":
                current_inprogress = tid
            elif status in ("completed", "cancelled", "deleted") and current_inprogress == tid:
                current_inprogress = None
            try:
                if int(tid) >= next_id:
                    next_id = int(tid) + 1
            except (ValueError, TypeError):
                pass

out = {"task_id": current_inprogress, "subject": "",
       "subagentType": None, "model": None, "dispatchBrief": None}

if current_inprogress and current_inprogress in tasks:
    t = tasks[current_inprogress]
    out["subject"] = t["subject"]
    m = re.search(r"```json:metadata\s*\n(.*?)\n```", t["description"], re.DOTALL)
    if m:
        try:
            meta = json.loads(m.group(1))
            for k in ("subagentType", "model", "dispatchBrief"):
                v = meta.get(k)
                if v:
                    out[k] = v
        except Exception:
            pass

print(json.dumps(out))
'

RESULT=$(python3 -c "$PY_SCAN" "$TRANSCRIPT_PATH" 2>/dev/null || echo "{}")
TASK_ID=$(echo "$RESULT" | jq -r '.task_id // "?"' 2>/dev/null)
REQ_SUBTYPE=$(echo "$RESULT" | jq -r '.subagentType // empty' 2>/dev/null)
REQ_MODEL=$(echo "$RESULT" | jq -r '.model // empty' 2>/dev/null)
REQ_BRIEF=$(echo "$RESULT" | jq -r '.dispatchBrief // empty' 2>/dev/null)
SUBJECT=$(echo "$RESULT" | jq -r '.subject // "?"' 2>/dev/null)

# Nothing required → pass.
if [[ -z "$REQ_SUBTYPE" && -z "$REQ_MODEL" && -z "$REQ_BRIEF" ]]; then
    trace "$TASK_ID" "pass" "no-dispatch-requirement"
    echo "$ALLOW"; exit 0
fi

trace "$TASK_ID" "parsed" "req_subtype=$REQ_SUBTYPE req_model=$REQ_MODEL req_brief_len=${#REQ_BRIEF}"

MISMATCHES=()
if [[ -n "$REQ_SUBTYPE" && "$AGENT_SUBTYPE" != "$REQ_SUBTYPE" ]]; then
    MISMATCHES+=("subagent_type: required='$REQ_SUBTYPE', got='$AGENT_SUBTYPE'")
fi
if [[ -n "$REQ_MODEL" && "$AGENT_MODEL" != "$REQ_MODEL" ]]; then
    MISMATCHES+=("model: required='$REQ_MODEL', got='$AGENT_MODEL'")
fi
if [[ -n "$REQ_BRIEF" && "$AGENT_PROMPT" != *"$REQ_BRIEF"* ]]; then
    MISMATCHES+=("dispatchBrief: prompt missing required substring '$REQ_BRIEF'")
fi

if [[ ${#MISMATCHES[@]} -eq 0 ]]; then
    trace "$TASK_ID" "pass" "dispatch-matches-requirement"
    echo "$ALLOW"; exit 0
fi

trace "$TASK_ID" "block" "dispatch-mismatch count=${#MISMATCHES[@]}"

{
    echo "AGENT DISPATCH DOES NOT MATCH TASK REQUIREMENT"
    echo
    echo "Task #$TASK_ID ('$SUBJECT') is in_progress and its metadata specifies"
    echo "how subagents for this task MUST be dispatched. Your Agent call"
    echo "disagrees on:"
    echo
    for m in "${MISMATCHES[@]}"; do
        echo "  - $m"
    done
    echo
    echo "Options:"
    echo "  1. Re-issue the Agent call with the required parameters. This is"
    echo "     the default — the plan author chose these for a reason"
    echo "     (cost, capability, parallelism)."
    echo "  2. If you are certain the requirement is wrong for this specific"
    echo "     dispatch, update the task's metadata via TaskUpdate to relax or"
    echo "     remove the constraint — then retry. Do this transparently, not"
    echo "     as a workaround."
    echo "  3. Escalate to the user via AskUserQuestion if you think the plan"
    echo "     spec'd the wrong tier."
    echo
    echo "(Runtime disable: SUPERPOWERS_DISPATCH_GUARD=0. Trace log: $TRACE_LOG)"
} >&2

exit 2
