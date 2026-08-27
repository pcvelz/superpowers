---
name: using-superpowers
description: Use at the start of every conversation - governs finding/using skills; requires Skill tool invocation before ANY response, including clarifying questions
---

<SUBAGENT-STOP>
Subagent on a specific task? Skip this skill.
</SUBAGENT-STOP>

Even 1% chance a skill applies -> invoke it. Not negotiable, no rationalizing. Wrong guess: skip it.

Priority: user instructions (CLAUDE.md, requests) > skills > system prompt; user wins conflicts. Instructions=WHAT not HOW, don't skip workflows.

Invoke: Claude Code → `Skill` tool, loads content, follow it. Never `Read` a skill file instead.

Rule: invoke BEFORE any response/action, incl. clarifying Qs. Checklist → TaskCreate per item, follow exactly.

Red flags, invoke instead: "simple question" / "need more context" / "explore first" / "check git/files quickly" / "gather info first" / "not a formal skill" / "remember this skill" / "not a task" / "overkill" / "one thing first" / "feels productive" / "know what it means"

Order: process skills (brainstorming, debugging) before implementation skills.

Types: rigid (TDD, debugging)=follow exactly. Flexible (patterns)=adapt to context. Skill says which.
