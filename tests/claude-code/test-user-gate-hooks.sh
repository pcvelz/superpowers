#!/usr/bin/env bash
# Test: User-gate hooks end-to-end on synthetic transcripts.
# Deterministic, no LLM. Mirrors the zoo example from docs/user-gate-flow.md.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POST_HOOK="$REPO_ROOT/hooks/examples/post-task-complete-revalidate.sh"
STOP_HOOK="$REPO_ROOT/hooks/examples/stop-revalidate-user-gates.sh"
BLOCKEDBY_HOOK="$REPO_ROOT/hooks/examples/pre-task-blockedby-enforce.sh"
DISPATCH_HOOK="$REPO_ROOT/hooks/examples/pre-agent-task-dispatch-validate.sh"
AGENT_RETURN_HOOK="$REPO_ROOT/hooks/examples/post-agent-return-validate.sh"
WORK=$(mktemp -d)
# Isolate trace log so these tests don't pollute the user's real one.
export SUPERPOWERS_USERGATE_TRACE_LOG="$WORK/trace.log"
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

echo "Test A: post-complete PASSES non-gate close when agent last output has assessment language"
# Non-gate task (no userGate / no banner). Agent posts "all green" before close.
cat > "$WORK/nongate-assessed.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Run unit tests","description":"**Goal:** run pytest.\n\n```json:metadata\n{\"files\":[\"tests/\"],\"verifyCommand\":\"pytest\",\"acceptanceCriteria\":[\"tests pass\"]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Ran pytest. Result: 42 tests passed, all green, exit 0."}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF
rc=$(run_post_hook 1 "$WORK/nongate-assessed.jsonl")
assert "non-gate + assessment text → pass (exit 0)" "0" "$rc"
echo ""

echo "Test B: post-complete PASSES non-gate close when user message in window"
cat > "$WORK/nongate-user-verified.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Refactor module","description":"**Goal:** refactor."}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"user","message":{"content":"Yes go ahead with that refactor"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Doing it now."}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF
rc=$(run_post_hook 1 "$WORK/nongate-user-verified.jsonl")
assert "non-gate + user message in window → pass (exit 0)" "0" "$rc"
echo ""

echo "Test C: post-complete BLOCKS non-gate silent close"
cat > "$WORK/nongate-silent.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Silent task","description":"**Goal:** something."}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"true"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF
rc=$(run_post_hook 1 "$WORK/nongate-silent.jsonl")
assert "non-gate + silent close → block (exit 2)" "2" "$rc"
grep -qF "TASK CLOSED WITHOUT ASSESSMENT" "$WORK/stderr" && echo "  [PASS] stderr has assessment prompt header" || { echo "  [FAIL] stderr missing assessment header"; FAILED=$((FAILED + 1)); }
grep -qFi "intentional" "$WORK/stderr" && echo "  [PASS] stderr asks if close was intentional" || { echo "  [FAIL] stderr missing intentional framing"; FAILED=$((FAILED + 1)); }
echo ""

echo "Test D: post-complete PASSES gate close when user verified (even without evidence markers)"
cat > "$WORK/gate-user-verified.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Gate with user verify","description":"**USER-ORDERED GATE — NON-SKIPPABLE.**\n\n```json:metadata\n{\"userGate\":true,\"tags\":[\"user-gate\"],\"acceptanceCriteria\":[\"c1\"]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"user","message":{"content":"I checked it myself, looks good, close it"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF
rc=$(run_post_hook 1 "$WORK/gate-user-verified.jsonl")
assert "gate + user verification in window → pass (exit 0)" "0" "$rc"
echo ""

echo "Test E: regression — superpowers-active no longer short-circuits the hook"
# Transcript that contains the word "superpowers" but has no assessment. Pre-rewrite this skipped; now it should block.
cat > "$WORK/superpowers-silent.jsonl" <<'EOF'
{"type":"user","message":{"content":"Using superpowers-extended-cc:subagent-driven-development to execute"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Task in superpowers run","description":"**Goal:** do stuff."}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF
rc=$(run_post_hook 1 "$WORK/superpowers-silent.jsonl")
assert "'superpowers' in transcript no longer auto-skips silent close" "2" "$rc"
echo ""

echo "Test L: post-complete BLOCKS empirical refactor close without A/B evidence"
cat > "$WORK/ab-required-missing.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Refactor /foo empirical","description":"**Goal:** empirical A/B of /foo.\n\n```json:metadata\n{\"files\":[\"cmd/foo.md\"],\"verifyCommand\":\"diff\",\"acceptanceCriteria\":[\"structural equivalence shown\"],\"requireABCompare\":true}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Refactor done, looks good, all tests passed."}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF
rc=$(run_post_hook 1 "$WORK/ab-required-missing.jsonl")
assert "post-complete exit 2 when requireABCompare=true and no A/B signals" "2" "$rc"
grep -qF "TASK CLOSE MISSING DECLARED EVIDENCE AXES" "$WORK/stderr" && echo "  [PASS] stderr has evidence-axes header" || { echo "  [FAIL] stderr missing evidence-axes header"; FAILED=$((FAILED + 1)); }
echo ""

echo "Test M: post-complete PASSES empirical refactor with both A/B tokens present"
cat > "$WORK/ab-required-satisfied.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Refactor /foo empirical","description":"**Goal:** A/B /foo.\n\n```json:metadata\n{\"acceptanceCriteria\":[\"both sides shown\"],\"requireABCompare\":true}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"iter-0 baseline: 831 chars, markers present. iter-1 refactored: equivalent structure, -40% tokens."}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF
rc=$(run_post_hook 1 "$WORK/ab-required-satisfied.jsonl")
assert "post-complete exit 0 when both BEFORE and AFTER tokens present" "0" "$rc"
echo ""

echo "Test N: post-complete BLOCKS when only AFTER side present (one-sided narrative)"
cat > "$WORK/ab-onesided.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Refactor /bar","description":"**Goal:** refactor.\n\n```json:metadata\n{\"requireABCompare\":true}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"New refactored version works great, updated and clean."}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF
rc=$(run_post_hook 1 "$WORK/ab-onesided.jsonl")
assert "post-complete exit 2 when BEFORE token missing" "2" "$rc"
echo ""

echo "Test O: evidence axes — v2→v3 migration close requires both 'v2' and 'v3' tokens"
cat > "$WORK/axes-migration-bad.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"ITP v2→v3 migration check","description":"**Goal:** migrate.\n\n```json:metadata\n{\"requireEvidenceTokens\":[[\"v2\",\"legacy\"],[\"v3\",\"migrated\"]]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Everything looks good — all endpoints hit correctly."}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF
rc=$(run_post_hook 1 "$WORK/axes-migration-bad.jsonl")
assert "axes close without v2/v3 tokens → block" "2" "$rc"
grep -qF "axis #0" "$WORK/stderr" && echo "  [PASS] stderr names missing axis #0" || { echo "  [FAIL] stderr missing axis #0"; FAILED=$((FAILED + 1)); }
echo ""

echo "Test P: evidence axes — same migration with real v2+v3 tokens passes"
cat > "$WORK/axes-migration-ok.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"ITP v2→v3 migration","description":"**Goal:** migrate.\n\n```json:metadata\n{\"requireEvidenceTokens\":[[\"v2\",\"legacy\"],[\"v3\",\"migrated\"]]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"v2 produced 5 webhooks per hour; after migration v3 produces the same 5 with identical payloads — confirmed via replay."}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF
rc=$(run_post_hook 1 "$WORK/axes-migration-ok.jsonl")
assert "axes close with v2 + v3 tokens → pass" "0" "$rc"
echo ""

echo "Test Q: 3-axis evidence — missing one axis still blocks"
cat > "$WORK/axes-3.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Perf triple-arm","description":"**Goal:** control vs A vs B.\n\n```json:metadata\n{\"requireEvidenceTokens\":[[\"control\"],[\"arm-a\",\"variant-a\"],[\"arm-b\",\"variant-b\"]]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"control=100ms, arm-a=85ms. B not measured."}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF
rc=$(run_post_hook 1 "$WORK/axes-3.jsonl")
assert "3-axis close missing arm-b → block" "2" "$rc"
grep -qF "axis #2" "$WORK/stderr" && echo "  [PASS] stderr names missing axis #2" || { echo "  [FAIL] stderr missing axis #2"; FAILED=$((FAILED + 1)); }
echo ""

echo "Test R: post-agent PASSES when in_progress task has no axes"
cat > "$WORK/agentret-noaxes.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Regular task","description":"**Goal:** no axes."}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
EOF
rc=$(printf '{"tool_name":"Agent","tool_response":"subagent said ok","transcript_path":"%s"}' \
    "$WORK/agentret-noaxes.jsonl" | bash "$AGENT_RETURN_HOOK" 2>"$WORK/stderr"; echo $?)
assert "post-agent exit 0 when no axes required" "0" "$rc"
echo ""

echo "Test S: post-agent BLOCKS when subagent return misses an axis"
cat > "$WORK/agentret-abreq.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Refactor task","description":"**Goal:** A/B.\n\n```json:metadata\n{\"requireABCompare\":true}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
EOF
rc=$(printf '{"tool_name":"Agent","tool_response":"Refactored everything, looks great!","transcript_path":"%s"}' \
    "$WORK/agentret-abreq.jsonl" | bash "$AGENT_RETURN_HOOK" 2>"$WORK/stderr"; echo $?)
assert "post-agent exit 2 when subagent return only mentions AFTER side" "2" "$rc"
grep -qF "SUBAGENT RETURN DOES NOT COVER DECLARED EVIDENCE AXES" "$WORK/stderr" && echo "  [PASS] stderr has subagent-return header" || { echo "  [FAIL] stderr missing header"; FAILED=$((FAILED + 1)); }
echo ""

echo "Test T: post-agent PASSES when subagent return covers both axes"
rc=$(printf '{"tool_name":"Agent","tool_response":"iter-0 baseline was 831 chars; iter-1 refactored version is 450 chars, structure preserved.","transcript_path":"%s"}' \
    "$WORK/agentret-abreq.jsonl" | bash "$AGENT_RETURN_HOOK" 2>"$WORK/stderr"; echo $?)
assert "post-agent exit 0 when return covers both axes" "0" "$rc"
echo ""

echo "Test U: post-agent respects SUPERPOWERS_AGENT_RETURN_GUARD=0"
rc=$(printf '{"tool_name":"Agent","tool_response":"nothing useful","transcript_path":"%s"}' \
    "$WORK/agentret-abreq.jsonl" | SUPERPOWERS_AGENT_RETURN_GUARD=0 bash "$AGENT_RETURN_HOOK" 2>"$WORK/stderr"; echo $?)
assert "post-agent exit 0 when guard disabled" "0" "$rc"
echo ""

echo "Test V: post-agent PASSES on non-Agent tool"
rc=$(printf '{"tool_name":"Bash","tool_response":"x","transcript_path":"%s"}' \
    "$WORK/agentret-abreq.jsonl" | bash "$AGENT_RETURN_HOOK" 2>"$WORK/stderr"; echo $?)
assert "post-agent exit 0 on non-Agent" "0" "$rc"
echo ""

echo "Test F: pre-dispatch PASSES when task has no dispatch requirement"
cat > "$WORK/dispatch-norequire.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Task with no req","description":"**Goal:** do stuff."}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
EOF
rc=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"do it"},"transcript_path":"%s"}' \
    "$WORK/dispatch-norequire.jsonl" | bash "$DISPATCH_HOOK" 2>"$WORK/stderr" >/dev/null; echo $?)
assert "pre-dispatch exit 0 when task has no requirement" "0" "$rc"
echo ""

echo "Test G: pre-dispatch BLOCKS when model mismatches task requirement"
cat > "$WORK/dispatch-modelreq.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Measurement task","description":"**Goal:** empirical A/B.\n\n```json:metadata\n{\"subagentType\":\"general-purpose\",\"model\":\"haiku\"}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
EOF
rc=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"run it"},"transcript_path":"%s"}' \
    "$WORK/dispatch-modelreq.jsonl" | bash "$DISPATCH_HOOK" 2>"$WORK/stderr"; echo $?)
assert "pre-dispatch exit 2 when model=opus but task requires haiku" "2" "$rc"
grep -qF "model: required='haiku'" "$WORK/stderr" && echo "  [PASS] stderr names model mismatch" || { echo "  [FAIL] stderr missing model mismatch line"; FAILED=$((FAILED + 1)); }
grep -qF "Measurement task" "$WORK/stderr" && echo "  [PASS] stderr names the task subject" || { echo "  [FAIL] stderr missing task subject"; FAILED=$((FAILED + 1)); }
echo ""

echo "Test H: pre-dispatch PASSES when model matches requirement"
rc=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"haiku","prompt":"run it"},"transcript_path":"%s"}' \
    "$WORK/dispatch-modelreq.jsonl" | bash "$DISPATCH_HOOK" 2>"$WORK/stderr" >/dev/null; echo $?)
assert "pre-dispatch exit 0 when model matches" "0" "$rc"
echo ""

echo "Test I: pre-dispatch BLOCKS when prompt lacks required dispatchBrief substring"
cat > "$WORK/dispatch-briefreq.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Committed template dispatch","description":"**Goal:** test commit template.\n\n```json:metadata\n{\"dispatchBrief\":\"local 35\\nCOMMIT EXECUTOR SUBAGENT\"}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
EOF
rc=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"local","prompt":"just run this"},"transcript_path":"%s"}' \
    "$WORK/dispatch-briefreq.jsonl" | bash "$DISPATCH_HOOK" 2>"$WORK/stderr"; echo $?)
assert "pre-dispatch exit 2 when prompt missing required brief" "2" "$rc"
echo ""

echo "Test J: pre-dispatch respects SUPERPOWERS_DISPATCH_GUARD=0"
rc=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"x"},"transcript_path":"%s"}' \
    "$WORK/dispatch-modelreq.jsonl" | SUPERPOWERS_DISPATCH_GUARD=0 bash "$DISPATCH_HOOK" 2>"$WORK/stderr" >/dev/null; echo $?)
assert "pre-dispatch exit 0 when guard disabled" "0" "$rc"
echo ""

echo "Test K: pre-dispatch PASSES on non-Agent tool"
rc=$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"transcript_path":"%s"}' \
    "$WORK/dispatch-modelreq.jsonl" | bash "$DISPATCH_HOOK" 2>"$WORK/stderr" >/dev/null; echo $?)
assert "pre-dispatch exit 0 on non-Agent tool" "0" "$rc"
echo ""

echo "Test 13: pre-blockedby hook PASSES when blocker is completed"
# Task 1 is a blocker for Task 2. Task 1 was closed. Moving Task 2 to
# in_progress must be allowed.
cat > "$WORK/blockedby-cleared.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"V0.1 Catalog logs","description":"foundation"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"V1.1 Replay","description":"consumes V0.1 output"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"2","addBlockedBy":[1]}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF
rc=$(printf '{"tool_name":"TaskUpdate","tool_input":{"taskId":"2","status":"in_progress"},"transcript_path":"%s"}' \
    "$WORK/blockedby-cleared.jsonl" | bash "$BLOCKEDBY_HOOK" 2>"$WORK/stderr" >/dev/null; echo $?)
assert "pre-blockedby exit 0 when blocker is completed" "0" "$rc"
echo ""

echo "Test 14: pre-blockedby hook BLOCKS on uncompleted blocker (ItsPerfect v3 failure mode)"
# Task 1 still pending. Agent tries to start Task 2 anyway.
cat > "$WORK/blockedby-open.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"V0.2 Cron catalog","description":"must run first"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"V1.2 STOCK cron replay","description":"zero setup, simplest"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"2","addBlockedBy":[1]}}]}}
EOF
rc=$(printf '{"tool_name":"TaskUpdate","tool_input":{"taskId":"2","status":"in_progress"},"transcript_path":"%s"}' \
    "$WORK/blockedby-open.jsonl" | bash "$BLOCKEDBY_HOOK" 2>"$WORK/stderr"; echo $?)
assert "pre-blockedby exit 2 when blocker still open" "2" "$rc"
grep -q "Task #1" "$WORK/stderr"      && echo "  [PASS] stderr names the missing blocker"      || { echo "  [FAIL] stderr doesn't name blocker"; FAILED=$((FAILED + 1)); }
grep -qi "hallucination" "$WORK/stderr" && echo "  [PASS] stderr invites hallucination self-check" || { echo "  [FAIL] stderr missing self-assess prompt"; FAILED=$((FAILED + 1)); }
grep -q "AskUserQuestion" "$WORK/stderr" && echo "  [PASS] stderr offers escalation path to user" || { echo "  [FAIL] stderr missing escalation option"; FAILED=$((FAILED + 1)); }
echo ""

echo "Test 15: pre-blockedby hook PASSES on non-in_progress status"
rc=$(printf '{"tool_name":"TaskUpdate","tool_input":{"taskId":"2","status":"completed"},"transcript_path":"%s"}' \
    "$WORK/blockedby-open.jsonl" | bash "$BLOCKEDBY_HOOK" 2>"$WORK/stderr" >/dev/null; echo $?)
assert "pre-blockedby exit 0 for status=completed (not our concern)" "0" "$rc"
echo ""

echo "Test 16: pre-blockedby hook respects SUPERPOWERS_BLOCKEDBY_GUARD=0"
rc=$(printf '{"tool_name":"TaskUpdate","tool_input":{"taskId":"2","status":"in_progress"},"transcript_path":"%s"}' \
    "$WORK/blockedby-open.jsonl" | SUPERPOWERS_BLOCKEDBY_GUARD=0 bash "$BLOCKEDBY_HOOK" 2>"$WORK/stderr" >/dev/null; echo $?)
assert "pre-blockedby exit 0 when guard disabled" "0" "$rc"
echo ""

echo "Test 17: pre-blockedby hook writes trace log entries"
# Clear the trace log, fire the blocker-present case, verify events logged.
: > "$SUPERPOWERS_USERGATE_TRACE_LOG"
printf '{"tool_name":"TaskUpdate","tool_input":{"taskId":"2","status":"in_progress"},"transcript_path":"%s"}' \
    "$WORK/blockedby-open.jsonl" | bash "$BLOCKEDBY_HOOK" 2>/dev/null || true
grep -q "pre-blockedby | task=2 | enter" "$SUPERPOWERS_USERGATE_TRACE_LOG" \
    && echo "  [PASS] trace logged 'enter' event" \
    || { echo "  [FAIL] trace log missing 'enter'"; FAILED=$((FAILED + 1)); cat "$SUPERPOWERS_USERGATE_TRACE_LOG" | head -5; }
grep -q "pre-blockedby | task=2 | block" "$SUPERPOWERS_USERGATE_TRACE_LOG" \
    && echo "  [PASS] trace logged 'block' decision" \
    || { echo "  [FAIL] trace log missing 'block'"; FAILED=$((FAILED + 1)); }
echo ""

echo "Test 11: plan.md ↔ tasks.json banner/metadata consistency"
# Writing-plans skill invariant: a USER-ORDERED GATE banner in the plan markdown
# MUST correspond 1:1 with userGate:true metadata in the sibling tasks.json.
# This test builds two synthetic fixtures (good + bad) and asserts the checker
# output. The checker is inline so it stays testable without a separate binary.

CHECKER='
md="$1"; tj="$2"
banners=$(grep -c "USER-ORDERED GATE" "$md" 2>/dev/null || echo 0)
gates=$(jq "[.tasks[] | select(.metadata.userGate == true)] | length" "$tj" 2>/dev/null || echo 0)
if [ "$banners" != "$gates" ]; then
    echo "MISMATCH: plan banners=$banners vs tasks.json userGate=$gates"
    exit 1
fi
echo "OK: banners=$banners gates=$gates"
exit 0
'

# Good fixture: 1 banner, 1 userGate:true
cat > "$WORK/good-plan.md" <<EOF
### Task 1: Verify deployment
**USER-ORDERED GATE — NON-SKIPPABLE.** test banner.
### Task 2: Regular work
no banner here.
EOF
cat > "$WORK/good-plan.md.tasks.json" <<EOF
{"tasks":[
  {"subject":"Task 1","metadata":{"userGate":true,"tags":["user-gate"]}},
  {"subject":"Task 2","metadata":{}}
]}
EOF
if bash -c "$CHECKER" _ "$WORK/good-plan.md" "$WORK/good-plan.md.tasks.json" >/dev/null; then
    echo "  [PASS] consistent plan passes checker"
else
    echo "  [FAIL] consistent plan should pass"
    FAILED=$((FAILED + 1))
fi

# Bad fixture: 17 banners, 0 userGate (the ItsPerfect v3 failure mode)
{
    for i in $(seq 1 17); do
        echo "### Task V$i"
        echo "**USER-ORDERED GATE — NON-SKIPPABLE.** banner $i"
    done
} > "$WORK/bad-plan.md"
cat > "$WORK/bad-plan.md.tasks.json" <<'EOF'
{"tasks":[
  {"subject":"Task V1"},{"subject":"Task V2"},{"subject":"Task V3"},
  {"subject":"Task V4"},{"subject":"Task V5"}
]}
EOF
if bash -c "$CHECKER" _ "$WORK/bad-plan.md" "$WORK/bad-plan.md.tasks.json" >/dev/null 2>&1; then
    echo "  [FAIL] banner flood should be detected"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] banner flood detected (17 banners vs 0 metadata)"
fi
echo ""

echo "Test 12: Step 1 detector regression — bare 'validate' must not fire"
# Writing-plans Step 1 is prose-instructed, not shell-implemented, so we can't
# drive an LLM here. Instead, assert the skill source text itself encodes the
# tightened trigger rule — this catches regressions that loosen Step 1 back to
# "any bucket matches" without running a live plan-writing session.
SKILL="$REPO_ROOT/skills/writing-plans/SKILL.md"
if grep -q "A \*\*Verbs\*\* match ALONE is not enough" "$SKILL" \
   && grep -q "Verbs.*match co-occurs with EITHER a Scope or a Proof" "$SKILL"; then
    echo "  [PASS] Step 1 trigger rule requires Verbs + (Scope|Proof) or Nouns|Scope match"
else
    echo "  [FAIL] Step 1 appears to have regressed to 'any bucket matches'"
    FAILED=$((FAILED + 1))
fi
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
