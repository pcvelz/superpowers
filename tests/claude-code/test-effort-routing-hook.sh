#!/usr/bin/env bash
# Test: pre-agent-model-routing hook -- effort-enforcement extension (enforceEffort).
#
# SPEC UNDER TEST (implemented in hooks/pre-agent-model-routing):
# model-routing.json may additionally carry:
#   {"mechanical":"haiku","standard":"sonnet","frontier":"inherit",
#    "effort":{"mechanical":"low","standard":"medium","frontier":"inherit"},
#    "enforceEffort": true}
# When enforceEffort is true AND the in-progress task's modelTier maps to a
# non-"inherit" effort, an Agent dispatch MUST resolve to that effort. Effort
# is resolved from the dispatched agent definition's YAML frontmatter key
# `effort:`, looked up in this order:
#   1. <cwd>/.claude/agents/<subagent_type>.md
#   2. $HOME/.claude/agents/<subagent_type>.md
#   3. the plugin's own <plugin_root>/agents/<subagent_type>.md, with any
#      "<plugin-name>:" prefix stripped from subagent_type first.
#
# ASSUMPTION (not spelled out verbatim in the spec, inferred from
# hooks/session-start's own convention -- see its CLAUDE_PLUGIN_ROOT branch):
# step 3's <plugin_root> is read from the CLAUDE_PLUGIN_ROOT env var, exactly
# as hooks/session-start already does. If the real implementation resolves
# plugin_root a different way, test 8 below will need its CLAUDE_PLUGIN_ROOT
# override adjusted to match.
#
# NOTE ON PROVENANCE: this suite was commissioned as a RED-phase (pre-GREEN)
# spec against a hook with no effort awareness at all. By the time this suite
# was finished, hooks/pre-agent-model-routing had already been given an
# enforceEffort implementation (a concurrent change, not made by this suite's
# author). All 11 cases below are written and verified against that actual,
# current implementation. Where a bare exit-code check can't tell a genuine
# effort verification apart from an old, coincidental allow/exempt path
# (tests 3, 4, 8), an additional trace-log assertion pins down that real
# effort-checking activity (the "effort-match"/"effort-mismatch" decision
# events, not just the unconditional "effort=..." resolution annotation)
# actually occurred.
#
# That trace assertion is load-bearing, not belt-and-braces. While this suite
# and the implementation were being reconciled, test 4 briefly asserted
# "reviewer effort (medium) allowed" against a fixture that was actually
# pinned high - and PASSED. The exit code alone could not distinguish the
# right answer from the right answer for the wrong reason. Rule: whenever a
# test's name makes a claim about WHY a dispatch was allowed, assert on the
# trace verdict too.
#
# Fixture efforts are chosen against the allowed set, which for a mechanical
# task is {low} UNION {standard's medium} - the reviewer union, mirroring the
# model side. So low = a valid implementer dispatch, medium = a valid reviewer
# dispatch, and high = reachable by neither role, which makes it the only
# genuine mismatch value available.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/pre-agent-model-routing"
WORK=$(mktemp -d)
export SUPERPOWERS_USERGATE_TRACE_LOG="$WORK/trace.log"
FAILED=0
# shellcheck disable=SC2064
trap "rm -rf '$WORK'" EXIT

echo "=== Test: pre-agent-model-routing enforceEffort extension ==="
echo ""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

assert() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label — expected exit=$expected, got exit=$actual"
        echo "         stderr: $(head -2 "$WORK/stderr" 2>/dev/null | tr '\n' ' ')"
        FAILED=$((FAILED + 1))
    fi
}

assert_stderr_contains() {
    local label="$1" needle="$2"
    if grep -qF "$needle" "$WORK/stderr" 2>/dev/null; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label — stderr missing: $needle"
        FAILED=$((FAILED + 1))
    fi
}

assert_trace_contains() {
    local label="$1" needle="$2"
    if grep -qF "$needle" "$SUPERPOWERS_USERGATE_TRACE_LOG" 2>/dev/null; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label — trace log missing: $needle"
        FAILED=$((FAILED + 1))
    fi
}

assert_trace_not_contains() {
    local label="$1" needle="$2"
    if grep -qF "$needle" "$SUPERPOWERS_USERGATE_TRACE_LOG" 2>/dev/null; then
        echo "  [FAIL] $label — trace log unexpectedly contains: $needle"
        FAILED=$((FAILED + 1))
    else
        echo "  [PASS] $label"
    fi
}

run_hook() {
    # Usage: run_hook <json-input> [env-overrides...]
    # Runs hook, discards stdout (ALLOW JSON), captures stderr.
    # Prints the hook's exit code on stdout so callers can rc=$(run_hook ...).
    # HOME is isolated by default so a real ~/.claude/superpowers/model-routing.json
    # on the machine can't pollute "no routing file" tests; later env-overrides
    # ("$@") win because env applies the last assignment.
    local input="$1" _rc; shift
    env HOME="$ISOLATED_HOME" "$@" bash "$HOOK" >/dev/null 2>"$WORK/stderr" <<< "$input" && _rc=$? || _rc=$?
    echo "$_rc"
}
ISOLATED_HOME="$WORK/isolated-home"
mkdir -p "$ISOLATED_HOME"

# ---------------------------------------------------------------------------
# Routing files
# ---------------------------------------------------------------------------

# enforceEffort:true project -- used by tests 3,4,5,6,7,8,9,10.
ROUTING_DIR="$WORK/project/docs/superpowers"
mkdir -p "$ROUTING_DIR"
cat > "$ROUTING_DIR/model-routing.json" <<'EOF'
{"mechanical":"haiku","standard":"sonnet","frontier":"inherit","effort":{"mechanical":"low","standard":"medium","frontier":"inherit"},"enforceEffort":true}
EOF

# Same effort mapping, but enforceEffort key absent entirely -- back-compat (test 2).
NOENFORCE_DIR="$WORK/project-noenforce/docs/superpowers"
mkdir -p "$NOENFORCE_DIR"
cat > "$NOENFORCE_DIR/model-routing.json" <<'EOF'
{"mechanical":"haiku","standard":"sonnet","frontier":"inherit","effort":{"mechanical":"low","standard":"medium","frontier":"inherit"}}
EOF

# No routing file at all (test 1).
mkdir -p "$WORK/project-none"

# Unparseable routing file (test 11).
BADJSON_DIR="$WORK/project-badjson/docs/superpowers"
mkdir -p "$BADJSON_DIR"
echo "this is not json" > "$BADJSON_DIR/model-routing.json"

# ---------------------------------------------------------------------------
# Agent definitions (frontmatter effort/model pins)
#
# Deliberately named worker-alpha/beta/gamma/delta -- NOT "effort-*" -- so
# that the hook's own trace lines (which echo `type=$AGENT_TYPE` verbatim)
# can never accidentally contain the substring "effort" just because of the
# agent type's name. That would silently invalidate the trace-log checks
# below, which exist precisely to detect whether genuine effort-checking
# logic ran, as opposed to a same-exit-code coincidence.
# ---------------------------------------------------------------------------

AGENTS_DIR="$ISOLATED_HOME/.claude/agents"
mkdir -p "$AGENTS_DIR"

# worker-alpha: model=haiku (matches mechanical's own tier model, so today's
# hook already allows via the pre-existing model-tier path), effort=low
# (matches the required effort for mechanical).
cat > "$AGENTS_DIR/worker-alpha.md" <<'EOF'
---
name: worker-alpha
description: Worker pinned at low effort, matching the mechanical tier requirement.
model: haiku
effort: low
---

You do focused low-effort work.
EOF

# worker-beta: model=haiku (matches mechanical), effort=medium. "medium" is
# the REVIEWER ("standard") tier's effort, not the mechanical task's own (low)
# -- it is deliberately used both as the back-compat mismatch fixture (test 2)
# and, once enforceEffort is on, as proof that the allowed set is the UNION of
# the task tier's effort AND the reviewer tier's effort (test 4), mirroring
# the existing model-tier union logic (spec/code-quality reviewers dispatch at
# "standard" while the implementer's task is still in_progress).
cat > "$AGENTS_DIR/worker-beta.md" <<'EOF'
---
name: worker-beta
description: Worker pinned at medium effort -- the reviewer tier's effort, not the task tier's own.
model: haiku
effort: medium
---

You do broader medium-effort work.
EOF

# worker-zeta: model=haiku (matches mechanical), effort=high. The allowed set
# for a mechanical task is {low} UNION {standard's medium}, so low and medium
# are both reachable by a legitimate role (implementer and reviewer). "high" is
# reachable by neither, which makes it the only genuine mismatch fixture - a
# medium pin would be indistinguishable from a valid reviewer dispatch.
cat > "$AGENTS_DIR/worker-zeta.md" <<'EOF'
---
name: worker-zeta
description: Worker pinned at high effort, outside both the task tier and the reviewer tier efforts.
model: haiku
effort: high
---

You do high-effort work.
EOF

# worker-gamma: model=haiku (matches mechanical), NO effort key at all.
cat > "$AGENTS_DIR/worker-gamma.md" <<'EOF'
---
name: worker-gamma
description: Worker with a model pin but nothing pinning its effort.
model: haiku
---

You work without any effort declared.
EOF

# Tests 8 and 12 use the plugin's OWN shipped agents/effort-{low,medium,high}.md
# (real files at $REPO_ROOT/agents/, not a synthetic fixture) via
# CLAUDE_PLUGIN_ROOT="$REPO_ROOT" -- those definitions pin `effort:` but
# deliberately carry NO `model:` key ("Model comes from the dispatch" per
# their own description), so they exercise a DIFFERENT branch than
# worker-alpha/beta/epsilon above: since resolve_agent_key("model") comes back
# empty, they never take the "definition carries its own model" branch at
# all -- they either fall into the "opted into routing" branch (when the call
# passes an explicit model param) or the "no model anywhere, fail-open"
# branch (when it doesn't). Neither cwd ($WORK/project/.claude/agents) nor
# home ($ISOLATED_HOME/.claude/agents) has a colon-prefixed file matching
# these plugin-scoped names, so resolution can only succeed via the
# CLAUDE_PLUGIN_ROOT fallback.

# ---------------------------------------------------------------------------
# Transcripts
# ---------------------------------------------------------------------------

# One in_progress task, modelTier=mechanical (requires effort=low).
cat > "$WORK/tier-mechanical.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tc1","name":"TaskCreate","input":{"subject":"Bulk transform task","description":"**Goal:** crunch data.\n\n```json:metadata\n{\"modelTier\":\"mechanical\",\"files\":[],\"verifyCommand\":\"true\",\"acceptanceCriteria\":[]}\n```"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tc1","content":"Task #1 created successfully: Bulk transform task"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu1","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
EOF

# One in_progress task, modelTier=frontier (maps to effort "inherit" -> no constraint).
cat > "$WORK/tier-frontier.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tc1","name":"TaskCreate","input":{"subject":"Deep design task","description":"**Goal:** deep reasoning.\n\n```json:metadata\n{\"modelTier\":\"frontier\",\"files\":[],\"verifyCommand\":\"true\",\"acceptanceCriteria\":[]}\n```"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tc1","content":"Task #1 created successfully: Deep design task"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu1","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
EOF

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

echo "Test 1: no routing file at all -> allow, dormant"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project-none")
: > "$SUPERPOWERS_USERGATE_TRACE_LOG"
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
assert_trace_contains "genuinely dormant (no-routing-file reason logged)" "no-routing-file"
echo ""

echo "Test 2a: REGRESSION - effort-only definition + WRONG model + enforceEffort ABSENT -> allow"
# Pins the containment fix. An agent definition pinning `effort:` but NO `model:`
# has, under enforceEffort, its model param checked against the tier. That check
# MUST NOT fire when enforceEffort is absent: doing so silently narrows a
# pre-existing exemption for every model-routing user, including anyone whose own
# agent definition happens to carry a bare `effort:` key for unrelated reasons.
#
# Measured before the fix: this exact dispatch returned exit 2 ("DOES NOT MATCH
# TASK MODEL TIER") where v6.3.0 returned exit 0 - a breaking change riding
# inside a feature nobody enabled.
#
# The model MUST be one the tier cannot accept by accident. worker-eta pins no
# model, the call passes opus, and mechanical resolves to haiku (reviewer union
# adds sonnet) - so opus can only pass if the exemption held. Passing haiku here
# would be indistinguishable from the check running and passing, which is the
# coincidental-pass trap this suite exists to avoid.
cat > "$AGENTS_DIR/worker-eta.md" <<'EOF'
---
name: worker-eta
description: Pins effort but no model - stands in for any user agent using a bare effort key.
effort: medium
tools: Read, Bash
---

You do work at a pinned effort with no model of your own.
EOF
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"worker-eta","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project-noenforce")
: > "$SUPERPOWERS_USERGATE_TRACE_LOG"
rc=$(run_hook "$INPUT")
assert "opus on a mechanical task allowed when enforceEffort absent" "0" "$rc"
assert_trace_contains "exemption held (did not fall through to a tier check)" "custom-agent-type-model-exempt"
assert_trace_not_contains "no tier verdict was reached at all" "tier-mismatch"

# And the same dispatch under enforceEffort:true MUST block - proving the fix
# gated the narrowing rather than deleting it.
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"worker-eta","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
: > "$SUPERPOWERS_USERGATE_TRACE_LOG"
rc=$(run_hook "$INPUT")
assert "same dispatch blocks when enforceEffort IS on" "2" "$rc"
assert_trace_contains "reached the tier check this time" "tier-mismatch"
echo ""

echo "Test 2: routing file present, enforceEffort ABSENT -> allow even though effort mismatches (back-compat)"
# worker-beta resolves effort=medium; required effort for mechanical is "low".
# Since enforceEffort is absent from this routing file, the mismatch must be
# tolerated entirely -- today's behavior, and the contract going forward.
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"worker-beta","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project-noenforce")
: > "$SUPERPOWERS_USERGATE_TRACE_LOG"
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
# The hook resolves an agent definition's effort: key unconditionally (it has
# not read the routing file yet at that point), so the resolution trace does
# mention effort=. What must be absent is any ENFORCEMENT verdict.
assert_trace_not_contains "no effort verdict when enforceEffort is absent" "effort-mismatch"
assert_trace_not_contains "no effort pass-verdict either" "effort-match"
echo ""

echo "Test 3: enforceEffort true, tier=mechanical (needs effort=low), subagent_type resolves effort=low -> allow"
# worker-alpha resolves model=haiku (mechanical's own tier model, so today's
# hook already allows via the PRE-EXISTING model-tier match) AND effort=low
# (matching). A bare exit-code check can't tell today's coincidental allow
# apart from a real effort verification, so this also requires proof that
# genuine effort-checking activity occurred in the trace log.
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"worker-alpha","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
: > "$SUPERPOWERS_USERGATE_TRACE_LOG"
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
assert_trace_contains "trace shows a genuine effort-match decision (not just model-tier coincidence)" "effort-match"
echo ""

echo "Test 4: enforceEffort true, tier=mechanical, subagent_type resolves effort=high -> BLOCK"
# worker-zeta resolves model=haiku (fine on model-tier grounds) but effort=high,
# which is outside the allowed set {low, medium} for a mechanical task. Note the
# set includes medium: the standard reviewer effort is unioned in, exactly as the
# standard reviewer MODEL is on the model side. So medium is a legitimate
# reviewer dispatch and only high is a true mismatch.
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"worker-zeta","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
# Substrings tied to the message's DYNAMIC parts, not its static boilerplate:
# the boilerplate names all three plugin-shipped types ("effort-low,
# effort-medium and effort-high") regardless of the actual scenario, so a bare
# "high"/"low"/"medium"/"effort" substring check would pass even for a wrong
# resolved value or a model-tier (non-effort) block message.
assert_stderr_contains "headline is the effort-specific one, not the model-tier one" "DOES NOT MATCH TASK THINKING EFFORT"
assert_stderr_contains "names required effort set" "thinking effort: low medium"
assert_stderr_contains "names actual effort" "resolves to effort 'high'"

# The reviewer half of that union, asserted with a genuinely medium-pinned
# fixture so a future narrowing of the rule fails loudly here instead of
# silently blocking every reviewer dispatch during a mechanical task.
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"worker-beta","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "reviewer effort (medium) allowed on a mechanical task" "0" "$rc"
assert_trace_contains "reviewer allow is a real effort verdict, not a coincidence" "effort-match"
echo ""

echo "Test 5: enforceEffort true, tier=mechanical, NO subagent_type on the call -> BLOCK"
# model=haiku is itself a perfectly valid dispatch per the EXISTING model-tier
# mapping for "mechanical", so today's hook allows (exit 0) via that
# pre-existing path. With no subagent_type there is no agent definition to
# resolve an effort pin from at all, so enforceEffort must block regardless
# of whether the raw model happens to match -- this is a clean exit-code
# regression today (0 now, must become 2).
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"model":"haiku","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
assert_stderr_contains "tells the agent to use an effort-pinned agent type" "effort-pinned"
echo ""

echo "Test 6: enforceEffort true, tier=frontier (effort maps to inherit) -> allow anything"
# frontier's effort mapping is "inherit", i.e. enforceEffort imposes no
# constraint at all for this tier -- this is the SAME "inherit" fast path the
# existing model-tier logic already takes for frontier's model mapping, so
# it is expected to pass today unmodified.
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-frontier.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code (model=opus)" "0" "$rc"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-frontier.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code (no model param)" "0" "$rc"
echo ""

echo "Test 7: enforceEffort true, agent def exists but has NO effort: key -> BLOCK"
# worker-gamma resolves model=haiku (today's hook allows via model-tier match)
# but carries no effort key whatsoever, so nothing pins its effort. Today's
# hook allows (exit 0) since it never looks for an effort key; the fixed hook
# must block since an unpinned effort cannot be verified against the low
# requirement.
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"worker-gamma","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
assert_stderr_contains "states no effort is pinned at all" "pins no effort at all"
echo ""

echo "Test 8: plugin-scoped subagent_type resolves NOWHERE - the plugin ships no agents"
# Guard against re-adding a <plugin_root>/agents/ lookup. This plugin ships no
# named agents (precedent: commit 8d9d82b removed the last one and the agents/
# directory with it), and the effort definitions that make enforcement usable
# are written by /onboard into <cwd>/.claude/agents or ~/.claude/agents - the
# two paths resolve_agent_key already searched before this feature existed.
#
# A third plugin-root path was tried and removed: with nothing shipped there it
# could never resolve, so it was dead code by construction. Here that is made
# observable - a plugin-scoped name with CLAUDE_PLUGIN_ROOT pointed at the real
# repo root must resolve to NOTHING. Under enforcement, nothing pinning an
# effort is a block, and the message must say so rather than naming a value.
#
# If someone reinstates the plugin-root lookup AND ships definitions again,
# this test fails and forces the vanilla-first cost question to be re-answered
# rather than reintroduced silently.
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"superpowers-extended-cc:effort-low","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
: > "$SUPERPOWERS_USERGATE_TRACE_LOG"
rc=$(run_hook "$INPUT" CLAUDE_PLUGIN_ROOT="$REPO_ROOT")
assert "exit code" "2" "$rc"
assert_stderr_contains "blocked because nothing pins an effort" "pins no effort at all"
assert_trace_not_contains "no effort value was resolved from anywhere" "effort-match"
echo ""

echo "Test 9: SUPERPOWERS_ROUTING_GUARD=0 -> allow regardless (kill switch overrides effort enforcement too)"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"worker-beta","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT" SUPERPOWERS_ROUTING_GUARD=0)
assert "exit code" "0" "$rc"
echo ""

echo "Test 10: tool_name != Agent -> allow (hook only applies to Agent dispatches)"
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 11: routing file unparseable -> allow (fail-open)"
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"worker-beta","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project-badjson")
rc=$(run_hook "$INPUT")
assert "exit code" "0" "$rc"
echo ""

echo "Test 12: effort-only definition (no model:) + explicit model param that VIOLATES the tier -> BLOCK"
# worker-eta pins effort: medium and NO model: key - the same shape /onboard
# writes for effort-low/medium/high, and the same shape any user definition
# carrying a bare effort: key has. Dispatched WITH an explicit model param
# ("opus") that is outside the mechanical tier's allowed set {haiku, sonnet}.
#
# Because the definition pins an effort but no model, it has opted into routing,
# so the model exemption custom types normally get for passing their own model
# param does not apply here - the ordinary model-tier check runs and blocks.
# The effort itself (medium) is perfectly valid, being the reviewer-tier effort,
# so if this blocks the reason must be the MODEL check. Asserted by the model-
# tier headline rather than the effort one, plus a trace showing effort-match
# passing immediately BEFORE the model-tier block, which isolates which dial
# tripped. Test 2a covers the same shape with enforcement OFF, where the
# exemption must hold instead.
INPUT=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"worker-eta","model":"opus","prompt":"go"},"transcript_path":"%s","cwd":"%s"}' \
    "$WORK/tier-mechanical.jsonl" "$WORK/project")
: > "$SUPERPOWERS_USERGATE_TRACE_LOG"
rc=$(run_hook "$INPUT")
assert "exit code" "2" "$rc"
assert_stderr_contains "blocked by the MODEL-tier check, not the effort check" "DOES NOT MATCH TASK MODEL TIER"
assert_stderr_contains "names the violating model" "model='opus'"
assert_trace_contains "effort itself passed (medium is the reviewer-tier effort)" "effort-match tiers=mechanical effort=medium"
assert_trace_contains "model-tier check is what actually blocked" "tier-mismatch"
echo ""

echo "=== Summary: $FAILED failure(s) ==="
exit "$FAILED"
