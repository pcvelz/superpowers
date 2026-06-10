#!/usr/bin/env bash
# Test: pre-taskcreate-model-tier hook — synthetic inputs, no LLM.
# Covers all decision branches per spec.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/pre-taskcreate-model-tier"
WORK=$(mktemp -d)
export SUPERPOWERS_USERGATE_TRACE_LOG="$WORK/trace.log"
FAILED=0
# shellcheck disable=SC2064
trap "rm -rf '$WORK'" EXIT

echo "=== Test: pre-taskcreate-model-tier ==="
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
        echo "         stderr: $(head -3 "$WORK/stderr" 2>/dev/null | tr '\n' ' ')"
        FAILED=$((FAILED + 1))
    fi
}

assert_stderr_contains() {
    local label="$1" needle="$2"
    if grep -qF "$needle" "$WORK/stderr" 2>/dev/null; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label — stderr missing: $needle"
        echo "         actual stderr:"
        head -10 "$WORK/stderr" 2>/dev/null | sed 's/^/           /'
        FAILED=$((FAILED + 1))
    fi
}

run_hook() {
    # Usage: run_hook <json-input> [env-overrides...]
    # Captures stderr. Prints exit code on stdout.
    # HOME is isolated by default so a real ~/.claude/superpowers/model-routing.json
    # on the machine can't pollute "no routing file" tests; later env-overrides win.
    local input="$1" _rc; shift
    env HOME="$ISOLATED_HOME" "$@" bash "$HOOK" >/dev/null 2>"$WORK/stderr" <<< "$input" && _rc=$? || _rc=$?
    echo "$_rc"
}
ISOLATED_HOME="$WORK/isolated-home"
mkdir -p "$ISOLATED_HOME"

# Build a valid JSON hook input using python3 to handle embedded newlines/quotes.
make_input() {
    local tool="$1" subject="$2" desc_var="$3" cwd="$4"
    python3 -c "
import json, sys
obj = {
    'tool_name': sys.argv[1],
    'tool_input': {'subject': sys.argv[2], 'description': sys.argv[3]},
    'cwd': sys.argv[4],
}
print(json.dumps(obj))
" "$tool" "$subject" "$desc_var" "$cwd"
}

# ---------------------------------------------------------------------------
# Description templates
# ---------------------------------------------------------------------------

DESC_TIER_MECHANICAL=$'**Goal:** do something.\n\n```json:metadata\n{"modelTier":"mechanical","files":[],"verifyCommand":"true","acceptanceCriteria":[]}\n```'
DESC_TIER_STANDARD=$'**Goal:** do something.\n\n```json:metadata\n{"modelTier":"standard","files":[],"verifyCommand":"true","acceptanceCriteria":[]}\n```'
DESC_TIER_FRONTIER=$'**Goal:** do something.\n\n```json:metadata\n{"modelTier":"frontier","files":[],"verifyCommand":"true","acceptanceCriteria":[]}\n```'
DESC_MODEL_PIN=$'**Goal:** pinned task.\n\n```json:metadata\n{"model":"haiku","files":[],"verifyCommand":"true","acceptanceCriteria":[]}\n```'
DESC_NO_TIER=$'**Goal:** missing tier.\n\n```json:metadata\n{"files":[],"verifyCommand":"true","acceptanceCriteria":[]}\n```'
DESC_INVALID_TIER=$'**Goal:** bad tier.\n\n```json:metadata\n{"modelTier":"experimental","files":[],"verifyCommand":"true","acceptanceCriteria":[]}\n```'
DESC_BAD_FENCE=$'**Goal:** bad json.\n\n```json:metadata\n{not valid json\n```'
DESC_NO_FENCE='plain ad-hoc task with no metadata fence and no template headers at all.'

# ---------------------------------------------------------------------------
# Project setups
# ---------------------------------------------------------------------------

# Project WITH routing file.
PROJ="$WORK/project"
mkdir -p "$PROJ/docs/superpowers"
cat > "$PROJ/docs/superpowers/model-routing.json" <<'EOF'
{"mechanical":"haiku","standard":"sonnet","frontier":"inherit"}
EOF

# Project WITHOUT routing file.
NOPROJ="$WORK/norouting"
mkdir -p "$NOPROJ"

# Project with unparseable routing file.
BADPROJ="$WORK/badproject"
mkdir -p "$BADPROJ/docs/superpowers"
printf 'this is not json\n' > "$BADPROJ/docs/superpowers/model-routing.json"

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

echo "Test 1: no routing file → allow"
INPUT=$(make_input "TaskCreate" "My task" "$DESC_TIER_MECHANICAL" "$NOPROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 2: non-TaskCreate tool → allow"
INPUT=$(make_input "Bash" "irrelevant" "$DESC_NO_TIER" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 3: description without metadata fence → allow"
INPUT=$(make_input "TaskCreate" "Ad-hoc task" "$DESC_NO_FENCE" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 4: fence with modelTier=mechanical → allow"
INPUT=$(make_input "TaskCreate" "Bulk work" "$DESC_TIER_MECHANICAL" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 5: fence with modelTier=standard → allow"
INPUT=$(make_input "TaskCreate" "Integration work" "$DESC_TIER_STANDARD" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 6: fence with modelTier=frontier → allow"
INPUT=$(make_input "TaskCreate" "Architecture work" "$DESC_TIER_FRONTIER" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 7: fence with model pin, no tier → allow"
INPUT=$(make_input "TaskCreate" "Pinned task" "$DESC_MODEL_PIN" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 8: fence missing modelTier → block (exit 2)"
INPUT=$(make_input "TaskCreate" "Missing tier task" "$DESC_NO_TIER" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
assert_stderr_contains "headline present" "PLAN TASK MISSING MODEL TIER"
assert_stderr_contains "tier mechanical in table" "mechanical"
assert_stderr_contains "tier standard in table" "standard"
assert_stderr_contains "tier frontier in table" "frontier"
echo ""

echo "Test 9: fence with invalid tier 'experimental' → block + shows invalid value"
INPUT=$(make_input "TaskCreate" "Experimental task" "$DESC_INVALID_TIER" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
assert_stderr_contains "headline present" "PLAN TASK MISSING MODEL TIER"
assert_stderr_contains "shows invalid value" "experimental"
echo ""

echo "Test 10: unparseable fence JSON → allow (fail-open)"
INPUT=$(make_input "TaskCreate" "Bad fence task" "$DESC_BAD_FENCE" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 11: unparseable routing file → allow (fail-open)"
INPUT=$(make_input "TaskCreate" "Any task" "$DESC_NO_TIER" "$BADPROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 12: SUPERPOWERS_ROUTING_GUARD=0 → allow (kill switch)"
INPUT=$(make_input "TaskCreate" "Blocked task" "$DESC_NO_TIER" "$PROJ")
rc=$(run_hook "$INPUT" SUPERPOWERS_ROUTING_GUARD=0)
assert "exit code" "0" "$rc"
echo ""

echo "Test 13: cwd containing spaces → routing file still found, violation still blocks"
SPACEPROJ="$WORK/space project"
mkdir -p "$SPACEPROJ/docs/superpowers"
cp "$PROJ/docs/superpowers/model-routing.json" "$SPACEPROJ/docs/superpowers/model-routing.json"
INPUT=$(make_input "TaskCreate" "Spaced cwd task" "$DESC_NO_TIER" "$SPACEPROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
echo ""

echo "Test 14: hostile subject/description (quotes, backticks, \$()) flow through safely"
HOSTILE_SUBJ='Fix `eval` and "$(rm -rf /)" handling \ end'
HOSTILE_DESC_OK=$'**Goal:** handle `backticks` and "quotes" and $(subst).\n\n```json:metadata\n{"modelTier":"mechanical","files":[],"verifyCommand":"true","acceptanceCriteria":[]}\n```'
INPUT=$(make_input "TaskCreate" "$HOSTILE_SUBJ" "$HOSTILE_DESC_OK" "$PROJ")
rc=$(run_hook "$INPUT")
assert "valid tier with hostile content → allow" "0" "$rc"
HOSTILE_DESC_BAD=$'**Goal:** handle `backticks` and "quotes".\n\n```json:metadata\n{"files":[],"verifyCommand":"true","acceptanceCriteria":[]}\n```'
INPUT=$(make_input "TaskCreate" "$HOSTILE_SUBJ" "$HOSTILE_DESC_BAD" "$PROJ")
rc=$(run_hook "$INPUT")
assert "missing tier with hostile content → block" "2" "$rc"
assert_stderr_contains "subject echoed verbatim (no expansion)" 'Fix `eval` and "$(rm -rf /)" handling \ end'
echo ""

echo "Test 15: user-level routing file (no project file) → enforce"
FAKEHOME="$WORK/fakehome"
mkdir -p "$FAKEHOME/.claude/superpowers"
cp "$PROJ/docs/superpowers/model-routing.json" "$FAKEHOME/.claude/superpowers/model-routing.json"
INPUT=$(make_input "TaskCreate" "User-level task" "$DESC_NO_TIER" "$NOPROJ")
rc=$(run_hook "$INPUT" HOME="$FAKEHOME")
assert "missing tier blocks via user-level file" "2" "$rc"
INPUT=$(make_input "TaskCreate" "User-level ok task" "$DESC_TIER_MECHANICAL" "$NOPROJ")
rc=$(run_hook "$INPUT" HOME="$FAKEHOME")
assert "valid tier allows via user-level file" "0" "$rc"
echo ""

echo "Test 16: project file wins over user-level file (no merge)"
# Project file present alongside a user-level file: project rules apply.
INPUT=$(make_input "TaskCreate" "Both-files task" "$DESC_NO_TIER" "$PROJ")
rc=$(run_hook "$INPUT" HOME="$FAKEHOME")
assert "block per project file with user file also present" "2" "$rc"
# User-level file absent + no project file → dormant even with HOME set.
EMPTYHOME="$WORK/emptyhome"
mkdir -p "$EMPTYHOME"
INPUT=$(make_input "TaskCreate" "No-files task" "$DESC_NO_TIER" "$NOPROJ")
rc=$(run_hook "$INPUT" HOME="$EMPTYHOME")
assert "dormant when neither file exists" "0" "$rc"
echo ""

echo "Test 17: plan-shaped without fence → block (live-session redacted bypass)"
# Numbered-plan subject, plain description, no fence: the exact shape that
# sailed past the gate in the live device session.
INPUT=$(make_input "TaskCreate" "Phase 0.1: Verify README automations" "Compare the README automation list against production device.yaml" "$PROJ")
rc=$(run_hook "$INPUT")
assert "numbered subject, no fence → block" "2" "$rc"
assert_stderr_contains "fence headline" "PLAN TASK MISSING METADATA FENCE"
# Template headers in description, non-numbered subject, no fence.
DESC_HEADERS_NO_FENCE=$'**Goal:** do the thing.\n\n**Acceptance Criteria:**\n- [ ] it works'
INPUT=$(make_input "TaskCreate" "Some component work" "$DESC_HEADERS_NO_FENCE" "$PROJ")
rc=$(run_hook "$INPUT")
assert "template headers, no fence → block" "2" "$rc"
# Genuinely ad-hoc: plain subject, plain description → still allowed.
INPUT=$(make_input "TaskCreate" "fix the login bug" "login 500s on empty password, needs a guard" "$PROJ")
rc=$(run_hook "$INPUT")
assert "ad-hoc task, no fence → allow" "0" "$rc"
# Dormancy: same plan-shaped input but NO routing file anywhere → allow.
INPUT=$(make_input "TaskCreate" "Phase 0.1: Verify README automations" "Compare the README automation list" "$NOPROJ")
rc=$(run_hook "$INPUT")
assert "plan-shaped, no routing file → allow (dormant)" "0" "$rc"
echo ""

echo "=== Summary: $FAILED failure(s) ==="
exit "$FAILED"
