#!/usr/bin/env bash
# Test: Fork-specific invariants (deterministic, no LLM)
# Catches upstream drift: wrong plugin names, TodoWrite leaks, missing native tasks
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILED=0

echo "=== Test: Fork Validation ==="
echo ""

# 1. Plugin name must be superpowers-extended-cc in metadata
echo "Test 1: Plugin name consistency..."
NAME_FAIL=0
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
    if ! grep -q "superpowers-extended-cc" "$REPO_ROOT/$f"; then
        echo "  [FAIL] $f missing superpowers-extended-cc"
        NAME_FAIL=$((NAME_FAIL + 1))
    fi
done
if [ $NAME_FAIL -gt 0 ]; then
    FAILED=$((FAILED + NAME_FAIL))
else
    echo "  [PASS] Plugin name consistent"
fi

# 2. No TodoWrite/TodoRead references in skills (must be TaskCreate/TaskList)
#    Excludes references/ dirs (cross-platform tool mapping tables mention TodoWrite legitimately)
echo "Test 2: No legacy task references in skills..."
LEGACY=$(grep -rn "TodoWrite\|TodoRead" "$REPO_ROOT/skills/" --include="*.md" \
    | grep -v "/references/" \
    || true)
if [ -n "$LEGACY" ]; then
    echo "  [FAIL] Found TodoWrite/TodoRead in skills:"
    echo "$LEGACY"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] No legacy task references"
fi

# 3. Skill references use superpowers-extended-cc: prefix (not bare superpowers:)
echo "Test 3: Skill prefix consistency..."
BARE=$(grep -rn "superpowers:" "$REPO_ROOT/skills/" "$REPO_ROOT/commands/" "$REPO_ROOT/hooks/" 2>/dev/null \
    | grep -v "superpowers-extended-cc:" \
    | grep -v "superpowers-extended-cc" \
    | grep -v "obra/superpowers" \
    | grep -v "github.com" \
    | grep -v "\.git" \
    || true)
if [ -n "$BARE" ]; then
    echo "  [FAIL] Found bare 'superpowers:' prefix (should be superpowers-extended-cc:):"
    echo "$BARE"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] All skill refs use correct prefix"
fi

# 4. No RELEASE-NOTES.md (we use GitHub releases)
echo "Test 4: No RELEASE-NOTES.md..."
if [ -f "$REPO_ROOT/RELEASE-NOTES.md" ]; then
    echo "  [FAIL] RELEASE-NOTES.md should not exist in our fork"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] No RELEASE-NOTES.md"
fi

# 5. Native task sections exist in key skills
echo "Test 5: Native task integration present..."
NATIVE_FAIL=0
for skill in writing-plans brainstorming dispatching-parallel-agents; do
    if ! grep -q "Native Task" "$REPO_ROOT/skills/$skill/SKILL.md" 2>/dev/null; then
        echo "  [FAIL] skills/$skill/SKILL.md missing Native Task section"
        NATIVE_FAIL=$((NATIVE_FAIL + 1))
    fi
done
if [ $NATIVE_FAIL -gt 0 ]; then
    FAILED=$((FAILED + NATIVE_FAIL))
else
    echo "  [PASS] Native task sections present"
fi

# 6. No docs/plans/ in tracked files (development artifacts)
echo "Test 6: No docs/plans/ in tracked files..."
if git -C "$REPO_ROOT" ls-files | grep -q "^docs/plans/"; then
    echo "  [FAIL] docs/plans/ contains tracked files (should be excluded):"
    git -C "$REPO_ROOT" ls-files | grep "^docs/plans/"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] No docs/plans/ in tracked files"
fi

# Summary
echo ""
if [ $FAILED -eq 0 ]; then
    echo "=== All fork validation tests passed ==="
    exit 0
else
    echo "=== FAILED: $FAILED fork validation checks ==="
    exit 1
fi
