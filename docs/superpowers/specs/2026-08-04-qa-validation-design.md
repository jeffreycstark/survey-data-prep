# Design: QA re-validation (registry + self-audit layer)

**Date:** 2026-08-04
**Status:** Approved (defaults confirmed by user)
**Author:** brainstorming session

## Problem

`docs/QA.md` is the document that makes the harmonization defensible in a paper.
It is stamped **Verified: 2026-07-06** — but four layers have landed since:
out-of-range triage (2b), bin-width parity (5c), module coverage (10) and the CI
gate. The stamp is therefore a claim about a system that no longer exists in the
form it describes.

Worse, nothing detects that. The guide's honesty is entirely manual: a layer can
change, gain a blind spot, or lose one, and the prose describing it stays put.
The failure is not that the checks are weak — they are strong and self-tested —
it is that **the document asserting they are strong has no way to go red**.

There is a second, structural version of the same gap. `src/r/audit/` holds 18
numbered scripts; QA.md's table cites 13. Whether the other five are layers,
helpers, or forgotten is currently invisible.

## Goal

Re-validate what QA.md claims, and make the claim mechanically self-invalidating
so it cannot go quietly stale again.

Explicitly **not** a goal: closing the gaps in §What QA does NOT guarantee, or
triaging the ABS backlogs. Those are separate work with their own trade-offs.

## Deliverable

1. `src/config/_audit/qa_layers.yml` — machine-readable registry of every QA layer.
2. `src/r/audit/08_qa_self_audit.R` — checker asserting registry against filesystem, git and QA.md.
3. `src/r/audit/test_qa_self_audit.R` — its fault-injection suite.
4. `make qa-validate` target; a second job in `.github/workflows/audit.yml`.
5. An updated, re-stamped `docs/QA.md`.
6. **Exact-sequence direction check** in `04_label_reconciliation.R` (added to scope
   2026-08-04 — see below).

## Architecture

Three artifacts, one new layer (numbered **11**, implemented as `08_*` since that
prefix is free).

**Registry.** One entry per layer: id, name, one-line description, script, test,
enforcement, survey scope, `verified:` date. Source of truth for every
table-level fact in QA.md.

**Checker.** Reads the registry; asserts it against the filesystem and `git log`;
regenerates the at-a-glance table and diffs it against what is committed. Reads
**no survey data** — every input is the source tree plus git metadata.

**QA.md.** Unchanged in character. Prose stays hand-written; only the
at-a-glance table is generated, between `<!-- BEGIN generated: qa-layers -->` /
`<!-- END generated: qa-layers -->` markers.

**Two venues, split by a proven constraint.** The structural checks need no data,
so they run in CI and can gate a PR. The layers' own `test_*.R` suites need
survey data (`test_label_reconciliation.R` checks out the pre-fix
`system_deserves_support` and runs it against ABS `.sav` files), and CI has none —
so they run locally via `make qa-validate`.

**The checker registers itself** as layer 11 and is subject to its own freshness
rule, so it cannot rot either. This mirrors layer 10: the prior question nobody
was asking, turned on the thing asking it.

## Registry schema

```yaml
schema_version: 1

layers:
  - id: "2b"
    name: Out-of-range triage
    checks: what the engine deleted for falling outside valid_range
    script: src/r/audit/03_oob_triage.R
    test: src/r/audit/test_oob_triage.R
    enforce: hard              # hard | soft | report | opt_in
    surveys: all               # or [abs] — records uneven coverage as data
    verified: 2026-07-31
    verified_note: 61 assertions; every headline event pinned as a fixture

not_a_layer:
  - path: src/r/audit/04_anchor_diagnostic.R
    reason: helper invoked by 04_anchor_coverage.R, not a layer in its own right
```

The four `enforce:` values map onto QA.md's existing legend: `hard` 🔴, `soft` 🟡,
`report` 📋, `opt_in` ⚪.

`surveys:` turns "strict reversal is ABS-only" from a caveat buried in prose into
a machine-readable fact.

`test: none` is permitted but requires a reason, so a layer without a suite is a
visible decision rather than an oversight.

## Assertion set

| | Assertion | Severity |
|---|---|---|
| A1 | Registry parses and matches schema | hard — config error, **exit 2** |
| A2 | Every `script:` resolves on disk | hard |
| A3 | Every `test:` resolves, or is `none` with a reason | hard |
| A4 | Every `src/r/audit/*.R` is a registered layer or in `not_a_layer:` with a reason | hard |
| A5 | `verified:` is not older than the last-commit date of its script or its test | hard |
| A6 | Regenerated table byte-matches what is committed between the markers | hard |
| A7 | A layer declaring `enforce: hard` contains a reachable `quit(status = 1)` | soft |
| A8 | Every layer id appears in `run_all.R`'s dispatch | soft |

**A5 is the load-bearing assertion.** If a script moved after the date someone
last proved it fires, the claim is stale by definition. This is exactly the
current situation, and it would have surfaced automatically.

**A4 applies layer 10's lesson to QA itself** — `07_module_coverage.R` exists
because nothing asked whether a module was audited at all; A4 asks whether an
audit script is claimed at all.

**A7 and A8 are soft because they are heuristics.** A grep for `quit(status = 1)`
can be fooled by an unreachable branch, and a layer may legitimately run outside
`run_all`. Useful as hints, not worth failing a build over — the same call the
repo already makes for battery coherence.

### Failure semantics

Fail closed, per house convention. An unparseable registry or missing QA.md
markers exit **2** as a config error, never a silent skip — matching
`03_oob_triage.R`'s malformed-log handling and `06_check_freshness.R`'s corrupt-
manifest rule. Any hard assertion failing exits **1**. Soft findings print and
exit **0**.

### What the assertions do not cover

A1–A8 verify the **table**, not the **prose**. No mechanical check can confirm
that "Misses: a transformation that's wrong but preserves sign and range" is
still true. Those sentences are the most valuable content in the guide and remain
human-verified — which is what Phase 1 below exists for.

## Exact-sequence direction check (scope addition, 2026-08-04)

Added after the `govt_responds_people` investigation demonstrated the gap live.

**The problem.** Layer 3 decides direction by classifying labels into poles with a
regex lexicon. Unknown vocabulary yields `skip`, and 789 of 1,133 ABS rows are
skips — 281 for `no_classifiable_poles` across 140 variables. `skip` is not a
pass, but nothing works the list, so a real inversion sat in it until a paper
found it empirically.

**The rule.** Compare the raw value labels and the spec's declared labels **as
ordered sequences, by code**. No vocabulary at all:

| raw vs declared | fn reverses | verdict |
|---|---|---|
| identical sequence | yes | **error** — harmonized cannot match its own labels |
| identical sequence | no | ok |
| exactly reversed | yes | ok |
| exactly reversed | no | **error** |
| neither | either | fall through to the lexicon, else `skip` |

Deterministic, needs no lexicon, and cannot false-positive: if the two sequences
are byte-identical and the function reverses, the claim and the data disagree by
construction.

**Live yield on introduction:** three variables the lexicon had skipped —
`access_identity_document` (w4), `access_public_school` (w4), `party_closeness`
(w1, w2). All three confirmed real and fixed the same day.

**What it does not do.** It only fires when the declared labels reuse the raw
wording. `govt_responds_people` (raw "Very responsive" vs declared "Very well")
is invisible to it; that one needs the lexicon or a human. A negation-parity
variant was prototyped and **rejected**: scales that mark polarity with antonyms
rather than negation ("easy/difficult", "agree/disapprove", "good/harm") make it
report agreement on correctly-reversed items, i.e. false positives on the
healthy majority.

**Companion deliverable — the skip census.** Emit the unclassifiable variables
*with their actual label vocabulary*, ranked, as a worklist. The lexicon should
grow deliberately, not when a paper trips over something.

## The staged exercise

**Phase 0 — build the instrument.** Registry, checker, test suite, make target,
CI job. Nothing is re-validated yet.

**Phase 1 — the cheap pass.**
1. Run the checker: which claims are stale by git date, which scripts unregistered.
2. Run every `test_*.R` locally: confirm the pinned injections still fire.
3. **Prose reconciliation** — read each layer's claim / proof / Misses paragraph
   against its current code; record every statement that no longer matches. No
   tool does this, and it is where the most findings are expected, since five
   layers have changed since the prose was written.

**Phase 2 — targeted fresh injection**, prioritised by Phase 1 in this order:
layers A5 flags as stale (expect 2b, 5c, 10); then **layers with large `skip`
populations**, because a skip is exactly where a bug hides from the check that
would otherwise catch it (789/1,133 on ABS layer 3, which is how
`govt_responds_people` survived); then layers whose prose could not be confirmed
by reading; then layers with thin fixtures. For each, invent a fault
that is **not** already a fixture, apply it **to a scratch copy — never a real
spec** (the safety rule QA.md already observes for the coverage-reconciliation
`over` case), and record whether the layer fires.

**Phase 3 — re-stamp.** Update prose, bump `verified:` dates, commit. The checker
goes green, and stays green only while the claims stay true.

**Rule when injection finds a gap: document first, fix only if cheap.** A layer
that fails its fresh fault gets its QA.md claim corrected immediately and an
entry in `JEFF_MUST_INVESTIGATE.md`. It does not silently expand this project
into fixing the layer. Without this rule Phase 2 is unbounded.

## Testing

`test_qa_self_audit.R` follows the `test_freshness_check.R` pattern: build a
throwaway fixture, assert clean, inject exactly one fault, assert the verdict
flips.

| Injected fault | Expected |
|---|---|
| Audit script present but unregistered | hard fail |
| `not_a_layer:` entry with no reason | hard fail |
| `script:` path missing | hard fail |
| `test:` missing, or `none` without a reason | hard fail |
| Script committed after `verified:` | hard fail (STALE) |
| Test committed after `verified:` | hard fail (STALE) |
| Generated table edited by hand | hard fail |
| Registry unparseable | exit 2, never clean |
| QA.md markers absent | exit 2 |
| `enforce: hard`, no `quit(status = 1)` | soft warn, exit 0 |
| Layer absent from `run_all.R` | soft warn, exit 0 |
| Clean control | exit 0 |

**Hermetic git fixtures.** A5 compares against commit dates, so each fixture
`git init`s a temp directory and makes commits with `--date` set explicitly,
rather than shelling out against the live repo. Otherwise the stale case would
pass or fail depending on when the suite ran.

## Scope / boundaries

- **In:** the registry, the checker, its tests, CI/make wiring, and the staged
  re-validation exercise ending in a re-stamped QA.md.
- **Out:** closing any gap in §What QA does NOT guarantee; triaging the 18 ABS
  label-reconciliation or 56 bin-width parity rows; flipping
  `HARMONIZE_AUDIT_GATE` to blocking; extending strict reversal beyond ABS;
  adding QA for the verbatim dictionaries.
- The verbatim-dictionary gap is real and currently unguarded (see the KIPA
  repair, `ebcfb71`), but it is *new detection*, not re-validation. Record it in
  `JEFF_MUST_INVESTIGATE.md` and scope it separately.

## Chosen defaults (confirmed)

| Decision | Choice |
|---|---|
| Primary goal | Re-validate what is claimed, not close gaps |
| Evidence bar | Staged: cheap pass first, then targeted fresh injection |
| Delivery | Hybrid — automate the mechanizable pass, keep injection human-driven |
| Source of truth | Registry YAML; QA.md table generated from it |
| Venue split | Structural checks in CI; test suites local via `make` |
| Enforcement of the new layer | Hard on A1–A6, soft on A7–A8, fails closed |

## Success criteria

1. `Rscript src/r/audit/08_qa_self_audit.R` exits 0 on a tree whose claims are true.
2. Reverting any single Phase-3 stamp, or touching a layer's script without
   re-stamping, turns it red.
3. `test_qa_self_audit.R` passes with every fault in the table above flipping the
   verdict.
4. The CI job runs on PRs and fails on a stale claim, without survey data.
5. `docs/QA.md` carries a `verified:` date per layer that is provably not older
   than the code it describes.
6. Every layer's Misses paragraph has been read against current code, and
   discrepancies are either corrected in place or filed in
   `JEFF_MUST_INVESTIGATE.md`.
