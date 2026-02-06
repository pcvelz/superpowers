# Fix Task Blocking Transfer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the issue where task blocking relationships are lost when transferring from planning to execution sessions.

**Architecture:** Minimal changes to two skill files - add explicit instructions for .tasks.json creation and dependency restoration.

**Tech Stack:** Markdown skill files

---

## Task 1: Add explicit .tasks.json creation to writing-plans

**Files:**
- Modify: `skills/writing-plans/SKILL.md`

**Problem:** The Task Persistence section (lines 191-215) describes writing `.tasks.json` but it's reference documentation at the bottom, not an actionable instruction in the workflow.

**Step 1: Add instruction between "Remember" and "Execution Handoff" sections**

Insert after line 109 (after the "Remember" section's last bullet), before "## Execution Handoff":

```markdown
## Save Task State

**REQUIRED before Execution Handoff:** Write tasks to `<plan-path>.tasks.json`:

```json
{
  "planPath": "<full-path-to-plan.md>",
  "tasks": [
    {"id": "1", "subject": "Task 1: ...", "status": "pending"},
    {"id": "2", "subject": "Task 2: ...", "status": "pending", "blockedBy": ["1"]}
  ],
  "lastUpdated": "<ISO-timestamp>"
}
```

Use the Write tool to save this file. Include ALL tasks with their blockedBy relationships.
```

**Step 2: Verify the change**

Read the file and confirm the new section exists between "Remember" and "Execution Handoff".

**Step 3: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "fix(writing-plans): add explicit .tasks.json creation step"
```

---

## Task 2: Strengthen executing-plans dependency restoration

**Files:**
- Modify: `skills/executing-plans/SKILL.md`

**Problem:** Step 1b line 39 says "After all tasks created, set dependencies using TaskUpdate with addBlockedBy" - too vague, easily skipped.

**Step 1: Strengthen Step 1b instruction**

Find line 39-40 in Step 1b and replace:

```markdown
3. After all tasks created, set dependencies using TaskUpdate with addBlockedBy
4. Run TaskList to confirm all tasks created with correct dependencies
```

With:

```markdown
3. **CRITICAL - Dependencies:** For EACH task that has blockedBy in the plan or .tasks.json:
   - Call `TaskUpdate` with `taskId` and `addBlockedBy: [list-of-blocking-task-ids]`
   - Do NOT skip this step - dependencies are essential for correct execution order
4. Call `TaskList` and verify blockedBy relationships show correctly (e.g., "blocked by #1, #2")
```

**Step 2: Verify the change**

Read the file and confirm Step 1b now has explicit dependency restoration.

**Step 3: Commit**

```bash
git add skills/executing-plans/SKILL.md
git commit -m "fix(executing-plans): strengthen dependency restoration in Step 1b"
```

---

## Task 3: Ensure Execution Handoff always offers both options

**Files:**
- Modify: `skills/writing-plans/SKILL.md`

**Problem:** User had to manually request option 2. The Execution Handoff section exists but Claude skipped offering both options.

**Step 1: Make Execution Handoff REQUIRED**

Find line 111-113:

```markdown
## Execution Handoff

After saving the plan, offer execution choice:
```

Replace with:

```markdown
## Execution Handoff

**REQUIRED:** After saving plan AND .tasks.json, present BOTH options to the user exactly as written below:
```

**Step 2: Verify the change**

Read the file and confirm the REQUIRED marker is present.

**Step 3: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "fix(writing-plans): mark Execution Handoff as REQUIRED"
```

---

## Task 4: Test the changes with a dry-run

**Dependencies:** Requires Tasks 1-3 complete.

**Step 1: Launch test subagent**

Use Task tool to launch a subagent that:
1. Reads the updated writing-plans skill
2. Creates a simple 3-task plan with dependencies
3. Reports whether it:
   - Created .tasks.json with blockedBy
   - Offered both execution options

**Step 2: Verify results**

- [ ] .tasks.json was mentioned/created
- [ ] Both options were offered

**Step 3: Final commit if needed**

If adjustments needed, make them and commit.

---

## Summary of Changes

| File | Change |
|------|--------|
| `skills/writing-plans/SKILL.md` | Add "Save Task State" section, mark Execution Handoff as REQUIRED |
| `skills/executing-plans/SKILL.md` | Strengthen Step 1b dependency restoration |

Total: ~15-20 lines added/modified across 2 files.
