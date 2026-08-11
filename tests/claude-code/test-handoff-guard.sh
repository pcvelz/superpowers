#!/usr/bin/env bash
# Test: pre-askuser-handoff-guard hook — synthetic transcripts, no LLM.
# Covers all decision branches: armed via Skill tool_use, armed via user-message
# invocation (live failure mode — content as string AND as text-block list),
# compliant two-option handoff → allow, wrong options → block, CLARIFICATION
# token → allow, disarmed by later execution Skill → allow, prior compliant
# handoff → allow, no TaskCreate after arm → allow, no routing file → allow,
# kill switch → allow, non-AskUserQuestion tool → allow,
# missing/garbage transcript → allow.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/pre-askuser-handoff-guard"
WORK=$(mktemp -d)
export SUPERPOWERS_USERGATE_TRACE_LOG="$WORK/trace.log"
FAILED=0
# shellcheck disable=SC2064
trap "rm -rf '$WORK'" EXIT

echo "=== Test: pre-askuser-handoff-guard ==="
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
        FAILED=$((FAILED + 1))
    fi
}

run_hook() {
    # Usage: run_hook <json-input> [env-overrides...]
    # Runs hook, discards stdout (ALLOW JSON), captures stderr.
    # Prints exit code on stdout.
    # HOME is isolated so a real ~/.claude/superpowers/model-routing.json
    # can't pollute "no routing file" tests.
    local input="$1" _rc; shift
    env HOME="$ISOLATED_HOME" "$@" bash "$HOOK" >/dev/null 2>"$WORK/stderr" <<< "$input" && _rc=$? || _rc=$?
    echo "$_rc"
}
ISOLATED_HOME="$WORK/isolated-home"
mkdir -p "$ISOLATED_HOME"

# Routing file used by most tests (presence triggers the guard).
ROUTING_DIR="$WORK/project/docs/superpowers"
mkdir -p "$ROUTING_DIR"
cat > "$ROUTING_DIR/model-routing.json" <<'EOF'
{"mechanical":"haiku","standard":"sonnet","frontier":"inherit"}
EOF

# ---------------------------------------------------------------------------
# Transcripts
# ---------------------------------------------------------------------------

# Transcript: writing-plans invoked via Skill tool_use + TaskCreate after.
cat > "$WORK/armed-via-skill.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"superpowers-extended-cc:writing-plans"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Task 1","description":"**Goal:** do thing\n```json:metadata\n{\"modelTier\":\"mechanical\"}\n```"}}]}}
EOF

# Transcript: writing-plans invoked via user message (slash command injection) — content as string.
# This is the live failure mode from session 2013ea56.
cat > "$WORK/armed-via-user-string.jsonl" <<'EOF'
{"type":"user","message":{"content":"superpowers-extended-cc:writing-plans skill"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Task 1","description":"**Goal:** do thing\n```json:metadata\n{\"modelTier\":\"mechanical\"}\n```"}}]}}
EOF

# Transcript: writing-plans invoked via user message — content as text-block list.
# Path passed as argv (not embedded in the source): MSYS path conversion on
# Windows rewrites argv only, so an inline '$WORK/...' string is unopenable
# for native Windows Python.
python3 -c "
import json, sys
lines = [
    {\"type\": \"user\", \"message\": {\"content\": [{\"type\": \"text\", \"text\": \"superpowers-extended-cc:writing-plans skill\"}]}},
    {\"type\": \"assistant\", \"message\": {\"content\": [{\"type\": \"tool_use\", \"name\": \"TaskCreate\", \"input\": {\"subject\": \"Task 1\", \"description\": \"Goal: do thing\"}}]}}
]
with open(sys.argv[1], 'w') as f:
    for l in lines:
        f.write(json.dumps(l) + '\n')
" "$WORK/armed-via-user-blocks.jsonl"

# Transcript: armed, then disarmed by later subagent-driven-development Skill invocation.
cat > "$WORK/disarmed-by-execution.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"superpowers-extended-cc:writing-plans"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Task 1","description":"goal"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"superpowers-extended-cc:subagent-driven-development"}}]}}
EOF

# Transcript: armed, then disarmed by a prior compliant AskUserQuestion.
python3 -c "
import json, sys
lines = [
    {\"type\": \"assistant\", \"message\": {\"content\": [{\"type\": \"tool_use\", \"name\": \"Skill\", \"input\": {\"skill\": \"superpowers-extended-cc:writing-plans\"}}]}},
    {\"type\": \"assistant\", \"message\": {\"content\": [{\"type\": \"tool_use\", \"name\": \"TaskCreate\", \"input\": {\"subject\": \"Task 1\", \"description\": \"goal\"}}]}},
    {\"type\": \"assistant\", \"message\": {\"content\": [{\"type\": \"tool_use\", \"name\": \"AskUserQuestion\", \"input\": {
        \"questions\": [{
            \"question\": \"Plan complete and saved. How would you like to execute it?\",
            \"header\": \"Execution\",
            \"options\": [
                {\"label\": \"Subagent-Driven (this session)\", \"description\": \"fast\"},
                {\"label\": \"Parallel Session (separate)\", \"description\": \"worktree\"}
            ]
        }]
    }}]}}
]
with open(sys.argv[1], 'w') as f:
    for l in lines:
        f.write(json.dumps(l) + '\n')
" "$WORK/disarmed-by-prior-handoff.jsonl"

# Transcript: writing-plans arm but no TaskCreate after it.
cat > "$WORK/arm-no-taskcreate.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"superpowers-extended-cc:writing-plans"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}
EOF

# No writing-plans signal at all.
cat > "$WORK/no-arm.jsonl" <<'EOF'
{"type":"user","message":{"content":"Hello"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Unrelated task","description":"goal"}}]}}
EOF

# Garbage transcript.
cat > "$WORK/garbage.jsonl" <<'EOF'
this is not json at all
{also bad}
EOF

# Empty transcript.
: > "$WORK/empty.jsonl"

# ---------------------------------------------------------------------------
# AskUserQuestion inputs
# ---------------------------------------------------------------------------

# Compliant handoff (two correct labels).
make_compliant_input() {
    local transcript="$1" cwd="${2:-$WORK/project}"
    python3 -c "
import json, sys
inp = {
    'tool_name': 'AskUserQuestion',
    'tool_input': {
        'questions': [{
            'question': 'Plan complete and saved to docs/superpowers/plans/2026-06-10-foo.md. How would you like to execute it?',
            'header': 'Execution',
            'options': [
                {'label': 'Subagent-Driven (this session)', 'description': 'I dispatch fresh subagent per task, review between tasks, fast iteration'},
                {'label': 'Parallel Session (separate)', 'description': 'Open new session in worktree with executing-plans, batch execution with checkpoints'}
            ]
        }]
    },
    'transcript_path': sys.argv[1],
    'cwd': sys.argv[2]
}
print(json.dumps(inp))
" "$transcript" "$cwd"
}

# Wrong options (improvised custom menu — the live failure pattern).
make_wrong_options_input() {
    local transcript="$1" cwd="${2:-$WORK/project}"
    python3 -c "
import json, sys
inp = {
    'tool_name': 'AskUserQuestion',
    'tool_input': {
        'questions': [{
            'question': 'How would you like to proceed?',
            'header': 'Execution Plan',
            'options': [
                {'label': 'Phase 1: Foundation (Tasks 1-5)', 'description': 'Start with core'},
                {'label': 'Phase 2: Integration (Tasks 6-12)', 'description': 'After phase 1'},
                {'label': 'Phase 3: Polish (Tasks 13-19)', 'description': 'Final phase'},
                {'label': 'All phases sequentially', 'description': 'Run everything'}
            ]
        }]
    },
    'transcript_path': sys.argv[1],
    'cwd': sys.argv[2]
}
print(json.dumps(inp))
" "$transcript" "$cwd"
}

# CLARIFICATION token in question.
make_clarification_input() {
    local transcript="$1" cwd="${2:-$WORK/project}"
    python3 -c "
import json, sys
inp = {
    'tool_name': 'AskUserQuestion',
    'tool_input': {
        'questions': [{
            'question': 'CLARIFICATION: Should the database migrations run before or after seeding?',
            'header': 'Migration order',
            'options': [
                {'label': 'Before seeding'},
                {'label': 'After seeding'}
            ]
        }]
    },
    'transcript_path': sys.argv[1],
    'cwd': sys.argv[2]
}
print(json.dumps(inp))
" "$transcript" "$cwd"
}

# Non-AskUserQuestion tool.
make_bash_input() {
    local transcript="$1" cwd="${2:-$WORK/project}"
    python3 -c "
import json, sys
inp = {
    'tool_name': 'Bash',
    'tool_input': {'command': 'ls'},
    'transcript_path': sys.argv[1],
    'cwd': sys.argv[2]
}
print(json.dumps(inp))
" "$transcript" "$cwd"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

echo "Test 1: no routing file → allow (dormant)"
INPUT=$(make_wrong_options_input "$WORK/armed-via-skill.jsonl" "$WORK")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 2: kill switch SUPERPOWERS_ROUTING_GUARD=0 → allow"
INPUT=$(make_wrong_options_input "$WORK/armed-via-skill.jsonl")
rc=$(run_hook "$INPUT" SUPERPOWERS_ROUTING_GUARD=0)
assert "exit code" "0" "$rc"
echo ""

echo "Test 3: non-AskUserQuestion tool → allow"
INPUT=$(make_bash_input "$WORK/armed-via-skill.jsonl")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 4: missing transcript → allow (fail-open)"
INPUT=$(python3 -c "
import json
print(json.dumps({'tool_name': 'AskUserQuestion', 'tool_input': {'questions': [{'question': 'x', 'options': [{'label': 'a'}]}]}, 'transcript_path': '/tmp/nonexistent-transcript-xyz.jsonl', 'cwd': '$WORK/project'}))
")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 5: garbage transcript → allow (fail-open)"
INPUT=$(make_wrong_options_input "$WORK/garbage.jsonl")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 6: no writing-plans signal → allow (not armed)"
INPUT=$(make_wrong_options_input "$WORK/no-arm.jsonl")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 7: writing-plans arm but no TaskCreate after it → allow (not armed)"
INPUT=$(make_wrong_options_input "$WORK/arm-no-taskcreate.jsonl")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 8: armed via Skill tool_use + wrong options → BLOCK"
INPUT=$(make_wrong_options_input "$WORK/armed-via-skill.jsonl")
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
assert_stderr_contains "headline present" "EXECUTION HANDOFF VIOLATION — WRONG AskUserQuestion STRUCTURE"
assert_stderr_contains "required YAML: option 1 label" "Subagent-Driven (this session)"
assert_stderr_contains "required YAML: option 2 label" "Parallel Session (separate)"
assert_stderr_contains "footer trace log" "Trace log:"
assert_stderr_contains "footer rationale" "docs/model-routing-flow.md"
echo ""

echo "Test 9: armed via Skill tool_use + correct two labels → allow"
INPUT=$(make_compliant_input "$WORK/armed-via-skill.jsonl")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 10: armed via user-message string (live failure mode) + wrong options → BLOCK"
INPUT=$(make_wrong_options_input "$WORK/armed-via-user-string.jsonl")
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
assert_stderr_contains "headline" "EXECUTION HANDOFF VIOLATION — WRONG AskUserQuestion STRUCTURE"
echo ""

echo "Test 11: armed via user-message string + correct two labels → allow"
INPUT=$(make_compliant_input "$WORK/armed-via-user-string.jsonl")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 12: armed via user-message text-block list + wrong options → BLOCK"
INPUT=$(make_wrong_options_input "$WORK/armed-via-user-blocks.jsonl")
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
assert_stderr_contains "headline (text-block path)" "EXECUTION HANDOFF VIOLATION — WRONG AskUserQuestion STRUCTURE"
echo ""

echo "Test 13: armed via user-message text-block list + correct labels → allow"
INPUT=$(make_compliant_input "$WORK/armed-via-user-blocks.jsonl")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 14: disarmed by later execution Skill invocation → allow"
INPUT=$(make_wrong_options_input "$WORK/disarmed-by-execution.jsonl")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 15: disarmed by prior compliant AskUserQuestion in transcript → allow"
INPUT=$(make_wrong_options_input "$WORK/disarmed-by-prior-handoff.jsonl")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 16: armed + CLARIFICATION token in question → allow (clarification escape)"
INPUT=$(make_clarification_input "$WORK/armed-via-skill.jsonl")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 17: block message contains required YAML header/option labels verbatim"
INPUT=$(make_wrong_options_input "$WORK/armed-via-skill.jsonl")
run_hook "$INPUT" >/dev/null || true
assert_stderr_contains "required YAML header" "header: \"Execution\""
assert_stderr_contains "required question text" "How would you like to execute it?"
assert_stderr_contains "subagent description in YAML" "fresh subagent per task"
assert_stderr_contains "parallel description in YAML" "executing-plans"
assert_stderr_contains "option 1 instruction" "Re-issue AskUserQuestion with exactly that structure"
assert_stderr_contains "option 2 instruction" "CLARIFICATION"
assert_stderr_contains "option 3 instruction" "SUPERPOWERS_ROUTING_GUARD=0"
echo ""

echo "Test 18: user-level routing file (no project file) → active"
FAKEHOME="$WORK/fakehome"
mkdir -p "$FAKEHOME/.claude/superpowers"
cp "$ROUTING_DIR/model-routing.json" "$FAKEHOME/.claude/superpowers/model-routing.json"
NOPROJ="$WORK/noproject"
mkdir -p "$NOPROJ"
INPUT=$(make_wrong_options_input "$WORK/armed-via-skill.jsonl" "$NOPROJ")
rc=$(run_hook "$INPUT" HOME="$FAKEHOME")
assert "violation blocks via user-level file" "2" "$rc"
rc=$(run_hook "$INPUT" HOME="$WORK")  # HOME with no .claude dir → dormant
assert "dormant when neither file exists" "0" "$rc"
echo ""

echo "Test 19: re-arm for a second plan — stale TaskCreate from plan 1 must NOT arm"
# Live false-block: plan 1 completes (arm → TaskCreate → compliant handoff),
# then writing-plans is re-invoked for a second plan. Before the second plan
# creates any tasks, a clarifying AskUserQuestion is legitimate — the
# TaskCreate from plan 1 must not count as "tasks created after arm".
cat > "$WORK/rearm-second-plan.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"superpowers-extended-cc:writing-plans"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Task 1","description":"goal"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[{"question":"Plan complete. How would you like to execute it?","options":[{"label":"Subagent-Driven (this session)"},{"label":"Parallel Session (separate)"}]}]}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"superpowers-extended-cc:writing-plans"}}]}}
EOF
INPUT=$(make_wrong_options_input "$WORK/rearm-second-plan.jsonl")
rc=$(run_hook "$INPUT")
assert "clarifying question in second plan cycle → allow" "0" "$rc"
# Once the second plan creates a task, the guard must arm again.
cat "$WORK/rearm-second-plan.jsonl" > "$WORK/rearm-with-taskcreate.jsonl"
cat >> "$WORK/rearm-with-taskcreate.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"Task 1 of plan 2","description":"goal"}}]}}
EOF
INPUT=$(make_wrong_options_input "$WORK/rearm-with-taskcreate.jsonl")
rc=$(run_hook "$INPUT")
assert "wrong menu after second plan's TaskCreate → block" "2" "$rc"
echo ""

echo "Test 20: invalid-UTF-8 byte in transcript poisons only its own line"
# Regression: text-mode readlines() threw UnicodeDecodeError for the WHOLE
# file on one bad byte, silently disarming the guard for the session.
{ printf '\x80 corrupt line\n'; cat "$WORK/armed-via-skill.jsonl"; } > "$WORK/badutf8-armed.jsonl"
INPUT=$(make_wrong_options_input "$WORK/badutf8-armed.jsonl")
rc=$(run_hook "$INPUT")
assert "armed transcript with bad byte + wrong options → still block" "2" "$rc"
INPUT=$(make_compliant_input "$WORK/badutf8-armed.jsonl")
rc=$(run_hook "$INPUT")
assert "armed transcript with bad byte + compliant → allow" "0" "$rc"
echo ""

echo "Test 21: /bin/bash canary — block path must work on stock macOS bash 3.2"
# Claude Code invokes hooks through run-hook.cmd (exec bash), which on a
# stock Mac is 3.2 — where e.g. an IFS of \\x01 silently fails to split (CTLESC).
# One block scenario under /bin/bash catches any always-allow regression there.
INPUT=$(make_wrong_options_input "$WORK/armed-via-skill.jsonl")
_rc=0
env HOME="$ISOLATED_HOME" /bin/bash "$HOOK" >/dev/null 2>"$WORK/stderr" <<< "$INPUT" && _rc=$? || _rc=$?
assert "armed wrong-menu blocks under /bin/bash" "2" "$_rc"
echo ""

echo "=== Summary: $FAILED failure(s) ==="
exit "$FAILED"
