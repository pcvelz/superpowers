#!/usr/bin/env bash
# Stop hook: block low-context stop-excuse phrases.
# Add this to your project's .claude/settings.local.json (see README).
#
# Shipped as an optional example, not auto-registered. Stop hooks fire on
# every assistant turn and enforce an opinionated workflow rule, so opting
# in is explicit.
#
# ## How it works
#
# Reads the last assistant text from the session transcript (path supplied
# by Claude Code via stdin) and measures actual context usage from the
# transcript's own usage data:
#     input_tokens + cache_read_input_tokens + cache_creation_input_tokens
#
# Blocks the stop (exit 2 + stderr message) when a known stop-excuse phrase
# is present AND context usage is below the threshold. At or above the
# threshold, the same phrases are allowed because context pressure may be
# legitimate.
#
# Fail-open: if the hook cannot read the transcript or measure context,
# it never blocks. Errors never cascade into the user's session.
#
# ## Blocked phrases (English, only below the threshold)
#
# Future-session deferral:
#   fresh session, next session, future session, separate session,
#   later session, given the time, given the hour, something for tomorrow
#
# Session-length excuses:
#   session too long, session getting long, chat too long, chat getting long
#
# Context excuses:
#   context is full, context is high, remaining context, clean session
#
# Session-end deferral:
#   end the session, wrap up the session, call it a session
#
# ## Environment variables (all optional)
#
# SUPERPOWERS_DEFLECTION_GUARD           Set to "0" to disable the hook
#                                        entirely at runtime. Useful for
#                                        quickly bypassing it when the hook
#                                        is registered in settings.local.json
#                                        but you want a one-off skip.
#                                        Default: 1 (active).
#
# SUPERPOWERS_CONTEXT_LIMIT              Total context window in tokens.
#                                        Default: 200000 (standard Opus).
#                                        Set to 1000000 for Opus 1M mode.
#
# SUPERPOWERS_DEFLECTION_THRESHOLD_PCT   Usage percentage below which phrases
#                                        are treated as hard violations.
#                                        Default: 50.

# Escape hatch.
if [[ "${SUPERPOWERS_DEFLECTION_GUARD:-1}" == "0" ]]; then
    exit 0
fi

# Fail-open: if anything unexpected breaks, never block the session.
trap 'exit 0' ERR

INPUT=$(cat)

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]] && exit 0

CONTEXT_LIMIT="${SUPERPOWERS_CONTEXT_LIMIT:-200000}"
THRESHOLD_PCT="${SUPERPOWERS_DEFLECTION_THRESHOLD_PCT:-50}"

# Extract last assistant text response + its usage tokens from the transcript.
# Walks the JSONL from the end, skipping tool-only messages, until it finds
# an assistant entry with at least one text content item. That entry's usage
# is our best snapshot of the current context footprint.
#
# Uses python3 -c instead of a heredoc to avoid bash 5.3+ heredoc-hang bugs
# (see hooks/session-start for the same workaround and upstream issue #571).
PY_EXTRACT='
import json, sys
path = sys.argv[1]
text = ""
tokens = 0
try:
    with open(path) as f:
        lines = f.readlines()
except Exception:
    print(json.dumps({"text": "", "tokens": 0}))
    sys.exit(0)

for line in reversed(lines):
    try:
        entry = json.loads(line)
    except Exception:
        continue
    if entry.get("type") != "assistant":
        continue
    msg = entry.get("message") or {}
    content = msg.get("content") or []
    parts = [
        c.get("text", "")
        for c in content
        if isinstance(c, dict) and c.get("type") == "text"
    ]
    if not parts:
        continue
    text = "\n".join(parts)
    usage = msg.get("usage") or {}
    tokens = (
        (usage.get("input_tokens") or 0)
        + (usage.get("cache_read_input_tokens") or 0)
        + (usage.get("cache_creation_input_tokens") or 0)
    )
    break

print(json.dumps({"text": text, "tokens": tokens}))
'

RESULT=$(python3 -c "$PY_EXTRACT" "$TRANSCRIPT_PATH" 2>/dev/null || echo "")

[[ -z "$RESULT" ]] && exit 0

TEXT=$(echo "$RESULT" | jq -r '.text // empty' 2>/dev/null)
TOKENS=$(echo "$RESULT" | jq -r '.tokens // 0' 2>/dev/null)

[[ -z "$TEXT" ]] && exit 0

# Integer math on percentage.
if [[ "${TOKENS:-0}" -le 0 || "${CONTEXT_LIMIT:-0}" -le 0 ]]; then
    CONTEXT_PCT=0
else
    CONTEXT_PCT=$(( TOKENS * 100 / CONTEXT_LIMIT ))
fi

# At or above threshold: allow. Below: scan phrases.
if [[ "$CONTEXT_PCT" -ge "$THRESHOLD_PCT" ]]; then
    exit 0
fi

# Hard-violator phrase list. Every entry here is an unambiguous stop-excuse
# that only makes sense if the context window is near its limit. Since the
# block only fires below the threshold, any match here is a proven lie.
PATTERNS=(
    # Future-session deferral
    "fresh session"
    "next session"
    "future session"
    "separate session"
    "later session"
    "given the time"
    "given the hour"
    "something for tomorrow"
    # Session-length excuses
    "session too long"
    "session getting long"
    "chat too long"
    "chat getting long"
    # Context excuses
    "context is full"
    "context is high"
    "remaining context"
    "clean session"
    # Session-end deferral
    "end the session"
    "wrap up the session"
    "call it a session"
)

for pattern in "${PATTERNS[@]}"; do
    if echo "$TEXT" | grep -qi "$pattern"; then
        echo "LOW-CONTEXT STOP EXCUSE DETECTED: '$pattern'" >&2
        echo "Context usage is ${CONTEXT_PCT}% of ${CONTEXT_LIMIT} tokens — not full. Keep working in this session." >&2
        echo "(To disable this check, set SUPERPOWERS_DEFLECTION_GUARD=0.)" >&2
        exit 2
    fi
done

exit 0
