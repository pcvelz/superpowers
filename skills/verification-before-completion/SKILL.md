---
name: verification-before-completion
description: Use when about to claim work is complete, fixed, or passing, before committing or creating PRs - requires running verification commands and confirming output before making any success claims; evidence before assertions always
---

# Verification Before Completion

## Overview

**Core principle:** Evidence before claims, always.

**Violating the letter of this rule is violating the spirit of this rule.**

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you haven't run the verification command in this message, you cannot claim it passes.

## The Gate Function

```
BEFORE claiming any status or expressing satisfaction:

1. IDENTIFY: What command proves this claim?
2. RUN: Execute the FULL command (fresh, complete)
3. READ: Full output, check exit code, count failures
4. VERIFY: Does output confirm the claim?
   - If NO: State actual status with evidence
   - If YES: State claim WITH evidence
5. ONLY THEN: Make the claim

Skip any step = lying, not verifying
```

## Common Failures

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | Test command output: 0 failures | Previous run, "should pass" |
| Linter clean | Linter output: 0 errors | Partial check, extrapolation |
| Build succeeds | Build command: exit 0 | Linter passing, logs look good |
| Bug fixed | Test original symptom: passes | Code changed, assumed fixed |
| Regression test works | Red-green cycle verified | Test passes once |
| Agent completed | VCS diff shows changes | Agent reports "success" |
| Requirements met | Line-by-line checklist | Tests passing |

## Red Flags - STOP

- Using "should", "probably", "seems to"
- Expressing satisfaction before verification ("Great!", "Perfect!", "Done!", etc.)
- About to commit/push/PR without verification
- Trusting agent success reports
- Relying on partial verification
- Thinking "just this once"
- Tired and wanting work over
- **ANY wording implying success without having run verification**

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Should work now" | RUN the verification |
| "I'm confident" | Confidence ≠ evidence |
| "Just this once" | No exceptions |
| "Linter passed" | Linter ≠ compiler |
| "Agent said success" | Verify independently |
| "I'm tired" | Exhaustion ≠ excuse |
| "Partial check is enough" | Partial proves nothing |
| "Different words so rule doesn't apply" | Spirit over letter |

## Key Patterns

**Tests:**
```
✅ [Run test command] [See: 34/34 pass] "All tests pass"
❌ "Should pass now" / "Looks correct"
```

**Regression tests (TDD Red-Green):**
```
✅ Write → Run (pass) → Revert fix → Run (MUST FAIL) → Restore → Run (pass)
❌ "I've written a regression test" (without red-green verification)
```

**Build:**
```
✅ [Run build] [See: exit 0] "Build passes"
❌ "Linter passed" (linter doesn't check compilation)
```

**Requirements:**
```
✅ Re-read plan → Create checklist → Verify each → Report gaps or completion
❌ "Tests pass, phase complete"
```

**Agent delegation:**
```
✅ Agent reports success → Check VCS diff → Verify changes → Report actual state
❌ Trust agent report
```

## When To Apply

**ALWAYS before:**
- ANY variation of success/completion claims
- ANY expression of satisfaction
- ANY positive statement about work state
- Committing, PR creation, task completion
- Moving to next task
- Delegating to agents

**Rule applies to:**
- Exact phrases
- Paraphrases and synonyms
- Implications of success
- ANY communication suggesting completion/correctness

## The Adversarial Pass (author → attacker)

Running the command proves the claim you thought to make. This pass hunts the claims you didn't. Once verification evidence is in hand, switch roles: you are now the reviewer whose job is to find why this work is WRONG.

Attack in order:
1. **The requirements before your answer to them.** Read the spec/ticket as a hostile lawyer: do two rules contradict? Is an "always/never" revoked by another clause? Does the requested interface conflict with the requested behavior? A contradiction resolved silently is a decision made for someone else without telling them — surface it and state your resolution. A flawless implementation of a broken spec is still broken.
2. **The inputs.** Empty, zero, negative, huge, malformed, concurrent, unicode, missing — what actually happens? Trace or run it; don't assume.
3. **The assumptions.** List what must be true (environment, versions, ordering, state, permissions); verify the load-bearing ones against reality, not memory.
4. **The evidence.** Would the test catch the bug it guards? A test that cannot fail proves nothing (red-green above).

The pass ends in one of three verdicts:
- **SURVIVED** — present the work. Findings the reader needs (edge cases that matter, what was checked) go in as facts.
- **REFUTED** — fix it, re-run the pass on the fix, present with the defect named plainly.
- **UNTESTABLE HERE** — present with exactly what could not be verified and why; your human partner inherits a known risk, not a hidden one.

**The deliverable stays lean.** Findings earn their place in it; process narration does not. "Fails on empty input, fixed" is a finding — keep it. "I attacked this from five angles" is diary — cut it. Never weaken the claim to dodge an attack ("works in most cases") without flagging the retreat explicitly.

**The tell:** wanting to skip this pass is the strongest signal it will find something. Reluctance to verify is data.

## Live State Beats Description

Verification runs against the LIVE system, not its description. Sources rank by how they lie:

| The claim comes from | Treat it as | Verify by |
|---|---|---|
| A README, doc, or wiki | Stale by default | Run the code path, read the actual source |
| A code comment | The code's opinion of itself | Read the code the comment describes |
| A config file in the repo | What was INTENDED | Query the running system for the EFFECTIVE value |
| Your memory or an earlier session | A point-in-time observation | Re-check now — the system moved since |
| The user's description | Honest but possibly outdated | Confirm with a read-only probe |
| A schema or type definition | Better, but migrations lie | Inspect actual data or live schema when it matters |

Pick the **cheapest sufficient check**: if the authoritative artifact is already in front of you, the check IS reading it — probe (run it, query it, curl it) only when the truth is not in view or behavior could differ from the text. When description and reality disagree, reality wins AND the gap itself is a finding — report it in one line ("README says X, code does Y"). Timestamp what you learn: "as of this check, X" ages honestly; "X is true" rots silently.
