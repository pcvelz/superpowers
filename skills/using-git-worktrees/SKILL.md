---
name: using-git-worktrees
description: Use when starting feature work that needs isolation from current workspace or before executing implementation plans - wraps Claude Code native worktree tools with project setup, baseline test verification, and symlink-aware gitignore-safety
---

# Using Git Worktrees

## Overview

Git worktrees create isolated workspaces sharing the same repository, allowing work on multiple branches simultaneously without switching. Claude Code provides native tools (`EnterWorktree`, `ExitWorktree`, `claude --worktree`) that handle worktree lifecycle end-to-end. This skill wraps those tools with three things the native flow does not provide: project-setup auto-detection, a baseline test verification step, and a gitignore-safety check tailored to the `.claude/worktrees/` location (including the symlink case).

**Core principle:** Use the native worktree tools for creation and cleanup. Add project setup, baseline verification, and gitignore-safety on top. Never run `git worktree add` manually.

**Announce at start:** "I'm using the using-git-worktrees skill to set up an isolated workspace."

## Creating a Worktree

### Mid-session

Call the `EnterWorktree` tool. It creates a worktree at `.claude/worktrees/<name>/` on branch `worktree-<name>`, then switches the session CWD into it.

- Pass a `name` parameter for a descriptive directory and branch name (e.g., `name: "auth-refactor"`).
- Omit `name` to auto-generate a random one.
- `EnterWorktree` automatically copies files listed in `.worktreeinclude` (at project root) into the new worktree — use this for gitignored config files the worktree needs to run (e.g., `.env`, `.env.local`).

### New session

Launch with `claude --worktree <name>` from the repo root. Claude Code creates the worktree before the session starts and opens the session inside it.

### FORBIDDEN

- Do **NOT** call `git worktree add` manually. It bypasses `.worktreeinclude` processing, session CWD management, and cleanup integration.
- Do **NOT** pass `isolation: "worktree"` on `Agent` tool calls to isolate subagents. Each subagent gets its own worktree; if the subagent makes any changes, Claude Code keeps the worktree on session exit, which requires manual `git worktree unlock` + `git worktree remove --force` cleanup. Use a single session-level worktree (this skill) and pass its CWD explicitly in Agent prompts instead.

## Gitignore-Safety Check (run BEFORE `EnterWorktree`)

The worktree's working tree physically lands at `.claude/worktrees/<name>/` inside the project. If the parent repo does not ignore that path, the worktree's files will appear as untracked in `git status` and risk accidental commits.

Check coverage from the repo root:

```bash
cd "$(git rev-parse --show-toplevel)"
git check-ignore -v .claude/worktrees/ 2>&1
```

**Three outcomes:**

1. **Ignored** (output like `.gitignore:N:pattern  .claude/worktrees/`) — safe, proceed to `EnterWorktree`.

2. **Not ignored** (empty output, exit code 1) — add it before creating the worktree:
   ```bash
   printf '\n# Claude Code native worktrees\n.claude/worktrees/\n' >> .gitignore
   git add .gitignore
   git commit -m "chore: ignore .claude/worktrees/"
   ```
   Then proceed.

3. **Symlink case** (error such as `fatal: pathspec '.claude/worktrees/' is beyond a symbolic link` or `fatal: pathspec '.claude/worktrees/' did not match any file(s)`, or `.claude` shows up as a symlink in `ls -la`) — `git check-ignore` cannot traverse symlinks. The native worktree lands in the symlink's target directory, which likely does NOT ignore that path. Warn the user explicitly:
   > ".claude/ is a symlink. Native worktrees will physically land at `<symlink-target>/worktrees/` and MAY appear as untracked files in the parent-of-symlink repo's `git status`. Verify with `git -C <symlink-target-root> status` before proceeding; add the appropriate gitignore entry at that repo's root if needed."

## Post-Creation Project Setup

After `EnterWorktree` succeeds and your CWD is inside the worktree, auto-detect and run the project's dependency install:

```bash
# Node.js / Bun
if [ -f bun.lockb ] || [ -f bunfig.toml ]; then bun install
elif [ -f package.json ]; then npm install; fi

# Rust
if [ -f Cargo.toml ]; then cargo build; fi

# Python
if [ -f uv.lock ] || [ -f pyproject.toml ]; then uv sync
elif [ -f requirements.txt ]; then pip install -r requirements.txt; fi

# Go
if [ -f go.mod ]; then go mod download; fi
```

Skip if no recognized project files are present.

## Baseline Test Verification

Run the project's test suite to confirm the worktree starts clean:

```bash
# Use the project's native test command
bun test        # Bun
npm test        # Node
cargo test      # Rust
pytest          # Python
go test ./...   # Go
```

- **Tests pass:** Report ready with count (e.g., "47 tests passing"). Proceed.
- **Tests fail:** Report failures verbatim. Ask the user whether to proceed with a broken baseline or pause to investigate.

## Exiting a Worktree

Call `ExitWorktree` when the work is done:

- `action: "keep"` — preserves worktree and branch on disk for later (use when handing off to another session or keeping work uncommitted).
- `action: "remove"` — deletes worktree and branch. Refuses if uncommitted changes exist, unless `discard_changes: true` is also passed.

If the session ends while still inside a worktree, Claude Code prompts the user to keep or remove it.

## Quick Reference

| Situation | Action |
|-----------|--------|
| Mid-session — need isolated workspace | Call `EnterWorktree` with a descriptive `name` |
| New session — need isolated workspace | Launch `claude --worktree <name>` |
| `.claude/worktrees/` not gitignored | Add + commit it, then `EnterWorktree` |
| `.claude/` is a symlink | Warn user about parent-repo exposure; verify with `git -C <target> status` |
| Need env files in worktree | Create `.worktreeinclude` at project root listing them |
| Done with worktree — keep work | `ExitWorktree` `action: "keep"` |
| Done with worktree — discard | `ExitWorktree` `action: "remove"` (add `discard_changes: true` if uncommitted) |
| Tests fail during baseline | Report verbatim; ask user whether to proceed |
| No package.json / Cargo.toml / etc. | Skip dependency install |
| Subagent needs isolation | NO per-subagent `isolation:"worktree"` — pass session worktree CWD explicitly |

## Common Mistakes

### Calling `git worktree add` manually

- **Problem:** Bypasses native lifecycle management, `.worktreeinclude` handling, and session CWD tracking.
- **Fix:** Always `EnterWorktree` (mid-session) or `claude --worktree` (new session).

### Using `isolation: "worktree"` on `Agent`

- **Problem:** Each subagent gets its own worktree. If the subagent makes any file changes, Claude Code keeps it on exit, requiring manual `git worktree unlock` + `git worktree remove --force` cleanup per subagent. This multiplies with parallel subagents.
- **Fix:** Create one session-level worktree with this skill; pass the worktree CWD explicitly in every `Agent` prompt.

### Skipping the gitignore-safety check

- **Problem:** If `.claude/worktrees/` is not ignored, the worktree's working tree gets tracked in the parent repo (pollutes `git status`, risks accidental commits). The symlink case is especially silent.
- **Fix:** Always run the three-outcome check before `EnterWorktree`.

### Skipping baseline test verification

- **Problem:** Can't distinguish new bugs from pre-existing failures when the work continues.
- **Fix:** Always run the test suite after setup; report results before proceeding.

## Integration

**Called by:**
- **brainstorming** (Phase 4) — REQUIRED when design is approved and implementation follows
- **subagent-driven-development** — REQUIRED before executing any tasks (one session-level worktree, NOT per-subagent isolation)
- **executing-plans** — REQUIRED before executing any tasks
- Any skill needing an isolated workspace

**Pairs with:**
- **finishing-a-development-branch** — REQUIRED for merge/keep/discard decisions after work is complete (delegates cleanup to `ExitWorktree`)

**Native tools wrapped:**
- `EnterWorktree` — create and enter worktree mid-session
- `ExitWorktree` — leave with keep/remove decision
- `claude --worktree <name>` — CLI entry point for new-session worktrees
- `.worktreeinclude` — project-root file listing gitignored files to copy into new worktrees
