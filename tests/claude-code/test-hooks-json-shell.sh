#!/usr/bin/env bash
# Test: every command hook the plugin registers in hooks/hooks.json declares
# "shell": "bash". Claude Code >= 2.1.81 then runs it through Git Bash on
# Windows instead of cmd.exe/PowerShell, where run-hook.cmd loses the script's
# exit code and a PreToolUse gate that should block (exit 2) lets the call pass.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"

echo "=== Test: hooks.json shell dispatch ==="

if ! jq -e . "$HOOKS_JSON" >/dev/null 2>&1; then
    echo "  [FAIL] hooks/hooks.json is not valid JSON"
    exit 1
fi

TOTAL=$(jq '[.hooks[][].hooks[] | select(.type == "command")] | length' "$HOOKS_JSON")
MISSING=$(jq -r '.hooks | to_entries[] | .key as $ev | .value[] | (.matcher // "*") as $m
    | .hooks[] | select(.type == "command" and .shell != "bash")
    | "\($ev) [\($m)]: \(.command)"' "$HOOKS_JSON")

FAILED=0
if [ "$TOTAL" -eq 0 ]; then
    echo "  [FAIL] no command hooks found"
    FAILED=1
elif [ -n "$MISSING" ]; then
    while IFS= read -r line; do
        echo "  [FAIL] missing \"shell\": \"bash\": $line"
        FAILED=$((FAILED + 1))
    done <<< "$MISSING"
else
    echo "  [PASS] all $TOTAL command hooks declare \"shell\": \"bash\""
fi

echo "=== Summary: $FAILED failure(s) ==="
exit "$FAILED"
