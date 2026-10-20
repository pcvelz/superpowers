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
- `tests/diagnosing-superpowers/test-skill-structure.sh` — structural checks for the diagnosing-superpowers skill (frontmatter, referenced files, leak scan, word budget); behavior-scenario eval records are kept by the maintainer outside the repo.

Run plugin tests via the relevant directory's `run-*.sh` or `npm test`.

## Skill behavior evals

Live in `evals/` (the [superpowers-evals](https://github.com/prime-radiant-inc/superpowers-evals/) eval lab, since renamed from Drill). Quorum is the harness CLI — one part of the system: it drives real coding-agent CLIs through a Gauntlet QA agent and grades them against each scenario's acceptance criteria plus deterministic post-checks. Scenarios live at `evals/scenarios/<name>/`. See `evals/README.md` for setup, the container runtime, and the safety model. Quick start (local break-glass run):

```bash
cd evals
bun install
export SUPERPOWERS_ROOT=/path/to/superpowers
bun run quorum run scenarios/triggering-test-driven-development --coding-agent claude
bun run quorum show <run-dir>
```

Quorum scenarios are slow (3-30+ minutes each) and run real LLM sessions in permissive modes — read `evals/README.md`'s Live Eval Risk section first. Only the static gates (`bun run check`, `bun run quorum check`) are safe for public CI; the natural follow-up remains a tiered model (static gates on PR, live sweep nightly + on-demand).
