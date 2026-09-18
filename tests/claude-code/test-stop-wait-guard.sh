#!/usr/bin/env bash
# Test: stop-wait-guard.sh on synthetic transcripts and a fake task store.
# Deterministic, no LLM. The fixtures mirror a live executor session
# (2026-09-12) that ended three turns on "waiting ..." / "I'll continue ...
# once it reports" with a plan task still in_progress.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/examples/stop-wait-guard.sh"
WORK=$(mktemp -d)
export SUPERPOWERS_WAIT_GUARD_TRACE="$WORK/trace.log"
export SUPERPOWERS_TASKS_DIR="$WORK/tasks"
SID="e0a6df14-0000-4000-8000-000000000000"
FAILED=0
# shellcheck disable=SC2064
trap "rm -rf '$WORK'" EXIT

echo "=== Test: stop-wait-guard ==="
echo ""

# --- task store ------------------------------------------------------------
mkdir -p "$WORK/tasks/session-e0a6df14" "$WORK/notasks/session-e0a6df14"
cat > "$WORK/tasks/session-e0a6df14/1.json" <<'EOF'
{"id":"1","subject":"Task 0: Repair venv","status":"completed","description":"**Goal:** fixed."}
EOF
cat > "$WORK/tasks/session-e0a6df14/14.json" <<'EOF'
{"id":"14","subject":"Task 13: Gates, release 0.9.0, production verification","status":"in_progress","description":"**Goal:** The phase is finished only when 0.9.0 runs on production with a freshly computed schedule.\n\n**USER-ORDERED GATE — NON-SKIPPABLE.** This task was requested by the user.\n\n**Files:**\n- Modify: x\n\n**Acceptance Criteria:**\n- [ ] Full pytest suite green\n- [ ] /release-widget 0.9.0 completes through deploy + verify\n- [ ] Production: recalculate pressed; event entity populated\n\n**Verify:** bash api.sh states/sensor.x\n\n```json:metadata\n{\"files\":[],\"modelTier\":\"frontier\"}\n```"}
EOF

# --- transcripts ----------------------------------------------------------
ARM='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"superpowers-extended-cc:executing-plans","args":"docs/plans/x.md"}}]}}'
ARM_USER='{"type":"user","message":{"content":"<command-message>executing-plans</command-message><command-name>/superpowers-extended-cc:executing-plans</command-name> docs/plans/x.md"}}'
SKILL_BODY='{"type":"user","message":{"content":[{"type":"text","text":"Base directory for this skill: /x/skills/executing-plans\n\nUse superpowers-extended-cc:executing-plans ..."}]}}'
WORKING='{"type":"assistant","message":{"content":[{"type":"text","text":"Gate at 172/199 clean."},{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}'
STALL_WAIT='{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Docker restarted; waiting out the grace period before probing."}]}}'
STALL_PROMISE='{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Step 0b is progressing (Docker at complete). I'"'"'ll continue to the tag and deploy once it reports."}]}}'
STALL_TABLE='{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Where the release stands:\n| Step | Result |\n| 0b Docker | running, a 15-min stability monitor is mid-flight |"}]}}'
DONE='{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Task 13 complete: v0.9.0 tagged and deployed, recalculate pressed, event entity populated."}]}}'
ASKED='{"type":"assistant","message":{"content":[{"type":"text","text":"Waiting on your decision."},{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[{"question":"Deploy now?","header":"Deploy","options":[{"label":"Yes"},{"label":"No"}]}]}}]}}'

mk() { # $1=name, rest=lines
    local name="$1"; shift
    : > "$WORK/$name.jsonl"
    for l in "$@"; do printf '%s\n' "$l" >> "$WORK/$name.jsonl"; done
}
mk armed-wait        "$ARM" "$WORKING" "$STALL_WAIT"
mk armed-promise     "$ARM" "$WORKING" "$STALL_PROMISE"
mk armed-table       "$ARM" "$WORKING" "$STALL_TABLE"
mk armed-done        "$ARM" "$WORKING" "$DONE"
mk armed-asked       "$ARM" "$WORKING" "$ASKED"
mk armed-working     "$ARM" "$WORKING"
mk user-armed-wait   "$ARM_USER" "$WORKING" "$STALL_WAIT"
mk body-only-wait    "$SKILL_BODY" "$WORKING" "$STALL_WAIT"
mk not-armed-wait    "$WORKING" "$STALL_WAIT"

run_hook() { # $1=transcript $2=stop_hook_active [$3=env assignments]
    local path="$1" active="${2:-false}"; shift 2
    printf '{"session_id":"%s","transcript_path":"%s","stop_hook_active":%s}' "$SID" "$path" "$active" \
        | env "$@" bash "$HOOK" 2>"$WORK/stderr"
    echo "$?"
}

assert() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label — expected exit=$expected, got exit=$actual"
        echo "         stderr: $(head -2 "$WORK/stderr" | tr '\n' ' ')"
        FAILED=$((FAILED + 1))
    fi
}

assert_stderr_contains() {
    local label="$1" needle="$2"
    if grep -qF "$needle" "$WORK/stderr"; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label — stderr missing: $needle"
        FAILED=$((FAILED + 1))
    fi
}

echo "Test 1: kill switch SUPERPOWERS_WAIT_GUARD=0 → allow"
assert "exit code" "0" "$(run_hook "$WORK/armed-wait.jsonl" false SUPERPOWERS_WAIT_GUARD=0)"
echo ""

echo "Test 2: not armed (executing-plans never invoked) → allow"
assert "exit code" "0" "$(run_hook "$WORK/not-armed-wait.jsonl" false _=1)"
echo ""

echo "Test 3: executing-plans skill body alone must not arm → allow"
assert "exit code" "0" "$(run_hook "$WORK/body-only-wait.jsonl" false _=1)"
echo ""

echo "Test 4: armed via Skill tool_use + wait sentence + in_progress task → BLOCK"
assert "exit code" "2" "$(run_hook "$WORK/armed-wait.jsonl" false _=1)"
assert_stderr_contains "headline" "TURN ENDED ON A WAIT WHILE A PLAN TASK IS IN PROGRESS"
assert_stderr_contains "quotes the wait sentence" "waiting out the grace period before probing."
assert_stderr_contains "names the task" "Task 13: Gates, release 0.9.0, production verification"
assert_stderr_contains "restates the goal" "Goal: The phase is finished only when 0.9.0 runs on production"
assert_stderr_contains "carries the user-gate banner" "USER-ORDERED GATE, NON-SKIPPABLE"
assert_stderr_contains "lists acceptance criteria" "/release-widget 0.9.0 completes through deploy + verify"
assert_stderr_contains "offers AskUserQuestion as the escalation" "AskUserQuestion"
echo ""

echo "Test 5: armed via slash command in a user message → BLOCK"
assert "exit code" "2" "$(run_hook "$WORK/user-armed-wait.jsonl" false _=1)"
echo ""

echo "Test 6: promise phrase (I'll continue ... once it reports) → BLOCK"
assert "exit code" "2" "$(run_hook "$WORK/armed-promise.jsonl" false _=1)"
assert_stderr_contains "quotes the promise" "once it reports"
echo ""

echo "Test 7: status table with mid-flight → BLOCK"
assert "exit code" "2" "$(run_hook "$WORK/armed-table.jsonl" false _=1)"
echo ""

echo "Test 8: completion text without a wait phrase → allow"
assert "exit code" "0" "$(run_hook "$WORK/armed-done.jsonl" false _=1)"
echo ""

echo "Test 9: turn ended with a tool call (AskUserQuestion) → allow"
assert "exit code" "0" "$(run_hook "$WORK/armed-asked.jsonl" false _=1)"
assert "turn ended with Bash call → allow" "0" "$(run_hook "$WORK/armed-working.jsonl" false _=1)"
echo ""

echo "Test 10: wait sentence but no in_progress task → allow"
assert "exit code" "0" "$(run_hook "$WORK/armed-wait.jsonl" false SUPERPOWERS_TASKS_DIR="$WORK/notasks")"
echo ""

echo "Test 11: second fire on the same stop (stop_hook_active=true) → allow"
assert "exit code" "0" "$(run_hook "$WORK/armed-wait.jsonl" true _=1)"
echo ""

echo "Test 12: missing / garbage transcript → allow (fail-open)"
assert "missing transcript" "0" "$(run_hook "$WORK/does-not-exist.jsonl" false _=1)"
printf 'not json\n{bad\n' > "$WORK/garbage.jsonl"
assert "garbage transcript" "0" "$(run_hook "$WORK/garbage.jsonl" false _=1)"
echo ""

echo "Test 13: /bin/bash canary — block path works on stock macOS bash 3.2"
printf '{"session_id":"%s","transcript_path":"%s","stop_hook_active":false}' "$SID" "$WORK/armed-wait.jsonl" \
    | /bin/bash "$HOOK" 2>"$WORK/stderr"; rc=$?
assert "exit code under /bin/bash" "2" "$rc"
echo ""

echo "=== Summary: $FAILED failure(s) ==="
exit "$FAILED"
