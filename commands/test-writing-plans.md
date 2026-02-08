---
description: Test writing-plans skill compliance with a Sonnet subagent
disable-model-invocation: true
---

Test the writing-plans skill by spawning a Sonnet subagent that executes it with a dummy task. Verify the subagent follows the mandatory workflow.

## Execution

1. Determine the absolute path of the current project root (where this command lives)
2. Spawn a Sonnet subagent with this prompt (replace `PROJECT_ROOT` with the actual path):

```
Task(
  subagent_type="general-purpose",
  model="sonnet",
  prompt="""You are testing a skill. Read the skill file and follow it EXACTLY as written. This is a test run.

First, read the skill at: PROJECT_ROOT/skills/writing-plans/SKILL.md

Then execute it with this task: "Add a hello-world CLI command to the superpowers project that prints 'Hello from superpowers'"

The project is at PROJECT_ROOT

Follow every step in the skill document in exact order. Do NOT skip any steps.

IMPORTANT: At the end, report which tools you called in order, specifically:
1. Did you call TaskList as the first tool? (yes/no)
2. Did you call ExitPlanMode at any point? (yes/no)
3. Did you call AskUserQuestion at the end? (yes/no)
4. Did you save the plan to docs/plans/YYYY-MM-DD-*.md? (yes/no)
5. Did you save .tasks.json next to the plan? (yes/no)"""
)
```

## After Subagent Completes

1. Check the subagent's compliance report (the 5 yes/no answers)
2. Verify files were created in the right location:
   ```
   ls docs/plans/*hello*
   ```
3. Clean up test artifacts:
   ```
   rm docs/plans/*hello*
   ```
4. Delete any native tasks created by the test subagent

## Expected Results

All 5 must pass for the test to succeed:
- TaskList called first: YES
- ExitPlanMode called: NO
- AskUserQuestion called: YES (or attempted — subagents may not have this tool)
- Plan saved to docs/plans/: YES
- .tasks.json co-located: YES
