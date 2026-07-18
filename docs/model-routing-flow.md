# Subagent Model Routing — Design

Canonical design document for the opt-in model-routing flow. The README section "Subagent Model Routing — Optional Flow" is the reader-facing summary; this file holds the full rationale, the economics, the architecture decisions, and the boundaries.

## The problem

Frontier-priced models (Opus-class and above; the Fable tier made this acute) changed the economics of agentic plan execution. The cost driver is not the rate card — it is fan-out:

- One plan task in `subagent-driven-development` dispatches an implementer, a spec reviewer, and a code-quality reviewer. Review loops re-dispatch the implementer and re-run reviewers. BLOCKED escalations re-dispatch again. A ten-task plan is thirty-plus subagent dispatches before counting a single retry.
- Every dispatch inherits the session model by default. On a frontier session, the most expensive model multiplies across tasks that are, by the plan's own design, mechanical.
- **Prompt caching does not solve this.** Caching discounts *input* tokens. Fan-out cost is dominated by *output* tokens — plans, subagent instructions, generated code, review reports, self-checks, retries are all freshly generated, full-rate output, every time. Output is also the direction where frontier pricing is steepest. A cost strategy that relies on caching addresses the cheap half of the bill.
- The fix the wider agent-builder community converged on: classify work upfront, route the bulk of actions to cheap models, reserve frontier capability for steps that genuinely need it. The majority of implementation tasks in a well-specified plan are mechanical — complete steps are precisely what makes them so. A plan that needed frontier reasoning for every step would be a failed plan by this plugin's own standards.

## Design decisions

**Abstract tiers, not model names, in plans.** Tasks carry `"modelTier": "mechanical" | "standard" | "frontier"` in their `json:metadata` fence. Model lineups change; plans survive. The project's `docs/superpowers/model-routing.json` decides what a tier means today. A concrete `"model"` pin in task metadata overrides the tier for tasks that need a specific model (empirical A/B measurements, pinned judgment calls); pins are enforced separately by the opt-in `pre-agent-task-dispatch-validate` hook.

**One opt-in switch: the routing file.** `docs/superpowers/model-routing.json` present → routing active. Absent → every routing component no-ops and behavior is byte-identical to vanilla. No settings registration, no second step. `/onboard` writes the file; deleting it switches everything off instantly.

**Optional `sonnetEffort` key (advisory only, defaults to medium).** The routing file may also carry a top-level `"sonnetEffort": "medium"` key. `/onboard` offers it whenever a tier resolves to `sonnet`. Above medium reasoning effort, Sonnet stops being cheaper than Opus at high effort while giving lower fidelity, so a high/xhigh Sonnet dispatch is a misconfiguration rather than a cost saving. Unlike tier routing, this key has **no enforcement gate** — the Claude Code `Agent` tool's input schema has no `effort` parameter to check, so `pre-agent-model-routing` cannot validate it. Delivery is the session-start notice only (`<sonnet-effort-active>`), which surfaces the recommendation at the moment a coordinator is about to dispatch. **The key does not need to be present to get the notice:** whenever any tier in the mapping resolves to `sonnet`, the notice fires with "medium" as an implicit default even if `sonnetEffort` was never written — this covers installs that onboarded before this key existed, without requiring a re-run of `/onboard`. An explicit `sonnetEffort` value in the file overrides the implicit default and is labeled "user-set" in the notice. Removing the key only reverts to the implicit-medium default, not to silence; there is no way to suppress the notice short of removing `sonnet` from the mapping or deleting the routing file.

**Gates, not prose.** This plugin's recurring lesson — written into `pre-agent-task-dispatch-validate.sh` as "skill prose is not enforcement; this hook is" — applies doubly to cost rules. An agent mid-plan under cognitive load skips conditional instructions and rationalizes ("I know what tiers mean"). So the skills contain **no routing instructions at all**, only inert `modelTier` stub keys in metadata examples. The flow is delivered by four harness-executed layers:

1. **Session notice** (`hooks/session-start`): when the routing file exists, the tier rules and the project's mapping are injected into session context at startup. Knowledge arrives without any voluntary file read.
2. **Plan gate** (`hooks/pre-taskcreate-model-tier`, PreToolUse on TaskCreate): a plan task missing a valid `modelTier` is blocked — identified by its `json:metadata` fence, or, when the fence is missing, by plan shape (template headers in the description / numbered-plan subject), so fence-less plan tasks cannot bypass the gate (the session 2013ea56 failure mode). The block message embeds the full tier table and tie-break rule — self-teaching at the moment of violation.
3. **Dispatch gate** (`hooks/pre-agent-model-routing`, PreToolUse on Agent): while a tiered task is in progress, an Agent dispatch must use an allowed model (below). The block message names the correct dispatch per role.
4. **Handoff guard** (`hooks/pre-askuser-handoff-guard`, PreToolUse on AskUserQuestion): when `writing-plans` has been invoked and tasks created, the only permitted `AskUserQuestion` at the handoff point must carry exactly the two mandated options ("Subagent-Driven (this session)" / "Parallel Session (separate)"). Any other structure is blocked. This gate was motivated by a live bypass (session 2013ea56) where a 19-task plan produced a four-option phased menu instead of the handoff, and the subagent pipeline — where model routing operates — never engaged.

Every layer is dormant without the routing file (one file-existence check, then allow), fails open on parse errors, and shares the kill switch `SUPERPOWERS_ROUTING_GUARD=0`. Trace log: `/tmp/claude-hooks/user-gate-trace.log`.

**The dispatch gate enforces a set, not a single model.** Reviewer subagents are dispatched while the same task is in progress, and reviewers deliberately run at `standard`. And because bounded parallel dispatch allows several disjoint tasks to be in progress at once, the gate validates against the UNION of every in-progress task's resolved tier, plus `standard`: `{ resolve(tier) for each in_progress task } ∪ { resolve("standard") }`. If any member resolves to `"inherit"`, the gate stands down entirely. This catches the failure that matters — a mechanical task's implementer dispatched at session price — without blocking legitimate reviewer dispatches or a parallel sibling task's correctly-tiered implementer.

**Role tiers.** Implementer and fix re-dispatches: the task's tier. Spec reviewer and code-quality reviewer: `standard` — compliance and diff-anchored review are mid-tier work, and review output is the expensive direction; leaving reviewers at session level was measured (in design-phase simulation) to keep ~46% of dispatches at frontier price, defeating the opt-in. Final whole-plan reviewer: runs after all tasks complete, so no task is in progress and the gate does not constrain it — it inherits the session model, one frontier judgment pass per plan.

**Tie-break for tier assignment.** Spec completeness wins: a task whose steps contain the complete code is `mechanical` regardless of file count; upgrade to `standard` only when the implementer must exercise judgment the steps don't capture. Assign tiers after the Steps are written, not before. Blanket assignments in either direction (everything `mechanical` to chase cost, everything `frontier` to play safe) defeat the feature.

**Escalation goes up, transparently.** An implementer that reports BLOCKED for reasoning depth gets re-dispatched one tier higher (`mechanical → standard → frontier`) by updating the task's metadata via TaskUpdate — visible, never a silent workaround. Downgrades are never silent. Reviewers do not tier-climb; a reviewer that cannot complete its review is a blocker to raise with the human partner.

**Fail-open everywhere except the block itself.** Unknown tier values, unparseable routing files, missing transcripts, malformed fences: allow and trace. Typos must not brick a session. The plan gate catches invalid tier values at creation time, which is the right place; the dispatch gate fails open on them.

## What this flow does NOT do

Stated plainly so nobody mistakes model selection for cost governance:

- **No token budgets or spend ceilings.** Routing lowers the per-token rate of dispatches. A plan with many retries still spends what it spends — at a lower rate, without a cap.
- **No per-task cost observability.** The plugin has no access to billing or token telemetry; it cannot report what a task cost.
- **No blast-radius estimation.** There is no pre-dispatch token-ceiling prediction or budget pre-validation. (Claude Code's native `Workflow` tool has a per-turn `budget` API; that is session tooling, not plugin scope.)
- **Role tiers for reviewers are gate-bounded, not gate-exact.** The gate guarantees a reviewer dispatch is within the allowed set; choosing `standard` rather than the task tier for a reviewer remains the coordinator's move, taught by the session notice and the gate messages.
- **Routing only engages when the coordinator dispatches subagents.** Nothing in the harness compels the coordinator to dispatch rather than implement inline. A session where the coordinator handles tasks itself bypasses both tier routing and the two-stage per-task review; the gate never fires because no Agent call is made. The flow's cost and quality properties are contingent on dispatch actually happening.
- **The routing file maps tiers to model names; name resolution is environment-dependent.** A proxy or harness configuration that rewrites model names (for example, mapping `haiku` to a local model) changes the effective capability floor and cost basis. The "cheapest model that can handle it" tier reasoning is calibrated against the named Anthropic model. Environments that substitute a different model under the same name get different capability and cost characteristics than the tier assignment implies.

## Future directions (explicitly out of scope today)

- **Full parallel wave dispatch:** bounded parallelism has shipped — `subagent-driven-development` permits concurrent dispatch for tasks with disjoint `files` lists and independent `blockedBy` chains (plus always-safe read-only agents), and the dispatch gate validates against the union of in-progress tiers. What remains future is the unbounded version: waves of overlapping writers isolated in per-agent worktrees. Routing is the prerequisite either way — fan-out multiplies subagent count, routing keeps the multiplication cheap.
- **Routing for one-shot reviewer dispatches** in `brainstorming` (spec-document reviewer) and `writing-plans` (plan-document reviewer): medium cost, judgment-shaped; candidates for the `standard` tier once the core flow has real-session evidence.
- **Tier-aware budget gates:** combining the routing file with per-plan dispatch-count ceilings.

## Verifying it works

- Session notice: start a session in a project with the routing file; the injected context contains `<model-routing-active>` with your mapping.
- Plan gate: with the routing file present, issue a TaskCreate whose description has a `json:metadata` fence without `modelTier` — it must block with the tier table. `bash tests/claude-code/test-taskcreate-tier-hook.sh` covers the matrix.
- Dispatch gate: with a tiered task in progress, dispatch an Agent with a disallowed model — it must block and name the allowed dispatches. `bash tests/claude-code/test-model-routing-hook.sh` covers the matrix.
- Handoff guard: with the routing file present, writing-plans invoked, and tasks created, a non-handoff `AskUserQuestion` must block with the required YAML. `bash tests/claude-code/test-handoff-guard.sh` covers the matrix.
- Trace: `tail -F /tmp/claude-hooks/user-gate-trace.log` while exercising any layer.
