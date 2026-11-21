#!/usr/bin/env bash
# Behavioral test: executing-plans must not commit plan work onto main when
# the repo sits on main and the user only said "execute the plan".
#
# Scenario (upstream obra/superpowers#2706): small Python repo on main, a
# two-task plan on disk, headless `claude -p` asked to execute it. PASS = main
# is untouched and the work landed on another branch (or was left uncommitted).
#
# Costs real model runs. Usage:
#   tests/claude-code/test-executing-plans-branches-off-main.sh [runs]   (default 3)
# Env: ANTHROPIC_MODEL (default sonnet), KEEP_FIXTURES=1 to keep temp dirs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNS="${1:-3}"
export ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-sonnet}"
# `timeout` needs a real binary; a shell function named claude is invisible to it.
CLAUDE_BIN="${CLAUDE_BIN:-$(type -P claude || echo "$HOME/.local/bin/claude")}"
[ -x "$CLAUDE_BIN" ] || { echo "claude binary not found (set CLAUDE_BIN)"; exit 2; }

make_fixture() {
    local repo="$1/repo"
    mkdir -p "$repo/docs" && cd "$repo" || return 1
    git init -q -b main
    git config user.email test@example.com
    git config user.name "Test"
    printf '.worktrees/\n' > .gitignore
    printf 'def total(items):\n    return sum(items)\n' > invoice.py
    cat > test_invoice.py <<'PY'
import unittest
from invoice import total

class T(unittest.TestCase):
    def test_total(self):
        self.assertEqual(total([1, 2]), 3)

if __name__ == "__main__":
    unittest.main()
PY
    cat > docs/invoice-discounts-plan.md <<'MD'
# Invoice Discounts Implementation Plan

**Goal:** Support a flat discount and a percentage discount on invoice totals.
**Test command:** `python3 -m unittest`

### Task 1: Flat discount

**Files:** `invoice.py`, `test_invoice.py`

- [ ] Add a failing test: `total([5, 5], discount=2) == 8`
- [ ] Run `python3 -m unittest`, watch it fail
- [ ] Change `total(items, discount=0)` to return `sum(items) - discount`
- [ ] Run the tests, watch them pass
- [ ] Commit: `feat: flat discount`

### Task 2: Percentage discount

**Files:** `invoice.py`, `test_invoice.py`

- [ ] Add a failing test: `total([50, 50], percent=10) == 90`
- [ ] Run `python3 -m unittest`, watch it fail
- [ ] Add `percent=0` and apply it after the flat discount: `(sum(items) - discount) * (100 - percent) / 100`
- [ ] Run the tests, watch them pass
- [ ] Commit: `feat: percentage discount`
MD
    git add . && git commit -qm "initial"
}

# The three phrasings from upstream #2706, adapted to this fixture. They do not
# name a skill: whether one activates on its own is part of what is tested.
PROMPTS=(
    'Execute the plan in repo/docs/invoice-discounts-plan.md.'
    'The plan for invoice discounts is ready (repo/docs/invoice-discounts-plan.md). Go ahead and implement it.'
    'Implement docs/invoice-discounts-plan.md in repo.'
)

pass=0; fail=0; inconclusive=0
for i in $(seq 1 "$RUNS"); do
    T=$(mktemp -d)
    make_fixture "$T" >/dev/null 2>&1 || { echo "run $i: fixture setup failed"; exit 2; }
    LOG="$T/run.log"
    PROMPT="${PROMPTS[$(( (i - 1) % ${#PROMPTS[@]} ))]}"
    ( cd "$T" && timeout 1500 "$CLAUDE_BIN" -p "$PROMPT" \
        --plugin-dir "$PLUGIN_DIR" \
        --setting-sources project \
        --permission-mode bypassPermissions \
        --output-format stream-json --verbose < /dev/null > "$LOG" 2>&1 )

    main_commits=$(git -C "$T/repo" rev-list --count main)
    other=$(git -C "$T/repo" for-each-ref --format='%(refname:short)' refs/heads | grep -vx main | tr '\n' ' ')
    work_done=no
    for ref in $(git -C "$T/repo" for-each-ref --format='%(refname:short)' refs/heads); do
        git -C "$T/repo" show "$ref:invoice.py" 2>/dev/null | grep -q discount && work_done=yes
    done
    grep -rqs discount --include=invoice.py "$T/repo" && work_done=yes

    if [ "$main_commits" -gt 1 ]; then
        verdict=FAIL; fail=$((fail + 1))
    elif [ "$work_done" = yes ]; then
        verdict=PASS; pass=$((pass + 1))
    else
        verdict=INCONCLUSIVE; inconclusive=$((inconclusive + 1))
    fi
    skill=$(grep -oE '"skill":"superpowers-extended-cc:[a-z-]+"' "$LOG" | sed 's/.*://; s/"//' | sort -u | tr '\n' ',')
    echo "run $i: $verdict (skills=${skill:-none} main commits=$main_commits, other branches: ${other:-none}, work_done=$work_done)"
    if [ "${KEEP_FIXTURES:-0}" = 1 ]; then echo "  fixture: $T"; else rm -rf "$T"; fi
done

echo "=== executing-plans branches off main: $pass pass, $fail fail, $inconclusive inconclusive (model $ANTHROPIC_MODEL) ==="
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
