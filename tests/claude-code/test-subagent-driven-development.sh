#!/usr/bin/env bash
# Test: subagent-driven-development skill
# Verifies that the skill is loaded and follows correct workflow
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Test: subagent-driven-development skill ==="
echo ""

# Test 1: Verify skill can be loaded
echo "Test 1: Skill loading..."

output=$(run_claude "What is the subagent-driven-development skill? Describe its key steps briefly." 120)

if assert_contains "$output" "subagent-driven-development\|Subagent-Driven Development\|Subagent Driven" "Skill is recognized"; then
    : # pass
else
    exit 1
fi

if assert_contains "$output" "Load Plan\|load plan\|[Rr]ead.*plan\|[Ee]xtract.*task\|[Pp]ull.*task\|[Pp]arse.*plan" "Mentions loading plan"; then
    : # pass
else
    exit 1
fi

echo ""

# Test 2: Verify skill describes correct workflow order
echo "Test 2: Workflow ordering..."

output=$(run_claude "In the subagent-driven-development skill, what comes first: spec compliance review or code quality review? Be specific about the order." 120)

if assert_order "$output" "spec.*compliance" "code.*quality" "Spec compliance before code quality"; then
    : # pass
else
    exit 1
fi

echo ""

# Test 3: Verify self-review is mentioned
echo "Test 3: Self-review requirement..."

output=$(run_claude "Does the subagent-driven-development skill require implementers to do self-review? What should they check?" 120)

if assert_contains "$output" "self-review\|self review" "Mentions self-review"; then
    : # pass
else
    exit 1
fi

if assert_contains "$output" "completeness\|Completeness\|complete\|fully implement\|nothing.*miss\|didn.t miss\|missed.*requirement\|missed.*spec\|everything.*implement\|all.*requirement\|edge case" "Checks completeness"; then
    : # pass
else
    exit 1
fi

echo ""

# Test 4: Verify plan is read once
echo "Test 4: Plan reading efficiency..."

output=$(run_claude "In subagent-driven-development, how many times should the controller read the plan file? When does this happen?" 120)

if assert_contains "$output" "once\|one time\|single\|only.*read\|read.*only\|just.*one\|one.*read\|single.*read\|read.*plan.*one" "Read plan once"; then
    : # pass
else
    exit 1
fi

if assert_contains "$output" "Step 1\|beginning\|start\|Load Plan\|upfront\|up front\|first\|initial\|outset\|before.*dispatch\|before.*subagent\|extract.*task" "Read at beginning"; then
    : # pass
else
    exit 1
fi

echo ""

# Test 5: Verify spec compliance reviewer is skeptical
echo "Test 5: Spec compliance reviewer mindset..."

output=$(run_claude "What is the spec compliance reviewer's attitude toward the implementer's report in subagent-driven-development?" 120 "Read,Glob,Grep")

if assert_contains "$output" "not trust\|don.t trust\|skeptical\|skeptic\|verif.*independent\|independent.*verif\|suspicious\|distrust\|doubt\|question.*claim\|don.t.*take.*word\|not.*take.*word\|not.*sufficient\|necessary but not\|replace.*actual.*review\|not replace\|close enough.*reject\|reject.*close enough" "Reviewer is skeptical"; then
    : # pass
else
    exit 1
fi

if assert_contains "$output" "read.*code\|reads.*code\|read.*actual\|inspect.*code\|inspects.*code\|verif.*code\|examin.*code\|review.*code\|check.*code\|actual.*implementation\|implementation.*code\|code.*inspection\|matches.*spec\|code.*match" "Reviewer reads code"; then
    : # pass
else
    exit 1
fi

echo ""

# Test 6: Verify review loops
echo "Test 6: Review loop requirements..."

output=$(run_claude "In subagent-driven-development, what happens if a reviewer finds issues? Is it a one-time review or a loop?" 120)

if assert_contains "$output" "loop\|again\|repeat\|iterat\|re-review\|re.review\|review.*again\|until.*approv\|until.*compliant\|until.*pass\|until.*clean\|cycle\|back.*forth" "Review loops mentioned"; then
    : # pass
else
    exit 1
fi

if assert_contains "$output" "implementer.*fix\|fix.*issue\|fix.*problem\|fix.*gap\|address.*issue\|resolve.*issue\|correct.*issue\|same.*subagent.*fix\|fixes them" "Implementer fixes issues"; then
    : # pass
else
    exit 1
fi

echo ""

# Test 7: Verify full task text is provided
echo "Test 7: Task context provision..."

output=$(run_claude "In subagent-driven-development, how does the controller provide task information to the implementer subagent? Does it make them read a file or provide it directly?" 120)

if assert_contains "$output" "provide.*directly\|directly.*provide\|full.*text\|full text\|paste\|include.*prompt\|in.*the.*prompt\|inline\|embed\|pass.*directly\|provide.*full\|provide.*complete\|complete.*text\|provides.*it\|controller.*provide" "Provides text directly"; then
    : # pass
else
    exit 1
fi

if assert_not_contains "$output" "subagent.*should.*read.*file\|makes.*subagent.*read\|instruct.*subagent.*read.*file\|tell.*subagent.*read.*file" "Doesn't make subagent read file"; then
    : # pass
else
    exit 1
fi

echo ""

# Test 8: Verify worktree requirement
echo "Test 8: Worktree requirement..."

output=$(run_claude "What workflow skills are required before using subagent-driven-development? List any prerequisites or required skills." 120)

if assert_contains "$output" "using-git-worktrees\|worktree" "Mentions worktree requirement"; then
    : # pass
else
    exit 1
fi

echo ""

# Test 9: Verify main branch warning
echo "Test 9: Main branch red flag..."

output=$(run_claude "In subagent-driven-development, is it okay to start implementation directly on the main branch?" 120)

if assert_contains "$output" "worktree\|feature.*branch\|not.*main\|never.*main\|avoid.*main\|don't.*main\|consent\|permission" "Warns against main branch"; then
    : # pass
else
    exit 1
fi

echo ""

echo "=== All subagent-driven-development skill tests passed ==="
