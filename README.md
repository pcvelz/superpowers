# Superpowers Extended for Claude Code

A community-maintained fork of [obra/superpowers](https://github.com/obra/superpowers) specifically for Claude Code users.

## Why This Fork Exists

The original Superpowers is designed as a cross-platform toolkit that works across multiple AI CLI tools (Claude Code, Codex, OpenCode, Gemini CLI). Features unique to Claude Code fall outside the scope of the upstream project due to its [cross-platform nature](https://github.com/obra/superpowers/pull/344#issuecomment-3795515617).

This fork integrates Claude Code-native features into the Superpowers workflow.

### What We Do Differently

- Leverage Claude Code-native features as they're released
- Community-driven - contributions welcome for any CC-specific enhancement
- Track upstream - stay compatible with obra/superpowers core workflow

### Current Enhancements

| Feature | Claude Code Version | Description |
|---------|---------------------|-------------|
| Native Task Management | v2.1.16+ | Dependency tracking, real-time progress visibility |
| Structured Task Metadata | v2.1.16+ | Goal/Files/AC/Verify structure with embedded `json:metadata` |
| Pre-commit Task Gate | v2.1.16+ | Plugin hook blocks `git commit` when tasks are incomplete |

## Visual Comparison

<table>
<tr>
<th>Superpowers (Vanilla)</th>
<th>Superpowers Extended CC</th>
</tr>
<tr>
<td valign="top">

![Vanilla](docs/screenshots/vanilla-session.png)

- Tasks exist only in markdown plan
- No runtime task visibility
- Agent may jump ahead or skip tasks
- Progress tracked manually by reading output

</td>
<td valign="top">

![Extended CC](docs/screenshots/extended-cc-session.png)

- **Dependency enforcement** - Task 2 blocked until Task 1 completes (no front-running)
- **Execution on rails** - Native task manager keeps agent following the plan
- **Real-time visibility** - User sees actual progress with pending/in_progress/completed states
- **Session-aware** - TaskList shows what's done, what's blocked, what's next

</td>
</tr>
</table>

## Installation

### Option 1: Via Marketplace (recommended)

```bash
# Register marketplace
/plugin marketplace add pcvelz/superpowers

# Install plugin
/plugin install superpowers-extended-cc@superpowers-extended-cc-marketplace
```

### Option 2: Direct URL

```bash
/plugin install --source url https://github.com/pcvelz/superpowers.git
```

### Verify Installation

Check that commands appear:

```bash
/help
```

```
# Should see:
# /superpowers-extended-cc:brainstorming - Interactive design refinement
# /superpowers-extended-cc:writing-plans - Create implementation plan
# /superpowers-extended-cc:executing-plans - Execute plan in batches
```

## The Basic Workflow

1. **brainstorming** - Activates before writing code. Refines rough ideas through questions, explores alternatives, presents design in sections for validation. Saves design document.

2. **using-git-worktrees** - Activates after design approval. Creates isolated workspace on new branch, runs project setup, verifies clean test baseline.

3. **writing-plans** - Activates with approved design. Breaks work into bite-sized tasks (2-5 minutes each). Every task has exact file paths, complete code, verification steps. *Creates native tasks with dependencies.*

4. **subagent-driven-development** or **executing-plans** - Activates with plan. Dispatches fresh subagent per task with two-stage review (spec compliance, then code quality), or executes in batches with human checkpoints.

5. **test-driven-development** - Activates during implementation. Enforces RED-GREEN-REFACTOR: write failing test, watch it fail, write minimal code, watch it pass, commit. Deletes code written before tests.

6. **requesting-code-review** - Activates between tasks. Reviews against plan, reports issues by severity. Critical issues block progress.

7. **finishing-a-development-branch** - Activates when tasks complete. Verifies tests, presents options (merge/PR/keep/discard), cleans up worktree.

**The agent checks for relevant skills before any task.** Mandatory workflows, not suggestions.

## How Native Tasks Work

When `writing-plans` creates tasks, each task carries structured metadata that survives across sessions and subagent dispatch:

```yaml
TaskCreate:
  subject: "Task 1: Add price validation to optimizer"
  description: |
    **Goal:** Validate input prices before optimization runs.

    **Files:**
    - Modify: `src/optimizer.py:45-60`
    - Create: `tests/test_price_validation.py`

    **Acceptance Criteria:**
    - [ ] Negative prices raise ValueError
    - [ ] Empty price list raises ValueError
    - [ ] Valid prices pass through unchanged

    **Verify:** `pytest tests/test_price_validation.py -v`

    ```json:metadata
    {"files": ["src/optimizer.py", "tests/test_price_validation.py"],
     "verifyCommand": "pytest tests/test_price_validation.py -v",
     "acceptanceCriteria": ["Negative prices raise ValueError",
       "Empty price list raises ValueError",
       "Valid prices pass through unchanged"]}
    ```
```

The `json:metadata` block is embedded in the description because `TaskGet` returns the description but not the `metadata` parameter. This ensures metadata is always available — for `executing-plans` verification, `subagent-driven-development` dispatch, and `.tasks.json` cross-session resume.

## What's Inside

### Skills Library

**Testing**
- **test-driven-development** - RED-GREEN-REFACTOR cycle (includes testing anti-patterns reference)

**Debugging**
- **systematic-debugging** - 4-phase root cause process (includes root-cause-tracing, defense-in-depth, condition-based-waiting techniques)
- **verification-before-completion** - Ensure it's actually fixed

**Collaboration**
- **brainstorming** - Socratic design refinement + *native task creation*
- **writing-plans** - Detailed implementation plans + *native task dependencies*
- **executing-plans** - Batch execution with checkpoints
- **dispatching-parallel-agents** - Concurrent subagent workflows
- **requesting-code-review** - Pre-review checklist
- **receiving-code-review** - Responding to feedback
- **using-git-worktrees** - Parallel development branches
- **finishing-a-development-branch** - Merge/PR decision workflow
- **subagent-driven-development** - Fast iteration with two-stage review (spec compliance, then code quality)

**Meta**
- **writing-skills** - Create new skills following best practices (includes testing methodology)
- **using-superpowers** - Introduction to the skills system

## Philosophy

- **Test-Driven Development** - Write tests first, always
- **Systematic over ad-hoc** - Process over guessing
- **Complexity reduction** - Simplicity as primary goal
- **Evidence over claims** - Verify before declaring success

Read more: [Superpowers for Claude Code](https://blog.fsck.com/2025/10/09/superpowers/)

## Contributing

Contributions for Claude Code-specific enhancements are welcome!

1. Fork this repository
2. Create a branch for your enhancement
3. Follow the `writing-skills` skill for creating and testing new skills
4. Submit a PR

See `skills/writing-skills/SKILL.md` for the complete guide.

## Recommended Configuration

### Disable Auto Plan Mode

Claude Code may automatically enter Plan mode during planning tasks, which conflicts with the structured skill workflows in this plugin. To prevent this, add `EnterPlanMode` to your permission deny list.

**In your project's `.claude/settings.json`:**

```json
{
  "permissions": {
    "deny": ["EnterPlanMode"]
  }
}
```

This blocks the model from calling `EnterPlanMode`, ensuring the brainstorming and writing-plans skills operate correctly in normal mode. See [upstream discussion](https://github.com/anthropics/claude-code/issues/23384) for context.

### Block Commits With Incomplete Tasks

When using native tasks, the agent should not commit until all tasks are finished. This plugin includes an example hook that blocks `git commit` when tasks are still open.

Add this to your `.claude/settings.local.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/plugins/marketplaces/superpowers-extended-cc-marketplace/hooks/examples/pre-commit-check-tasks.sh"
          }
        ]
      }
    ]
  }
}
```

The hook ships with the plugin at `hooks/examples/pre-commit-check-tasks.sh`. The marketplace path is stable across versions. It parses the session transcript for `TaskCreate`/`TaskUpdate` calls and blocks `git commit` when any tasks are not completed, cancelled, or deleted. Non-commit Bash commands pass through unaffected.

### Block Low-Context Stop Excuses

Long sessions sometimes end with the assistant trying to defer work to "a fresh session later" or claiming "context is full" while actual usage is low. This plugin ships an optional `Stop`-event hook that blocks such phrases, but only when actual context usage (measured from the session transcript) is below 50%.

Opt in by adding this to your `.claude/settings.local.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/plugins/marketplaces/superpowers-extended-cc-marketplace/hooks/examples/stop-deflection-guard.sh"
          }
        ]
      }
    ]
  }
}
```

See the header of `hooks/examples/stop-deflection-guard.sh` for the full list of blocked phrases, configuration environment variables, and fail-open behavior.

## Updating

Skills update automatically when you update the plugin:

```bash
/plugin update superpowers-extended-cc@superpowers-extended-cc-marketplace
```

## Upstream Compatibility

This fork tracks `obra/superpowers` main branch. Changes specific to Claude Code are additive - the core workflow remains compatible.

## License

MIT License - see LICENSE file for details

## Support

- **Issues**: https://github.com/pcvelz/superpowers/issues
- **Upstream**: https://github.com/obra/superpowers
