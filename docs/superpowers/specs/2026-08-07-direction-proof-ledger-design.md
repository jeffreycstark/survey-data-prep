# Design: proving harmonization direction — the verification ledger

**Date:** 2026-08-07
**Status:** Draft for review
**Author:** brainstorming session (extends `2026-08-04-qa-validation-design.md`; that spec proves the *checkers* are current, this one proves the *data* is verified)

## Problem

A spec's `labels:` block is a claim and its `fn:` is an action, and nothing
connects them at build time — the engine reads only `source`, `fn`, `missing`
and `qc.valid_range`. Label reconciliation connects them after the fact, but
lexically, and today it proves **413 of 1,133** ABS variable-waves (36%).

The measured consequences, from the 2026-08-04→07 sweep:

- **All 16 direction bugs found this week sat in the 720-row `skip` list.**
  None was ever reported as an error; each was invisible until a lexicon
  addition, the W6 label restore, or a paper's impossible correlation reached it.
- **Skips regenerate on every run.** There is no way to work the list down, so
  it never got worked. A `skip` is not a pass, but it is also not a task.
- **Six of the sixteen fixes were per-wave** — ABS flips raw coding mid-series
  (`party_closeness` w2→w3, `sat_president_govt` w1 vs w3-w6,
  `efficacy_ability_participate` and `demo_political_equality` w1). Any proof
  must be per (variable, wave), never per variable.
- **The engine deletes evidence invisibly** (2026-08-07 fault injection):
  `.safe_npt` absorbs out-of-domain values inside the fn and `method: recode`
  never logs unmapped values, so Check E only ever sees `method: identity`
  deletions. A wider raw truncates silently; a narrower raw *shifts*
  (the `gov_leaders_abuse_power` class).

## Goal

Every ordinal variable × wave carries a durable, self-invalidating verdict on
its direction; the percentage verified is a number `run_all` and CI can hold at
100; and the residual human review is done **once**, not re-triaged per run.

The defensible sentence this buys for papers: *"every harmonized variable's
direction is verified against its source value labels — mechanically where
classifiable, by documented human review otherwise — and re-verification is
forced whenever any input changes."*

## Non-goals

- Fixing or auditing the ~90 bespoke `recode_*`/`collapse_*` helpers (separate
  sweep; `reverse_trust_vietnam_w2/w3` already noted as guard-free).
- Promoting the anchor census to a gate. It stays soft: two independent methods
  agreeing is the point; the statistical method must never overrule the ledger.
- Other surveys in the first pass. The machinery is survey-generic; ABS is the
  pilot because its skip list is the largest and its bugs are freshest.

## Architecture

Four pieces, phased so each is useful alone.

### Phase 0 — engine truthfulness (prerequisite)

The auto-verifier is only trustworthy if the engine stops deleting evidence
silently. From the fault-injection findings, in order:

1. **`.safe_npt` reports absorption.** It knows exactly which values hit its
   `TRUE ~ NA_real_` arm; it attaches `n_absorbed` (count + observed values)
   as an attribute, and `harmonize_variable()` logs it into the same oob log
   Check E reads. Closes Check E's structural blindness to `r_function`.
2. **`method: recode` logs unmapped values** — any non-NA input matching no
   mapping key and no declared-null key, same log.
3. **Domain guard.** Raw values outside `1..n` ∪ missing codes are precisely
   what #1 now logs; additionally, when the *entire* top or bottom of `1..n`
   is unobserved in a wave (shift signature), warn at harmonize time.
4. **The spec's missing codes govern.** `harmonize_variable()` passes the
   resolved convention codes into the fn (`missing_codes = ...`), so fn
   defaults no longer silently extend the declaration. Fn defaults remain only
   for direct calls outside the engine.
5. **B5 (existing ticket): `valid_range` becomes mandatory** except under
   `skip_range_check`. 9 specs are currently ungated.

Each lands with a fault-injection regression in
`test_engine_fault_injection.R` (already committed as the reconnaissance
script; it becomes a real suite with pass/fail assertions).

### Phase 1 — the ledger

**File:** `src/config/<survey>/_direction_ledger.yml` (underscore prefix, like
`_drafts/`; excluded from spec discovery). One row per (variable, wave):

```yaml
schema_version: 1
rows:
  - variable: expert_rule
    wave: w1
    verdict: human_verified        # auto_verified | human_verified | exempt | unverified
    method: exact_sequence         # what verified it: lexicon | exact_sequence | human | n/a
    spec_hash: "sha256:…"          # canonical(declared labels + resolved fn for this wave)
    raw_hash:  "sha256:…"          # canonical(raw value labels of the source column)
    note: ""                       # mandatory for human_verified and exempt
    verified_on: 2026-08-10
```

**Verdict semantics:**

- `auto_verified` — the checker re-derives this every run (lexicon match or
  exact-sequence match) and *stores* it with hashes so CI can see coverage
  without data.
- `human_verified` — written once via the review flow; `note` says what was
  compared (e.g. "raw 1=Strongly agree matches declared pole; fn reverses").
- `exempt` — no direction exists: nominal, identifier, weight, derived-index.
  Auto-populated from `type:` + a small exempt list; `note` mandatory.
- `unverified` — the default for anything else. **The gate counts these.**

**Invalidation is the proof mechanism.** The checker recomputes both hashes
each run. `spec_hash` drift (labels edited, fn changed) or `raw_hash` drift
(source data changed) flips the row to `unverified` in its report — the stored
file is never silently rewritten; a human (or the auto-verifier, if it can now
verify) re-establishes the verdict. A sign-off cannot go stale invisibly. This
is the freshness-layer contract applied to judgment.

**Hash split, deliberately:** `spec_hash` inputs live in the source tree, so
CI can detect spec-side drift with no data; `raw_hash` needs the `.sav`/rds
and is checked locally by `run_all`. Same venue split as the 2026-08-04 spec.

**Checker:** `src/r/audit/09_direction_ledger.R`.
Exit 0 = no unverified, no drift; exit 1 = unverified or drifted rows; exit 2 =
ledger unparseable (fails closed, house convention). Wired into `run_all` as a
hard layer and into the post-harmonize gate's report.

### Phase 2 — the human sweep, once

The review sheet already built (holds vs. spec-says, per wave, with codebook
text) gains an export: reviewed rows produce ledger entries via an applier
script (`apply_direction_verdicts.R` — same pattern as the existing
oob/coverage appliers). The 720 skips collapse to ~140 distinct variables;
most repeat one pattern across waves. Estimated one-time human cost: a few
evenings. The lexicon treadmill ends — unknown vocabulary meets a human once
and the verdict persists.

### Phase 3 — declarations and cross-checks

- **D7 (existing ticket): `qc.wave_direction_flip:`** — declare known mid-series
  raw flips; the checker verifies the declaration against raw labels, turning
  future `party_closeness` cases from ambushes into assertions.
- **`qc.expected_anchor_sign:`** (schema addition only) — the *coded
  variable's* expected sign against the trust anchors, not the concept's
  valence. Consumed by the anchor census, which stays soft. Census-vs-ledger
  disagreement is a reported work item, never a gate.
- **CI:** the data-free job asserts the ledger parses, spec-side hashes match,
  and the committed unverified count has not increased. Full verification
  (raw side) remains local, stated honestly in `docs/QA.md`.

## Testing

House pattern — fixture, assert clean, inject one fault, assert the flip:

| fault | expected |
|---|---|
| ledger row whose `spec_hash` no longer matches | reported unverified, exit 1 |
| raw labels changed under a `human_verified` row | reported unverified, exit 1 (local) |
| `human_verified` without `note` | config error, exit 2 |
| unparseable ledger | exit 2, never clean |
| `.safe_npt` given code 5 on 4-pt | oob log gains an event (Phase 0) |
| `recode` with unmapped substantive value | oob log gains an event (Phase 0) |
| fn called by engine with spec codes {7,8,9}, raw 0 present | 0 survives (Phase 0) |
| clean control | exit 0 |

## Success criteria

1. ABS reports **0 unverified** rows after the Phase-2 sweep; the number is in
   `run_all`'s summary line and fails the run if it rises.
2. Re-running the 16 known bugs' pre-fix specs against the finished system
   flags every one (regression fixtures pinned from this week's commits).
3. A synthetic new wave with flipped raw coding cannot pass unnoticed:
   `raw_hash` drift flips affected rows to unverified.
4. Check E's oob log gains events from non-identity methods (verified by the
   Phase-0 injections); the "identity-only" blind spot paragraph in
   `docs/QA.md` is retired.
5. The one-time human sweep is not repeatable toil: re-running the checker
   after the sweep produces zero new work absent input changes.

## Chosen defaults (proposed, pending review)

| Decision | Choice |
|---|---|
| Ledger granularity | per (variable, wave) — six of sixteen bugs were per-wave |
| Staleness mechanism | input hashing, split spec-side (CI) / raw-side (local) |
| Auto-verify sources | polarity lexicon + exact-sequence rule; census stays advisory |
| Human flow | review sheet → applier script → ledger rows |
| Pilot survey | ABS; machinery survey-generic |
| Failure semantics | fails closed; unverified is a counted, gating state |
