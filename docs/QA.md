# QA & Confidence Guide

**What this is.** A map of every QA/audit layer in this repo, with — for each — *proof* that it catches the fault it claims to (I injected the fault and watched it fire), and an honest statement of what it does **not** catch. Use it to calibrate how far to trust a "clean" result.

**Verified:** 2026-07-06 (fault-injection pass; see [`docs/superpowers/specs/2026-07-06-qa-confidence-guide-design.md`](superpowers/specs/2026-07-06-qa-confidence-guide-design.md)).

**One-line verdict.** The direction/reversal machinery is genuinely strong and *self-tested* — the repo ships fault-injection regression tests that reintroduce known bugs and confirm the checks flag them, and they pass. **But the hard direction gate is report-only by default, and ABS currently carries 18 real label-reconciliation errors that a normal run passes silently.** "Clean from `run_all.R`" means "no check *crashed* and no *hard* check that is *wired to fail* found something" — it does **not** mean "directionally verified." Read [§What QA does NOT guarantee](#what-qa-does-not-guarantee).

---

## At a glance

Legend — **Enforcement:** 🔴 hard (nonzero exit / stops pipeline) · 🟡 soft (reports, never fails) · ⚪ report-only-by-default (hard only when you opt in). **Verified:** ✓ caught an injected fault · ⚠ catches but only as a soft hint · 📋 reporting tool, no pass/fail.

| # | Layer | What it checks | Enforce | Verified | Source |
|---|-------|----------------|:------:|:--------:|--------|
| 1 | Spec validation | YAML matches schema; every `fn:` / convention exists | 🔴 | ✓ | `src/r/harmonize/validate_spec.R` |
| 2 | Output invariants | per-var×wave coverage, range, type, transformation sign | 🔴¹ | ✓ | `src/r/data_prep_modules/2.5_validate_harmonization.R` |
| 3 | **Label reconciliation** | value stored **opposite its own labels** | 🔴 | ✓ | `src/r/audit/04_label_reconciliation.R` |
| 4 | Battery coherence | item negatively correlated with its battery-mates | 🟡 | ⚠ | `src/r/audit/04_battery_coherence.R` |
| 5a | Anchor coverage | is each ordinal var covered by an anchor? | 🟡 | 📋 | `src/r/audit/04_anchor_coverage.R` |
| 5b | Strict reversal (**ABS only**) | reverser really produces r≈−1 vs raw | 🔴 | ✓ | `src/r/audit/04_strict_reversal.R` |
| 6a | Distribution drift | wave-to-wave distribution shifts | 📋 | 📋 | `src/r/audit/05_drift_check.R` |
| 6b | Determinism | recorded outputs still hash-match | 🔴 | ✓ | `src/r/audit/06_check_determinism.R` |
| 6c | Input drift | raw inputs unchanged since last run | 🔴 | ✓ | `src/r/audit/06_check_input_drift.R` |
| 6d | **Pre-flight freshness** | would a re-run change the output? incl. **added** specs | 🔴 | ✓ | `src/r/audit/06_check_freshness.R` |
| 7 | Coverage reconciliation | spec `source:` claims vs codebook reality | 🔴² | ✓ | `src/r/audit/02_*coverage*.R` |
| 8 | Post-harmonize gate | runs 3+8 direction checks after each build | ⚪ | ✓ | `src/r/audit/99_post_harmonize_gate.R` |
| 9 | Unit tests | the checks' own regression suite | 🔴 | ✓ | `src/r/**/test_*.R` |
| — | Orchestrator | runs 1–7 for every survey, tallies pass/fail | 🔴 | ✓ | `src/r/audit/run_all.R` |

¹ writes `error` rows to a CSV; `run_all` maps `error`→fail. ² exit 1 on ≤80% coverage or any confirmable `over`-claim; `02_source_coverage_reconcile` is ABS/IPUS/KINU only.

---

## Per-layer detail (claim → proof → blind spot)

### 1. Spec validation — 🔴 hard
**Claim.** A malformed spec, or one referencing a nonexistent recode function / missing-convention, cannot be used.
**Proof (injected).** On a scratch spec: setting a variable's `fn:` to `totally_nonexistent_fn_xyz` → `❌ Cross-reference validation failed: … fn … is not in the recoding registry`. Adding a stray top-level key → `❌ Specification validation failed: <root>: must NOT have additional properties`. Both **stop**. Clean control passed.
**Catches.** Schema drift, typo'd `fn:`, undeclared `use_convention`, duplicate `id`.
**Misses.** Whether the *right* function was chosen — a spec that uses `safe_4pt_none` where `safe_reverse_4pt` was needed is schema-valid. That is layer 3's job.

### 2. Output invariants — 🔴 (via error rows)
**Claim.** Harmonized values stay in declared range, keep type, and correlate with the raw in the declared direction; coverage isn't silently lost.
**Proof (injected).** `validate_range(c(1,2,3,4,99), c(1,4))` → `status=error`. `validate_transformation(raw, raw, method="reverse")` (identity applied where a reversal was declared) → `status=error, pearson=1`; the correct `5−raw` → `status=ok, pearson=−1`. Real-world: the last Afro build flagged 4 genuine coverage-loss `error` rows (`corr_perc_*`).
**Catches.** Out-of-range codes, wrong-direction reversal (sign flip), >1% coverage loss, type instability.
**Misses.** A transformation that's wrong but preserves sign and range (e.g. a mis-collapse `{1,2}→1, {3,4}→2` where `{1}→1,{2,3,4}→2` was intended) — correlation stays high, range stays valid, no flag.

### 3. Label reconciliation — 🔴 hard (the marquee check)
**Claim.** Flags any variable whose harmonized values run **opposite the direction its own `scale.labels` declare** — the `system_deserves_support` bug class.
**Proof.** The committed regression test `test_label_reconciliation.R` checks out the *pre-fix* buggy `system_deserves_support` (`ebe4f00^`) and asserts it → `error`, and the current fixed version → clean. It passes (44/44). Live: `04_label_reconciliation.R --survey abs` reports **18 error rows across 7 variables right now** (see gap section).
**Catches.** An item reversed (or not reversed) against its labels, per wave, using the raw `.sav` value labels + a bilingual KO/EN polarity lexicon.
**Misses.** Variables whose raw labels aren't pole-classifiable → `skip` (e.g. ABS W6 has no raw label metadata for some items → skipped, not verified). Nominal passthroughs (no direction). Surveys/waves without raw label metadata.

### 4. Battery coherence — 🟡 soft
**Claim.** Within a battery (shared stem, or same concept+scale), an item that's reversed relative to its mates shows up as a negative sibling correlation.
**Proof.** `test_phase3_checks.R` injects `5−x` on one battery member and asserts a `hint` with `neg_corr` in every wave (passes 17/17). Live: my recent Afro club-goods battery came back coherent (mean pairwise r≈0.48, no hint); ABS currently shows 101 hints.
**Catches (as a hint only).** A single flipped item inside a ≥3-member battery with ≥30 complete pairs.
**Misses / caveats.** **Never fails a run** — it only prints hints. A *whole battery* reversed consistently stays internally coherent → no hint (that's layer 3's job). Batteries with <30 pairs or <3 members → `na`/`skip`.

### 5a. Anchor coverage — 🟡 reporting
Confirms each ordinal/continuous var is registered as an anchor/loader somewhere (or exempt). It's a *coverage metric*, not a correctness check: ABS reports **207 uncovered** variables — meaning "not checked by the anchor system," not "wrong." Never fails a run.

### 5b. Strict reversal — 🔴 hard, **ABS only**
For ABS variables using a pure monotone reverser, asserts pearson(raw, harmonized) ≈ −1 (or +1 for declared identities). Fails (exit 1) on a sign mismatch. **v1 has a raw-data resolver for ABS only** — every other survey emits `skip` rows, so this protection does not exist outside ABS.

### 6a. Distribution drift — 📋 reporting only
`05_drift_check.R` computes wave-to-wave distribution shifts (TVD/KS). **It has no pass/fail concept** — every row is normal output; it exits 0 unless it crashes. Treat its findings as *puzzles to investigate*, never as a gate. (Same spirit as the Slope Prospector.)

### 6b / 6c. Determinism & input drift — 🔴 hard
**Claim.** If any recorded input/spec/output changed since the last build, the outputs are potentially stale.
**Proof (injected).** Corrupting one recorded `sha256` in a scratch copy of the manifest → `inputs … drift=1`, names the exact file, `*** 1 path(s) failed`, **exit 1**; the real manifest → all match, exit 0.
**Catches.** A spec edited after the last harmonize; a hand-edited output; a changed/removed raw `.sav`.
**Misses.** Only files listed in `outputs/<survey>/manifest.json`. No manifest (e.g. V-Dem scaffold) → not checked. It detects *that* something changed, not *whether* the change matters. Crucially, it re-hashes only the paths the manifest *already records*, so a **newly added spec that was never harmonized** produces zero drift and exits 0 — see 6d.

### 6d. Pre-flight freshness — 🔴 hard, **run this before consuming data**
`06_check_freshness.R --all` answers one question per survey: *if I re-ran the pipeline right now, would the harmonized output change?* Verdicts are `FRESH` / `STALE` (a spec, input, or engine file changed, or a spec was **added or deleted**) / `TAMPERED` (a harmonized output no longer matches its recorded hash) / `SKIP` (no manifest). Exit 1 on any `STALE` or `TAMPERED`. Hashing is delegated to `.hash_file()` in `provenance.R`, so there is one hashing implementation in the repo.

**Claim.** A gitignored `data/processed/*.rds` cannot silently drift behind the specs that produce it.
**Proof (injected).** `src/r/audit/test_freshness_check.R` — 20 assertions, each building a throwaway fixture, asserting `FRESH`, injecting exactly one fault and asserting the verdict flips: spec edited → `STALE`; spec **added but never harmonized** → `STALE` (the case 6b/6c misses); spec deleted → `STALE`; engine file edited → `STALE`; input edited → `STALE`; output edited → `TAMPERED` (and *not* `STALE`); both → `STALE` wins; no manifest → `SKIP`; corrupt manifest → `STALE`, i.e. **fails closed, never `FRESH`**.
**Catches.** Exactly the failure that left KIPA's `corr_punishment_*` stuck at `NA`-where-`7` for 2018–2020: the 7-point-ceiling spec fix was committed, nobody re-ran, and the gitignored `.rds` kept serving the old values with nothing to signal it.
**Misses.** It says a re-run *would* change something, never *what*. Back up the `.rds`, re-run, and diff before trusting the result — most drift turns out behaviourally inert (on 2026-07-09, eight of nine stale surveys rebuilt byte-identical; the `recoding.R` hash had moved only because new functions were appended).
**Blind spot it inherits.** Surveys with no manifest are `SKIP`, not `FRESH`. `gcb` is currently `SKIP`. And `wvs` is `STALE` **and unrebuildable** — its manifest records `data/wvs/raw/wave6|7/wvs_wave6|7.parquet` as inputs, those files no longer exist, and no script in the repo regenerates them from the `.sav` that is present.

### 7. Coverage reconciliation — 🔴
`02_coverage_report.R` fails (exit 1) if <80% of spec `source:` claims reconcile to the extracted codebook. `02_source_coverage_reconcile.R` (ABS/IPUS/KINU only) emits `over` (spec maps a raw var with no data in that wave — a confirmable error, exit 1) and `under` (data exists but unmapped — needs review, does not fail). *Verified by code + the subagent's read; a live `over` injection would require editing a real spec, which the safety rule forbids, so it's described not demonstrated here.* Also note the harmonize engine's own pre-flight warns when a wave is unmapped but its raw var has valid values.

### 8. Post-harmonize gate — ⚪ report-only by default
Runs after every `99_create_final_dataset.R`: label reconciliation (hard) + battery coherence + anchor coverage (soft). **Default = report-only: it prints the error count loudly and exits 0 — it cannot stop a build.**
**Proof (injected/live).** `--survey afro --block` → exit 0 (clean). `--survey abs --block` → **exit 1**, `BLOCKING: 18 label-reconciliation error(s)`. With `HARMONIZE_AUDIT_GATE=block` it **fails closed** — a check that *crashes* also fails (verified in `test_phase5_gate.R`, 7/7).
**The catch.** Until you set `HARMONIZE_AUDIT_GATE=block`, the 18 ABS errors do not stop anything.

### 9. Unit tests — 🔴
The checks test themselves. Ran 2026-07-06: `test_label_reconciliation` (44), `test_phase2_checks` (17), `test_phase3_checks` (17), `test_phase5_gate` (7), `test_validation_completeness` (pass), `test_harmonize` (6), `test_codebook` (22) — **0 failures**. These include the fault-injection regressions cited above, which is why layers 3/4/8 are trustworthy. (`test_identity_functions.R` registered 0 testthat cases — worth a look; not a failure, but not contributing coverage.)

---

## What QA does NOT guarantee

Read this before trusting a "clean" run.

1. **A default `run_all.R` / build does not verify direction.** The gate is **report-only**; the ABS strict-reversal check is ABS-only; the label-recon check runs but its errors only *fail a run* through `run_all`'s L4_labels tally, not through the per-build gate. **ABS carries 18 label-reconciliation error rows (7 variables: `demo_political_equality`, `econ_family_income_fair_6pt`, `govt_should_censor_ideas`, `no_accountability_between_elections`, `gov_elections_real_choice`, `sat_president_govt`, `efficacy_ability_participate`) right now** — a known, deferred backlog ([`project_abs_label_recon_backlog`], `JEFF_MUST_INVESTIGATE.md`). Flip `HARMONIZE_AUDIT_GATE=block` to make them stop the pipeline; until the backlog is triaged, "clean" ≠ "ABS is directionally correct."
2. **Wrong-but-consistent recodes pass everything.** If a recode is wrong yet produces in-range values, coherent within its battery, and matching its (also-wrong) labels, *no* layer catches it. QA verifies internal consistency and label agreement, not ground truth against the questionnaire.
3. **Soft checks never fail a run.** Battery coherence, anchor coverage, and drift only warn/report. A battery hint or 207 "uncovered" vars will not turn `run_all` red.
4. **Coverage of the hard checks is uneven across surveys.** Strict reversal and source-coverage reconciliation exist for ABS (+IPUS/KINU for the latter) only. Non-ABS surveys lean on label reconciliation + invariants alone for direction.
5. **Cross-survey scale mixing is not checked.** The trust-scale / unification-direction gotchas in [`CLAUDE.md`](../CLAUDE.md#cross-survey-scale-gotchas) are documentation, not enforced code. Row-binding KAMOS (0–10) with ABS (1–4) trust will not trip any check.
6. **Missing-convention correctness isn't verified.** A convention that masks a *substantive* code (e.g. deleting ethnic code 7=Afrikaner by reusing an ordinal `treat_as_na` set on a nominal passthrough — see the paper-22 Afro fix) produces valid-looking in-range output; only a human reading the label set catches it.
7. **Deferred checks (B5/B6).** Mandatory `valid_range` and `qc.validate.phrase` enforcement was scoped but deferred pending review ([`project_audit_phase_b_deferred`]). Absent-`valid_range` currently only *warns*.
8. **Label reconciliation `skip`s where it can't classify poles** (ABS W6, surveys without raw label metadata). A `skip` is "not verified," not "verified clean."

---

## Track record (bugs QA actually caught)

Concrete evidence the machinery works on real bugs, not just injected ones:

| Bug | How caught | Fix |
|-----|-----------|-----|
| ABS `system_deserves_support` harmonized opposite its battery-mates | label reconciliation (Check A) + battery coherence hint | `ebe4f00` (2026-06-20) |
| ABS democracy-supply battery (4 `dem_*` items) reversed vs labels | same | `6e622f5` (2026-06-20) |
| ABS `econ_family_income_fair_6pt` stored opposite labels | label reconciliation | **caught, still open** — in the 18-error backlog above |

The third row is the point: the check *found* it (Phase 5, `1308831`); the report-only gate is why it's still sitting there.

---

## How to run & read the output

```bash
# BEFORE you read data/processed/*.rds into a paper — is it stale?
Rscript src/r/audit/06_check_freshness.R --all           # exit 1 if any STALE/TAMPERED
Rscript src/r/audit/06_check_freshness.R --all --quiet   # only the problems
Rscript src/r/audit/06_check_freshness.R --survey kgss
Rscript src/r/audit/test_freshness_check.R               # its 20 fault-injection tests

# Full hygiene sweep (all surveys) → audit/SUMMARY.md + stdout tldr
Rscript src/r/audit/run_all.R                    # exit 1 if any hard check fails
Rscript src/r/audit/run_all.R --survey abs       # one survey
Rscript src/r/audit/run_all.R --quick            # skip drift + codebook (faster)

# The direction gate, standalone — REPORT-ONLY unless you opt in:
Rscript src/r/audit/99_post_harmonize_gate.R --survey abs            # prints errors, exit 0
Rscript src/r/audit/99_post_harmonize_gate.R --survey abs --block    # errors → exit 1
HARMONIZE_AUDIT_GATE=block Rscript .../99_create_final_dataset.R     # enforce in a build

# Read a survey's invariant results:
#   outputs/<survey>/03-invariants.md   (human)   audit/reports/<survey>/03-invariants.csv (machine)
# Every check CSV lives under audit/reports/<survey>/04-*.csv, 02-*, 05-*.
```

Reading a result: `status` columns use `ok / warn / error / skip` (invariants), `ok / error / skip` (label recon — **`error` is the one that matters**), `ok / hint / weak / na / skip` (battery), `covered / exempt / uncovered / skip` (anchor coverage). **`skip` is not a pass.**

## Calibrated confidence verdict

- **Trust as strong:** spec validation, output invariants (range/type/coverage), determinism/input-drift, and — where it runs green — label reconciliation. These are hard, self-tested, and demonstrably catch their fault classes.
- **Trust but read the report:** battery coherence and anchor coverage (soft; hints and coverage %, never a gate), coverage reconciliation (ABS-centric).
- **Do not treat as a safety net:** distribution drift (a puzzle generator, not a check), and any *default* run's silence on ABS direction (report-only gate + open 18-error backlog).
- **Not covered at all:** ground-truth correctness of a recode, cross-survey scale compatibility, missing-convention appropriateness — these still need a human against the questionnaire.

**Bottom line for a paper:** if `run_all.R` is green *and* `--survey <yours> --block` on the gate is also green *and* the survey isn't leaning on `skip`s, you can defend the harmonization's internal consistency and label-direction. That is not the same as defending that each variable means what the paper says it means — that argument still comes from the verbatim dictionary and your own reading.
