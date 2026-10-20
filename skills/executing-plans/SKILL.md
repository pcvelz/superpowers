---
name: executing-plans
description: Use when executing an implementation plan as the implementer yourself in a separate session — your human partner chose "Parallel Session, inline" at the writing-plans handoff
---

## CRITICAL CONSTRAINTS

**You MUST NOT call `EnterPlanMode` or `ExitPlanMode` during this skill.** This skill operates in normal mode, executing a plan that already exists on disk. Plan mode is unnecessary and dangerous here — it restricts Write/Edit tools needed for implementation.

# Executing Plans

Execute the plan yourself, task by task, in this session: no implementer
subagent per task, no reviewer per task. One fresh-context review of the
whole branch at the end.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

**Why inline:** Subagent-driven development pays for a fresh implementer
and a fresh reviewer on every task, each re-reading the codebase from zero.
Inline execution pays for one context (yours) plus one reviewer at the end.
What it gives up is a fresh context per task and a second pair of eyes per
task. This skill keeps what those two things bought, by other means: the
brief is the spec, the ledger is your memory, TDD is the per-task gate, and
the final reviewer is the second pair of eyes.

**Core principle:** The plan already did the thinking. Execute it exactly,
prove each step with a test you watched fail and then pass, and leave a
record that survives your own forgetting.

**Narration:** between tool calls, narrate at most one short line — the
ledger and the tool results carry the record.

**Continuous execution:** Do not pause to check in with your human partner
between tasks. They chose a separate session to run the plan, not to answer
"should I continue?" after every task. Execute all tasks from the plan
without stopping.

**Rulings, not stalls.** Conflicts, ambiguities, plan defects — decide them.
The spec is the binding authority, the plan is its argument, and your
judgment settles what neither answers. When the plan author session is
alive (see Consulting the Plan Author), ask it first and ledger its answer
as the ruling. Record every decision in the ledger as
`Ruling: <what you decided> — <why> — <what it costs if wrong>`, and keep
going. Deviating from the plan without a ledgered ruling is a decision made
in secret.

Four things stop you, and only these: an irreversible or destructive
operation; a security-sensitive action; a side effect outside this worktree
that norms say you ask about first (a merge, a push to a shared branch, a
publish); and a plan so broken that every path forward is a guess. For
those, stop and ask.

## When to Use

- You have a plan from superpowers-extended-cc:writing-plans and your human
  partner chose "Parallel Session, inline" at the handoff. That choice gave up
  superpowers-extended-cc:subagent-driven-development's per-task review
  loop — stay on this skill; do not switch to subagent-driven development.
- Tasks are mostly independent — the same precondition as
  superpowers-extended-cc:subagent-driven-development.

A fully specified plan makes inline execution transcription plus testing:
it runs well on a mid-tier session model, and the one place the most
capable model earns its cost is the final review, which this skill
dispatches separately.

Inline execution over a long plan still works — the ledger is what makes
it recoverable — but the last tasks get the least of you.

## Consulting the Plan Author

Once, at start: run ListAgents and check whether the plan-writing session is alive (the handoff prompt normally names it). If it is, note its name — on every ambiguity or design question during execution, ask IT via SendMessage before guessing and before interrupting your human partner, and ledger its answer as the ruling. If it is not listed, rule yourself as described in "Rulings, not stalls".

## The Process

```dot
digraph process {
    rankdir=TB;

    subgraph cluster_per_task {
        label="Per Task";
        "task-start: brief + BASE; read the brief; TaskUpdate in_progress" [shape=box];
        "Work the steps in order: TDD, run every verification, read every output" [shape=box];
        "Step output matches plan's Expected?" [shape=diamond];
        "Plan wrong? Ask author or rule, and ledger. Code wrong? systematic-debugging" [shape=box];
        "Commit as the plan's commit steps say" [shape=box];
        "Completion contract met?" [shape=diamond];
        "task-done: run tests, ledger the result; TaskUpdate completed + sync .tasks.json" [shape=box];
    }

    "Setup: tasks, worktree, workspace + ledger, read plan + spec, pre-flight scan" [shape=box];
    "More tasks remain?" [shape=diamond];
    "Final whole-branch review (fresh reviewer)" [shape=box];
    "Re-grade, then: Critical/Important → ONE fix pass, each fix RED→GREEN + green suite; Minor → ledger" [shape=box];
    "Final review clean: delete this plan's workspace" [shape=box];
    "Use superpowers-extended-cc:finishing-a-development-branch" [shape=box style=filled fillcolor=lightgreen];

    "Setup: tasks, worktree, workspace + ledger, read plan + spec, pre-flight scan" -> "task-start: brief + BASE; read the brief; TaskUpdate in_progress";
    "task-start: brief + BASE; read the brief; TaskUpdate in_progress" -> "Work the steps in order: TDD, run every verification, read every output";
    "Work the steps in order: TDD, run every verification, read every output" -> "Step output matches plan's Expected?";
    "Step output matches plan's Expected?" -> "Plan wrong? Ask author or rule, and ledger. Code wrong? systematic-debugging" [label="no"];
    "Plan wrong? Ask author or rule, and ledger. Code wrong? systematic-debugging" -> "Work the steps in order: TDD, run every verification, read every output";
    "Step output matches plan's Expected?" -> "Commit as the plan's commit steps say" [label="yes, last step"];
    "Commit as the plan's commit steps say" -> "Completion contract met?";
    "Completion contract met?" -> "Work the steps in order: TDD, run every verification, read every output" [label="no - finish the task"];
    "Completion contract met?" -> "task-done: run tests, ledger the result; TaskUpdate completed + sync .tasks.json" [label="yes"];
    "task-done: run tests, ledger the result; TaskUpdate completed + sync .tasks.json" -> "More tasks remain?";
    "More tasks remain?" -> "task-start: brief + BASE; read the brief; TaskUpdate in_progress" [label="yes"];
    "More tasks remain?" -> "Final whole-branch review (fresh reviewer)" [label="no"];
    "Final whole-branch review (fresh reviewer)" -> "Re-grade, then: Critical/Important → ONE fix pass, each fix RED→GREEN + green suite; Minor → ledger";
    "Re-grade, then: Critical/Important → ONE fix pass, each fix RED→GREEN + green suite; Minor → ledger" -> "Final review clean: delete this plan's workspace";
    "Final review clean: delete this plan's workspace" -> "Use superpowers-extended-cc:finishing-a-development-branch";
}
```

## Setup

### Step 0: Load Persisted Tasks

1. Call `TaskList` to check for existing native tasks
2. **CRITICAL - Locate tasks file:** Try `<plan-path>.tasks.json`, if not found glob for matching `.tasks.json`
3. If tasks file exists AND native tasks empty: recreate from JSON using TaskCreate:
   - Include full `description` from .tasks.json (not just subject)
   - Include `metadata` field if present (files, verifyCommand, acceptanceCriteria)
   - Restore `blockedBy` with TaskUpdate
4. If native tasks exist: verify they match plan, resume from first `pending`/`in_progress`
5. If neither: bootstrap from the plan (Step 1b below)

Update `.tasks.json` after every task status change.

### Verify Workspace (Worktree Check)

Ensure the work happens in an isolated workspace. Before calling `using-git-worktrees`, check if a worktree already exists:

1. Run `git worktree list` to see all existing worktrees
2. If a worktree for the plan's branch already exists: **cd into it — do NOT create a new one**
3. If on main/master with no worktree: **REQUIRED SUB-SKILL:** Use `superpowers-extended-cc:using-git-worktrees` to create one

Never start implementation on a main/master branch without your human
partner's explicit consent.

### Workspace and Ledger

Conversation memory does not survive compaction. An inline executor that
loses its place re-implements tasks whose commits already exist — the same
failure as a controller re-dispatching them, paid for in your own context.
Track progress in a ledger file, not only in native tasks. Native tasks are
a live view; the ledger is the record.

The workspace and ledger are shared with superpowers-extended-cc:subagent-driven-development
— same directory, same format — so a plan can change executors mid-flight
and the new one resumes from the same ledger.

- Each plan owns a workspace: at skill start, run
  `bash ../subagent-driven-development/scripts/sdd-workspace PLAN_FILE` — it
  prints the plan's git-ignored directory
  (under `<repo-root>/.superpowers/sdd/`), home to every
  artifact for THIS plan: ledger, briefs, review packages. Another plan's
  directory is never yours to read or write.
- Check for this plan's ledger at `<workspace>/progress.md`. If its first
  line names your plan file, tasks with a `Task <N>: complete` line are
  DONE — do not redo them; resume at the first task without one. Their
  commits exist in git even when your context no longer remembers making
  them: after compaction, trust the ledger and `git log` over your own
  recollection. A ledger whose first line names a different plan file is
  another plan's progress: leave it and start your own, fresh.
- Create the ledger with its identity as the first line:
  `# SDD ledger — plan: <plan file path>`.
- `git clean -fdx` will destroy the workspace (it's git-ignored scratch);
  if that happens, recover from `git log`.

### Read the Plan

Read the plan once and note its context and Global Constraints. If the plan
names a Spec, read that too: the spec is the authority the plan argues from,
and conflicts inside the plan resolve against it. A plan with no reachable
spec gets a ledger note saying so — rulings made without one are provisional.

### Step 1b: Bootstrap Tasks from Plan (if needed)

If TaskList returned no tasks and no `.tasks.json` exists, or tasks don't match plan:

1. Parse the plan document for `## Task N:` or `### Task N:` headers
2. For each task found, use TaskCreate with:
   - subject: The task title from the plan
   - description: Full structured content (Goal, Files, Acceptance Criteria, Verify, Steps) with `json:metadata` code fence at the end containing files, verifyCommand, acceptanceCriteria
   - activeForm: Present tense action (e.g., "Implementing X")
3. **CRITICAL - Dependencies:** For EACH task that has blockedBy in the plan or .tasks.json:
   - Call `TaskUpdate` with `taskId` and `addBlockedBy: [list-of-blocking-task-ids]`
   - Do NOT skip this step - dependencies are essential for correct execution order
4. Call `TaskList` and verify blockedBy relationships show correctly (e.g., "blocked by #1, #2")

### Load TDD and Pre-flight

**REQUIRED SUB-SKILL:** load superpowers-extended-cc:test-driven-development now,
before Task 1. It governs every step of every task below; a plan whose
steps already say "write the failing test first" does not exempt you
from reading it.

Before Task 1, scan the plan for conflicts between tasks. The plan's
Interfaces blocks tell you where to look: for every task that consumes
what an earlier task produces, one ledger row — the two tasks, what one
produces against what the other consumes, and what you found. Tasks that
share nothing get no row; a plan whose tasks share nothing gets the single
line `Pre-flight: no shared interfaces`. Rule on each conflict a row
surfaces with the spec as the binding authority (asking the plan author
first when it is alive), record the ruling beside its row, and start
Task 1. Each task's own text is checked when you read its brief, not here.

## The Task Loop

Everything you print, and every tool result, stays resident in your
context for the rest of the session. Redirect long test output to a file
in the workspace and read its tail; read a brief, not the whole plan.

### 1. Take the task

- Run this skill's `bash scripts/task-start PLAN_FILE N`. It prints the brief
  path and BASE (the commit the task's range is cut from) in one call.
  Read the brief for every task, including ones you remember from setup:
  what you remember is a summary, the brief has the exact values,
  signatures, and test cases.
- `TaskUpdate` the task to `in_progress` and sync `.tasks.json`.

Every tool call is a turn that re-reads your whole context. Bookkeeping
rides along with work — a ledger append in the same call as the commit,
never in a call of its own.

### 2. Work the steps

The plan's steps are already in RED-GREEN order; follow them in that
order under superpowers-extended-cc:test-driven-development, loaded at setup. A test
step's code is written first and run first. Watching it fail is a step,
not a formality — a test that passes before the implementation exists is
a finding about the test.

Every step that runs a command has an `Expected:` line. Run the command,
read its output, and compare. Three outcomes:

- **Matches.** Next step.
- **The code is wrong.** Use superpowers-extended-cc:systematic-debugging. Find the
  cause; never patch the symptom to make the step's output match.
- **The plan is wrong** — a step contradicts the spec, an interface from an
  earlier task doesn't match what this task consumes, a command that
  cannot work. Ask the plan author via SendMessage if it is alive;
  otherwise rule on the smallest change that satisfies the spec. Ledger it
  as `Task <N>: Ruling: <finding> — <what you decided and why>`, and
  continue. The ruling is carried, not remembered: later tasks that touch
  the same interface read it from the ledger.

Commit as the plan's commit steps say. A task that spans several commits
is fine; BASE is what the review range is cut from, never `HEAD~1`.

### 3. The completion contract

Before a task's ledger line, all of the following are true, with evidence
in this session — not inferred from the diff looking right:

- Every test the brief names exists and ran in this task, and you read
  the output.
- The final test run for the task passed — `task-done` is that run, and
  it writes the command and result into the ledger line.
- Every `Expected:` line in the brief was compared against real output.
- Every deviation from the brief has a `Ruling:` line in the ledger.
- **Metadata verified:** Parse the `json:metadata` code fence from the task
  description, or from the task's entry in `.tasks.json` if it has none.
  `verifyCommand` was run and
  each `acceptanceCriteria` entry was checked against real output.
- **User-thrown gates are non-skippable.** If the task's metadata has `"userGate": true` OR its `tags` array contains `"user-gate"`, you MUST:
  - Execute the gate exactly as specified — no inline shortcut, no cheaper substitute, no "I already verified this informally".
  - Capture concrete output for every entry in `acceptanceCriteria` (command output, entity state, log line, subagent result).
  - If any criterion cannot be proven right now, leave the task `in_progress` and surface the blocker to the user. Do NOT close it.
  - **Do not re-decide what the plan settled.** A verification approach the plan already fixed may be re-surfaced to the user ONLY if a MATERIAL condition changed since planning: a different branch/fixture, a new blocker, or a broken plan assumption. Absent a changed condition, execute the settled verification as written. Pause for consent ONLY at the genuinely irreversible mechanical step (e.g. force-push / live merge), and frame that pause as "confirm this irreversible action," NEVER as "should we do the lesser check instead." Re-asking a settled approach with no changed condition is walking around the gate.

**REQUIRED SUB-SKILL:** superpowers-extended-cc:verification-before-completion governs
the claim. If any item is missing, the task is not complete: finish it.

### 4. Complete the task

Run this skill's `bash scripts/task-done PLAN_FILE N BASE -- <test command>`
with the test command the brief names for the whole task. It runs the
tests, keeps the full output in the workspace, prints the tail, and — only
if they pass — appends the completion line to the ledger:

`Task <N>: complete (commits <base7>..<head7>, tests: <command> → <result>)`

A failing run records nothing; the task is not complete. When it records:

1. `TaskUpdate` the task to `completed`.
2. **Sync `.tasks.json`:** Read the tasks file, update the task's `"status"` to `"completed"`, set `"lastUpdated"` to current ISO timestamp, write back. This keeps the persistence file in sync with native tasks for cross-session resume.
3. Take the next task.

## Final Review

Run `bash ../subagent-driven-development/scripts/review-package PLAN_FILE MERGE_BASE HEAD`
(MERGE_BASE = the commit the branch started from, e.g.
`git merge-base main HEAD`) and review from the file it prints.

Dispatch the reviewer on the most capable
available model — the whole-branch review is a judgment task — using
superpowers-extended-cc:requesting-code-review's
[code-reviewer.md](../requesting-code-review/code-reviewer.md), with the
package path, the plan and spec paths, the plan's Review Focus section
verbatim if it has one (the input classes and failure modes the plan's
tests do not exercise — the reviewer checks each deliberately), and a
pointer to the ledger's `Ruling:` lines so it can weigh the calls you
made. Specify the model
explicitly; an omitted model inherits the session's, which may not be the
most capable. This is the one fresh context the whole run buys. Do not
skip it, and do not replace it with your own read of the diff.

Sort the findings before you act on any of them. The reviewer's severity
labels are advice; the gate is yours. Its "Declined to judge" list is
yours too: every line there is a ruling you make and ledger, exactly like
a plan conflict — `Final: Ruling: <behavior the reviewer set aside> —
<what a reasonable person using this software gets, and why that stands
or why it is now a finding> — <cost if wrong>`. Re-grade first, by effect: the
spec is a vision document, and a finding's grade is what a reasonable
person using this software gets if it ships, not whether the spec names
the input that triggers it — a reviewer who set a finding at Minor
because the spec was silent has graded the spec, not the effect. Then:

- **Critical and Important** enter the fix pass.
- **Minor** goes to the ledger as `Final: minor (deferred): <one-liner>`
  and to your final message under "Deferred minors". Minors never enter
  the fix pass, and never become rulings — a ruling is a decision about a
  conflict, not a note that you declined a polish suggestion.

Fix the Critical and Important findings yourself — you are the
implementer here — in ONE pass. Each fix is verified by TDD, not by a
second reviewer: write the test that reproduces the finding, watch it
fail, make it pass, then run the whole suite. Record each in the ledger as
`Final: fixed <finding> — <test name> RED→GREEN, suite <N>/<N>`. A fix
without a test that failed first is not verified; a suite that is not
green after the pass means the pass is not over. Do not dispatch a
re-review: it would re-read a diff whose covering tests already answer
"addressed" and whose suite run already answers "broke nothing".

A finding you decide not to fix is a ruling — `Final: Ruling: <finding> —
<why the code stands> — <cost if wrong>` — and reaches your human partner
in the rulings list. There is no second fix pass.

## Finish

Before you delete anything, collect every ledger line containing
`Ruling:` into your final message under "Rulings I made", in the order you
made them, each with what it costs if wrong, and every `minor (deferred)`
line under "Deferred minors". Both lists are exhaustive. Your final
message is the only place the decisions you took on your human partner's
behalf — and the findings you chose not to act on — reach them.

When the final review is clean and its fixes are committed, delete this
plan's workspace directory — the git history is the record now. Sibling
directories belong to other plans; leave them alone.

Announce: "I'm using the finishing-a-development-branch skill to complete this work."

**REQUIRED SUB-SKILL:** Use superpowers-extended-cc:finishing-a-development-branch.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "I remember what Task N says" | You remember a summary. The brief has the exact values. Read it. |
| "The plan's code is right, skip watching the test fail" | A test you never saw fail proves nothing. It is one step. Run it. |
| "I'll run the full suite at the end instead of per step" | Per-step runs are how you learn which step broke it. The end-of-task run is the contract, not a substitute. |
| "The plan is wrong here, I'll just do the right thing" | Ask the plan author if it is alive, then do the right thing and ledger the ruling. Unledgered deviation is a decision made in secret. |
| "I'll write the ledger lines after a few tasks" | Compaction does not wait for a convenient moment. One line per task, in the same message as the commit. |
| "I'll sync .tasks.json at the end" | A session that dies mid-plan resumes from `.tasks.json`. Sync after every status change. |
| "Let me check in before the next task" | They chose a separate session so the plan would run. Progress prompts spend their time instead. Only the four stops stop you. |
| "I read my own diff carefully; the final reviewer is redundant" | Same author, same blind spots. The reviewer is the only fresh context this run buys. |
| "Tests should pass, the change was trivial" | "Should" is not evidence. The contract requires the command and its output. |
| "Subagents are slow and expensive, I'll skip the final review too" | Inline already removed the per-task reviewers. One review of the whole branch is the floor, not the ceiling. |
| "The reviewer said Minor, so it's Minor" | The label graded the spec's silence. Grade what the person gets. Re-grade, then gate. |
| "The fix is obvious, no need for a failing test first" | The failing test is the only proof the finding was real and is now gone. Without it you have a diff and a hope. |
| "I'll fix the minors too while I'm in there" | Every minor you fix is a test, a fix, and a suite run your partner did not ask for. Ledger them; your partner decides. |

## Example Workflow

```
You: I'm using the executing-plans skill to implement this plan.

[ListAgents: plan author session "feature-planning" is alive]
[TaskList: empty; docs/superpowers/plans/feature-plan.md.tasks.json found → TaskCreate per task with full description, blockedBy restored]
[Setup: git worktree list → existing worktree for the branch, cd into it]
[Read plan once: docs/superpowers/plans/feature-plan.md; spec read]
[Resolve workspace: bash sdd-workspace docs/superpowers/plans/feature-plan.md — no ledger inside, fresh start]
[Pre-flight scan: 2 shared-interface rows, clean; written to ledger]

Task 1: Hook installation script

[task-start plan 1 → brief read; BASE a1b2c3d; TaskUpdate in_progress]
[Step 1: write failing test — written]
[Step 2: run it — FAIL: install_hook not defined. Matches Expected.]
[Step 3: implement — written]
[Step 4: run it — PASS 1/1. Matches Expected.]
[Step 5: commit — d4e5f6a]
[Contract: tests ran, output read, verifyCommand run, acceptanceCriteria checked, no deviations]
[task-done plan 1 a1b2c3d -- npm test -- hooks → ledger: Task 1: complete (commits a1b2c3d..d4e5f6a, tests: npm test -- hooks → 1/1 pass)]
[TaskUpdate completed; .tasks.json synced]

Task 2: Recovery modes

[task-start plan 2 → brief read; BASE d4e5f6a; TaskUpdate in_progress]
[Step 2: run failing test — FAIL, but on an import error: Task 1 exported
 installHook, brief consumes install_hook]
[SendMessage to "feature-planning": which name is intended? → "installHook; the brief is a typo"]
[Ledger: Task 2: Ruling: install_hook → installHook — plan author confirmed, matches Task 1 Produces — cost if wrong: one rename]
[Steps 2-5 as planned; commit b7c8d9e]
[task-done plan 2 d4e5f6a -- npm test -- recovery → ledger: Task 2: complete (commits d4e5f6a..b7c8d9e, tests: npm test -- recovery → 8/8 pass)]
[TaskUpdate completed; .tasks.json synced]

...

[After all tasks: review-package plan MERGE_BASE HEAD; dispatch code-reviewer, most capable model]
Reviewer: One Important finding — progress reporting interval hardcoded. Two Minor.
[Re-grade: Important stands; minors → ledger as deferred]
[Fix pass: test_progress_interval_configurable RED → extract PROGRESS_INTERVAL → GREEN; suite 12/12; commit]
[Ledger: Final: fixed hardcoded interval — test_progress_interval_configurable RED→GREEN, suite 12/12]

Rulings I made:
- Task 2: install_hook → installHook (brief typo, confirmed by plan author; cost if wrong: one rename)

Deferred minors:
- README lacks a usage example
- recovery.js could split verify/repair into two files

[Delete this plan's workspace — the record now lives in git]

Using superpowers-extended-cc:finishing-a-development-branch.
```

## Integration

**Required workflow skills:**
- **superpowers-extended-cc:using-git-worktrees** - Ensures isolated workspace (creates one or verifies existing)
- **superpowers-extended-cc:writing-plans** - Creates the plan this skill executes
- **superpowers-extended-cc:test-driven-development** - Governs every step of every task
- **superpowers-extended-cc:requesting-code-review** - Final whole-branch reviewer template
- **superpowers-extended-cc:finishing-a-development-branch** - Complete development after all tasks
