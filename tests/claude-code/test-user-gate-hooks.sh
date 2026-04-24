#!/usr/bin/env bash
# Test: User-gate hooks end-to-end on synthetic transcripts.
# Deterministic, no LLM. Mirrors the zoo example from docs/user-gate-flow.md.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POST_HOOK="$REPO_ROOT/hooks/examples/post-task-complete-revalidate.sh"
STOP_HOOK="$REPO_ROOT/hooks/examples/stop-revalidate-user-gates.sh"
WORK=$(mktemp -d)
FAILED=0
# shellcheck disable=SC2064
trap "rm -rf '$WORK'" EXIT

echo "=== Test: User-Gate Hooks (post-complete + stop) ==="
echo ""

# Build a canonical transcript that mirrors docs/user-gate-flow.md's zoo example:
#   Task 1 = user-gate task (userGate:true, tags:[user-gate])
#   Task 2 = regular task (no gate markers)
#   Task 1 is closed with status=completed
#   Assistant then claims "Both gates passed" WITHOUT posting AC:…PROVEN BY evidence
cat > "$WORK/zoo-no-proof.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Gate 1: E2E on one instance","description":"**Goal:** Prove the full pipeline works on ONE instance.\n\n**USER-ORDERED GATE — NON-SKIPPABLE.** This task was requested by the user.\n\n```json:metadata\n{\"files\":[],\"verifyCommand\":\"./zoo.sh status v0.1.15\",\"acceptanceCriteria\":[\"Fresh instance spun up\",\"Sonnet subagent dispatched\",\"JIT captured\"],\"userGate\":true,\"tags\":[\"user-gate\"]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Task 5: Manager scraper","description":"**Goal:** Parse JIT events.\n\n```json:metadata\n{\"files\":[\"mgr/scraper.py\"],\"verifyCommand\":\"pytest tests/\",\"acceptanceCriteria\":[\"10/10 tests pass\"]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Both gates passed. Plan 0-7 + Gate 1 + Gate 2 all complete."}]}}
EOF

# Same transcript, but WITH proof posted after the close.
cat > "$WORK/zoo-with-proof.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Gate 1","description":"**USER-ORDERED GATE — NON-SKIPPABLE.**\n\n```json:metadata\n{\"userGate\":true,\"tags\":[\"user-gate\"],\"acceptanceCriteria\":[\"c1\",\"c2\"]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Gate 1 done.\nAC: c1 — PROVEN BY sensor.foo=idle\nAC: c2 — PROVEN BY notification_message diff\n\nBoth gates passed."}]}}
EOF

# Transcript with only the prose banner — no json:metadata fence.
cat > "$WORK/zoo-prose-only.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Gate X","description":"**Goal:** verify.\n\n**USER-ORDERED GATE — NON-SKIPPABLE.** The user requested this."}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF

run_post_hook() {
    local tid="$1" path="$2"
    printf '{"tool_name":"TaskUpdate","tool_input":{"taskId":"%s","status":"completed"},"transcript_path":"%s"}' \
        "$tid" "$path" | bash "$POST_HOOK" 2>"$WORK/stderr"
    echo "$?"
}

run_stop_hook() {
    local path="$1"
    printf '{"transcript_path":"%s"}' "$path" | bash "$STOP_HOOK" 2>"$WORK/stderr"
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

echo "Test 1: post-complete hook BLOCKS on gate close without proof"
rc=$(run_post_hook 1 "$WORK/zoo-no-proof.jsonl")
assert "exit code" "2" "$rc"
assert_stderr_contains "stderr mentions /gate-check as recovery path" "/gate-check 1"
assert_stderr_contains "stderr lists acceptance criteria" "Fresh instance spun up"
echo ""

echo "Test 2: post-complete hook PASSES on regular task close"
rc=$(run_post_hook 2 "$WORK/zoo-no-proof.jsonl")
assert "exit code" "0" "$rc"
echo ""

echo "Test 3: post-complete hook BLOCKS on prose-only gate banner"
rc=$(run_post_hook 1 "$WORK/zoo-prose-only.jsonl")
assert "exit code" "2" "$rc"
echo ""

echo "Test 4: post-complete hook respects SUPERPOWERS_USERGATE_GUARD=0"
printf '{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"},"transcript_path":"%s"}' \
    "$WORK/zoo-no-proof.jsonl" \
    | SUPERPOWERS_USERGATE_GUARD=0 bash "$POST_HOOK" 2>"$WORK/stderr"
rc=$?
assert "exit code" "0" "$rc"
echo ""

echo "Test 5: stop hook BLOCKS on completion keyword + unproven gate"
rc=$(run_stop_hook "$WORK/zoo-no-proof.jsonl")
assert "exit code" "2" "$rc"
assert_stderr_contains "stderr names the unproven gate" "Gate 1: E2E on one instance"
assert_stderr_contains "stderr mentions /gate-check" "/gate-check"
echo ""

echo "Test 6: stop hook PASSES when proof is posted"
rc=$(run_stop_hook "$WORK/zoo-with-proof.jsonl")
assert "exit code" "0" "$rc"
echo ""

echo "Test 7: stop hook PASSES with no completion keyword"
cat > "$WORK/zoo-working.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Gate 1","description":"**USER-ORDERED GATE**\n\n```json:metadata\n{\"userGate\":true,\"tags\":[\"user-gate\"],\"acceptanceCriteria\":[]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Continuing with Task 2."}]}}
EOF
rc=$(run_stop_hook "$WORK/zoo-working.jsonl")
assert "exit code" "0" "$rc"
echo ""

echo "Test 8: stop hook respects SUPERPOWERS_USERGATE_STOP_GUARD=0"
printf '{"transcript_path":"%s"}' "$WORK/zoo-no-proof.jsonl" \
    | SUPERPOWERS_USERGATE_STOP_GUARD=0 bash "$STOP_HOOK" 2>"$WORK/stderr"
rc=$?
assert "exit code" "0" "$rc"
echo ""

echo "Test 9: post-complete hook is idempotent after evidence is posted"
# Scenario: first close fires the block → agent reopens → posts AC: evidence
# → closes again. Second close must NOT re-fire.
cat > "$WORK/zoo-reclose.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Gate","description":"**USER-ORDERED GATE**\n\n```json:metadata\n{\"userGate\":true,\"tags\":[\"user-gate\"],\"acceptanceCriteria\":[\"c1\"]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Gate: verify\nAC: c1 — PROVEN BY unittest OK"},{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF
rc=$(run_post_hook 1 "$WORK/zoo-reclose.jsonl")
assert "post-hook exit 0 when evidence already on record" "0" "$rc"
echo ""

echo "Test 10: doc + skill files referenced by hooks exist"
for f in docs/user-gate-flow.md \
         skills/checking-gates/SKILL.md \
         skills/specifying-gates/SKILL.md \
         commands/gate-check.md \
         commands/specify-gate.md \
         skills/shared/task-format-reference.md; do
    if [ -f "$REPO_ROOT/$f" ]; then
        echo "  [PASS] $f exists"
    else
        echo "  [FAIL] $f missing"
        FAILED=$((FAILED + 1))
    fi
done
echo ""

echo "=== Summary: $FAILED failure(s) ==="
exit "$FAILED"
