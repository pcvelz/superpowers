---
name: specifying-gates
description: Use when a user-gate task has requiresUserSpecification=true OR the agent's "do I know HOW?" self-check returns no. Locks down verification mechanics through a short AskUserQuestion sequence and writes the answers back into the task's metadata. Does NOT run the verification itself.
---

# Specifying User-Thrown Gates

## When this skill runs

Exactly one of:

1. A user-gate task has `"requiresUserSpecification": true` in its `json:metadata` fence, OR
2. The agent ran the "do I know HOW?" self-check (see `executing-plans`) and concluded the verification mechanics are ambiguous, OR
3. The user ran `/specify-gate <task-id>` manually.

In all other cases — where `verifyCommand` is concrete and every `acceptanceCriteria` has an observable proof — the agent executes the gate directly and does NOT invoke this skill.

**Announce at start:** "I'm using the specifying-gates skill to lock down verification mechanics for Task N."

## CRITICAL — what this skill does NOT do

- Does not run the verification command. Specification only.
- Does not close the task. It only enriches metadata; the agent returns to `executing-plans` afterward.
- Does not re-run brainstorming. The design is already decided; only the HOW of one gate is missing.

## Input

The target task ID. Resolved from the command argument or from the currently-in-progress user-gate task.

Load the task with `TaskGet` and parse the `json:metadata` fence from its description.

## The four questions

Use `AskUserQuestion` — one question at a time per the brainstorming skill's rule.

### Q1 — Observable outcome

```yaml
AskUserQuestion:
  question: "Gate: <task subject>. What exact state proves this works? One line per criterion. 'It works' is not an answer — name a sensor, HTTP status, log line, file presence, or equivalent."
  header: "Gate outcome"
  options:
    - label: "I'll type the criteria"
      description: "Write 1-5 concrete, observable conditions"
    - label: "Copy from task's acceptanceCriteria"
      description: "Use the existing list (only if it's already concrete)"
```

Store the user's free-text answer as a list of strings in `acceptanceCriteria`. If any entry is vague (contains "works", "fine", "as expected", "properly" without a concrete target), push back and ask them to name the observable.

### Q2 — Proof mechanism

```yaml
AskUserQuestion:
  question: "How should the agent capture that state?"
  header: "Mechanism"
  options:
    - label: "CLI command"
      description: "A shell command whose output shows the criterion"
    - label: "REST / API call"
      description: "HTTP request, inspect response"
    - label: "Subagent with briefing"
      description: "Dispatch Sonnet or Haiku with a prompt template"
    - label: "Direct inspection"
      description: "Read a file, query an entity, check a log"
```

If "Subagent with briefing" → ask Q5 (dispatch contract) before proceeding.

### Q3 — Scope

```yaml
AskUserQuestion:
  question: "Run this once, or over multiple targets?"
  header: "Scope"
  options:
    - label: "Once"
      description: "Single execution, single target"
    - label: "Per instance / target"
      description: "Run identically across a list (e.g. all environments)"
    - label: "First on one, then on all"
      description: "Prove it on one target, then roll out to the rest — the classic two-gate pattern"
    - label: "Custom"
      description: "Describe the rule in free text"
```

Store as `gateScope`: `"once"` | `"per-target"` | `"one-then-all"` | custom string.

### Q4 — Failure policy

```yaml
AskUserQuestion:
  question: "If the gate fails, what happens?"
  header: "On failure"
  options:
    - label: "Stop the plan (Recommended)"
      description: "No further tasks until this gate passes"
    - label: "Reopen this task, continue others"
      description: "Mark in_progress, keep the plan moving elsewhere"
    - label: "Log and continue"
      description: "Record failure, proceed — use only for informational gates"
```

Store as `failurePolicy`: `"stop-plan"` | `"reopen-continue"` | `"log-continue"`.

### Q5 (conditional) — Subagent dispatch contract

Only when Q2 = "Subagent with briefing".

```yaml
AskUserQuestion:
  question: "Paste the exact prompt / briefing the subagent should receive. This becomes the dispatch contract — the agent cannot substitute a shorter version at runtime."
  header: "Dispatch brief"
  options:
    - label: "I'll paste it"
      description: "Provide the briefing text"
    - label: "Use instances/<tag>/seed-briefing.md"
      description: "Per-target briefing file already written by a plan task"
    - label: "Generate from task description"
      description: "Build the briefing from the task's Goal + Files + Acceptance Criteria"
```

Store as `subagentBrief` (string or file-path).

## Writing back

After all questions answered:

1. **Update the task description.** Rewrite the `json:metadata` fence with the new fields. Remove `requiresUserSpecification`. Keep everything else. Call `TaskUpdate` with the full new description.

```json:metadata
{
  "files": [...],
  "verifyCommand": "<from Q2 — the CLI/API string, or '(subagent)' sentinel>",
  "acceptanceCriteria": ["<from Q1>", ...],
  "userGate": true,
  "tags": ["user-gate"],
  "gateScope": "<from Q3>",
  "failurePolicy": "<from Q4>",
  "subagentBrief": "<from Q5 if applicable>"
}
```

2. **Append a "Specification" section** to the human-readable part of the task description, above the `json:metadata` fence:

```markdown
### Specification (via /specify-gate on <ISO-date>)

- **Outcome:** <Q1>
- **Mechanism:** <Q2>
- **Scope:** <Q3>
- **Failure policy:** <Q4>
- **Subagent brief:** <Q5 if applicable>
```

3. **Sync `.tasks.json`.** Update the task entry's description and metadata, set `lastUpdated`.

4. **Announce:** "Specification locked. Returning control to executing-plans to run the gate."

## Handoff

Control returns to `executing-plans`. The agent reads the updated task, executes `verifyCommand` (or dispatches the subagent with `subagentBrief`), captures output, and posts `AC: <criterion> — PROVEN BY <evidence>` per criterion before closing.

## What NOT to do in this skill

- Do NOT invoke `ExitPlanMode` or `EnterPlanMode`.
- Do NOT start the verification. The verification runs back in `executing-plans` after this skill exits.
- Do NOT ask more than 4-5 questions. If the user's answers feel insufficient, prefer reopening with one follow-up over piling additional questions into the initial flow.
- Do NOT write to disk anything other than the task description and `.tasks.json`. No side files.

## Integration

- **Invoked from:** `executing-plans` (automatic), `/specify-gate` slash command (manual).
- **Returns to:** `executing-plans`.
- **References:** `skills/shared/task-format-reference.md` for metadata schema.
