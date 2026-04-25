# Native Task Format Reference

Skills that create native tasks (TaskCreate) MUST follow this format.

## Task Description Template

Every TaskCreate description MUST follow this structure:

### Required Sections

**Goal:** One sentence — what this task produces (not how).

**Files:**
- Create/Modify/Delete: `exact/path/to/file.py` (with line ranges for modifications)

**Acceptance Criteria:**
- [ ] Concrete, testable criterion
- [ ] Another criterion

**Verify:** `exact command to run` → expected output summary

### Optional Sections (include when relevant)

**Context:** Why this task exists, what depends on it, architectural notes.
Only needed when the task can't be understood from Goal + Files alone.

**Steps:** Ordered implementation steps (only for multi-step tasks where order matters).
TDD cycles happen WITHIN steps, not as separate steps.

## Metadata Schema

Embed metadata as a `json:metadata` code fence at the end of the TaskCreate description. The `metadata` parameter on TaskCreate is accepted but **not returned by TaskGet** — embedding in the description is the only reliable way.

| Key | Type | Required | Purpose |
|-----|------|----------|---------|
| `files` | string[] | yes | Paths to create/modify/delete |
| `verifyCommand` | string | yes | Command to verify task completion |
| `acceptanceCriteria` | string[] | yes | List of testable criteria |
| `estimatedScope` | "small" \| "medium" \| "large" | no | Relative effort indicator |
| `userGate` | boolean | no | `true` when the user explicitly requested this task as a verification gate. Signals to hooks and reviewers that the task is USER-ORDERED and MUST NOT be closed until its `acceptanceCriteria` have been re-validated independently. See "User-Thrown Gates" below. |
| `tags` | string[] | no | Free-form tags (e.g. `["user-gate", "verification"]`). Opt-in hooks key off tags like `user-gate` to trigger re-validation on close. |
| `requiresUserSpecification` | boolean | no | Set by `writing-plans` when the user's brief says WHAT should be verified but not HOW. Signals to `/gate-check` that it must hand off to `/specify-gate` before running verification. Removed automatically once `/specify-gate` has captured the HOW. |
| `gateScope` | "once" \| "per-target" \| "one-then-all" \| string | no | How many times / across how many targets the gate should run. Set by `/specify-gate` (Q3). Free-form string allowed for custom rules. |
| `failurePolicy` | "stop-plan" \| "reopen-continue" \| "log-continue" | no | What happens if the gate fails. Set by `/specify-gate` (Q4). |
| `subagentBrief` | string | no | Exact prompt/briefing for the dispatch subagent when the gate's proof mechanism is "subagent". Set by `/specify-gate` (Q5). Agent MUST pass this verbatim at dispatch — substituting a shorter version defeats the purpose. |

## User-Thrown Gates

A **user-thrown gate** is a verification task the user *explicitly asked for in the conversation* — not a check you invented while decomposing the plan. Typical signals in the user's message: "make sure to verify X before moving on", "add a gate", "run the full end-to-end before closing", "don't proceed until Y is proven", "first on one, then on all".

When you create such a task, set BOTH:
- `userGate: true`
- `tags: ["user-gate"]` (append, do not replace existing tags)

And add a mandatory line in the task description, verbatim:

> **USER-ORDERED GATE — NON-SKIPPABLE.** This task was requested by the user in the current conversation. It MUST NOT be closed by walking around it, by declaring it "verified inline", or by substituting a cheaper check. Close only after every item in `acceptanceCriteria` has been re-validated independently, with output captured.

Why both the flag and the prose: the prose protects the current session (visible to TaskGet), the flag protects future hooks and subagents that parse metadata.

### Example — user-thrown gate

```yaml
TaskCreate:
  subject: "Gate 1: End-to-end verification on one instance"
  description: |
    **Goal:** Prove the full pipeline works on exactly ONE instance before scaling to all.

    **USER-ORDERED GATE — NON-SKIPPABLE.** This task was requested by the user in the current conversation. It MUST NOT be closed by walking around it, by declaring it "verified inline", or by substituting a cheaper check. Close only after every item in `acceptanceCriteria` has been re-validated independently, with output captured.

    **Acceptance Criteria:**
    - [ ] Fresh instance spun up from scratch
    - [ ] Sonnet subagent dispatched with its briefing (no inline shortcut)
    - [ ] JIT event captured in notification_message
    - [ ] Manager scrape shows the event

    **Verify:** `./zoo.sh status <tag>` + `cat logs/<tag>.jsonl | tail -1`

    ```json:metadata
    {"files": [], "verifyCommand": "./zoo.sh status v0.1.15 && cat logs/v0.1.15.jsonl | tail -1", "acceptanceCriteria": ["Fresh instance spun up from scratch", "Sonnet subagent dispatched with its briefing", "JIT event captured in notification_message", "Manager scrape shows the event"], "userGate": true, "tags": ["user-gate", "verification"]}
    ```
```

### Example

```yaml
TaskCreate:
  subject: "Add JIT selection prompt to /hame Pre-flight"
  description: |
    **Goal:** Replace auto-latest JIT selection with interactive 3-option prompt.

    **Files:**
    - Modify: `.claude/commands/hame-optimal-cycle-inspection.md:45-60`

    **Acceptance Criteria:**
    - [ ] AskUserQuestion presents 3 most recent JIT messages
    - [ ] Selected JIT's SOC and schedule are parsed into variables
    - [ ] --jit override bypasses the prompt (backwards compat)

    **Verify:** Read the Pre-flight Step 2 section and confirm AskUserQuestion block with 3 JIT options

    ```json:metadata
    {"files": [".claude/commands/hame-optimal-cycle-inspection.md"], "verifyCommand": "grep -A 20 'Step 2' .claude/commands/hame-optimal-cycle-inspection.md", "acceptanceCriteria": ["AskUserQuestion with 3 JIT options", "SOC + schedule parsed from selection", "--jit override bypasses prompt"]}
    ```
```

## Task Granularity

### The Right Scope

A task is **a coherent unit of work that produces a testable, committable outcome**.

**Scope test — ask these questions:**
1. Does this task produce something I can verify independently? (if no → too small)
2. Does it touch more than one concern? (if yes → too big)
3. Would it get its own commit? (if no → too small; if commit message needs bullet points → too big)

### Examples

| Scope | Example | Why |
|-------|---------|-----|
| Too small | "Write failing test for X" | Not independently verifiable — needs implementation |
| Too small | "Run pytest" | Verification step, not a task |
| Too small | "Add import statement" | Part of a larger change |
| **Right** | "Implement WebSocket protocol layer with tests" | Coherent unit, testable, one commit |
| **Right** | "Add JIT selection prompt to Pre-flight" | Single concern, verifiable, one commit |
| **Right** | "Create optimizer test class for SOC 73% case" | Complete test suite for one scenario |
| Too big | "Implement entire auth system" | Multiple concerns, multiple commits |
| Too big | "Fix all /hame output issues" | Multiple independent changes |

### TDD Within Tasks (Not Across Tasks)

TDD cycles (write test → verify fail → implement → verify pass) happen WITHIN a single task, not as separate tasks. The task is "Implement X with tests" — the TDD steps are execution detail, not task boundaries.

### Commit Boundary = Task Boundary

Each task should produce exactly one commit. If a task needs multiple commits, split it. If separate tasks share a commit, merge them.
