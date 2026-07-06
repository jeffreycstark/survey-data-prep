# Design: QA Confidence Guide (fault-injection verified)

**Date:** 2026-07-06
**Status:** Approved (defaults confirmed by user)
**Author:** brainstorming session

## Problem

`survey-data-prep`'s QA/audit system is genuinely powerful but has grown to 7+
layers (spec validation, output invariants, Layer-4 direction checks, drift/
determinism, coverage reconciliation, the post-harmonize gate, unit tests,
Python tri-source cross-validation). The user can *navigate* it but does **not
have confidence** in it: the existing ~100 KB of audit docs (`audit/00-discovery`,
`01-audit-framework`, `02-implementation-tickets`) are organized around *how it
was built* (phases, ticket IDs like H1/E2/F4), not around *"can I trust it, and
what does it miss."*

## Goal

Produce a single navigable document that earns confidence in the QA — backed by
**proof** (fault injection) that each layer catches the faults it claims to,
plus an **honest list** of what it cannot catch.

Confidence comes from verification ("I broke it and QA caught it"), not from
description.

## Deliverable

One human-facing doc at **`docs/QA.md`**, linked from `README.md` and
`CLAUDE.md`. It points *into* the existing `audit/00–02` build-history docs
rather than replacing them (those remain the reference/history).

## Verification method — fault-injection ledger

For each QA layer: inject a known fault into a **scratch copy** (never mutating
real specs or data), re-run that layer (preferring the cheapest valid method —
a scratch spec + targeted re-run of just that check, on a small survey such as
KAMOS/GCB, or ABS/Afro for reversal cases), and record the outcome as one of:

- **✓ caught** — the layer flags it as an error/hard fail
- **⚠ soft** — the layer surfaces it as a hint/warning only (report-only)
- **✗ silent** — the layer passes it clean (a real gap)

| # | QA layer | Source | Injected fault | Expected |
|---|----------|--------|----------------|----------|
| 1 | Spec validation | `src/r/harmonize/validate_spec.R` | missing required field; `fn:` → nonexistent function | hard fail |
| 2 | Output invariants | `src/r/data_prep_modules/2.5_validate_harmonization.R` → `03-invariants` | harmonized value out of declared range; broken identity (transformation r ≠ +1) | error rows |
| 3 | Label reconciliation (Check A, hard) | `src/r/audit/04_label_reconciliation.R` | flip a reversal so values are stored opposite their labels (the `system_deserves_support` bug class) | hard error |
| 4 | Battery coherence (Check B, soft) | `src/r/audit/04_battery_coherence.R` | reverse one item of a coherent battery | soft hint (negative-correlation) |
| 5 | Anchor / strict reversal | `src/r/audit/04_anchor_coverage.R`, `04_strict_reversal.R` | reversal that disagrees with a declared anchor | sign-disagreement |
| 6 | Drift / determinism | `src/r/audit/05_drift_check.R`, `06_check_determinism.R`, `06_check_input_drift.R` | re-run for byte-identity; perturb an input hash | drift/nondeterminism flag |
| 7 | Coverage reconciliation | `src/r/audit/02_*` | null a source mapping that still has valid data | under-coverage flag / pre-flight warning |
| 8 | Post-harmonize gate | `src/r/audit/99_post_harmonize_gate.R` | set `HARMONIZE_AUDIT_GATE=block` + a real label-recon error | pipeline stops (fail-closed) |
| 9 | Unit tests | `src/r/**/test_*.R` (10 files) | run all | green + note coverage |

(Python tri-source cross-validation — Phase 6 — is noted and lightly checked, not
fault-injected in this pass.)

Any layer that returns **✗ silent** on its own claimed fault is a finding recorded
in the doc's gap section — not fixed in this task.

## Document structure (`docs/QA.md`)

1. **At-a-glance table** — layer · what it checks · blocking / advisory / report-only · *verified?* (✓/⚠/✗) · source file.
2. **Per-layer sections** — plain-English claim → mechanism → the fault I injected + result → what it provably catches → **what it misses**.
3. **"What QA does NOT guarantee"** — the honest gap list: wrong-but-internally-consistent recodes; the **report-only gate** (not enforced by default); the label-recon **backlog** (16 ABS vars unenforced); anchor **coverage exemptions** (~207 uncovered); deferred checks (B5/B6); cross-survey scale-mixing not caught; nominal-passthrough substantive-code masking.
4. **Track record** — real bugs QA *did* catch, with commits: ABS `system_deserves_support` reversal (`ebe4f00`), democracy-supply battery (`6e622f5`), `econ_family_income_fair_6pt`.
5. **How to run + read output** — `run_all.R`, the gate env var, reading `03-invariants`, running the tests.
6. **Calibrated confidence verdict** — where "clean" is trustworthy vs. where the user should still eyeball.

## Scope / boundaries

- Verify the **layers** (survey-agnostic); inject faults on 1–2 representative surveys per layer (not exhaustive per-survey).
- Injection scripts are **scratch-only** (discarded); results live in the doc.
- **Not** in scope: fixing the gaps found, flipping the gate to blocking, or the broader repo-doc consolidation (stale `PROJECT_INDEX.md`, redundant engine/codebook docs) — each is a separate follow-up.

## Safety

All fault injection happens on scratch copies under the session scratchpad or
throwaway temp specs. Real `src/config/**` specs and `data/processed/**` outputs
are never mutated.

Where possible, injections target a check's **inputs directly** (a scratch spec
that mis-declares direction against the *real, unchanged* harmonized data, or a
small synthetic harmonized frame) so that no real survey has to be re-harmonized.
Where a re-harmonize is genuinely required, it writes to a **scratch output
path** — the real `outputs/**` and `data/processed/**` master files are left
intact. No corrupted spec or stale output is left in the tree; the git working
tree is unchanged by the verification pass except for the new `docs/QA.md` and
the doc links.

## Chosen defaults (confirmed)

- Location: `docs/QA.md`
- Injection scripts: scratch-only (not committed)
- Survey coverage of fault tests: representative (1–2 surveys per layer)

## Success criteria

- Every one of the 9 layers has a recorded ✓/⚠/✗ verdict backed by an actual run.
- The doc states, per layer, at least one thing it provably catches and one thing
  it does not.
- The "does NOT guarantee" section is concrete (named gaps, not hand-waving).
- A new reader (or future-user) can, in one doc, decide how far to trust a
  `run_all.R` "clean" result.
