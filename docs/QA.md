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
| 2b | **Out-of-range triage** | what the engine **deleted** for falling outside `valid_range` | 🔴 | ✓ | `src/r/audit/03_oob_triage.R` |
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
| 10 | **Module coverage** | is each pipeline module audited **at all**? | 🔴 | ✓ | `src/r/audit/07_module_coverage.R` |
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

### 2b. Out-of-range triage — 🔴 hard
**Claim.** Every value the harmonize engine coerced to `NA` for falling outside `qc.valid_range` is classified and graded, so a stray response code cannot be deleted without anyone noticing.

**Why it exists.** The engine already *detected* these (`harmonize.R:279–321`): it counts them, writes them to `outputs/<survey>/oob_log.csv`, and coerces them to `NA`. **Nothing read that log.** `run_all` did not tally it, the post-harmonize gate did not look at it, it is gitignored, and the only build-time signal was a `message()` that scrolled past. Note also that layer 2's `validate_range` runs on the harmonized `.rds` resolving the *same* range the engine already scrubbed with, so in the production path it is structurally always 0 — the engine is the real detector and this log was its only record.

That matters more than a missing tally, because the engine's default action is to **destroy the evidence**: once an undeclared code is `NA` it is indistinguishable from item nonresponse.

**What it found on introduction (2026-07-31).** 90 events across 7 surveys — **29,699 silently deleted respondent-values**, 6 of them error-grade. Headline error rows: `wvs freedom_vs_equality` w2 (8,787 × code 3 on a 1–2 item — an entire third response option), `abs hh_generations` w6 (107 × code 10 on a 1–4 item), `afro urban_rural` w6/w7 (128 × code 460), `arab-barometer dem_feature_1st` w2 (a 4–5-digit code frame where the spec declares 1–10), `afro bribe_police` w2 (30 × code 4 on a 0–3 item).

The largest deletions turned out to be **already triaged**: `lbs education_level` y2004 (2,491 × code 0), `lbs age` y2010 (2,483 × code 0) and `afro dem_satisfaction` w9 (932 × code 0 — the group preserved in `dem_country_not_democracy`) all declare their drops in `qc.coverage_missing_codes_by_wave`, so they report `ok_declared`. See "How" below: this layer initially re-raised all three as errors, which is a failure mode worth naming — an audit that re-opens settled decisions trains people to ignore it.

**How.** Two clearing mechanisms run before grading. `qc.coverage_missing_codes[_by_wave]` in the variable's own spec is the repo's existing first-class "this drop is deliberate" declaration — `validate_coverage()` already honours it, which is why `lbs age` y2010 reports "Coverage OK (100.0%)" despite 2,483 deletions. Matching events become `ok_declared`; spec-declared intent outranks the grade. Spans are never cleared outright — the engine logs only n/min/max, so matching endpoints cannot prove the values in between are declared, and such events cap at `warn` with the reason recorded. Anything else acceptable goes in `src/config/_audit/oob_exemptions.yml` (`ok_exempt`, written reason mandatory).

Then deterministic classification, no statistical inference (same standard as Check D), preferring what the survey's own specs declare over any hardcoded guess:

| class | meaning | grade |
|---|---|---|
| `scale_extension` | stray sits immediately outside the range and is not a sentinel — the wave's response set is **wider than the spec believes** | error ≥30, else warn |
| `zero_leak` | code 0 where the scale starts at 1 — missing or substantive? needs a human | error ≥30, else warn |
| `out_of_frame_code` | ≥10× the frame — the wave is coded on a **different code frame** | error |
| `sentinel_leak` | the code is declared missing elsewhere in this survey (or is a classic sentinel) — spec under-declares, outcome benign | warn |
| `outlier_tail` | continuous var with a spread past its bound (age 115–130) — dirty raw data | warn |
| `unclassified` | none of the above | error ≥50, else warn |

Volume escalation exists because bulk deletion is never benign regardless of class: one stray 6 in a 1–5 item is a typo, 8,787 of them is a lost response category.

**Proof.** `test_oob_triage.R` — 61 assertions, 0 failures. Every headline event above is pinned as a regression fixture; plus exact threshold boundaries (29 warn / 30 error), missing-log → `skip` vs empty-log → `ok`, malformed log → config error, and exemption scoping (wave- and survey-scoped exemptions must not leak, and must never silence `warn` rows). Three design faults were caught during the build and are now pinned. The costliest: the layer shipped without reading `qc.coverage_missing_codes`, and so re-raised three already-documented drops as errors — found only by cross-checking its own output against the specs. The other two were caught by the tests: `scale_extension` firing on continuous variables (WVS age 15 against a floor of 16 is a 15-year-old, not a lost category), and the sentinel evidence base being polluted by bespoke per-variable missing codes — ABS declares `{0,3,5,6,7,8,9,10,11}` as missing on one variable or another, which downgraded both the `afro dem_satisfaction` 932 and the `abs hh_generations` 107 to warn until the evidence base was restricted to sentinel-*shaped* codes.

**Catches.** Undeclared response categories, wave-specific code frames, undeclared missing codes, and bulk deletion of any kind — the class where the harmonized output looks perfectly clean *because* the offending values are already gone.

**Misses / caveats.**
- **It audits a build artifact, not the data.** The log is only as fresh as the last harmonize run — pair with 6d. A survey that has never been run with logging reports `skip`, which is not a pass.
- **It only sees what a declared range caught.** 9 of 1,133 variable specs declare neither `valid_range` nor `skip_range_check` (all weights/IDs/nominal passthroughs); strays there are invisible to it, and a *defensively over-wide* range (declaring `[1,6]` on what is really a 1–4 item) hides them by construction. It answers "outside the range you declared," never "this tail looks suspicious."
- **It reports what the engine deleted, not whether deleting was right.** `outlier_tail` and `sentinel_leak` are warns precisely because the coercion is usually correct; a human still decides.
- Thresholds (30/50) are judgement calls, and `unclassified` exists by design rather than forcing a guess.

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

### 5c. Bin-width parity (Check D) — 🔴 hard
**Claim.** Within a variable, every wave's recode packs the SAME number of source categories into each harmonized bin; a wave whose bins are structurally wider than its siblings' is flagged `parity_error`.
**Proof.** `test_bin_width_parity.R` (23 tests): synthetic W5-class seam, recode-mapping seam, uniform-collapse ok, midpoint-drop ok, exemption plumbing, plus the real-ABS regression fixture pinning the 41-variable finding set. The motivating live catch: **ABS W5 6→4pt trust pole-merge** — native "Trust fully"+"Trust a lot" both → 4, inflating W5 top-box ~2.4–4.6× in all 13 trust items in every country while every direction check passed (found via paper 05, 2026-07-21; the class also covers the 4 W5 social-trust items and `econ_family_income_fair`).
**How.** Static only — YAML `recode` mappings, identity over the declared scale, or `requires_data: false` registry fns called over their declared `input_scale` domain. No raw data is read.
**Catches.** Cross-wave bin-width divergence declared in specs/registry — the "directionally correct but not level-comparable" class no other layer sees.
**Misses / caveats.** Collapses applied uniformly in EVERY wave (comparability preserved — deliberately not a finding); `requires_data` fns and `derive` methods (`skip` rows); raw domains wider than the registry's declared `input_scale` (would need the deferred empirical crosstab arm); fns missing from the registry surface as `no_registry_entry` (warn-class; registry↔code drift is `check_registry_complete.R`'s job). Acknowledged seams live in `src/config/_audit/bin_width_exemptions.yml` with reasons; the ABS W5 findings are deliberately NOT exempted.

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

### 10. Module coverage — 🔴
**Claim.** Every module in `src/r/data_prep_modules/` is either audited or *explicitly, reasoned* exempted — so no module is silently unwatched.

**Why it exists.** Every other layer answers "is this survey's data right?". None asked the prior question: *is this module being audited at all?* The system enumerated its targets from two hardcoded vectors — `run_all.R`'s `.SUPPORTED_SURVEYS` and `06_check_freshness.R`'s `.FRESHNESS_SURVEYS` — synchronised only by a comment reading "kept in sync". Nothing compared either to what was on disk.

**What it found on introduction (2026-07-29).** 4 of 15 modules had **zero** audit coverage: `marpor`, `unga`, `unsc` (added 2026-07-28) and **`vdem`, invisible since it was scaffolded**. Between them they ship 8 live artifacts to `data/processed/`.

This was worse than a missing check. Layer 6d is the documented pre-flight — *"run this before consuming data"* — and it returned a clean bill of health while never having looked at those modules. **A false all-clear, not a gap.** That is the failure mode this layer exists to make impossible.

**Proof.** `test_module_coverage.R`, 14 fault-injection cases, 0 failures: unregistered module → hard; reasonless exemption → hard; one-sided list edit (either direction) → hard; residual-coverage gap → soft; stale exemption → soft; unparseable source → config error, never a silent pass.

**Blind spot.** It verifies a module is *registered*, not that the checks it runs are *adequate*. A module can be registered and still be shallowly audited. It also cannot judge whether an exemption's reason is honest — exemptions are per-check (`exempt_from` / `still_required`) precisely so a module that can't be label-reconciled still can't quietly escape staleness checking.

**Resolved 2026-07-29.** The four (then five, once `oecd_dac` appeared) exempt modules now emit manifests and are in `.FRESHNESS_SURVEYS`; all report FRESH. Layer 10 is clean.

Closing that required fixing the invariant itself. Layer 10 originally asserted `.SUPPORTED_SURVEYS` **==** `.FRESHNESS_SURVEYS`; the correct rule is **⊆**. Freshness legitimately covers *more* than the survey checks, because staleness is the one failure every generated artifact is exposed to, while a non-survey module has no specs to reconcile. The dangerous direction is asymmetric and stays hard: a survey that is audited but absent from the pre-flight looks covered while its data silently rots. A freshness-only entry is allowed only when it is a registered exemption.

It also required an extension to `write_manifest()`. Engine files were hardcoded to the four harmonize-engine paths; a non-survey module records **its own scripts** instead via the new `engine =` argument, since nothing in those modules calls `harmonize_all()` or `recoding.R` and recording them would mark all five STALE on every unrelated `recoding.R` edit. Default is unchanged, so every existing survey manifest is untouched.

---

## What QA does NOT guarantee

Read this before trusting a "clean" run.

1. **A default `run_all.R` / build does not verify direction.** The gate is **report-only**; the ABS strict-reversal check is ABS-only; the label-recon and bin-width-parity checks run but their errors only *fail a run* through `run_all`'s L4_labels / L4_binwidth tallies, not through the per-build gate. **ABS carries 18 label-reconciliation error rows (7 variables: `demo_political_equality`, `econ_family_income_fair_6pt`, `govt_should_censor_ideas`, `no_accountability_between_elections`, `gov_elections_real_choice`, `sat_president_govt`, `efficacy_ability_participate`) AND 56 bin-width parity_error rows (41 variables, headlined by the W5 6→4pt trust class) right now** — known, deferred backlogs ([`project_abs_label_recon_backlog`], `JEFF_MUST_INVESTIGATE.md`). Flip `HARMONIZE_AUDIT_GATE=block` to make them stop the pipeline; until the backlogs are triaged, "clean" ≠ "ABS is directionally correct and level-comparable." Separately, **6 out-of-range error rows are open across abs/wvs/afro/arab-barometer** (layer 2b) — these *do* fail `run_all`, but they are not wired into the per-build gate, so a build still cannot be stopped by them.
2. **Wrong-but-consistent recodes pass almost everything.** If a recode is wrong yet produces in-range values, coherent within its battery, and matching its (also-wrong) labels, *no* layer catches it. QA verifies internal consistency and label agreement, not ground truth against the questionnaire. **One partial exception, added 2026-07-31:** where the wrong recode *also* pushes some codes out of range, layer 2b surfaces the deletion, and following that deletion back to the raw value labels can expose the mislabelling — which is exactly how the WVS `freedom_vs_equality` W2 bug was found. That only works when the error leaves an out-of-range trace; a wrong recode entirely inside the valid range still passes silently.
3. **Soft checks never fail a run.** Battery coherence, anchor coverage, and drift only warn/report. A battery hint or 207 "uncovered" vars will not turn `run_all` red.
4. **Coverage of the hard checks is uneven across surveys.** Strict reversal and source-coverage reconciliation exist for ABS (+IPUS/KINU for the latter) only. Non-ABS surveys lean on label reconciliation + invariants alone for direction.
5. **Cross-survey scale mixing is not checked.** The trust-scale / unification-direction gotchas in [`CLAUDE.md`](../CLAUDE.md#cross-survey-scale-gotchas) are documentation, not enforced code. Row-binding KAMOS (0–10) with ABS (1–4) trust will not trip any check.
6. **Missing-convention correctness isn't verified.** A convention that masks a *substantive* code (e.g. deleting ethnic code 7=Afrikaner by reusing an ordinal `treat_as_na` set on a nominal passthrough — see the paper-22 Afro fix) produces valid-looking in-range output; only a human reading the label set catches it.
7. **Deferred checks (B5/B6).** Mandatory `valid_range` and `qc.validate.phrase` enforcement was scoped but deferred pending review ([`project_audit_phase_b_deferred`]). Absent-`valid_range` currently only *warns* — and where it is absent, layer 2b is blind by construction, since a range that was never declared can never be exceeded. In practice only 9 of 1,133 variable specs are exposed, all weights/IDs/nominal passthroughs.
8. **Label reconciliation `skip`s where it can't classify poles** (ABS W6, surveys without raw label metadata). A `skip` is "not verified," not "verified clean."
9. **Out-of-range detection is still declaration-driven, and still destructive.** Layer 2b audits the engine's deletions, but the engine's behaviour is unchanged: an out-of-range value is coerced to `NA`, where it is indistinguishable from item nonresponse. Nothing infers a variable's real scale from its empirical distribution, so an over-wide `valid_range` hides strays rather than surfacing them. Layer 2b tells you what *was* deleted; it cannot tell you what should have been.

---

## Track record (bugs QA actually caught)

Concrete evidence the machinery works on real bugs, not just injected ones:

| Bug | How caught | Fix |
|-----|-----------|-----|
| ABS `system_deserves_support` harmonized opposite its battery-mates | label reconciliation (Check A) + battery coherence hint | `ebe4f00` (2026-06-20) |
| ABS democracy-supply battery (4 `dem_*` items) reversed vs labels | same | `6e622f5` (2026-06-20) |
| ABS `econ_family_income_fair_6pt` stored opposite labels | label reconciliation | **caught, still open** — in the 18-error backlog above |
| ABS W5 trust 6→4pt pole-merge (top-box inflated ~2.4–4.6×, direction correct) | bin-width parity (Check D) | **caught, still open** — 18 W5 items (13 institutional + 4 social trust + `econ_family_income_fair`) flagged `parity_error`; left visible by decision 2026-07-22, see `JEFF_MUST_INVESTIGATE.md` |
| 29,699 respondent-values silently coerced to `NA` across 7 surveys | out-of-range triage (Check E) | **all 6 error rows fixed** 2026-07-31; 9,052 values recovered |
| **WVS `freedom_vs_equality` W2 stored the wrong category as "Equality"** — W2 codes are 1=Freedom, 2=Neither, 3=Equality, but the spec assumed W7's binary order, so all 8,787 Equality responses were deleted and the 2,029 "Neither" responses were relabelled "Equality" | out-of-range triage (Check E) flagged the deletions; raw value labels confirmed the mislabelling | fixed 2026-07-31 — the first catch of the "wrong-but-consistent recode" class item 2 below says nothing covers |

The third row is the point: the check *found* it (Phase 5, `1308831`); the report-only gate is why it's still sitting there. The fourth row closes a whole class the direction checks could never see — it was found by a downstream paper first (paper 05), and Check D now regression-pins it.

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

# What did the last build silently delete for being out of range?
Rscript src/r/audit/03_oob_triage.R --all-surveys           # exit 1 on any error row
Rscript src/r/audit/03_oob_triage.R --all-surveys --quiet   # error rows only
Rscript src/r/audit/03_oob_triage.R --survey afro
Rscript src/r/audit/test_oob_triage.R                       # its 61 fault-injection tests

# The direction gate, standalone — REPORT-ONLY unless you opt in:
Rscript src/r/audit/99_post_harmonize_gate.R --survey abs            # prints errors, exit 0
Rscript src/r/audit/99_post_harmonize_gate.R --survey abs --block    # errors → exit 1
HARMONIZE_AUDIT_GATE=block Rscript .../99_create_final_dataset.R     # enforce in a build

# Read a survey's invariant results:
#   outputs/<survey>/03-invariants.md   (human)   audit/reports/<survey>/03-invariants.csv (machine)
# Every check CSV lives under audit/reports/<survey>/04-*.csv, 02-*, 05-*.
```

Reading a result: `status` columns use `ok / warn / error / skip` (invariants), `ok / error / skip` (label recon — **`error` is the one that matters**), `ok / hint / weak / na / skip` (battery), `covered / exempt / uncovered / skip` (anchor coverage), `error / warn / ok_declared / ok_exempt` (out-of-range triage — every row is a real deletion; the grade says how likely it was wrong, and `ok_declared` means the spec already documented the drop). **`skip` is not a pass.**

## Calibrated confidence verdict

- **Trust as strong:** spec validation, output invariants (range/type/coverage), out-of-range triage, determinism/input-drift, and — where it runs green — label reconciliation. These are hard, self-tested, and demonstrably catch their fault classes.
- **Trust but read the report:** battery coherence and anchor coverage (soft; hints and coverage %, never a gate), coverage reconciliation (ABS-centric).
- **Do not treat as a safety net:** distribution drift (a puzzle generator, not a check), and any *default* run's silence on ABS direction (report-only gate + open 18-error backlog).
- **Not covered at all:** ground-truth correctness of a recode, cross-survey scale compatibility, missing-convention appropriateness — these still need a human against the questionnaire.

**Bottom line for a paper:** if `run_all.R` is green *and* `--survey <yours> --block` on the gate is also green *and* the survey isn't leaning on `skip`s, you can defend the harmonization's internal consistency and label-direction. That is not the same as defending that each variable means what the paper says it means — that argument still comes from the verbatim dictionary and your own reading.
