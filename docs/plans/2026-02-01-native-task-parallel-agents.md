# Native Task Integration for Parallel Agents Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add native task management (TaskCreate/TaskUpdate/TaskList) support to the dispatching-parallel-agents skill.

**Architecture:** Add a new section to the existing skill that teaches the pattern for creating parent tasks before dispatching agents, without restructuring existing content.

**Tech Stack:** Claude Code native task tools (v2.1.16+)

---

## Research Analysis

### Upstream Comparison

**Status:** Our `dispatching-parallel-agents` skill is **byte-for-byte identical** to upstream `obra/superpowers`.

**Upstream native task support:** None. The skill uses conceptual `Task()` examples but no native task tools.

### Claude Code Best Practices (External Sources)

| Source | Key Finding |
|--------|-------------|
| [Anthropic Engineering](https://code.claude.com/docs) | No native task API documented for parallel coordination |
| [Zach Wills](https://zachwills.net/how-to-use-claude-code-subagents-to-parallelize-development/) | Recommends distinct file artifacts for audit trail, synthesis challenge acknowledged |
| [Simon Willison](https://simonwillison.net/2025/Oct/5/parallel-coding-agents/) | "Natural bottleneck is how fast I can review results" - review capacity, not agent throughput |
| [Tim Dietrich](https://timdietrich.me/blog/claude-code-parallel-subagents/) | No task tracking discussed; recommends specificity and defined scope |

### Our Current Implementation

**writing-plans skill** already has:
- Native Task Integration Reference section (lines 134-187)
- Task Persistence with `.tasks.json` files (lines 191-215)
- TaskCreate/TaskUpdate patterns for plan tasks

**executing-plans skill** already has:
- Step 0: Load Persisted Tasks from `.tasks.json`
- TaskList on startup, restore from JSON if needed
- Task status updates during execution

**subagent-driven-development skill** has:
- References TodoWrite (older pattern, not native tasks)
- Sequential task execution with review loops

### Gap Analysis

| Feature | writing-plans | executing-plans | dispatching-parallel-agents |
|---------|--------------|-----------------|----------------------------|
| TaskCreate | ✅ | ✅ (restore) | ❌ |
| TaskUpdate | ✅ | ✅ | ❌ |
| TaskList | ✅ | ✅ | ❌ |
| Blocking deps | ✅ | ✅ | ❌ |
| Progress visibility | ✅ | ✅ | ❌ |

**Conclusion:** The pattern exists in writing-plans and executing-plans. We need to adapt it for parallel dispatch context.

### Key Differences for Parallel Agents

| Sequential (writing/executing) | Parallel (dispatching) |
|-------------------------------|------------------------|
| Tasks run one at a time | Multiple tasks run concurrently |
| Linear blockedBy chain | No blockedBy (independent) |
| Single agent updates status | Each agent updates its own task |
| Controller monitors sequentially | Controller monitors all in parallel |

---

## Task 0: Research Analysis Summary

**Status:** Complete (documented above)

**Deliverable:** Research section in this plan document

---

## Task 1: Add Native Task Section to dispatching-parallel-agents

**Files:**
- Modify: `skills/dispatching-parallel-agents/SKILL.md`

**Change Summary:** Add new section "## Native Task Integration" after "## Key Benefits" section (after line 163).

**Step 1: Read the current skill file**

```bash
cat skills/dispatching-parallel-agents/SKILL.md
```

Verify the section order matches expected structure.

**Step 2: Add the new section**

Insert the following after line 163 (after "## Key Benefits" section, before "## Verification"):

```markdown

## Native Task Integration

Use Claude Code's native task tools for visibility and tracking when dispatching parallel agents.

### Before Dispatch

Create a parent task for each agent:

```
TaskCreate:
  subject: "Fix agent-tool-abort.test.ts"
  description: |
    Investigate and fix the 3 failing tests:
    - "should abort tool with partial output capture"
    - "should handle mixed completed and aborted tools"
    - "should properly track pendingToolCount"

    Root cause: Likely timing/race conditions.
    Return: Summary of findings and fixes.
  activeForm: "Fixing agent-tool-abort tests"
```

Repeat for each independent domain. Then dispatch all agents in parallel.

### Agent Instructions

Include in each agent prompt:

```markdown
**Task Tracking:**
1. When you start: `TaskUpdate taskId=N status=in_progress`
2. When you finish: `TaskUpdate taskId=N status=completed`
```

### Monitor Progress

While agents run:

```
TaskList
```

Shows status of all parallel investigations.

### Example Flow

```
# 1. Create tasks (returns IDs 1, 2, 3)
TaskCreate subject="Fix abort tests" ...
TaskCreate subject="Fix batch tests" ...
TaskCreate subject="Fix race tests" ...

# 2. Dispatch agents in parallel (single message, multiple Task calls)
Task("Fix abort tests... TaskUpdate taskId=1...")
Task("Fix batch tests... TaskUpdate taskId=2...")
Task("Fix race tests... TaskUpdate taskId=3...")

# 3. Monitor
TaskList  # Shows in_progress for running, completed when done

# 4. Review when all complete
```

### Benefits

- **Visibility:** See which agents are running/done
- **Progress:** CLI shows spinner with activeForm text
- **Coordination:** Know when all parallel work completes
- **Audit trail:** Task history shows what was attempted

### Notes

- No blockedBy relationships (parallel = independent)
- Each agent manages its own task status
- Parent session can TaskList to check progress
```

**Step 3: Verify the edit**

```bash
grep -n "Native Task Integration" skills/dispatching-parallel-agents/SKILL.md
```

Expected: Line number where section was added.

**Step 4: Commit**

```bash
git add skills/dispatching-parallel-agents/SKILL.md
git commit -m "feat(dispatching-parallel-agents): add native task integration section"
```

---

## Task 2: Update Version

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

**Step 1: Bump version in plugin.json**

Change `"version": "4.1.3"` to `"version": "4.1.4"`

**Step 2: Bump version in marketplace.json**

Change `"version": "4.1.3"` to `"version": "4.1.4"`

**Step 3: Commit version bump**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "chore: bump version to 4.1.4"
```

---

## Task 3: Push and Tag Release

**Step 1: Push to origin**

```bash
git push origin main
```

**Step 2: Create tag and release**

```bash
git tag v4.1.4 && git push origin v4.1.4
gh release create v4.1.4 --title "v4.1.4" --notes "feat(dispatching-parallel-agents): add native task integration section"
```

---

## Verification Checklist

After all tasks complete:

- [ ] `skills/dispatching-parallel-agents/SKILL.md` has "Native Task Integration" section
- [ ] Section appears after "Key Benefits", before "Verification"
- [ ] No restructuring of existing content
- [ ] Version bumped to 4.1.4 in both JSON files
- [ ] Tag v4.1.4 exists
- [ ] GitHub release created
