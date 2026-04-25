# User-Thrown Gate Enforcement Flow

Canonical design doc for the optional gate-enforcement flow. The README section "User-Thrown Gate Enforcement — Optional Flow" is a reader-facing summary; this file is the source of truth.

## Problem

Recurring failure mode observed in real sessions:

1. User says "add a gate" / "verify it works" / "first on one then on all" — without specifying **how** the verification happens.
2. Agent invents a verification method (pick a command, pick a subagent, pick an entity).
3. At execution time the chosen method turns out expensive or annoying.
4. Agent substitutes a cheaper check inline and closes the gate.
5. User discovers later the gate was never actually run as intended.

The fix must satisfy two competing constraints:

- **Don't bombard the user during planning.** Users who want questions say "brainstorm". Mid-plan forms are friction. Tag, don't interrogate.
- **Don't let the agent silently invent gate mechanics.** That's what got us here. Force a single, focused question moment at execution time — and only when the alternative is invention.

Additional requirement: the whole enforcement apparatus is **opt-in**. Installing the plugin without enabling the hook must leave existing flows byte-for-byte unchanged.

## Architecture — two loads: surgical (main flow) vs. activated (hook-gated)

```
  ┌──────────────────────────────────────────────────────────────┐
  │   SURGICAL IMPROVEMENTS — always active, zero friction       │
  │                                                              │
  │   • writing-plans detects gate-language and tags the task    │
  │     (userGate:true, tags:["user-gate"]).                     │
  │   • executing-plans gains one rule: "run user-gate tasks     │
  │     exactly as specified, capture output per AC, do not      │
  │     substitute a cheaper check."                             │
  │                                                              │
  │   These are wins regardless of hook state. Extra metadata    │
  │   is harmless. The executing-plans rule costs one paragraph. │
  └──────────────────────────────────────────────────────────────┘

  ┌──────────────────────────────────────────────────────────────┐
  │   ACTIVATED FLOW — only when the opt-in hook is registered   │
  │                                                              │
  │   Hook (PostToolUse / Stop)                                  │
  │     └─▶ /gate-check <task-id>   (do-I-know-HOW? self-check)  │
  │            ├─▶ HOW clear      → run verify, post AC:…PROVEN  │
  │            └─▶ HOW ambiguous  → /specify-gate <task-id>      │
  │                                    ├─▶ 4 AskUserQuestion     │
  │                                    └─▶ rewrite metadata      │
  │                                    re-enter /gate-check      │
  │                                                              │
  │   Without the hook registered, /gate-check and /specify-gate │
  │   sit dormant. Nothing forces them to run.                   │
  └──────────────────────────────────────────────────────────────┘
```

### Why keep `/gate-check` out of executing-plans

Earlier drafts tried to put the "do I know HOW?" self-check inline into `executing-plans`. That pollutes a general-purpose skill with enforcement logic only some users want. Extracting it into its own slash command + skill means:

- Users without the hook installed get untouched `executing-plans`.
- Users with the hook installed get a focused, scoped handler they can read end-to-end.
- `executing-plans` keeps its short, generic shape and stays easy to reason about.

## Hook ON / Hook OFF — the activation contract

| State | What happens when executing-plans hits a user-gate task |
|-------|----------------------------------------------------------|
| **Hook ON** (registered in `.claude/settings.local.json`) | Hook stderr nudges the agent to run `/gate-check <task-id>`. That command runs the do-I-know-HOW self-check and either executes the verification with captured evidence or hands off to `/specify-gate`. Task closes only after `AC: <criterion> — PROVEN BY <evidence>` lines are posted. |
| **Hook OFF** (default) | Regular `executing-plans` flow. The surgical improvements still apply (agent runs the verifyCommand as specified, captures output), but there is no forced routing, no slash command invocation, no interactive questioner. `/gate-check` and `/specify-gate` exist but are never auto-triggered. |

**Crucial:** installing the plugin does not enable the flow. The flow activates only when you explicitly add the hook to `.claude/settings.local.json`. Remove the hook entry and the flow deactivates — the slash commands remain available for manual use but no longer run automatically.

## Layer 1 — writing-plans (silent tagging)

**Main flow, surgical.** Even without the hook.

### Detection rules

During write-plan, scan the brief and each task description for gate-language. Strict definition — tag liberally:

- Verbs: `verify`, `prove`, `validate`, `confirm`, `ensure`, `check`, `gate`
- Noun patterns: `verification gate`, `acceptance test`, `smoke test`, `end-to-end`, `E2E`
- Scope patterns: `first on one`, `then all`, `one before the rest`, `before proceeding`, `don't continue until`
- Proof-demand patterns: `prove it works`, `make sure`, `demonstrate`

Tag any matching task with:

```json
{"userGate": true, "tags": ["user-gate"], ...}
```

Add the verbatim banner near the top of the description:

> **USER-ORDERED GATE — NON-SKIPPABLE.** This task was requested by the user in the current conversation.

### Three shades of gate

The tag intentionally covers three cases:

| Shade | Example | Tagged? |
|-------|---------|---------|
| Strict user gate | User says "add a verification gate before Task 5" | Yes |
| Strict agent gate | Write-plan decides "this API change needs a smoke test" | Yes |
| Gray in-between | Task description reads "confirm the migration ran" | Yes |

Over-tagging is cheap (one extra metadata field, no user impact). Under-tagging is expensive (the whole reason this flow exists).

### HOW-specification signal

When the user's message specifies the HOW concretely (e.g., "verify `sensor.foo = idle`", "run `pytest tests/e2e.py`", "dispatch a Sonnet subagent against brief X"), encode it directly in `verifyCommand` and `acceptanceCriteria`. No further action needed at plan time.

When the user's message leaves the HOW ambiguous ("check it works", "make sure it's fine"), set an additional metadata field:

```json
{"userGate": true, "tags": ["user-gate"], "requiresUserSpecification": true}
```

This flag is Layer 2's signal to invoke `/specify-gate` on first touch, regardless of the agent's self-assessment.

**No user questions during write-plan.** The opinionated default is "tag it and move on".

## Layer 2 — `/gate-check` (separate command, hook-activated)

Runs the do-I-know-HOW? self-check in isolation and either executes the verification or routes to `/specify-gate`. Lives in `skills/checking-gates/SKILL.md`.

### When it runs

- The opt-in hook emitted stderr telling the agent to run it (auto).
- The user invoked `/gate-check <task-id>` manually.
- The agent chose to run it at start of a user-gate task (optional discipline when hook is active).

### The do-I-know-HOW? rule

A criterion has a clear HOW when all three hold:

1. **Observable named** — sensor entity, HTTP endpoint, file path, log pattern, entity ID. Not "state", not "result".
2. **Capture method named** — the command, API call, subagent, or direct read that produces the observable.
3. **Pass/fail rule named** — an exact value, regex, or threshold. Not "reasonable" or "correct".

If any of the three is missing for any criterion → the HOW is ambiguous → hand off to `/specify-gate`.

**Err on the side of ambiguity.** Inventing a HOW silently is the exact failure this flow exists to prevent.

### Evidence format

After running the verification, post exactly this shape (the Stop hook and the PostToolUse hook both key off these markers):

```
Gate: <task subject>
AC: <criterion 1> — PROVEN BY <command or excerpt of output>
AC: <criterion 2> — PROVEN BY <...>
```

Then `TaskUpdate status=completed`.

## Layer 3 — `/specify-gate` (separate command, interactive)

Lives in `skills/specifying-gates/SKILL.md`. Asks the user 3–5 short AskUserQuestion questions (outcome / mechanism / scope / failure policy / optional subagent dispatch contract), rewrites the task's metadata fence, removes `requiresUserSpecification`, appends a human-readable Specification section to the task description, and returns control.

Does NOT run verification. That's `/gate-check`'s job.

## Hooks — activation layer

Both opt-in via `.claude/settings.local.json`. See README "Recommended Configuration" for exact JSON.

| Hook | Event | Trigger | Stderr message points at |
|------|-------|---------|--------------------------|
| `post-task-complete-revalidate.sh` | `PostToolUse` matcher=`TaskUpdate` | `status=completed` on a user-gate task without `AC:…PROVEN BY` evidence posted | `/gate-check <task-id>` |
| `stop-revalidate-user-gates.sh` | `Stop` | Completion keywords ("plan complete", "both gates passed", …) + at least one closed user-gate task lacking evidence | `/gate-check <task-id>` |

Both hooks fail-open on error. Escape hatches: `SUPERPOWERS_USERGATE_GUARD=0`, `SUPERPOWERS_USERGATE_STOP_GUARD=0`.

## End-to-end example — hook ON

User's original brief: *"Build the zoo, verify it works on one instance first, then on all."*

**Layer 1 — writing-plans output (silent):**

- Task 7: E2E on one instance
  ```json
  {"userGate": true, "tags": ["user-gate"], "requiresUserSpecification": true, "gateScope": "one"}
  ```
  (Brief mentions "verify" + vague HOW → flagged for user specification)

- Task 8: E2E on all instances (blocked by #7)
  ```json
  {"userGate": true, "tags": ["user-gate"], "requiresUserSpecification": true, "gateScope": "all"}
  ```

No user questions asked. Plan is written and saved.

**Layer 2 — executing-plans reaches Task 7:**

1. Agent marks Task 7 `in_progress`.
2. Hook is active → agent runs `/gate-check 7`.
3. `/gate-check` loads metadata, sees `requiresUserSpecification: true`, hands off to `/specify-gate 7`.

**Layer 3 — `/specify-gate 7`:**

Four questions. User answers:
- **Outcome:** "`sensor.marstek_battery_<suffix>_optimization_status` reads `idle` AND JIT notification fires within 10s of recalculate"
- **Mechanism:** "Sonnet subagent using `instances/<tag>/seed-briefing.md` as prompt"
- **Scope:** "one instance per minor version"
- **Failure:** "reopen the task, do not block the plan"
- **Subagent brief:** *(user pastes the briefing template)*

Metadata updated, `requiresUserSpecification` removed. Returns control to `/gate-check 7`.

**Back in `/gate-check 7`:**

HOW is now concrete on all three axes. Dispatch the Sonnet subagent, capture the real output, post:

```
Gate: Task 7 E2E on one instance
AC: sensor optimization_status = idle — PROVEN BY curl /api/states/sensor.marstek_battery_a3f1_optimization_status → "idle"
AC: JIT notification fires within 10s — PROVEN BY notification_message diff, ts delta 5.2s
```

`TaskUpdate status=completed`. Hook sees the AC evidence in subsequent text, does not block. Gate is genuinely verified.

**If the hook had been OFF:** Step 2 above skips. Agent reads the task description, runs it as specified (surgical main-flow rule), captures output — or quietly substitutes a cheaper check if it feels like it. Exactly the pre-flow behavior, minus one paragraph of discipline added to executing-plans.

## What this does NOT do

- Does not turn every task into a gate. Only tasks matching gate-language triggers.
- Does not force questions during planning. L1 is silent.
- Does not enforce anything if the hooks aren't installed. Pure opt-in.
- Does not replace `brainstorming`. Brainstorming explores design; this flow nails down verification mechanics at the latest moment when they matter (execute time).
- Does not modify `executing-plans` decision logic. Executing-plans gains one surgical paragraph ("run gates as specified") and nothing else.

## Open work

All design-doc open items have been delivered:

- ✅ Gate-language detector step in `writing-plans` Step 1 (mechanical keyword table).
- ✅ `requiresUserSpecification`, `gateScope`, `failurePolicy`, `subagentBrief` rows added to the metadata table.
- ✅ End-to-end integration test at `tests/claude-code/test-user-gate-hooks.sh` (10 test cases including idempotency regression).
- ✅ README section distinguishes surgical (always-on) vs. activated (hook-gated) improvements.
- ✅ Per-task isolation self-check added to `writing-plans` Step 5 (catches the "sibling-bleed" pattern where concrete per-op context masks a vague final task).

### Remaining quality questions (not blocking)

- **`requiresUserSpecification` fire rate:** 0/1 in the single live opus-4.7 session. Step 5 self-check targets this; effectiveness is unverified — needs 2-3 more live sessions with varied vague phrasings to confirm.
- **Multi-harness testing:** only exercised on Claude Code via Opus 4.7. Sonnet/Haiku behavior, and Cursor/Gemini/Codex harness behavior, untested.
