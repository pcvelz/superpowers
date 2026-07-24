# Testing Superpowers

Superpowers has two distinct kinds of tests, each in its own directory:

- **`tests/`** — does the plugin's non-LLM code work, and do skills load/trigger correctly? Bash + node + python integration tests for brainstorm-server JS, hooks, shell lint, and Claude Code skill behavior.
- **`evals/`** — do agents behave correctly on real LLM sessions? Python harness driving real tmux sessions of Claude Code, with an LLM actor and verifier judging skill compliance.

## Plugin tests

Live in `tests/`. Currently:

- `tests/brainstorm-server/` — node test suite for the brainstorm server JS code.
- `tests/claude-code/` — bash tests that invoke the Claude Code CLI headlessly to verify skill content and behavior. See `tests/claude-code/README.md` for structure and how to add tests. Includes `test-subagent-driven-development.sh`, `test-subagent-driven-development-integration.sh`, `test-worktree-native-preference.sh` (RED-GREEN-REFACTOR for the using-git-worktrees skill), `test-sdd-workspace.sh`, `test-fork-validation.sh`, `test-handoff-guard.sh`, `test-model-routing-hook.sh`, `test-taskcreate-tier-hook.sh`, `test-user-gate-hooks.sh`, and `test-worktree-path-policy.sh`.
- `tests/hooks/` — bash tests for hook scripts (e.g. `test-session-start.sh`).
- `tests/explicit-skill-requests/` — Haiku-specific, multi-turn, and skill-name-prompted tests exercising explicit skill invocation.
- `tests/shell-lint/` — bash test wrapping `scripts/lint-shell.sh`.

Run plugin tests via the relevant directory's `run-*.sh` or `npm test`.

## Skill behavior evals

Live in `evals/`. Drill is the harness; scenarios live at `evals/scenarios/*.yaml`. See `evals/README.md` for setup. Quick start:

```bash
cd evals
uv sync --extra dev
export ANTHROPIC_API_KEY=sk-...
uv run drill run triggering-test-driven-development -b claude
```

Drill scenarios are slow (3-30+ minutes each) and run real LLM sessions. They are not part of CI today; the natural follow-up is a tiered model (fast subset on PR, full sweep nightly + on-demand).
