#!/usr/bin/env bash
# Test: pre-taskcreate-commit-strategy hook - synthetic inputs, no LLM.
# Covers all decision branches: dormancy, plan-shaping, commit-step detection,
# the final-commit-task exemption, kill switch, /bin/bash canary.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/pre-taskcreate-commit-strategy"
WORK=$(mktemp -d)
export SUPERPOWERS_USERGATE_TRACE_LOG="$WORK/trace.log"
FAILED=0
# shellcheck disable=SC2064
trap "rm -rf '$WORK'" EXIT

echo "=== Test: pre-taskcreate-commit-strategy ==="
echo ""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

assert() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label - expected exit=$expected, got exit=$actual"
        echo "         stderr: $(head -3 "$WORK/stderr" 2>/dev/null | tr '\n' ' ')"
        FAILED=$((FAILED + 1))
    fi
}

assert_stderr_contains() {
    local label="$1" needle="$2"
    if grep -qF "$needle" "$WORK/stderr" 2>/dev/null; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label - stderr missing: $needle"
        echo "         actual stderr:"
        head -10 "$WORK/stderr" 2>/dev/null | sed 's/^/           /'
        FAILED=$((FAILED + 1))
    fi
}

run_hook() {
    # Usage: run_hook <json-input> [env-overrides...]
    # HOME is isolated by default so a real ~/.claude/superpowers/workflow.json
    # on the machine can't pollute "no workflow file" tests.
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

DESC_CLEAN=$'**Goal:** implement the widget.\n\n**Files:**\n- Modify: `src/widget.py`\n\n**Acceptance Criteria:**\n- [ ] widget renders\n\n**Verify:** `pytest tests/ -v`\n\n**Steps:**\n- [ ] **Step 1: Write the failing test**\n- [ ] **Step 2: Implement**\n\n```json:metadata\n{"files":["src/widget.py"],"verifyCommand":"pytest tests/ -v","acceptanceCriteria":["renders"],"modelTier":"mechanical"}\n```'
DESC_STEP_COMMIT=$'**Goal:** implement the widget.\n\n**Steps:**\n- [ ] **Step 1: Write the failing test**\n- [ ] **Step 2: Implement**\n- [ ] **Step 3: Commit**\n\n```bash\ngit add src/widget.py\ngit commit -m "feat: add widget"\n```\n\n```json:metadata\n{"files":["src/widget.py"],"verifyCommand":"true","acceptanceCriteria":[],"modelTier":"mechanical"}\n```'
DESC_GIT_COMMIT=$'**Goal:** migrate the files.\n\n**Acceptance Criteria:**\n- [ ] files moved\n\n**Verify:** `ls new/`\n\n**Steps:**\n- [ ] **Step 1: Move files**\n- [ ] **Step 2: Commit** - repo files via git commit -m "move".'
DESC_NO_COMMIT_REWORDED=$'**Goal:** migrate the files.\n\n**Acceptance Criteria:**\n- [ ] files moved\n\n**Verify:** `ls new/`\n\n**Steps:**\n- [ ] **Step 1: Move files**\n- [ ] **Step 2: No commit** - all migration files are committed together in the final task (at-end strategy).'
DESC_ADHOC_COMMIT='unstick the repo: run git commit with the staged hotfix and push'
DESC_HEADERS_NO_FENCE=$'**Goal:** do the thing.\n\n**Acceptance Criteria:**\n- [ ] it works\n\n**Steps:**\n- [ ] **Step 5: Commit**\n\n```bash\ngit commit -m "done"\n```'

# ---------------------------------------------------------------------------
# Project setups
# ---------------------------------------------------------------------------

# Project WITH at-end workflow file.
PROJ="$WORK/project"
mkdir -p "$PROJ/docs/superpowers"
cat > "$PROJ/docs/superpowers/workflow.json" <<'EOF'
{"commitStrategy": "at-end"}
EOF

# Project WITHOUT workflow file.
NOPROJ="$WORK/noworkflow"
mkdir -p "$NOPROJ"

# Project with per-task (explicit default).
PERTASK="$WORK/pertask"
mkdir -p "$PERTASK/docs/superpowers"
cat > "$PERTASK/docs/superpowers/workflow.json" <<'EOF'
{"commitStrategy": "per-task"}
EOF

# Project with unparseable workflow file.
BADPROJ="$WORK/badproject"
mkdir -p "$BADPROJ/docs/superpowers"
printf 'this is not json\n' > "$BADPROJ/docs/superpowers/workflow.json"

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

echo "Test 1: no workflow file → allow (dormant, vanilla)"
INPUT=$(make_input "TaskCreate" "Task 1: Widget" "$DESC_STEP_COMMIT" "$NOPROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 2: non-TaskCreate tool → allow"
INPUT=$(make_input "Bash" "irrelevant" "$DESC_STEP_COMMIT" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 3: at-end + plan task with '**Step N: Commit**' heading → block"
INPUT=$(make_input "TaskCreate" "Task 1: Widget" "$DESC_STEP_COMMIT" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
assert_stderr_contains "headline present" "PER-TASK COMMIT STEP"
assert_stderr_contains "names the final task" "Commit the full implementation"
echo ""

echo "Test 4: at-end + plan task with bare git commit in steps (no fence) → block"
INPUT=$(make_input "TaskCreate" "Migrate the files" "$DESC_GIT_COMMIT" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
echo ""

echo "Test 5: at-end + plan task with 'No commit' reworded steps → allow"
INPUT=$(make_input "TaskCreate" "Task 1: Widget" "$DESC_NO_COMMIT_REWORDED" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 6: at-end + clean plan task (fence, no commit steps) → allow"
INPUT=$(make_input "TaskCreate" "Task 1: Widget" "$DESC_CLEAN" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 7: at-end + final 'Commit the full implementation' task with git commit → allow (exemption)"
INPUT=$(make_input "TaskCreate" "Task 12: Commit the full implementation" "$DESC_GIT_COMMIT" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 8: at-end + template headers without fence + commit step → block"
INPUT=$(make_input "TaskCreate" "Some component work" "$DESC_HEADERS_NO_FENCE" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
echo ""

echo "Test 9: at-end + ad-hoc (non-plan-shaped) task mentioning git commit → allow"
INPUT=$(make_input "TaskCreate" "unstick the repo" "$DESC_ADHOC_COMMIT" "$PROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 10: commitStrategy=per-task → allow (explicit default)"
INPUT=$(make_input "TaskCreate" "Task 1: Widget" "$DESC_STEP_COMMIT" "$PERTASK")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 11: unparseable workflow file → allow (fail-open)"
INPUT=$(make_input "TaskCreate" "Task 1: Widget" "$DESC_STEP_COMMIT" "$BADPROJ")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 12: SUPERPOWERS_WORKFLOW_GUARD=0 → allow (kill switch)"
INPUT=$(make_input "TaskCreate" "Task 1: Widget" "$DESC_STEP_COMMIT" "$PROJ")
rc=$(run_hook "$INPUT" SUPERPOWERS_WORKFLOW_GUARD=0)
assert "exit code" "0" "$rc"
echo ""

echo "Test 13: user-level workflow file (no project file) → enforce"
FAKEHOME="$WORK/fakehome"
mkdir -p "$FAKEHOME/.claude/superpowers"
cp "$PROJ/docs/superpowers/workflow.json" "$FAKEHOME/.claude/superpowers/workflow.json"
INPUT=$(make_input "TaskCreate" "Task 1: Widget" "$DESC_STEP_COMMIT" "$NOPROJ")
rc=$(run_hook "$INPUT" HOME="$FAKEHOME")
assert "commit step blocks via user-level file" "2" "$rc"
INPUT=$(make_input "TaskCreate" "Task 1: Widget" "$DESC_CLEAN" "$NOPROJ")
rc=$(run_hook "$INPUT" HOME="$FAKEHOME")
assert "clean task allows via user-level file" "0" "$rc"
echo ""

echo "Test 14: project file wins over user-level file (no merge)"
# Project per-task + user-level at-end → project wins → allow.
INPUT=$(make_input "TaskCreate" "Task 1: Widget" "$DESC_STEP_COMMIT" "$PERTASK")
rc=$(run_hook "$INPUT" HOME="$FAKEHOME")
assert "per-task project file overrides at-end user file" "0" "$rc"
echo ""

echo "Test 15: /bin/bash canary - block path must work on stock macOS bash 3.2"
INPUT=$(make_input "TaskCreate" "Task 1: Widget" "$DESC_STEP_COMMIT" "$PROJ")
_rc=0
env HOME="$ISOLATED_HOME" /bin/bash "$HOOK" >/dev/null 2>"$WORK/stderr" <<< "$INPUT" && _rc=$? || _rc=$?
assert "commit step blocks under /bin/bash" "2" "$_rc"
echo ""

echo "Test 16: near-miss commit headings → block; continuing word → allow"
DESC_COMMIT_CHANGES=$'**Goal:** ship it.\n\n**Acceptance Criteria:**\n- [ ] shipped\n\n**Steps:**\n- [ ] **Step 3: Commit changes**\n  - Stage and record the widget work.'
INPUT=$(make_input "TaskCreate" "Task 2: Ship widget" "$DESC_COMMIT_CHANGES" "$PROJ")
rc=$(run_hook "$INPUT")
assert "'Commit changes' heading blocks" "2" "$rc"
DESC_COMMIT_PUSH=$'**Goal:** ship it.\n\n**Acceptance Criteria:**\n- [ ] shipped\n\n**Steps:**\n- [ ] **Step 3: Commit & push**\n  - Save the work to version control.'
INPUT=$(make_input "TaskCreate" "Task 2: Ship widget" "$DESC_COMMIT_PUSH" "$PROJ")
rc=$(run_hook "$INPUT")
assert "'Commit & push' heading blocks" "2" "$rc"
DESC_COMMITMENT=$'**Goal:** review pledges.\n\n**Acceptance Criteria:**\n- [ ] reviewed\n\n**Steps:**\n- [ ] **Step 2: Commitment ledger review**\n  - Read the ledger.'
INPUT=$(make_input "TaskCreate" "Task 2: Ledger" "$DESC_COMMITMENT" "$PROJ")
rc=$(run_hook "$INPUT")
assert "'Commitment ...' heading allows (word continues)" "0" "$rc"
echo ""

echo "Test 17: exemption is anchored to the subject, not a substring"
INPUT=$(make_input "TaskCreate" "Step 2: commit the full implementation of the widget feature, then continue" "$DESC_STEP_COMMIT" "$PROJ")
rc=$(run_hook "$INPUT")
assert "verbose subject containing the phrase is NOT exempt" "2" "$rc"
INPUT=$(make_input "TaskCreate" "Commit the full implementation" "$DESC_GIT_COMMIT" "$PROJ")
rc=$(run_hook "$INPUT")
assert "bare verbatim subject stays exempt" "0" "$rc"
echo ""

echo "Test 18: backtick-quoted git commit in prose → allow; bare → block"
DESC_QUOTED_PROSE=$'**Goal:** document the at-end rule.\n\n**Acceptance Criteria:**\n- [ ] doc updated\n\n**Steps:**\n- [ ] **Step 1: Update the doc**\n  - Explain that tasks must never run `git commit` themselves under at-end.'
INPUT=$(make_input "TaskCreate" "Task 4: Docs" "$DESC_QUOTED_PROSE" "$PROJ")
rc=$(run_hook "$INPUT")
assert "backtick-quoted git commit reference allows" "0" "$rc"
DESC_BARE_PROSE=$'**Goal:** document the at-end rule.\n\n**Acceptance Criteria:**\n- [ ] doc updated\n\n**Steps:**\n- [ ] **Step 1: Wrap up**\n  - Then run git commit -m done to finish.'
INPUT=$(make_input "TaskCreate" "Task 4: Docs" "$DESC_BARE_PROSE" "$PROJ")
rc=$(run_hook "$INPUT")
assert "bare git commit instruction still blocks" "2" "$rc"
echo ""

echo "=== Summary: $FAILED failure(s) ==="
exit "$FAILED"
