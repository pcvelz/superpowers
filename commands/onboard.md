---
description: "Guided setup for superpowers' optional features. Asks short multiple-choice questions and writes the chosen configuration files in place. Everything it configures can also be set up manually — see README.md."
---

# Superpowers Onboarding

Walk the user through superpowers' optional features one at a time. For each feature: ask, then immediately write the chosen configuration — no deferred "now apply this yourself" summary.

## Ground rules

- **Assume a clean slate.** Do NOT scan for existing configuration before asking — go straight to the questions. The user runs this command to set settings, not to audit them.
- **Discrepancy handling (the only state handling you do):** if a file you are about to write already exists with different content, stop and show the difference, then let the user decide free-form (keep / overwrite / adjust). "Different" means: for `docs/superpowers/model-routing.json` and `docs/superpowers/workflow.json`, any existing content that differs from what you are about to write; for `.claude/settings.json`, an existing hook entry whose `command` references the same script filename you are adding.
- Each feature is optional. "No" means write nothing and move to the next feature.
- **NEVER commit anything.** Files are written to the working tree only; committing is the user's call.
- After the last feature, summarize: what was written and where, what was skipped, and how to undo each (see Closing).

## Scope — ask ONCE, before Feature 1

One scope answer governs every write in this run: config files AND hook registrations.

```yaml
AskUserQuestion:
  question: "Where should superpowers configuration live?"
  header: "Scope"
  multiSelect: false
  options:
    - label: "This project (recommended)"
      description: "Config files in docs/superpowers/ of this repo; hook registrations in this project's .claude/settings.json. Applies only here. Create missing directories; that is intentional."
    - label: "User-level (all projects)"
      description: "Config files in ~/.claude/superpowers/; hook registrations in ~/.claude/settings.json. Applies to every project without its own project-level config; a project file always overrides entirely."
```

The scope fixes these targets for the rest of the run:

| Scope | Config files (Features 1 & 3) | Hook registrations (Feature 2) |
|-------|-------------------------------|--------------------------------|
| This project | `docs/superpowers/<file>.json` | `<cwd>/.claude/settings.json` |
| User-level | `~/.claude/superpowers/<file>.json` | `~/.claude/settings.json` |

State the two chosen targets back to the user in one line, then proceed to Feature 1. Never re-ask scope per feature.

## Feature 1: Subagent Model Routing

One-line intro for the user before asking: plan execution dispatches an implementer plus reviewers per task, and by default they all inherit the session model — on frontier-priced sessions (Opus, Fable) that multiplies the most expensive model across routine tasks. Full explanation: README.md → "Subagent Model Routing — Optional Flow".

```yaml
AskUserQuestion:
  question: "Enable model routing for plan-execution subagents?"
  header: "Routing"
  multiSelect: false
  options:
    - label: "Guided tiers (recommended)"
      description: "mechanical→haiku, standard→sonnet, frontier→session model. Cheap models for routine implementation, mid-tier for integration and reviews, full power only where judgment lives."
    - label: "One fixed model"
      description: "Every subagent uses one model you pick next — flat cost cap, no per-task gradation."
    - label: "No"
      description: "Keep the default: every subagent inherits the session model. Nothing is written."
```

- **Guided tiers** → write `model-routing.json` to the scope's config target with this content:

  ```json
  {"mechanical": "haiku", "standard": "sonnet", "frontier": "inherit"}
  ```

  "standard" resolves to `sonnet`, so also ask the Sonnet effort follow-up below before writing (fold `sonnetEffort` into the same file).

- **One fixed model** → ask the model follow-up below first (do NOT write before both answers), then write the same structure with all three tiers set to the chosen value. If the chosen model is `sonnet`, also ask the Sonnet effort follow-up below before writing (fold `sonnetEffort` into the same file).

  ```yaml
  AskUserQuestion:
    question: "Which model should every subagent use?"
    header: "Model"
    multiSelect: false
    options:
      - label: "haiku"
        description: "Cheapest and fastest. Fine when plans are well-specified."
      - label: "sonnet"
        description: "Mid-tier reasoning at mid-tier price. The balanced cap."
      - label: "opus"
        description: "Frontier reasoning. Caps cost only on Fable-class sessions."
      - label: "fable"
        description: "Highest capability and price. Only useful as a cap if your session model is above it."
  ```

- **Sonnet effort follow-up** (ask whenever `sonnet` is the resolved model for any tier — "standard" in Guided tiers, or the chosen model in One fixed model):

  ```yaml
  AskUserQuestion:
    question: "What reasoning effort should Sonnet subagent dispatches use?"
    header: "Sonnet effort"
    multiSelect: false
    options:
      - label: "Sonnet at medium effort (Recommended)"
        description: "Above medium, Sonnet stops being cheaper than Opus at high effort while giving lower fidelity — high/xhigh Sonnet dispatches pay Opus-class cost without Opus-class quality. Medium is the sweet spot."
      - label: "Leave effort unset"
        description: "Dispatches inherit whatever effort the session or agent definition already uses. No recommendation is written."
  ```

  - **Medium (Recommended)** → add `"sonnetEffort": "medium"` as a top-level key in the same `model-routing.json` write (alongside the tier mapping).
  - **Leave unset** → write the tier mapping only; do not add the key.

- **No** (to the top-level routing question) → write nothing.

After writing the file, tell the user: the plugin's routing gates activate immediately (they check for this file on every relevant tool call), and from the next session on a routing notice is injected at session start. No restart, no settings edits, no hook registration needed. Off-switch: delete the file. If `sonnetEffort` was written, note that it is advisory only — no gate enforces it (the Agent tool has no effort parameter to check) — the session-start notice is the entire delivery mechanism; removing the key or the file turns the notice off.

## Feature 2: User-Thrown Gate Enforcement Hooks

One-line intro: when the user asks for a verification gate ("make sure X works before proceeding"), opt-in hooks force re-validation with captured evidence when such a task is closed — without them, gate tags are inert metadata. Full explanation: README.md → "User-Thrown Gate Enforcement — Optional Flow".

```yaml
AskUserQuestion:
  question: "Enable enforcement hooks for user-thrown verification gates?"
  header: "Gates"
  multiSelect: false
  options:
    - label: "Yes, both hooks (recommended)"
      description: "Per-task close enforcement + end-of-plan stop enforcement. They compose."
    - label: "Per-task hook only"
      description: "Only re-validate when an individual gate task is closed."
    - label: "No"
      description: "Gate tagging stays inert metadata. Nothing is written."
```

On yes, write the hook registration(s) into the scope's settings target — `<cwd>/.claude/settings.json` for this-project scope, `~/.claude/settings.json` for user-level:

1. Take the JSON block(s) from README.md → "Recommended Configuration": "Force Re-Validation on User-Thrown Gate Close" (per-task) and "Re-Validate Gates on 'Plan Complete' Claims" (end-of-plan).
2. **Verify the script path before writing.** The README blocks reference scripts under `~/.claude/plugins/marketplaces/superpowers-extended-cc-marketplace/hooks/examples/`. Check that path exists (`ls` the directory); if the plugin lives elsewhere on this machine, substitute the real path in the `command` values.
3. **Merge, never overwrite.** Read the scope's settings file first (resolve a symlink and edit the real target). If it exists: parse it, append each new hook entry into the matching array (`hooks.PostToolUse` / `hooks.Stop`), creating only the missing keys, and write the full merged result back. If it does not exist: create it containing only the chosen hooks structure. Never drop existing entries.
4. **Duplicate check spans both scopes:** if the same hook script is already registered in EITHER the project file or the user file, do not add it again — report where it already lives and which scope it covers.
5. **Confirm the write.** Re-read the target file, verify the new entries parse and are present, and report the confirmed absolute path back to the user. Output of this feature MUST name the file that was actually written.
6. **"Yes" also disables Auto Plan Mode:** merge `{"permissions": {"deny": ["EnterPlanMode"]}}` into the scope's settings file (same read-merge-write as step 3).

## Feature 3: Commit Strategy

One-line intro: plan execution commits after every task by default — each plan task ends with its own Commit step and implementer subagents commit their own work; switching to a single commit at the end of the plan gives one reviewable commit per feature. Full explanation: README.md → "Commit Strategy".

```yaml
AskUserQuestion:
  question: "How should plan execution commit its work?"
  header: "Commits"
  multiSelect: false
  options:
    - label: "Per-task commits (recommended)"
      description: "The default: every task ends with its own commit — fine-grained history, per-task rollback. Nothing is written."
    - label: "Single commit at plan end"
      description: "Tasks leave changes uncommitted; one final plan task commits the full implementation as a single commit."
```

- **Per-task commits** → write nothing (an absent file already means per-task).
- **Single commit at plan end** → write `workflow.json` to the scope's config target with this content:

  ```json
  {"commitStrategy": "at-end"}
  ```

After writing the file, tell the user: this feature has no enforcement gates — it is delivered by a notice injected at session start, so it takes effect from the next session on (the current session keeps per-task behavior). Off-switch: delete the file, or remove the `commitStrategy` key.

## Feature 4: Plugin Auto-Update

One-line intro: third-party marketplaces do NOT auto-update by default, so new `superpowers-extended-cc` releases won't reach this install on their own — you'd have to run `/plugin marketplace update` by hand each time. Enabling auto-update lets Claude Code refresh the marketplace and its plugins at startup.

**This feature is the one exception to the clean-slate rule** — it checks current state before asking, because proposing a change that is already in place is noise. Auto-update is marketplace-level (there is no per-plugin toggle) and lives wherever the marketplace is registered — almost always user-level `~/.claude/settings.json`. The onboard scope choice does NOT apply here; marketplaces are registered user-wide.

1. **Detect.** Read `~/.claude/settings.json` (resolve a symlink to the real target) and inspect `extraKnownMarketplaces["superpowers-extended-cc-marketplace"].autoUpdate`. If the marketplace entry is not there, check the project `<cwd>/.claude/settings.json`. Then:
   - `true` → already enabled: tell the user, write nothing, move on.
   - `false` or the key absent → not enabled; ask.
   - marketplace entry in neither file → it is not registered in settings (unusual for an installed plugin); say so and skip this feature. Do NOT invent a marketplace entry.

2. **Ask** (only when not already enabled):

   ```yaml
   AskUserQuestion:
     question: "Enable auto-update for the superpowers-extended-cc marketplace? New releases would then install at the next Claude Code startup."
     header: "Auto-update"
     multiSelect: false
     options:
       - label: "Yes, enable auto-update (recommended)"
         description: "Sets autoUpdate=true on the marketplace entry in settings.json. Claude Code refreshes the marketplace and updates its plugins at the next startup."
       - label: "No"
         description: "Leave it off — stay on the current version until you run /plugin marketplace update manually. Nothing is written."
   ```

3. **Yes** → set `extraKnownMarketplaces["superpowers-extended-cc-marketplace"].autoUpdate = true` in the file where that entry lives. Read-merge-write (resolve the symlink, edit the real target); never drop the entry's other keys (e.g. `source`) or any other marketplace. Re-read to confirm the value is `true`, report the absolute path written, and tell the user it takes effect at the next Claude Code startup (no in-session restart).

4. **No** → write nothing.

## Final step: remove the upstream double-install (optional)

Installing `superpowers-extended-cc` alongside the original `obra/superpowers` leaves both active at the same time. Every skill ships under both the `superpowers:` namespace and the `superpowers-extended-cc:` namespace — the slash-command palette shows doubled entries for `brainstorming`, `writing-plans`, `executing-plans`, and every other shared skill, and the session-start skill loader may trigger either version ambiguously. This fork supersedes upstream, so the original is redundant once the fork is installed.

Assess for yourself whether both are actually present. This fork lives at `~/.claude/plugins/marketplaces/superpowers-extended-cc-marketplace/`; the upstream plugin would sit right next to it at `~/.claude/plugins/marketplaces/superpowers-marketplace/`, or — if it came from the official plugin directory instead — be registered as `superpowers@claude-plugins-official` in `~/.claude/plugins/installed_plugins.json`.

If upstream is not there: say nothing, skip this step entirely, and proceed directly to Closing.

If both are present: explain the conflict to the user in one short paragraph — both plugins are active, they ship identical skill names under two prefixes, and the fork supersedes upstream — then, and only then, ask:

```yaml
AskUserQuestion:
  question: "Remove the upstream obra/superpowers plugin to clear the duplicate entries?"
  header: "Double-install"
  multiSelect: false
  options:
    - label: "Yes, remove upstream"
      description: "Uninstall the upstream superpowers plugin and, if it was the only plugin from that marketplace, remove the marketplace too. Uses /plugin in-context."
    - label: "No, leave both installed"
      description: "Keep both active — you can clean this up later via /plugin."
```

- **Yes** → carry out the removal via the `/plugin` interface in-context: uninstall the upstream plugin (`superpowers@superpowers-marketplace` or `superpowers@claude-plugins-official`, whichever is registered), then, if its marketplace now has no other installed plugins, remove the marketplace as well. Confirm each step back to the user.
- **No** → acknowledge and move on.

## Closing

Report in one short block: the chosen scope, files written (confirmed absolute paths), features skipped, and how to undo each — delete the scope's `model-routing.json` (routing); remove the hook objects you added from the arrays in the scope's settings file, `<cwd>/.claude/settings.json` or `~/.claude/settings.json` (gate hooks); delete the scope's `workflow.json` or remove its `commitStrategy` key (commit strategy); set `extraKnownMarketplaces["superpowers-extended-cc-marketplace"].autoUpdate` back to `false` in settings.json (auto-update). Do not commit. Do not re-ask any question.
