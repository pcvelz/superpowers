# Upstream Merge & Publishing Workflow Validation

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Merge 77 upstream commits and validate that CLAUDE.md's publishing workflow documentation is accurate

**Architecture:** Sequential validation - research context, perform merge, compare documented vs actual steps, discuss versioning

**Tech Stack:** Git, bash

---

## Context

The CLAUDE.md was recently updated with new publishing workflow steps. This plan:
1. Researches the session that informed those changes
2. Performs an actual upstream merge
3. Validates the documentation against actual steps
4. Discusses versioning with user

**Current state:**
- Our version: 4.1.4
- Upstream version: 4.1.1
- Commits behind: 77

---

### Task 1: Research Session 441b53b5 Context

**Goal:** Understand what led to the CLAUDE.md publishing workflow changes

**Step 1: Review extracted session**

The session is already extracted. Key findings from session 441b53b5:
- User requested native task integration for `dispatching-parallel-agents` skill
- Session used `/writing-plans` and `/subagent-driven-development` skills
- Commits made: `docs(dispatching): add native task integration guidance`
- Version bumped to 4.1.4, RELEASE-NOTES.md removed

**Step 2: Identify relevant workflow insights**

From session transcript:
- Checked upstream with `git fetch upstream`
- Compared versions: ours vs upstream
- Made skill changes
- Committed and pushed
- Created release tag

**Acceptance:** Summary documented, ready for diff research task

---

### Task 1.5: Research Upstream Diff for Native Task Opportunities

**Goal:** Thoroughly assess which upstream changes could benefit from native task integration

**Step 1: Review the diff**

Compare: https://github.com/pcvelz/superpowers/compare/main...obra%3Asuperpowers%3Amain

Run via WebFetch or review manually the 77 commits difference.

**Step 2: Identify skills needing native task integration**

For each skill changed in upstream, assess:
- Does it involve multi-step workflows?
- Would task tracking improve visibility?
- Complexity of integration (low/medium/high)

**Step 3: Use existing diffs as reference**

Our existing native task implementations to use as examples:
- `skills/writing-plans/SKILL.md` - Task persistence pattern
- `skills/brainstorming/SKILL.md` - Task creation during exploration
- `skills/dispatching-parallel-agents/SKILL.md` - Parallel task tracking

**Step 4: Document findings**

Create assessment table:

| Skill | Native Task Opportunity | Complexity | Priority |
|-------|------------------------|------------|----------|
| TBD   | TBD                    | TBD        | TBD      |

**Principles (from CLAUDE.md):**
1. Keep it simple - ~20-30 lines max
2. Don't refactor upstream - add sections at end
3. Use existing diffs as coding examples

**Acceptance:** Assessment complete with prioritized list of skills needing native task integration

---

### Task 2: Perform Upstream Merge

**Goal:** Merge 77 upstream commits into our fork

**Step 1: Verify current state**

Run:
```bash
git status --porcelain
git log --oneline -1
```

Expected: Clean working directory, on commit a16f97c

**Step 2: Perform merge**

Run:
```bash
git merge upstream/main -m "Merge upstream/main (77 commits)"
```

**Step 3: Handle RELEASE-NOTES.md conflict (if any)**

If RELEASE-NOTES.md exists in merge:
```bash
git rm RELEASE-NOTES.md
git commit --amend --no-edit
```

**Step 4: Verify merge result**

Run:
```bash
git log --oneline -5
git status --porcelain
```

**Acceptance:** Merge complete, no conflicts, RELEASE-NOTES.md removed

---

### Task 3: Assess CLAUDE.md Publishing Workflow

**Goal:** Compare documented steps vs actual merge steps performed

**Step 1: Review documented workflow**

From CLAUDE.md lines 55-84:
```
0. Check upstream for new commits:
   git fetch upstream
   BEHIND=$(git rev-list HEAD..upstream/main --count)

   If BEHIND > 0: Merge upstream changes first:
   git merge upstream/main
   git rm RELEASE-NOTES.md 2>/dev/null && git commit --amend --no-edit

   Version conflict check:
   OURS=$(jq -r .version .claude-plugin/plugin.json)
   THEIRS=$(git show upstream/main:.claude-plugin/plugin.json | jq -r .version)
```

**Step 2: Compare against actual steps**

Document discrepancies:

| Documented | Actual | Match? |
|------------|--------|--------|
| `git fetch upstream` | ✓ Performed | ✓ |
| Check BEHIND count | ✓ Performed (77) | ✓ |
| `git merge upstream/main` | To perform in Task 2 | TBD |
| `git rm RELEASE-NOTES.md && commit --amend` | TBD | TBD |
| Version conflict check | ✓ (4.1.4 > 4.1.1, ok) | ✓ |

**Step 3: Identify issues**

After completing Task 2, note any documentation gaps or inaccuracies.

**Acceptance:** Assessment complete with specific findings

---

### Task 4: Discuss Versioning Strategy with User

**Goal:** Get user decision on versioning approach

**Step 1: Present findings**

Summary to present:
- Our version (4.1.4) > upstream (4.1.1) - no conflict
- Merge complete (from Task 2)
- CLAUDE.md workflow accuracy assessment (from Task 3)

**Step 2: Ask user**

Use AskUserQuestion:
- "Do we need to bump version after this merge?"
- "Is the versioning guidance in CLAUDE.md correct?"
- "Any other workflow documentation changes needed?"

**Acceptance:** User decision captured, any documentation updates made

---

## Summary

| Task | Subject | Dependencies |
|------|---------|--------------|
| 1 | Research session context | - |
| 1.5 | Research upstream diff for native task opportunities | 1 |
| 2 | Perform upstream merge | 1, 1.5 |
| 3 | Assess publishing workflow | 2 |
| 4 | Discuss versioning with user | 3 |
