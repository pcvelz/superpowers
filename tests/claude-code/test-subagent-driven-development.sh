#!/usr/bin/env bash
# Test: subagent-driven-development skill
# Verifies that the skill is loaded and follows correct workflow
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Test: subagent-driven-development skill ==="
echo ""

FAILED=0

# Batch 1: Skill identity, workflow ordering, plan reading (was tests 1, 2, 4)
echo "Batch 1: Skill identity and workflow..."
output=$(run_claude "About the subagent-driven-development skill: (1) What is it and what are its key steps? (2) What comes first: spec compliance review or code quality review? (3) How many times should the controller read the plan file, and when does this happen?" 90)

if ! assert_contains "$output" "subagent" "Skill is recognized"; then FAILED=$((FAILED + 1)); fi
if ! assert_order "$output" "spec.*compliance" "code.*quality" "Spec compliance before code quality"; then FAILED=$((FAILED + 1)); fi
if ! assert_contains "$output" "once\|one time\|single\|beginning\|start" "Read plan once"; then FAILED=$((FAILED + 1)); fi
echo ""

# Batch 2: Review process (was tests 3, 5, 6)
echo "Batch 2: Review process..."
output=$(run_claude "About review in the subagent-driven-development skill: (1) Does it require self-review and what should implementers check? (2) What is the spec compliance reviewer's attitude toward the implementer's report? (3) What happens if a reviewer finds issues - is it a one-time review or a loop?" 90)

if ! assert_contains "$output" "self.review\|self review" "Mentions self-review"; then FAILED=$((FAILED + 1)); fi
if ! assert_contains "$output" "not trust\|skeptical\|verify\|independent\|suspicious" "Reviewer is skeptical"; then FAILED=$((FAILED + 1)); fi
if ! assert_contains "$output" "loop\|again\|repeat\|until.*approved\|re.implement\|fix" "Review loops"; then FAILED=$((FAILED + 1)); fi
echo ""

# Batch 3: Task provision, prerequisites, branch safety (was tests 7, 8, 9)
echo "Batch 3: Task provision and prerequisites..."
output=$(run_claude "About the subagent-driven-development skill: (1) How does the controller provide task information to the implementer subagent - via file or directly in the prompt? (2) What prerequisite workflow skills are required before using it? (3) Is it okay to start implementation directly on the main branch?" 90)

if ! assert_contains "$output" "provide\|full.*text\|paste\|include\|directly\|prompt" "Provides text directly"; then FAILED=$((FAILED + 1)); fi
if ! assert_contains "$output" "worktree" "Mentions worktree requirement"; then FAILED=$((FAILED + 1)); fi
if ! assert_contains "$output" "worktree\|feature.*branch\|not.*main\|never.*main\|don't.*main" "Warns against main branch"; then FAILED=$((FAILED + 1)); fi
echo ""

if [ $FAILED -gt 0 ]; then
    echo "=== FAILED: $FAILED assertion(s) failed ==="
    exit 1
fi

echo "=== All subagent-driven-development skill tests passed ==="
