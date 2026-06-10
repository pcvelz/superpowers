# Workflow Configuration (Commit Strategy) — Design

Canonical design document for the opt-in workflow-configuration flow. The README section "Commit Strategy" is the reader-facing summary; this file holds the rationale, the architecture decisions, and the boundaries. The flow follows the same philosophy as `docs/model-routing-flow.md`: opt-in via config-file presence, knowledge delivered deterministically at session start, zero changes to skill prose, fail-open everywhere.

## The problem

Plan execution commits per task, by construction: the `writing-plans` Task Structure template bakes a final "Commit" step into every task, and `subagent-driven-development` implementer subagents are instructed to commit their own work. Frequent commits are a deliberate core principle and remain the default. But some teams and workflows want exactly one commit per plan — a single reviewable change set, squash-style history, or a repo policy that forbids intermediate broken-state commits on shared branches. Today that preference cannot be expressed; the per-task commits are hardcoded into the templates.

## Design decisions

**One config file, one key.** `docs/superpowers/workflow.json`, project-level, with a user-level fallback at `~/.claude/superpowers/workflow.json`. Lookup is project first, then user — the first file found wins entirely, no merging (the same lookup pattern as `model-routing.json`). Content:

```json
{"commitStrategy": "at-end"}
```

Valid values: `"per-task"` (the default) and `"at-end"`. Absent file, absent key, or any unrecognized value → per-task, byte-identical to today's behavior. Setting `"per-task"` explicitly is equivalent to no file; its only use is a project file overriding a user-level `"at-end"` default.

**Delivery via the session-start notice, not skill prose.** When `commitStrategy` resolves to `at-end`, `hooks/session-start` injects a compact `<workflow-config-active>` block into session context, telling the agent: omit per-task Commit steps from plans, add one final "Commit the full implementation" task (blockedBy all implementation tasks), and instruct implementer subagents not to commit — the coordinator's final task makes the single commit. Knowledge arrives deterministically at session start; no voluntary file read is required. The skills themselves are untouched — no conditional instructions for agents to skip under load, and vanilla behavior cannot regress because the skill text did not change.

**The config file is hostile content.** It is project-controlled, so the hook sanitizes it with the same pass as the routing file (`LC_ALL=C tr -d '[:cntrl:]'` + `iconv -c`) before parsing. The extracted value is only compared against `"at-end"`, never embedded in the emitted JSON.

**No enforcement gates in v1 — a deliberate, documented boundary.** Model routing got gates because uncontrolled cost is an invariant worth enforcing per tool call. Commit strategy is a workflow preference, not a cost or safety invariant: the failure mode of non-compliance is extra commits — today's default behavior, fully recoverable with an interactive rebase. Soft delivery via the session notice is the accepted reliability tradeoff. This means compliance depends on the agent honoring the notice at plan-writing and dispatch time; there is no hook that blocks a plan task containing a Commit step or an implementer prompt containing a commit instruction.

**Fail-open everywhere.** Unreadable file, invalid JSON, control bytes, unknown values: the hook emits no notice and behavior stays per-task. A typo in the config must not brick a session or surprise anyone with a behavior change.

## What this flow does NOT do

- **No enforcement gate.** The notice is the only mechanism; it relies on plan-time and dispatch-time compliance. Plans written before the config existed keep their per-task Commit steps — the notice does not rewrite existing plans.
- **No commit policy.** Message format, signing, branch protection, push behavior are out of scope; the key only decides *when* plan execution commits.
- **No partial-progress safety net at `at-end`.** With a single final commit, a mid-plan failure leaves all changes uncommitted in the working tree. That is inherent to the chosen strategy; teams who want incremental recovery points should stay on the default.
- **No merging of project and user files.** The first file found wins entirely, exactly like model routing.

## Future directions (explicitly out of scope today)

- **TaskCreate-gate hardening:** if live sessions show drift (plans still carrying per-task Commit steps while `at-end` is configured), a PreToolUse gate on TaskCreate could block plan tasks whose steps contain commit commands — same self-teaching block-message pattern as the model-tier gate.
- **More workflow keys:** `workflow.json` is deliberately named generically; future workflow preferences can live alongside `commitStrategy` without a new file or lookup mechanism.

## Verifying it works

- Session notice: start a session in a project whose `docs/superpowers/workflow.json` contains `{"commitStrategy": "at-end"}`; the injected context contains `<workflow-config-active>`. Remove the file (or set `"per-task"`): the block is absent and output is byte-identical to vanilla.
- Hook output stays valid JSON in both states: run `hooks/session-start` with `CLAUDE_PLUGIN_ROOT` set and pipe the output through `python3 -c "import json,sys; json.load(sys.stdin)"`.
- Plan-level: with the notice active, a freshly written plan must contain no per-task Commit steps and exactly one final commit task blocked by all implementation tasks.
