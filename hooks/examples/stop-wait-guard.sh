#!/usr/bin/env bash
# Stop hook: a turn that ends on a wait is not a finished turn.
#
# Shipped as an optional example, not auto-registered. Stop hooks fire on
# every assistant turn and enforce an opinionated workflow rule, so opting
# in is explicit. Register it in ~/.claude/settings.json so parallel
# executor sessions inherit it, or in a project's .claude/settings.json:
#
#   {"hooks": {"Stop": [{"matcher": "", "hooks": [{"type": "command",
#     "command": "bash ~/.claude/plugins/marketplaces/superpowers-extended-cc-marketplace/hooks/examples/stop-wait-guard.sh"}]}]}}
#
# ## The failure this catches
#
# During plan execution the agent ends its turn with a status report that
# says it is waiting: "Docker restarted; waiting out the grace period",
# "I'll continue to the tag and deploy once it reports", "a 15-min monitor
# is mid-flight". No tool call, no question to the human, task still
# in_progress. The session then sits idle until the human types "ok" or
# "And?" (observed gaps: 3 and 27 minutes). The pattern clusters around
# steps the model is reluctant to take on its own (production deploys,
# live writes) even when the plan's task spells out that step.
#
# ## What it does
#
# Fires on the Stop event. Blocks (exit 2 + stderr message) only when ALL
# of these hold:
#
#   1. Armed: the transcript shows executing-plans was invoked in this
#      session (Skill tool_use, or the slash command in a user message).
#      Sessions that never ran executing-plans are never touched.
#   2. The last assistant entry ended the turn with text only: no tool_use
#      block, no AskUserQuestion.
#   3. That text contains a wait phrase (list below).
#   4. A native task is in_progress for this session
#      (~/.claude/tasks/session-<sid8>/*.json).
#
# The block message does not argue. It quotes the wait sentence back,
# then re-states the in_progress task exactly as the plan wrote it: the
# Goal line, the USER-ORDERED GATE banner when present, and the
# acceptance criteria. The plan is the human's standing instruction; the
# hook only puts it back in front of the model at the moment it stopped.
#
# Fires once per stop: when Claude Code reports stop_hook_active=true the
# hook allows, so a second identical stop goes through and the human sees
# it. Fail-open on any read error.
#
# ## Wait phrases (case-insensitive)
#
#   waiting on|for|out, wait for, I'll continue, will continue,
#   will proceed, once it reports, when it reports, once it completes,
#   after it completes|finishes, still running, is running, mid-flight,
#   standing by, let me know, ready when you are, shall I, should I
#   proceed, do you want me to, your call
#
# ## Environment variables (all optional)
#
# SUPERPOWERS_WAIT_GUARD         "0" disables the hook. Default: 1.
# SUPERPOWERS_WAIT_GUARD_TRACE   Path of an append-only trace log.
#                                Default: /tmp/claude-hooks/wait-guard-trace.log

if [[ "${SUPERPOWERS_WAIT_GUARD:-1}" == "0" ]]; then
    exit 0
fi

# Fail-open: if anything unexpected breaks, never block the session.
trap 'exit 0' ERR

TRACE_LOG="${SUPERPOWERS_WAIT_GUARD_TRACE:-/tmp/claude-hooks/wait-guard-trace.log}"
SID8="?"
trace() {
    mkdir -p "$(dirname "$TRACE_LOG")" 2>/dev/null || true
    printf '%s | stop-wait-guard | session=%s | %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SID8" "$*" >> "$TRACE_LOG" 2>/dev/null || true
}

INPUT=$(cat)

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null | tr -d '\r')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -d '\r')
if [[ -z "$SESSION_ID" && -n "$TRANSCRIPT_PATH" ]]; then
    SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl)
fi
SID8="${SESSION_ID:0:8}"

STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null | tr -d '\r')
if [[ "$STOP_ACTIVE" == "true" ]]; then
    trace "allow | stop_hook_active (already fired once for this stop)"
    exit 0
fi

[[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]] && exit 0
TASKS_DIR="${SUPERPOWERS_TASKS_DIR:-$HOME/.claude/tasks}/session-$SID8"

# One python pass over transcript + task store. Prints a small report the
# bash side turns into the block message. Line 1: verdict. The rest: fields.
REPORT=$(python3 - "$TRANSCRIPT_PATH" "$TASKS_DIR" <<'PYEOF'
import json, sys, re, glob, os

path, tasks_dir = sys.argv[1], sys.argv[2]

WAIT = re.compile(
    r"(waiting (on|for|out)|wait for|I['’]ll continue|will continue|will proceed|"
    r"once (it|they|the \w+) (reports?|completes?|finish(es)?)|"
    r"when (it|they|the \w+) (reports?|completes?|finish(es)?)|"
    r"after (it|they|the \w+) (completes?|finish(es)?)|"
    r"still running|is running|mid-flight|standing by|let me know|"
    r"ready when you are|shall I|should I proceed|do you want me to|your call)",
    re.IGNORECASE,
)
ARM_SKILL = ("executing-plans", "execute-plan")

armed = False
last_assistant = None
try:
    f = open(path, "rb")
except Exception:
    print("allow|transcript-unreadable"); sys.exit(0)
with f:
    for raw in f:
        try:
            e = json.loads(raw.decode("utf-8", "replace"))
        except Exception:
            continue
        t = e.get("type")
        msg = e.get("message") or {}
        content = msg.get("content")
        if t == "assistant":
            last_assistant = e
            if isinstance(content, list):
                for c in content:
                    if isinstance(c, dict) and c.get("type") == "tool_use" and c.get("name") == "Skill":
                        sk = str((c.get("input") or {}).get("skill", ""))
                        if any(sk == a or sk.endswith(":" + a) for a in ARM_SKILL):
                            armed = True
        elif t == "user":
            text = ""
            if isinstance(content, str):
                text = content
            elif isinstance(content, list):
                text = " ".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
            if text.lstrip().startswith("Base directory for this skill:"):
                continue
            head = text[:400]
            if "superpowers-extended-cc:executing-plans" in head or "superpowers-extended-cc:execute-plan" in head:
                armed = True

if not armed:
    print("allow|not-armed"); sys.exit(0)
if last_assistant is None:
    print("allow|no-assistant"); sys.exit(0)

content = (last_assistant.get("message") or {}).get("content") or []
if not isinstance(content, list):
    content = [{"type": "text", "text": str(content)}]
if any(isinstance(c, dict) and c.get("type") == "tool_use" for c in content):
    print("allow|turn-ended-with-tool-call"); sys.exit(0)
text = "\n".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text").strip()
if not text:
    print("allow|no-text"); sys.exit(0)
m = WAIT.search(text)
if not m:
    print("allow|no-wait-phrase"); sys.exit(0)

# Sentence around the match, for the quote.
start = max(text.rfind(".", 0, m.start()), text.rfind("\n", 0, m.start())) + 1
end_candidates = [i for i in (text.find(".", m.end()), text.find("\n", m.end())) if i != -1]
end = min(end_candidates) + 1 if end_candidates else len(text)
sentence = re.sub(r"\s+", " ", text[start:end]).strip()[:240]

tasks = []
for fp in sorted(glob.glob(os.path.join(tasks_dir, "*.json"))):
    try:
        tk = json.load(open(fp))
    except Exception:
        continue
    if tk.get("status") == "in_progress":
        tasks.append(tk)
if not tasks:
    print("allow|no-in-progress-task"); sys.exit(0)

print("block|wait-phrase=%s" % m.group(0))
print("SENTENCE\t" + sentence)
for tk in tasks[:2]:
    desc = tk.get("description") or ""
    goal = ""
    mg = re.search(r"\*\*Goal:\*\*\s*(.+)", desc)
    if mg:
        goal = re.sub(r"\s+", " ", mg.group(1)).strip()[:400]
    else:
        # Tasks created without the Goal marker (plain executing-plans
        # descriptions): the description head IS the instruction.
        head = re.split(r"\n\s*\n|```json:metadata", desc, maxsplit=1)[0]
        goal = re.sub(r"\s+", " ", head).strip()[:400]
    banner = "USER-ORDERED GATE" in desc
    ac = []
    mac = re.search(r"\**Acceptance Criteria:\**\s*\n(.*?)(\n\**Verify|\n\*\*|\n```|\Z)", desc, re.S)
    if mac:
        for line in mac.group(1).splitlines():
            line = line.strip()
            if line.startswith(("-", "*")):
                ac.append(re.sub(r"^[-*]\s*(\[[ x]\]\s*)?", "", line)[:220])
    print("TASK\t%s\t%s\t%s\t%s" % (tk.get("id", "?"), tk.get("subject", ""), goal, "1" if banner else "0"))
    for a in ac[:6]:
        print("AC\t" + a)
PYEOF
) || REPORT="allow|python-error"

VERDICT="${REPORT%%$'\n'*}"
case "$VERDICT" in
    block*) ;;
    *) trace "${VERDICT}"; exit 0 ;;
esac

trace "$VERDICT | tasks_dir=$TASKS_DIR"

{
    echo "TURN ENDED ON A WAIT WHILE A PLAN TASK IS IN PROGRESS"
    echo ""
    echo "$REPORT" | grep '^SENTENCE' | cut -f2- | sed 's/^/Your last message: "/; s/$/"/'
    echo ""
    echo "$REPORT" | awk -F'\t' '
        $1=="TASK" {
            printf "Task %s \"%s\" is in_progress. Its instruction, as the plan wrote it:\n", $2, $3
            if ($4 != "") printf "  Goal: %s\n", $4
            if ($5 == "1") printf "  USER-ORDERED GATE, NON-SKIPPABLE: the human asked for this step in so many words.\n"
            ac = 0
        }
        $1=="AC" { if (ac == 0) printf "  Acceptance criteria:\n"; ac++; printf "    - %s\n", $2 }
    '
    echo ""
    echo "A wait is work, not a stopping point. Options, in order:"
    echo "  1. Poll what you are waiting on (TaskOutput, Monitor, re-run the check) and carry on."
    echo "  2. Proceed to the next step of this task that does not depend on the wait."
    echo "  3. If only your human partner can decide the next step, ask with AskUserQuestion now."
    echo ""
    echo "This hook fires once per stop. Disable: SUPERPOWERS_WAIT_GUARD=0. Trace: $TRACE_LOG"
} >&2

exit 2
