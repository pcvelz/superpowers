# Evaluate Native Task Persistence Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Decide whether to adopt the `.tasks.json` persistence approach from the cache version or keep our lean session-scoped approach.

**Architecture:** Compare three approaches: (A) our current lean approach, (B) full cache version, (C) minimal persistence. Implement the chosen approach.

**Tech Stack:** Claude Code native tasks, SKILL.md files, JSON

---

## Background

### Current State (Our Fork)
- `writing-plans/SKILL.md`: 189 lines (adds REQUIRED FIRST STEP + Native Task Reference)
- `executing-plans/SKILL.md`: 77 lines (unchanged from upstream)
- Tasks are session-scoped only
- Note says: "Tasks are session-scoped; re-run TaskCreate from plan for new sessions"

### Cache Version (swiss-sense modifications)
- `writing-plans/SKILL.md`: 227 lines (+38 lines for Persistent Task Lists section)
- `executing-plans/SKILL.md`: 191 lines (+114 lines for Step 0 + Bootstrap sections)
- Tasks persist to `.tasks.json` alongside plan
- Any session can resume from where it left off

### Key Difference
| Feature | Our Fork | Cache Version |
|---------|----------|---------------|
| Total added lines | ~72 | ~190 |
| Cross-session persistence | No | Yes (.tasks.json) |
| Complexity | Low | Medium |
| Session resume | Bootstrap from plan | Read from JSON |

---

## Options Analysis

### Option A: Keep Current Lean Approach (Recommended)

**Rationale:**
1. Plan document IS the persistent record - tasks are derived state
2. TaskCreate/TaskList from plan headers is fast (<1 second)
3. No additional JSON file maintenance needed
4. Simpler skill files are easier to maintain and understand
5. Cross-session persistence rarely needed (most work completes in 1-3 sessions)

**Changes needed:** None - we already have this.

**Pros:**
- Lean and mean (72 lines vs 190 lines)
- Plan is source of truth
- No file management overhead

**Cons:**
- Tasks reset each session (must re-bootstrap)
- No automatic resume from exact stopping point

### Option B: Full Cache Version Persistence

**Rationale:**
- Exact resume capability for long-running plans
- Validated working in swiss-sense session

**Changes needed:**
1. Add "Persistent Task Lists" section to writing-plans (~40 lines)
2. Add "Step 0: Load Persisted Task State" to executing-plans (~60 lines)
3. Add "Task Bootstrap from Plan" section to executing-plans (~50 lines)

**Pros:**
- Exact cross-session resume
- Task state durability

**Cons:**
- +118 lines of skill documentation
- Requires Write tool calls after every TaskUpdate
- `.tasks.json` files accumulate unless cleaned up
- More complexity to maintain

### Option C: Minimal Persistence (Hybrid)

**Rationale:**
- Get resume capability with less bloat
- Keep bootstrap in executing-plans, skip JSON persistence

**Changes needed:**
1. Add "Task Bootstrap from Plan" to executing-plans (~30 lines simplified)
2. Use TaskList + pattern matching to detect incomplete tasks
3. No JSON file - rely on task status in session + plan headers

**Pros:**
- Middle ground on complexity
- No JSON file management

**Cons:**
- Still loses exact stopping point across sessions
- Additional skill complexity

---

## Recommendation

**Choose Option A: Keep Current Lean Approach**

The cache version solves a real problem (cross-session resume), but:
1. The added complexity (~118 lines) isn't justified for the use case
2. The plan document already serves as the permanent record
3. Bootstrapping tasks from plan headers is fast and reliable
4. Most implementation work completes within a few sessions anyway

If cross-session persistence becomes a real pain point later, we can add it then. For now, YAGNI.

---

## Task 0: Document Decision

**Files:**
- Modify: `docs/plans/2026-01-28-evaluate-task-persistence.md` (this file)

**Step 1: Confirm approach with user**

Present the three options and get confirmation on which to implement.

**Acceptance Criteria:**
- [ ] User has confirmed approach
- [ ] Decision documented

---

## Task 1: Verify Current Implementation

**Files:**
- Read: `skills/writing-plans/SKILL.md`
- Read: `skills/executing-plans/SKILL.md`

**Step 1: Verify writing-plans has REQUIRED FIRST STEP**

Check that our current writing-plans includes the "REQUIRED FIRST STEP: Initialize Task Tracking" section.

**Step 2: Verify executing-plans is unchanged from upstream**

Confirm executing-plans has not been modified from upstream.

**Acceptance Criteria:**
- [ ] writing-plans has native task integration
- [ ] executing-plans is clean/upstream

---

## Task 2: Compare with Upstream (if keeping Option A)

**Files:**
- Run: `git diff upstream/main..main -- skills/`

**Step 1: Document our minimal changes**

List exactly what we've changed from upstream:
- writing-plans: +72 lines (REQUIRED FIRST STEP + Native Task Reference)
- brainstorming: +40 lines (native task integration)

**Acceptance Criteria:**
- [ ] Changes documented
- [ ] Confirmed lean and targeted

---

## Task 3: Session Review

**Session ID:** 93967b72-3389-4814-a3eb-c1fa7138ef1b (current session)

**Step 1: Review this session's workflow**

Analyze how this session used the writing-plans skill and native tasks:
- Was TaskList called first? Yes (per skill requirement)
- Were tasks created appropriately? Yes
- Any friction points?

**Step 2: Document improvements if any**

**Acceptance Criteria:**
- [ ] Session workflow reviewed
- [ ] Improvements documented (if any)

---

## Summary

The cache version's `.tasks.json` persistence is a valid solution but adds complexity we don't need. Our current fork takes a leaner approach:

1. **writing-plans**: Requires TaskList first, creates native tasks
2. **executing-plans**: Unchanged from upstream (simple batch execution)
3. **Persistence**: Plan document is the record; tasks bootstrap each session

This gives us native task progress tracking without the overhead of JSON file management.
