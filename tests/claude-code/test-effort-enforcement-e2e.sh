#!/usr/bin/env bash
# End-to-end: "a certain model runs at a certain thinking level" is enforced.
#
# This drives the exact artifacts /onboard writes when the user picks "Pin and
# enforce": a routing file carrying "enforceEffort": true, plus effort-low /
# effort-medium / effort-high agent definitions in the scope's .claude/agents/.
# The plugin itself ships NO named agents (precedent: commit 8d9d82b), so these
# are created here the same way onboarding creates them - keeping the definitions
# behind the opt-in instead of costing every install unconditionally.
#
# Complements test-effort-routing-hook.sh, which covers the decision branches
# with synthetic fixtures. This one proves the two dials are enforced
# INDEPENDENTLY through the real opt-in artifacts: wrong model with right effort
# blocks, right model with wrong effort blocks, right model with no effort pinned
# blocks.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/pre-agent-model-routing"
WORK=$(mktemp -d)
FAILED=0
# shellcheck disable=SC2064
trap "rm -rf '$WORK'" EXIT

echo "=== Test: effort enforcement end-to-end (onboarding-written artifacts) ==="
echo ""

mkdir -p "$WORK/project/docs/superpowers" "$WORK/home/.claude/agents"
printf '%s\n' '{"mechanical":"haiku","standard":"sonnet","frontier":"inherit","effort":{"mechanical":"low","standard":"medium","frontier":"inherit"},"enforceEffort":true}' \
    > "$WORK/project/docs/superpowers/model-routing.json"

# The three definitions /onboard writes. No model: key by design - the model
# travels on the Agent call and is enforced separately, so the dials stay
# independent. Body kept minimal; only the frontmatter is under test here.
for lvl in low medium high; do
    {
        printf -- '---\n'
        printf 'name: effort-%s\n' "$lvl"
        printf 'description: Implementer pinned at %s thinking effort. Model comes from the dispatch.\n' "$lvl"
        printf 'effort: %s\n' "$lvl"
        printf 'tools: Read, Write, Edit, Bash, Glob, Grep\n'
        printf -- '---\n\nYou execute one plan task exactly as specified.\n'
    } > "$WORK/home/.claude/agents/effort-$lvl.md"
done

# Transcript: one in_progress task at tier "mechanical" (-> model haiku, effort low).
{
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu1","name":"TaskCreate","input":{"subject":"Task 1: mechanical work","description":"**Goal:** x\n\n```json:metadata\n{\"modelTier\":\"mechanical\",\"files\":[],\"verifyCommand\":\"true\",\"acceptanceCriteria\":[]}\n```"}}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu1","content":"Task #1 created successfully"}]}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu2","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}'
} > "$WORK/t.jsonl"

# run <subagent_type|""> <model|"">  -> echoes hook exit code
run() {
    local ti='{"tool_name":"Agent","tool_input":{' rc
    [[ -n "$1" ]] && ti="$ti\"subagent_type\":\"$1\","
    [[ -n "$2" ]] && ti="$ti\"model\":\"$2\","
    ti="$ti\"prompt\":\"go\"},\"transcript_path\":\"$WORK/t.jsonl\",\"cwd\":\"$WORK/project\"}"
    printf '%s' "$ti" | env HOME="$WORK/home" \
        SUPERPOWERS_USERGATE_TRACE_LOG="$WORK/trace.log" \
        bash "$HOOK" >/dev/null 2>"$WORK/stderr"
    rc=$?
    echo "$rc"
}

assert() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label - expected exit=$expected, got exit=$actual"
        echo "         stderr: $(head -1 "$WORK/stderr" 2>/dev/null)"
        FAILED=$((FAILED + 1))
    fi
}

assert_stderr_contains() {
    local label="$1" needle="$2"
    if grep -qF "$needle" "$WORK/stderr" 2>/dev/null; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label - stderr missing: $needle"
        FAILED=$((FAILED + 1))
    fi
}

echo "Test 1: both dials correct"
assert "haiku + effort-low on a mechanical task -> allow" "0" "$(run effort-low haiku)"
echo ""

echo "Test 2: model dial - wrong model, correct effort"
assert "opus + effort-low -> block" "2" "$(run effort-low opus)"
assert_stderr_contains "block names the MODEL tier" "DOES NOT MATCH TASK MODEL TIER"
echo ""

echo "Test 3: effort dial - correct model, wrong effort"
assert "haiku + effort-high -> block" "2" "$(run effort-high haiku)"
assert_stderr_contains "block names the THINKING EFFORT" "DOES NOT MATCH TASK THINKING EFFORT"
echo ""

echo "Test 4: effort dial - correct model, nothing pins effort"
assert "haiku, no subagent_type -> block" "2" "$(run "" haiku)"
assert_stderr_contains "block points at an effort-pinned agent type" "effort-pinned agent type"
echo ""

echo "Test 5: definitions resolve from the scope /onboard writes to"
# If the user-level lookup regressed, effort would resolve to nothing and Test 1
# would block. Asserting it explicitly keeps the cause legible.
assert "user-level .claude/agents definition resolves -> allow" "0" "$(run effort-low haiku)"
echo ""

echo "Test 6: reviewer path - standard effort allowed while a mechanical task runs"
# Spec and code-quality reviewers run at the "standard" tier (effort medium)
# while their task is in_progress, so medium joins the allowed set alongside the
# task's own low. Mirrors the model side's reviewer union.
assert "sonnet + effort-medium reviewer on a mechanical task -> allow" "0" "$(run effort-medium sonnet)"
echo ""

echo "Test 7: enforcement is opt-in - no enforceEffort key means advisory"
printf '%s\n' '{"mechanical":"haiku","standard":"sonnet","frontier":"inherit"}' \
    > "$WORK/project/docs/superpowers/model-routing.json"
assert "wrong effort allowed when enforceEffort absent" "0" "$(run effort-high haiku)"
# And the model exemption these effort-only definitions used to enjoy is intact
# while enforcement is off - a violating model must NOT be blocked here.
assert "effort-only type keeps its model exemption when enforcement is off" "0" "$(run effort-low opus)"
echo ""

echo "=== Summary: $FAILED failure(s) ==="
[ "$FAILED" -eq 0 ] || exit 1
