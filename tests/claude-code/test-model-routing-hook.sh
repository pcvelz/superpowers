#!/usr/bin/env bash
# Test: pre-agent-model-routing hook — synthetic transcripts, no LLM.
# Covers all decision branches: no routing file, no task, allowed-set matching
# (task tier + reviewer "standard" tier), "inherit" semantics on both members,
# unknown tier, model pin deference, kill switch, non-Agent tool.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/pre-agent-model-routing"
WORK=$(mktemp -d)
export SUPERPOWERS_USERGATE_TRACE_LOG="$WORK/trace.log"
FAILED=0
# shellcheck disable=SC2064
trap "rm -rf '$WORK'" EXIT

echo "=== Test: pre-agent-model-routing ==="
echo ""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

assert() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label — expected exit=$expected, got exit=$actual"
        echo "         stderr: $(head -2 "$WORK/stderr" 2>/dev/null | tr '\n' ' ')"
        FAILED=$((FAILED + 1))
    fi
}

assert_stderr_contains() {
    local label="$1" needle="$2"
    if grep -qF "$needle" "$WORK/stderr" 2>/dev/null; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label — stderr missing: $needle"
        FAILED=$((FAILED + 1))
    fi
}

run_hook() {
    # Usage: run_hook <json-input> [env-overrides...]
    # Runs hook, discards stdout (ALLOW JSON), captures stderr.
    # Prints the hook's exit code on stdout so callers can rc=$(run_hook ...).
    # HOME is isolated by default so a real ~/.claude/superpowers/model-routing.json
    # on the machine can't pollute "no routing file" tests; later env-overrides
    # ("$@") win because env applies the last assignment.
    local input="$1" _rc; shift
    env HOME="$ISOLATED_HOME" "$@" bash "$HOOK" >/dev/null 2>"$WORK/stderr" <<< "$input" && _rc=$? || _rc=$?
    echo "$_rc"
}
ISOLATED_HOME="$WORK/isolated-home"
mkdir -p "$ISOLATED_HOME"

# Routing file used by most tests: mechanical→haiku, standard→sonnet, frontier→inherit.
ROUTING_DIR="$WORK/project/docs/superpowers"
mkdir -p "$ROUTING_DIR"
cat > "$ROUTING_DIR/model-routing.json" <<'EOF'
{"mechanical":"haiku","standard":"sonnet","frontier":"inherit"}
EOF

# Routing file where the reviewer tier ("standard") maps to inherit (wildcard).
WILDCARD_DIR="$WORK/wildcardproject/docs/superpowers"
mkdir -p "$WILDCARD_DIR"
cat > "$WILDCARD_DIR/model-routing.json" <<'EOF'
{"mechanical":"haiku","standard":"inherit","frontier":"inherit"}
EOF

# ---------------------------------------------------------------------------
# Transcripts
# ---------------------------------------------------------------------------

# Transcript: one in_progress task with modelTier=mechanical.
cat > "$WORK/tier-mechanical.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Bulk processing","description":"**Goal:** crunch data.\n\n```json:metadata\n{\"modelTier\":\"mechanical\",\"files\":[],\"verifyCommand\":\"true\",\"acceptanceCriteria\":[]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
EOF

# Transcript: in_progress task with modelTier=standard.
cat > "$WORK/tier-standard.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Standard work","description":"**Goal:** regular.\n\n```json:metadata\n{\"modelTier\":\"standard\",\"files\":[],\"verifyCommand\":\"true\",\"acceptanceCriteria\":[]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
EOF

# Transcript: in_progress task with modelTier=frontier ("inherit").
cat > "$WORK/tier-frontier.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Frontier reasoning task","description":"**Goal:** heavy reasoning.\n\n```json:metadata\n{\"modelTier\":\"frontier\",\"files\":[],\"verifyCommand\":\"true\",\"acceptanceCriteria\":[]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
EOF

# Transcript: in_progress task with a concrete model pin (no modelTier).
cat > "$WORK/model-pin.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Pinned model task","description":"**Goal:** pinned.\n\n```json:metadata\n{\"model\":\"haiku\",\"files\":[],\"verifyCommand\":\"true\",\"acceptanceCriteria\":[]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
EOF

# Transcript: in_progress task with BOTH a model pin and a modelTier. The pin
# must win: the gate defers to pre-agent-task-dispatch-validate even though the
# tier alone would forbid the pinned model. This is the contract that prevents
# contradictory blocks when both hooks are registered (pin says haiku,
# tier=standard says sonnet — without deference the two gates would deadlock).
cat > "$WORK/pin-and-tier.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Pinned and tiered task","description":"**Goal:** pinned+tiered.\n\n```json:metadata\n{\"model\":\"haiku\",\"modelTier\":\"standard\",\"files\":[],\"verifyCommand\":\"true\",\"acceptanceCriteria\":[]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
EOF

# Transcript: in_progress task with unknown tier.
cat > "$WORK/tier-unknown.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Typo tier task","description":"**Goal:** something.\n\n```json:metadata\n{\"modelTier\":\"superduper\",\"files\":[],\"verifyCommand\":\"true\",\"acceptanceCriteria\":[]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
EOF

# Transcript: no in_progress task (task was completed).
cat > "$WORK/no-inprogress.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Completed task","description":"**Goal:** done.\n\n```json:metadata\n{\"modelTier\":\"mechanical\",\"files\":[],\"verifyCommand\":\"true\",\"acceptanceCriteria\":[]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF

# Transcript: no tasks at all.
cat > "$WORK/empty.jsonl" <<'EOF'
{"type":"user","message":{"content":"Hello"}}
EOF

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

echo "Test 1: no routing file in cwd → allow"
# Point cwd at a dir without the routing file.
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 2: routing file present + no in_progress task → allow"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/no-inprogress.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 3: no tasks at all → allow"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/empty.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 4: tier=mechanical, dispatch model=haiku → allow (implementer tier match)"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"haiku","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 5: tier=mechanical, dispatch model=sonnet → allow (reviewer 'standard' tier)"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"sonnet","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 6: tier=mechanical, dispatch model=opus → block (outside allowed set)"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
assert_stderr_contains "headline present" "AGENT DISPATCH DOES NOT MATCH TASK MODEL TIER"
assert_stderr_contains "names the task" "Bulk processing"
assert_stderr_contains "names got model" "model='opus'"
assert_stderr_contains "roles header" "Allowed per docs/superpowers/model-routing.json:"
assert_stderr_contains "implementer role line" "implementer / fix dispatches → the model of the task they serve"
assert_stderr_contains "allowed set names haiku" "one of: haiku"
assert_stderr_contains "reviewer role line" "spec & code-quality reviewers → model: sonnet"
assert_stderr_contains "final reviewer role line" "final whole-plan reviewer (runs after all tasks complete) → no in_progress task, this gate won't fire"
echo ""

echo "Test 7: tier=mechanical, no model param → block (missing model counts as mismatch)"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
assert_stderr_contains "shows (none) for missing model" "model='(none)'"
echo ""

echo "Test 8: tier=frontier (maps to inherit), any model → allow"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-frontier.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 9: tier=frontier (maps to inherit), no model param → allow"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-frontier.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 10: unknown tier → allow (fail-open, typos must not brick dispatches)"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-unknown.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 11: task has concrete model pin → allow (deferred to dispatch-validate hook)"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/model-pin.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 12: SUPERPOWERS_ROUTING_GUARD=0 → allow (kill switch)"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT" SUPERPOWERS_ROUTING_GUARD=0)
assert "exit code" "0" "$rc"
echo ""

echo "Test 13: non-Agent tool → allow (hook only applies to Agent)"
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 14: unparseable routing file → allow (fail-open)"
BADROUTING_DIR="$WORK/badproject/docs/superpowers"
mkdir -p "$BADROUTING_DIR"
echo "this is not json" > "$BADROUTING_DIR/model-routing.json"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/badproject")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 15: standard maps to inherit → wildcard, any model allowed"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/wildcardproject")
rc=$(run_hook "$INPUT")
assert "exit code (model=opus)" "0" "$rc"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/wildcardproject")
rc=$(run_hook "$INPUT")
assert "exit code (no model param)" "0" "$rc"
echo ""

echo "Test 16: block message includes options and footer"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
run_hook "$INPUT" >/dev/null
assert_stderr_contains "option 1 text" "Re-issue the Agent call with the model matching the task this"
assert_stderr_contains "option 2 text" "TaskUpdate transparently"
assert_stderr_contains "option 3 text" "AskUserQuestion"
assert_stderr_contains "footer tier rules" "Tier rules: docs/model-routing-flow.md"
assert_stderr_contains "footer kill switch" "SUPERPOWERS_ROUTING_GUARD=0"
echo ""

echo "Test 17: hook writes trace log entries on block"
: > "$SUPERPOWERS_USERGATE_TRACE_LOG"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
run_hook "$INPUT" >/dev/null
grep -q "pre-routing" "$SUPERPOWERS_USERGATE_TRACE_LOG" \
    && echo "  [PASS] trace log contains pre-routing events" \
    || { echo "  [FAIL] trace log missing pre-routing entries"; FAILED=$((FAILED + 1)); cat "$SUPERPOWERS_USERGATE_TRACE_LOG" | head -5; }
grep -q "block" "$SUPERPOWERS_USERGATE_TRACE_LOG" \
    && echo "  [PASS] trace log records block decision" \
    || { echo "  [FAIL] trace log missing block decision"; FAILED=$((FAILED + 1)); }
echo ""

echo "Test 18: tier=standard, dispatch model=sonnet → allow (deduped set, tier match)"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"sonnet","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-standard.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 19: tier=standard, dispatch model=haiku → block (haiku is neither task tier nor standard)"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"haiku","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-standard.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
assert_stderr_contains "names resolved model sonnet" "model 'sonnet'"
assert_stderr_contains "names got model haiku" "model='haiku'"
echo ""

echo "Test 20: pin AND tier in metadata → pin wins, gate defers (no double-block deadlock)"
# tier=standard resolves to sonnet; the pinned model haiku is OUTSIDE the tier's
# allowed set. Dispatching the pinned model MUST be allowed by this gate —
# dispatch-validate owns pins. A regression here makes the two hooks demand
# different models for the same dispatch.
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"haiku","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/pin-and-tier.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code (dispatch pinned model outside tier set)" "0" "$rc"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/pin-and-tier.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code (any model defers when pin present)" "0" "$rc"
echo ""

echo "Test 21: cwd containing spaces → routing file still found, violation still blocks"
SPACED_DIR="$WORK/space project/docs/superpowers"
mkdir -p "$SPACED_DIR"
cp "$ROUTING_DIR/model-routing.json" "$SPACED_DIR/model-routing.json"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/space project")
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
echo ""

echo "Test 22: custom subagent_type exempt — llama/Explore dispatches never gated"
# Same violating scenario as Test 6 (tier=mechanical, model=opus) but with a
# custom agent type: must allow. Free local tiers carry no meaningful model
# param; only implementer/reviewer-grade (general-purpose) dispatches route.
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"llama","prompt":"llama 35 do thing"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "llama type, no model param → allow" "0" "$rc"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","model":"opus","prompt":"scan"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "Explore type, violating model → still allow" "0" "$rc"
# Absent subagent_type = general-purpose default: must still block.
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "absent type treated as general-purpose → block" "2" "$rc"
echo ""

echo "Test 23: user-level routing file (no project file) → enforce; project wins when both"
FAKEHOME="$WORK/fakehome"
mkdir -p "$FAKEHOME/.claude/superpowers"
cp "$ROUTING_DIR/model-routing.json" "$FAKEHOME/.claude/superpowers/model-routing.json"
NOPROJ="$WORK/noproject"
mkdir -p "$NOPROJ"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$NOPROJ")
rc=$(run_hook "$INPUT" HOME="$FAKEHOME")
assert "violation blocks via user-level file" "2" "$rc"
assert_stderr_contains "block message names user-level file" "~/.claude/superpowers/model-routing.json"
rc=$(run_hook "$INPUT" HOME="$WORK")   # HOME without the file, no project file → dormant
assert "dormant when neither file exists" "0" "$rc"
# Project file wins entirely: wildcard user file must NOT relax a project block.
WILDHOME="$WORK/wildhome"
mkdir -p "$WILDHOME/.claude/superpowers"
cp "$WILDCARD_DIR/model-routing.json" "$WILDHOME/.claude/superpowers/model-routing.json"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT" HOME="$WILDHOME")
assert "project file wins over wildcard user file" "2" "$rc"
echo ""

echo "Test 24: TWO tasks in_progress (standard most recent + mechanical older) → union allowed"
# Bounded parallel dispatch: a dispatch may serve ANY in_progress task, so the
# allowed set is the union of their tiers. Pre-fix behavior validated only the
# most recent task and falsely blocked the older task's implementer.
cat > "$WORK/parallel-two-tiers.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Mechanical export task","description":"**Goal:** export.\n\n```json:metadata\n{\"modelTier\":\"mechanical\",\"files\":[\"a.py\"],\"verifyCommand\":\"true\",\"acceptanceCriteria\":[]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Standard audit task","description":"**Goal:** audit.\n\n```json:metadata\n{\"modelTier\":\"standard\",\"files\":[\"b.py\"],\"verifyCommand\":\"true\",\"acceptanceCriteria\":[]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"2","status":"in_progress"}}]}}
EOF
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"haiku","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/parallel-two-tiers.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "haiku (older mechanical task's tier) → allow" "0" "$rc"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"sonnet","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/parallel-two-tiers.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "sonnet (recent standard task's tier) → allow" "0" "$rc"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/parallel-two-tiers.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "opus (in no in_progress tier) → block" "2" "$rc"
assert_stderr_contains "block names both tiers" "mechanical,standard"
echo ""

echo "Test 25: parallel with a frontier (inherit) member → allow any"
cat > "$WORK/parallel-with-frontier.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Mechanical task","description":"**Goal:** m.\n\n```json:metadata\n{\"modelTier\":\"mechanical\",\"files\":[],\"verifyCommand\":\"true\",\"acceptanceCriteria\":[]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Frontier task","description":"**Goal:** f.\n\n```json:metadata\n{\"modelTier\":\"frontier\",\"files\":[],\"verifyCommand\":\"true\",\"acceptanceCriteria\":[]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"2","status":"in_progress"}}]}}
EOF
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/parallel-with-frontier.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "frontier member in progress → any model allowed" "0" "$rc"
echo ""

echo "Test 26: parallel completion — older task closed, only recent constrains"
cat > "$WORK/parallel-one-closed.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Mechanical export task","description":"**Goal:** export.\n\n```json:metadata\n{\"modelTier\":\"mechanical\",\"files\":[],\"verifyCommand\":\"true\",\"acceptanceCriteria\":[]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Standard audit task","description":"**Goal:** audit.\n\n```json:metadata\n{\"modelTier\":\"standard\",\"files\":[],\"verifyCommand\":\"true\",\"acceptanceCriteria\":[]}\n```"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"2","status":"in_progress"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
EOF
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"haiku","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/parallel-one-closed.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "closed mechanical task no longer legitimizes haiku → block" "2" "$rc"
echo ""

echo "Test 27: invalid-UTF-8 byte in transcript poisons only its own line"
# Regression: text-mode readlines() threw UnicodeDecodeError for the WHOLE
# file on one bad byte, silently disabling the gate for the session.
{ printf '\x80 corrupt line\n'; cat "$WORK/tier-mechanical.jsonl"; } > "$WORK/badutf8.jsonl"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/badutf8.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "violating dispatch with bad byte in transcript → still block" "2" "$rc"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"haiku","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/badutf8.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "matching dispatch with bad byte in transcript → allow" "0" "$rc"
echo ""

echo "Test 28: garbage (non-JSON) hook stdin → allow (ERR-trap fail-open)"
rc=$(run_hook "this is not json input at all")
assert "exit code" "0" "$rc"
echo ""

echo "Test 29: /bin/bash canary — block path must work on stock macOS bash 3.2"
# Claude Code invokes hooks through run-hook.cmd (exec bash), which on a
# stock Mac is 3.2 — where e.g. an IFS of \\x01 silently fails to split (CTLESC).
# One block scenario under /bin/bash catches any always-allow regression there.
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
_rc=0
env HOME="$ISOLATED_HOME" /bin/bash "$HOOK" >/dev/null 2>"$WORK/stderr" <<< "$INPUT" && _rc=$? || _rc=$?
assert "violating dispatch blocks under /bin/bash" "2" "$_rc"
echo ""

echo "Test 30: real native-session transcript format — gate must parse tiers from live records"
# Regression: synthetic transcripts omit fields that Claude Code writes in real
# sessions (model, id, stop_reason, usage, diagnostics, context_management,
# caller, session_id, uuid, request_id at top level). This test uses a fixture
# captured from an actual headless session to prove the Python scan handles the
# full-fidelity record structure.
FIXTURE="$REPO_ROOT/tests/claude-code/fixtures/native-task-transcript.jsonl"
NATIVE_DIR="$WORK/nativeproject/docs/superpowers"
mkdir -p "$NATIVE_DIR"
# Fixture tier is "standard" → maps to sonnet in the routing file.
cat > "$NATIVE_DIR/model-routing.json" <<'EOF'
{"mechanical":"haiku","standard":"sonnet","frontier":"inherit"}
EOF
# (a) dispatch with the mapped model (sonnet) → allow.
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"sonnet","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$FIXTURE" "$WORK/nativeproject")
rc=$(run_hook "$INPUT")
assert "native format, tier=standard, model=sonnet → allow" "0" "$rc"
# (b) dispatch with a different model (haiku) → block (haiku is not standard's
#     mapped model nor is it the reviewer model in this routing config).
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"haiku","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$FIXTURE" "$WORK/nativeproject")
rc=$(run_hook "$INPUT")
assert "native format, tier=standard, model=haiku → block" "2" "$rc"
assert_stderr_contains "native format block names resolved tier model" "model 'sonnet'"
assert_stderr_contains "native format block names got model" "model='haiku'"
echo ""

echo "=== Summary: $FAILED failure(s) ==="
exit "$FAILED"
