---
name: release
description: Use when publishing a new version of superpowers-extended-cc - handles upstream sync, version bump, testing, tagging, and GitHub release creation
---

# Release

## Overview

Full release workflow for superpowers-extended-cc fork. Handles upstream sync, testing, version bumping, and publishing.

**Announce at start:** "Using release skill to publish a new version."

## The Process

### Step 1: Run Tests

```bash
./tests/claude-code/run-skill-tests.sh --verbose
```

If tests fail, use `AskUserQuestion`: "Tests failed (flaky due to LLM output variation). Proceed anyway or investigate?"

### Step 2: Check Upstream

```bash
bash /Users/peter/Documents/Code/master-template/projects/_overall/.claude/scripts/fork-release-preflight.sh
```

**If exit 0 (up to date):** Skip to Step 3.

**If exit 1 (behind):** Must merge before release.

```bash
git merge upstream/main
```

**For each merge conflict** (except version numbers in `.claude-plugin/*.json`): Use `AskUserQuestion` to present the conflict and ask user how to resolve.

Standard resolutions:
- Remove RELEASE-NOTES.md: `git rm RELEASE-NOTES.md`
- Keep our plugin name/version in `.claude-plugin/*.json`
- README.md: Accept upstream changes, but preserve our fork-specific additions (visual comparison table, installation via marketplace, "Why This Fork Exists" section)

### Step 3: Verify Native Task Content

After merge, verify our customizations survived:

```bash
grep -c "Step 0:\|Step 1b:" skills/executing-plans/SKILL.md  # Should be 2
grep -c "Native Task" skills/writing-plans/SKILL.md skills/brainstorming/SKILL.md skills/dispatching-parallel-agents/SKILL.md
```

If content was lost, restore from pre-merge and commit separately:
```bash
git show HEAD~1:skills/[skill]/SKILL.md > skills/[skill]/SKILL.md
git add skills/[skill]/SKILL.md
git commit -m "feat: restore native task integration to [skill]"
```

### Step 3b: Convert Legacy References to Native Tasks

Dispatch an Opus subagent to research the diff between our main and upstream:

```
Task(subagent_type="general-purpose", model="opus", prompt="""
Research the diff: git diff upstream/main..main -- skills/

Identify ALL references that need native task conversion:
- TodoWrite → TaskCreate
- TodoRead → TaskList/TaskGet
- Any other legacy task/todo patterns

Use our existing implementations as examples:
- skills/writing-plans/SKILL.md
- skills/executing-plans/SKILL.md
- skills/brainstorming/SKILL.md
- skills/dispatching-parallel-agents/SKILL.md

Report: which files need changes and what specifically to convert.
""")
```

**If conversions needed:** Make changes and commit separately:
```bash
git add skills/[modified-skill]/SKILL.md
git commit -m "feat: convert legacy task references to native tasks in [skill]"
```

### Step 4: Version Check

```bash
OURS=$(jq -r .version .claude-plugin/plugin.json)
THEIRS=$(git show upstream/main:.claude-plugin/plugin.json 2>/dev/null | jq -r .version || echo "0.0.0")
echo "Ours: $OURS | Upstream: $THEIRS"
```

**If upstream version >= ours:** Use `AskUserQuestion` to confirm version jump (e.g., 5.0.0).

### Step 5: Bump Version

Determine new version (patch/minor/major based on changes).

Edit BOTH files with same version:
- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`

### Step 6: Commit and Push

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "chore: bump version to X.Y.Z"
git push origin main
```

### Step 7: Tag and Release

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
gh release create vX.Y.Z --repo pcvelz/superpowers --title "vX.Y.Z" --notes "Description of changes"
```

### Step 8: Verify (Show User)

Tell user to verify locally:

```
To verify the release:

rm -rf ~/.claude/plugins/cache/superpowers-extended-cc-marketplace
/plugin marketplace add pcvelz/superpowers
/plugin install superpowers-extended-cc@superpowers-extended-cc-marketplace

Restart Claude Code to load the new version.
```

## Key Links

- Tags: https://github.com/pcvelz/superpowers/tags
- Releases: https://github.com/pcvelz/superpowers/releases
