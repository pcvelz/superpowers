#!/usr/bin/env bash
# Fast hook regression suites — the subset safe to run from a git pre-commit gate.
#
# Distinct from run-skill-tests.sh, which drives the Claude Code CLI (minutes per
# file, needs `claude` on PATH, costs tokens). Everything listed here is pure bash:
# it pipes a synthetic hook payload into a hook and asserts the DECISION (exit 2
# = block, exit 0 = allow). Whole set runs in ~20s.
#
# Deliberately NOT included (they hang or shell out to the CLI):
#   test-subagent-driven-development.sh, test-sdd-workspace.sh,
#   test-fork-validation.sh, test-worktree-native-preference.sh,
#   test-worktree-path-policy.sh, test-effort-enforcement-e2e.sh,
#   test-subagent-driven-development-integration.sh
# Run those by hand or via run-skill-tests.sh.
#
# A gate cannot invent a missing test case, but it stops a passing suite from
# regressing unnoticed: this repo has no CI, and its pre-commit hook otherwise
# only checks git identity.
#
# Usage: bash tests/claude-code/run-hook-tests.sh [--quiet]
# Exit:  0 = all passed, 1 = at least one suite failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

QUIET=false
[[ "${1:-}" == "--quiet" ]] && QUIET=true

# Per-file budget. The slowest suite here takes ~5s; 60s is pure headroom so a
# genuinely hung suite fails the gate instead of wedging the commit forever.
TIMEOUT_SECS=60

SUITES=(
    test-effort-routing-hook.sh
    test-handoff-guard.sh
    test-model-routing-hook.sh
    test-taskcreate-tier-hook.sh
    test-taskcreate-commit-strategy-hook.sh
    test-user-gate-hooks.sh
)

# `timeout` is GNU coreutils; on macOS it arrives as gtimeout (or not at all).
TIMEOUT_BIN=""
for candidate in timeout gtimeout; do
    if command -v "$candidate" >/dev/null 2>&1; then TIMEOUT_BIN="$candidate"; break; fi
done

FAILED=0
FAILED_NAMES=()

for suite in "${SUITES[@]}"; do
    if [[ ! -f "$suite" ]]; then
        echo "MISSING: $suite (listed in run-hook-tests.sh but not on disk)" >&2
        FAILED=$((FAILED + 1)); FAILED_NAMES+=("$suite (missing)")
        continue
    fi

    log="/tmp/superpowers-hook-test-${suite%.sh}.log"
    if [[ -n "$TIMEOUT_BIN" ]]; then
        "$TIMEOUT_BIN" "$TIMEOUT_SECS" bash "$suite" >"$log" 2>&1
    else
        bash "$suite" >"$log" 2>&1
    fi
    rc=$?

    if [[ $rc -eq 0 ]]; then
        [[ "$QUIET" == true ]] || echo "  [PASS] $suite"
    else
        [[ $rc -eq 124 ]] && note="timed out after ${TIMEOUT_SECS}s" || note="exit $rc"
        echo "  [FAIL] $suite ($note) — log: $log" >&2
        FAILED=$((FAILED + 1)); FAILED_NAMES+=("$suite")
    fi
done

if [[ $FAILED -ne 0 ]]; then
    echo "" >&2
    echo "=== $FAILED hook suite(s) failed: ${FAILED_NAMES[*]} ===" >&2
    exit 1
fi

[[ "$QUIET" == true ]] || echo "=== all ${#SUITES[@]} hook suites passed ==="
exit 0
