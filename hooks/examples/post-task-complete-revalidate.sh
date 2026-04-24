#!/usr/bin/env bash
# PostToolUse hook: when a USER-THROWN gate task is closed, force Claude to
# re-state evidence before moving on.
#
# Add this to your project's .claude/settings.local.json (see README).
#
# ## What it does
#
# Triggers on TaskUpdate tool calls with status=completed. Looks up the
# task's description in the session transcript and parses the embedded
# `json:metadata` fence. If metadata says the task is a user-thrown gate —
# `userGate: true` OR `tags` contains `"user-gate"` — emits a blocking
# reminder (exit 2 + stderr) that forces Claude to confirm every
# acceptanceCriteria with concrete evidence in the next turn.
#
# Regular (non-gate) tasks pass through silently.
#
# ## Why PostToolUse (not PreToolUse)
#
# The close itself is allowed — a user-gate task *can* legitimately be
# completed. What the hook protects against is closing-and-moving-on
# without proof. PostToolUse fires after the tool succeeds, so the block
# is a system-reminder the model MUST address before its next action,
# not a refusal to close the task.
#
# ## Escape hatch
#
# Set SUPERPOWERS_USERGATE_GUARD=0 to disable at runtime. The hook is
# opt-in already, so an escape hatch exists mainly for subagent contexts
# where re-validation has already happened upstream.

if [[ "${SUPERPOWERS_USERGATE_GUARD:-1}" == "0" ]]; then
    exit 0
fi

# Fail-open: if anything unexpected breaks, never block.
trap 'exit 0' ERR

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[[ "$TOOL_NAME" != "TaskUpdate" ]] && exit 0

STATUS=$(echo "$INPUT" | jq -r '.tool_input.status // empty' 2>/dev/null)
[[ "$STATUS" != "completed" ]] && exit 0

TASK_ID=$(echo "$INPUT" | jq -r '.tool_input.taskId // empty' 2>/dev/null)
[[ -z "$TASK_ID" ]] && exit 0

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]] && exit 0

# Walk the transcript JSONL to find the TaskCreate (and any later TaskUpdate)
# for this taskId, extract the description, and parse the json:metadata fence.
# Python (no heredoc — avoids bash 5.3 heredoc-hang regression).
PY_PARSE='
import json, re, sys
path = sys.argv[1]
task_id = str(sys.argv[2])

description = ""
subject = ""
# IDs are 1-based and increment in creation order. Rebuild that counter as we
# walk the transcript so we can match TaskCreate calls (which do not carry
# taskId in their input) to the target taskId.
next_id = 1
# Track line indices for the scan window below: where the most recent
# in_progress status change occurred for this taskId, and all assistant-text
# messages. If evidence already appears between in_progress and the close,
# the hook should NOT re-fire — that is what "already validated" means.
last_inprogress_idx = -1
text_indices = []  # list of (line_idx, text)

try:
    with open(path) as f:
        lines = f.readlines()
except Exception:
    print(json.dumps({}))
    sys.exit(0)

for idx, line in enumerate(lines):
    try:
        entry = json.loads(line)
    except Exception:
        continue
    if entry.get("type") != "assistant":
        continue
    msg = entry.get("message") or {}
    for c in msg.get("content") or []:
        if not isinstance(c, dict):
            continue
        if c.get("type") == "text":
            txt = c.get("text", "") or ""
            if txt.strip():
                text_indices.append((idx, txt))
            continue
        if c.get("type") != "tool_use":
            continue
        name = c.get("name", "")
        inp = c.get("input") or {}
        if name == "TaskCreate":
            if str(next_id) == task_id:
                description = inp.get("description", "") or ""
                subject = inp.get("subject", "") or ""
            next_id += 1
        elif name == "TaskUpdate":
            tid = str(inp.get("taskId", ""))
            if tid == task_id:
                if inp.get("description"):
                    description = inp.get("description", "") or ""
                if inp.get("status") == "in_progress":
                    last_inprogress_idx = idx
            try:
                if int(tid) >= next_id:
                    next_id = int(tid) + 1
            except (ValueError, TypeError):
                pass

out = {"subject": subject, "userGate": False, "tags": [],
       "criteria": [], "evidence_on_record": False}

# Parse the `json:metadata` code fence inside the task description.
m = re.search(r"```json:metadata\s*\n(.*?)\n```", description, re.DOTALL)
if m:
    try:
        meta = json.loads(m.group(1))
        out["userGate"] = bool(meta.get("userGate", False))
        tags = meta.get("tags", [])
        out["tags"] = tags if isinstance(tags, list) else []
        crits = meta.get("acceptanceCriteria", [])
        out["criteria"] = crits if isinstance(crits, list) else []
    except Exception:
        pass

# Also count a task as a gate if the description carries the verbatim
# USER-ORDERED GATE banner, even when the metadata fence is missing.
if "USER-ORDERED GATE" in description.upper():
    out["userGate"] = True

# Evidence scan: if at least one assistant-text message between the most
# recent in_progress for this task and now contains an AC:/PROVEN BY
# marker, treat the close as already validated. Scope the window to the
# in_progress marker to avoid counting evidence from a *different* gate.
# If no in_progress was seen (agent skipped straight to completed), fall
# back to scanning the whole transcript.
scan_from = last_inprogress_idx if last_inprogress_idx >= 0 else 0
ac_re = re.compile(r"\bAC\s*:", re.IGNORECASE)
pb_re = re.compile(r"\bPROVEN\s+BY\b", re.IGNORECASE)
for (i, txt) in text_indices:
    if i < scan_from:
        continue
    if ac_re.search(txt) or pb_re.search(txt):
        out["evidence_on_record"] = True
        break

print(json.dumps(out))
'

RESULT=$(python3 -c "$PY_PARSE" "$TRANSCRIPT_PATH" "$TASK_ID" 2>/dev/null || echo "{}")

IS_GATE=$(echo "$RESULT" | jq -r '
    (.userGate == true) or ((.tags // []) | any(. == "user-gate"))
' 2>/dev/null)

[[ "$IS_GATE" != "true" ]] && exit 0

# Idempotency: if evidence (AC:/PROVEN BY markers) is already on record for
# this task since its most recent in_progress transition, the re-close is
# legitimate and the hook should stay silent. Without this check the hook
# loops after /gate-check has already posted evidence.
EVIDENCE_ON_RECORD=$(echo "$RESULT" | jq -r '.evidence_on_record // false' 2>/dev/null)
[[ "$EVIDENCE_ON_RECORD" == "true" ]] && exit 0

SUBJECT=$(echo "$RESULT" | jq -r '.subject // "(unknown)"' 2>/dev/null)
CRITERIA_JSON=$(echo "$RESULT" | jq -c '.criteria // []' 2>/dev/null)

{
    echo "USER-GATE CLOSED — RE-VALIDATION REQUIRED"
    echo
    echo "Task #$TASK_ID ('$SUBJECT') is a USER-ORDERED gate. You just closed it."
    echo
    echo "The correct recovery path is to reopen the task and route it through"
    echo "the user-gate flow:"
    echo
    echo "    1. TaskUpdate taskId=$TASK_ID status=in_progress"
    echo "    2. /gate-check $TASK_ID"
    echo
    echo "/gate-check runs the 'do I know HOW?' self-check, then either executes"
    echo "the verification with captured evidence OR hands off to /specify-gate"
    echo "when the HOW is ambiguous. It posts one line per acceptance criterion:"
    echo "    AC: <criterion> — PROVEN BY <evidence>"
    echo
    echo "Acceptance criteria on record:"
    echo "$CRITERIA_JSON" | jq -r '.[] | "  - " + .' 2>/dev/null || true
    echo
    echo "If /gate-check is not installed in this harness, post the AC: lines"
    echo "inline by running the verification yourself. Either way, do NOT move"
    echo "on without concrete evidence per criterion."
    echo "(To disable this check, set SUPERPOWERS_USERGATE_GUARD=0.)"
} >&2

exit 2
