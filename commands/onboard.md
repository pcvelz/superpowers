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

- **One fixed model** → ask the model follow-up below first (do NOT write before both answers), then write the same structure with all three tiers set to the chosen value.

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

- **No** → write nothing.

After writing the file, tell the user: the plugin's routing gates activate immediately (they check for this file on every relevant tool call), and from the next session on a routing notice is injected at session start. No restart, no settings edits, no hook registration needed. Off-switch: delete the file.

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

## Closing

Report in one short block: the chosen scope, files written (confirmed absolute paths), features skipped, and how to undo each — delete the scope's `model-routing.json` (routing); remove the hook objects you added from the arrays in the scope's settings file, `<cwd>/.claude/settings.json` or `~/.claude/settings.json` (gate hooks); delete the scope's `workflow.json` or remove its `commitStrategy` key (commit strategy). Do not commit. Do not re-ask any question.
