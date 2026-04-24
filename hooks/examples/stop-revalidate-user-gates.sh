#!/usr/bin/env bash
# Stop hook: when Claude signals "plan complete / all gates passed" but a
# user-thrown gate was closed without captured evidence, block stop and
# require a final re-validation sweep.
#
# Add this to your project's .claude/settings.local.json (see README).
#
# ## What it does
#
# Fires on the Stop event. Two conditions must BOTH hold to block:
#
#   1. The last assistant message contains a "completion" keyword
#      (e.g. "plan complete", "implementation complete", "all gates passed",
#      "both gates passed", "all tasks complete", "plan 0–7 done").
#
#   2. The session transcript contains at least one TaskUpdate to
#      status=completed for a task whose description is a user-thrown gate
#      (metadata `userGate: true`, OR metadata `tags` contains `"user-gate"`,
#      OR description carries the verbatim "USER-ORDERED GATE" banner), AND
#      no subsequent assistant message surfaces explicit per-criterion
#      proof (patterns like "AC:", "PROVEN BY").
#
# When both hold, the hook emits a blocking stderr message (exit 2) naming
# the gates that lack evidence. Claude must then produce the proof before
# stopping again.
#
# ## Why Stop (not PostToolUse)
#
# PostToolUse already has a sibling hook (post-task-complete-revalidate.sh)
# that catches individual closes. This Stop hook is the net underneath —
# it catches end-of-plan claims ("both gates passed") even when per-task
# closure moved through legitimate-looking paths.
#
# ## Escape hatch
#
# Set SUPERPOWERS_USERGATE_STOP_GUARD=0 to disable at runtime.

TRACE_LOG="${SUPERPOWERS_USERGATE_TRACE_LOG:-/tmp/claude-hooks/user-gate-trace.log}"
mkdir -p "$(dirname "$TRACE_LOG")" 2>/dev/null || true
trace() {
    local event="${1:-?}" reason="${2:-}"
    printf '%s | stop-revalidate | session=%s | %s%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${TRANSCRIPT_SHORT:-?}" "$event" \
        "${reason:+ | $reason}" >> "$TRACE_LOG" 2>/dev/null || true
}

if [[ "${SUPERPOWERS_USERGATE_STOP_GUARD:-1}" == "0" ]]; then
    trace "skip" "stop-guard=0"
    exit 0
fi

# Fail-open: never cascade errors into the user's session.
trap 'trace "error" "trap-ERR"; exit 0' ERR

INPUT=$(cat)

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
TRANSCRIPT_SHORT=$(basename "${TRANSCRIPT_PATH:-?}" .jsonl | cut -c1-8)
[[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]] && { trace "skip" "no-transcript"; exit 0; }

trace "enter"

# Walk the transcript: find all TaskCreate + TaskUpdate calls, identify
# which completed tasks are user-thrown gates, and look for per-criterion
# proof in assistant text AFTER the close.
PY_SCAN='
import json, re, sys
path = sys.argv[1]

tasks = {}           # id -> {"subject", "description", "status",
                     #        "userGate", "tags", "closedAtIdx"}
last_text = ""
assistant_texts = []  # (line_idx, text)

try:
    with open(path) as f:
        lines = f.readlines()
except Exception:
    print(json.dumps({"blocked_gates": [], "last_text": "", "proofs": []}))
    sys.exit(0)

next_id = 1
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
                assistant_texts.append((idx, txt))
                last_text = txt
        elif c.get("type") == "tool_use":
            name = c.get("name", "")
            inp = c.get("input") or {}
            if name == "TaskCreate":
                tasks[str(next_id)] = {
                    "subject": inp.get("subject", ""),
                    "description": inp.get("description", "") or "",
                    "status": "pending",
                    "userGate": False,
                    "tags": [],
                    "closedAtIdx": None,
                }
                next_id += 1
            elif name == "TaskUpdate":
                tid = str(inp.get("taskId", ""))
                if tid in tasks:
                    if inp.get("description"):
                        tasks[tid]["description"] = inp["description"]
                    if inp.get("subject"):
                        tasks[tid]["subject"] = inp["subject"]
                    new_status = inp.get("status")
                    if new_status:
                        tasks[tid]["status"] = new_status
                        if new_status == "completed":
                            tasks[tid]["closedAtIdx"] = idx
                try:
                    if int(tid) >= next_id:
                        next_id = int(tid) + 1
                except (ValueError, TypeError):
                    pass

# Classify each completed task.
for tid, t in tasks.items():
    desc = t["description"]
    m = re.search(r"```json:metadata\s*\n(.*?)\n```", desc, re.DOTALL)
    if m:
        try:
            meta = json.loads(m.group(1))
            t["userGate"] = bool(meta.get("userGate", False))
            tags = meta.get("tags", [])
            if isinstance(tags, list):
                t["tags"] = tags
        except Exception:
            pass
    if "USER-ORDERED GATE" in desc.upper():
        t["userGate"] = True

# Completion keywords in the last assistant text — broad enough to catch
# the language models actually use when declaring a plan finished.
keywords = [
    "plan complete",
    "plan is complete",
    "plan finished",
    "implementation complete",
    "implementation is complete",
    "all tasks complete",
    "all tasks done",
    "all gates passed",
    "both gates passed",
    "both gates pass",
    "gate passed",
    "gate passes",
    "verification gate — passes",
    "verification gate passed",
    "plan 0",  # catches "Plan 0-7 done" style
    "tasks 0",  # catches "Tasks 0-7 + Gate 1 done"
]
low = last_text.lower()
has_completion_claim = any(k in low for k in keywords)

blocked_gates = []
if has_completion_claim:
    for tid, t in tasks.items():
        if t["status"] != "completed":
            continue
        is_gate = t["userGate"] or ("user-gate" in (t["tags"] or []))
        if not is_gate:
            continue
        # Look for per-criterion proof markers in assistant text after close.
        proof_found = False
        close_idx = t["closedAtIdx"] or 0
        for (i, txt) in assistant_texts:
            if i <= close_idx:
                continue
            # "AC:" prefix or "PROVEN BY" marker = explicit evidence.
            if re.search(r"\bAC\s*:", txt, re.IGNORECASE) or \
               re.search(r"\bPROVEN\s+BY\b", txt, re.IGNORECASE):
                proof_found = True
                break
        if not proof_found:
            blocked_gates.append({"id": tid, "subject": t["subject"]})

print(json.dumps({
    "has_completion_claim": has_completion_claim,
    "blocked_gates": blocked_gates,
    "total_tasks": len(tasks),
}))
'

RESULT=$(python3 -c "$PY_SCAN" "$TRANSCRIPT_PATH" 2>/dev/null || echo "{}")

BLOCKED_COUNT=$(echo "$RESULT" | jq -r '.blocked_gates | length // 0' 2>/dev/null)
HAS_CLAIM=$(echo "$RESULT" | jq -r '.has_completion_claim // false' 2>/dev/null)
TOTAL=$(echo "$RESULT" | jq -r '.total_tasks // 0' 2>/dev/null)
trace "scanned" "tasks=$TOTAL claim=$HAS_CLAIM blocked_gates=$BLOCKED_COUNT"

if [[ "${BLOCKED_COUNT:-0}" -le 0 ]]; then
    trace "pass" "no-unproven-gates"
    exit 0
fi

trace "block" "unproven_gates=$BLOCKED_COUNT"

{
    echo "PLAN-COMPLETE CLAIM DETECTED — SELF-ASSESS BEFORE STOPPING"
    echo
    echo "You signalled the plan / gates as complete, but the transcript shows"
    echo "$BLOCKED_COUNT user-thrown gate(s) closed without per-criterion proof in"
    echo "your subsequent text."
    echo
    echo "First — is this a hallucination or memory lapse? Check the transcript:"
    echo "  • Did you already post AC:/PROVEN BY evidence for these gates in"
    echo "    different wording? If yes, restate in the canonical shape so the"
    echo "    hook recognises it."
    echo "  • Did you genuinely verify these gates and forget to write the"
    echo "    evidence down? Then doing the verification again NOW is correct —"
    echo "    but do not fabricate evidence from memory."
    echo
    echo "If evidence is actually missing, and verifying is not currently"
    echo "possible (external system down, credentials missing, data unavailable),"
    echo "do NOT silently leave the claim standing. Either:"
    echo "  • Retract the completion claim in your next message, OR"
    echo "  • Raise the blocker to the user with AskUserQuestion — describe"
    echo "    what's missing and offer options (wait, skip with note, reshape)."
    echo
    echo "Gates missing evidence:"
    echo
    echo "$RESULT" | jq -r '.blocked_gates[] | "  - Task #" + .id + ": " + .subject' 2>/dev/null || true
    echo
    echo "Before stopping, reopen each listed gate and run /gate-check on it:"
    echo
    echo "    1. TaskUpdate taskId=<id> status=in_progress"
    echo "    2. /gate-check <id>"
    echo
    echo "/gate-check posts evidence in the shape this hook recognises:"
    echo
    echo "  Gate: <subject>"
    echo "  AC: <criterion> — PROVEN BY <exact command/output/subagent result>"
    echo "  AC: <criterion> — PROVEN BY <...>"
    echo
    echo "If /gate-check is not installed, post the AC: lines inline by running"
    echo "the verification yourself. If a gate cannot be proven right now,"
    echo "reopen it and retract the completion claim above."
    echo "(To disable this check, set SUPERPOWERS_USERGATE_STOP_GUARD=0.)"
} >&2

exit 2
