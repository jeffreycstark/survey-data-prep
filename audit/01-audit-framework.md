# Phase 2 — Audit Framework Design

A layered audit, designed against what Phase 1 found in this repo: 11 surveys, ~120 production YAMLs, a shared R harmonization engine, no working test runner, no provenance, no CI, no reverse-direction safety net, and a hand-rolled spec validator that doesn't reject unknown keys.

This document describes **what each layer must do** and **how it plugs into the existing engine** — not how to implement it. Phase 3 (`02-implementation-tickets.md`) decomposes each layer into 1–3 hour tickets.

---

## Design principles

1. **Survey-agnostic.** Wave keys are not standardized in this repo (`w1`, `y1995`, `r1`, `w2003`, `2018`). Every framework component must consume wave names from the spec, not assume an enumeration. The engine already does this via `resolve_wave_rule()` (`src/r/harmonize/harmonize.R:42`); the audit must too.

2. **Fail loud, not warn quiet.** R's `warning()` channel is suppressible and easy to miss in long log scrolls. Audit failures must be returned as structured exit codes and structured artifacts (CSV, JSON), not just console output.

3. **Spec-as-contract.** The YAML is the single declarative source. Every audit assertion ultimately compares some other artifact (raw data, codebook, harmonized output) to a claim made in the YAML. If a claim cannot be expressed in the YAML, it cannot be audited.

4. **No code without a verifiable comparand.** The "silent killer" pattern is `safe_reverse_4pt` running on a variable whose true direction nobody verified. Every transformation must be backstopped by a comparison the YAML can describe (anchor variable, value-label match, distribution shape).

5. **Cheap before expensive.** Schema and provenance checks run on every commit. Cross-wave drift and codebook reconciliation are heavier and run on PR / release. Tier the layers to keep the inner-loop fast.

6. **Reproducible from source, not from `outputs/`.** Several audit reports already in `outputs/` (e.g. `HARMONIZATION_VALIDATION_SUMMARY.md`) are stale dumps. The framework's artifacts must be regeneratable from a single command and timestamped.

7. **Multi-survey, not ABS-only.** The discovery flagged that ABS uses `harmonize_validated/` while every other survey uses `harmonize/`. Every layer must accept a `--survey` parameter and walk both directory conventions.

---

## Cross-cutting infrastructure (prerequisite)

Two pieces of shared infrastructure that every layer depends on:

### CC1. Spec discovery utility

A single function that, given a survey name, returns the canonical spec directory and file list. ABS resolves to `harmonize_validated/`, all others to `harmonize/`. Excludes `MODEL_VARIABLE.yml`, `TEMPLATE.yml`, `README*`. This already half-exists as `list_survey_specs()` (`src/r/data_prep_modules/2_harmonize_all.R:237-242`); promote it to a public utility used by every audit layer. Single responsibility, no surprises.

### CC2. Recoding-function registry

`src/r/utils/recoding.R` contains ~91 functions referenced by name in `fn:` fields. The engine validates referenced functions exist (`check_recoding_functions`, `harmonize.R:336-346`), but there is no machine-readable record of:

- What scale each function consumes (3pt, 4pt, 5pt, 6pt, 0–10).
- What scale it produces.
- Whether it reverses direction (yes / no / conditional).
- Whether it is monotonic.
- Whether it requires `data` (e.g. country-conditional functions like `reverse_trust_vietnam_w2`).

A registry — a YAML or CSV next to `recoding.R`, hand-curated initially but kept in sync via Layer 1 — turns these properties into auditable claims. Multiple layers (1, 3, 4) consume it.

Cost: one-time hand-curation of ~91 rows. Maintenance: every new function adds a row, enforced by Layer 1.

---

## Layer 1 — Configuration integrity

**Goal.** Every YAML conforms to a versioned schema. Required fields are present. Wave-rule blocks resolve unambiguously. No silent acceptance of typos or unknown keys.

### What this layer does

1. **Replace the imperative `validate_harmonize_spec()` with a JSON Schema.**
   - One canonical schema file: `src/config/_schema/harmonize_v1.schema.json`.
   - `additionalProperties: false` at every level — typos in `harmnoize:` or `vaild_range:` fail loud.
   - Versioned: every spec gets a top-level `schema_version: 1` field. Engine refuses to harmonize specs without it.
   - Validation runs in both R (jsonvalidate or yaml::read_yaml + tinytest assertions) and as a CI step.

2. **Enumerate every controlled vocabulary.**
   - `type:` ∈ {ordinal, nominal, continuous} (already a soft check; promote to enum).
   - `harmonize.<rule>.method:` ∈ {identity, r_function, recode, derive, null}. Engine already errors on unknown methods, but the schema must too.
   - `harmonize.<rule>.fn:` constrained to entries in the recoding-function registry (CC2).
   - `qc.expected_direction:` ∈ {positive, negative, none} — currently free text, never asserted.
   - `missing.use_convention:` constrained to keys in this spec's `missing_conventions:` block (cross-reference check).

3. **Cross-wave consistency check.** Same `id` declared in two specs is an error. Same source variable in different waves with the same `id` should agree on `type`, `valid_range` (unless `valid_range_by_wave` overrides), and `expected_direction`.

4. **Orphan / leak detection.**
   - Spec references a wave the survey doesn't have → error.
   - Spec references a `fn:` not in the registry → error.
   - Spec references a `missing.use_convention:` not declared → error.
   - Raw data has a variable matching `<id>` of a spec but the spec has `null` for that wave → warning (potential silent drop). Already partially implemented as the pre-flight in `harmonize.R:118-143`; promote to structured output.

5. **Required-field enforcement, hardened.**
   - `qc.valid_range` (or `qc.valid_range_by_wave`) is **required** for non-nominal, non-skipped variables. Currently optional with a soft warning (`harmonize.R:282-288`).
   - `qc.validate.phrase` is **required** for every `r_function` rule that names a `safe_reverse_*` function. Forces the YAML author to commit to a label-text expectation, which Layer 2 then verifies.

### Inputs / outputs

| In | Out |
|---|---|
| `src/config/<survey>/harmonize{,_validated}/*.yml` | `audit/reports/<survey>/01-config-integrity.json` (status per spec, per error) |
| Recoding-function registry (CC2) | Process exit code (0 = pass, non-zero = block) |
| `src/config/_schema/harmonize_v1.schema.json` | |

### Pass / fail

- **Block:** any schema violation, any unknown key, any unresolved cross-reference.
- **Warning (proceed but record):** orphan raw variables that look like they should be mapped.

### Hooks into existing code

- Replaces `validate_harmonize_spec()` (`src/r/harmonize/validate_spec.R:28-132`).
- Subsumes `check_recoding_functions()` (`src/r/harmonize/validate_spec.R:383-420`).
- Runs at the top of `harmonize_all()` (`src/r/harmonize/harmonize.R:334-370`) — engine refuses to harmonize an invalid spec.
- Runs as a standalone CLI: `Rscript src/r/audit/01_check_config.R --survey abs`.

### What this layer does NOT do

It does not verify that `q99` in W2 is actually about government satisfaction (Layer 2). It does not verify the harmonization output is sane (Layer 3). It only verifies that the YAML claims a coherent contract.

---

## Layer 2 — Codebook reconciliation

**Goal.** Every YAML claim — value labels, valid range, missing codes, question text — is mechanically verifiable against the source codebook. Variables that cannot be reconciled are flagged, not silently passed.

### What this layer does

This is the layer with the steepest implementation cost, because no machine-readable codebook exists for any survey in this repo. The framework must construct one.

1. **Define a canonical extracted-codebook schema.** One CSV or parquet per wave per survey, at `data/<survey>/codebook/<wave>.parquet`, with columns:

   ```
   wave, raw_var, question_text, response_label, response_code, missing_code_flag, source_doc, source_page
   ```

   Each row = one (variable, response code) pair. Question text duplicates per code; the verbatim CSV stores it once per item. Trade-off accepted: parquet is cheap, joins are easier, downstream Layer 4 anchor diagnostics need it in this shape.

2. **Build the extracted codebook.** Three viable sources, in priority order:
   - **SPSS / Stata variable metadata.** `haven::read_sav()` returns labels and value labels as attributes. For most ABS waves these are populated and trustworthy. Extract via R script. **This is the cheapest source and should be done first.**
   - **Verbatim CSVs.** `data/<survey>/questionnaire_text/*.csv` already contains question and response text per (wave, variable). Hand-curated; trust level high but coverage incomplete. Use as fallback when SPSS metadata is empty.
   - **PDF / DOCX / HWP questionnaires.** Last resort; LLM-assisted extraction with manual review. Coverage can be deferred.

   The extraction script is hand-written per survey because raw formats differ. The schema is unified.

3. **Diff the YAML against the extracted codebook.** Per (variable, wave):

   - **Question-text claim.** YAML's `qc.validate.phrase` is a regex; check the extracted question_text matches.
   - **Value-label claim.** YAML's `scale.labels` (the optional `{1: "Very dissatisfied", ...}` map) must match the extracted response_labels. Direction encoded in label order is the most important signal.
   - **Valid-range claim.** YAML's `qc.valid_range` must equal `[min(non_missing_codes), max(non_missing_codes)]` from the extracted codebook.
   - **Missing-code claim.** YAML's `missing.codes` ∪ `missing_conventions[<convention>].codes` must include every code flagged as missing in the extracted codebook for that variable.

4. **Surface unreconcilable variables.** If extraction failed for a (variable, wave), or the extracted codebook is silent, the diff returns `unreconciled` rather than `pass` or `fail`. **This is the worst case and must be flagged loudly.** A variable that nobody can reconcile is a variable nobody should harmonize.

5. **Per-survey extraction-coverage report.** What fraction of YAML claims have a backing codebook entry? Coverage starts low (probably <50% for surveys without good SPSS metadata) and ratchets up over time as extraction is filled in.

### Inputs / outputs

| In | Out |
|---|---|
| YAML specs (Layer 1 must pass) | `audit/reports/<survey>/02-codebook-recon.csv` (per variable × wave: status, observed vs claimed) |
| Extracted codebooks at `data/<survey>/codebook/` | `audit/reports/<survey>/02-coverage.json` (extraction coverage stats) |
| Verbatim CSVs as fallback | |

### Pass / fail

- **Block:** any explicit mismatch (claimed labels disagree with extracted labels; claimed valid_range disagrees with extracted codes).
- **Warning:** unreconciled (extraction not yet complete for this variable). Lists specific variables that need attention.

### Hooks into existing code

- Subsumes and extends `validate_phrases()` (`src/r/harmonize/validate_spec.R:149-304`).
- Adds a new directory `data/<survey>/codebook/` (per-survey extracted parquet/CSVs).
- Standalone CLI: `Rscript src/r/audit/02_check_codebook.R --survey abs`.

### Survey-specific gotchas covered

- **ABS missing-code wave variation** (7/8/9 vs 77/88/99 vs 7777/8888/9999): the extracted codebook records what is actually used per wave; the YAML's `missing_conventions` block is checked per wave.
- **Translation-induced category drift**: out of scope for v1 of this layer (English-only checks). Document it as a known unverified-dimension; revisit as a stretch goal.

---

## Layer 3 — Output invariants

**Goal.** Post-harmonization, every variable obeys its declared bounds, missingness is accounted for, no values were silently dropped, no levels were silently collapsed.

### What this layer does

This layer is the cheapest to implement because most of it already exists in `src/r/utils/validation.R` — it just isn't run on every harmonization. Promote to a mandatory post-step.

1. **Range invariant.** Every harmonized value ∈ `qc.valid_range` (or `qc.valid_range_by_wave`). The engine already coerces violators to NA at `harmonize.R:289-311`; the audit must report the count and the OOR log. **Pass requires zero violations OR an explicit `qc.allow_oob: true` flag with justification.**

2. **Coverage invariant.** Compare raw `n_valid` (after applying declared missing codes) to harmonized `n_valid`. Existing implementation: `validate_coverage()` (`src/r/utils/validation.R:126-171`). Threshold: ≤ 0.1% loss = ok; > 1% = error. Already coded; just needs to run.

3. **Crosstab invariant.** Each raw value maps to exactly one harmonized value (or NA). Already implemented as `validate_crosstab()` (`src/r/utils/validation.R:419-503`). Catches the case where a recoding function silently collapses two raw codes into one output, which can happen in scale conversion.

4. **Type stability.** A variable declared `type: ordinal` in the YAML is integer-valued in the output (or NA). Declared `continuous` is numeric. Declared `nominal` is integer or character but never silently double. Currently unchecked.

5. **Level preservation.** A variable declared `scale.min: 1, scale.max: 4` should have observed unique values that are a subset of {1, 2, 3, 4}. If the observed set is {1, 3, 4}, that may be legitimate sparseness — flag, don't block. If the observed set is {1, 2, 3, 4, 5}, that is a bug — block.

6. **Distribution-sanity smoke check.** Per (variable, wave), `mean()`, `sd()`, marginal histogram. Compare to the same statistics computed from raw → reverse-direction → re-NA, applying the engine's expected transformations. Spearman ρ ≈ ±1 (depending on direction). Already in `validate_transformation()` (`src/r/utils/validation.R:185-268`). **The threshold of 0.99 is appropriate for monotonic transforms; for `recode` and `derive` methods, this check is skipped (see `.vvw_skip_transform_fns` in `validation.R:604-610`).**

### Inputs / outputs

| In | Out |
|---|---|
| YAML specs | `audit/reports/<survey>/03-invariants.csv` (per variable × wave: each invariant pass/fail, observed value, threshold) |
| Harmonized output (`outputs/master_*.rds`, `data/processed/<survey>_harmonized.rds`) | `audit/reports/<survey>/03-oob.csv` (out-of-range log, persisted via existing `oob_log_path`) |
| Raw waves (`data/processed/<wave>.rds` for ABS; per-survey for others) | |

### Pass / fail

- **Block:** any range violation without `allow_oob`, any coverage > 1% loss, any crosstab one-to-many mapping.
- **Warning:** coverage 0.1–1% loss, level-set sparseness, sd shifts > 2× from raw.

### Hooks into existing code

- Extends `2.5_validate_harmonization.R` (already implements coverage/transformation/crosstab/range). Required changes: wire `oob_log_path` always-on; promote `run_validation()` from on-demand to mandatory post-step; emit structured CSV/JSON instead of markdown only.
- Standalone CLI: `Rscript src/r/audit/03_check_invariants.R --survey abs`.

### Survey-specific gotchas covered

- **Numeric vs ordinal treatment**: type-stability check (item 4) catches `type: ordinal` variables silently coerced to numeric mean.
- **Skip-pattern / filter questions**: covered by coverage check IF the YAML's `missing.codes` includes the structural-missing code. If the YAML doesn't declare it, this layer can't catch it — Layer 2 (codebook reconciliation) must.

---

## Layer 4 — Reverse-coding diagnostics (the silent killer)

**Goal.** Independent verification that every reversed variable was reversed correctly, every non-reversed variable was correctly left alone, and any cross-wave direction flip is either declared in the YAML or flagged for human review.

This is the most consequential layer. It is also the one with the most novel work — the existing repo has nothing equivalent.

### What this layer does

1. **Define construct-anchor pairs in YAML.** One file per construct, at `src/config/_anchors/<construct>.yml`. Each construct (e.g. democratic_attitudes, institutional_trust, economic_evaluations) names:

   - The anchor variable: a single item with stable, well-known direction across all waves and surveys (e.g. for democratic-attitudes battery, `dem_sat_national` after harmonization → high = satisfied).
   - The variables expected to load on it: a list of `id`s drawn from one or more YAMLs.
   - For each expected loader: expected sign of correlation with anchor (+, −, or "either" for ambivalent items).
   - Justification text: 1–2 sentences citing the substantive literature reason for the expected sign.

   This is hand-curation work; for ~600 variables across ~30 constructs, it's roughly 30 anchor files to write, each ~20–40 lines. Real cost. But irreplaceable.

2. **Cross-wave anchor-correlation diagnostic.** For every (variable, wave) where both the variable and its construct's anchor are present:

   - Compute Pearson(harmonized_var, harmonized_anchor) within country, within wave.
   - Aggregate to one signed correlation per (variable, wave, country). Pool to (variable, wave) by mean of country-level correlations weighted by `n` per country.
   - Compare observed sign to YAML-declared `qc.expected_direction` and the anchor file's expected loading.
   - **Flag conditions:**
     - Sign opposite to expected: error.
     - |correlation| < 0.05: warning (anchor may not load).
     - Sign flips between consecutive waves: error unless an explicit `qc.wave_direction_flip: [w3]` declaration exists. Forces the YAML author to either fix the bug or document the wave-specific direction change.

3. **Reverse-coded vs not-reversed sanity.** Independent of anchor: for every variable using `safe_reverse_*pt`, compute correlation between raw (after missing-code masking) and harmonized, **per wave, per country**. Expected: -1.0 within rounding (because the function is `n+1-x`). Observed correlation ≠ -1.0 means the recoding function did not run cleanly (e.g. the raw variable had unexpected codes that survived to produce a non-reversed mapping).

4. **Bidirectional verification: undeclared reversal.** For variables where the YAML uses `method: identity`, compute the same anchor correlation. If it has the *opposite* sign of the construct's expected loading, the YAML probably forgot a reverse and the variable is silently misdirected. Flag.

5. **Per-country sanity.** ABS wave 2 famously has Vietnam-specific scale flips (`reverse_trust_vietnam_w2`, `recoding.R:66-104`). The anchor diagnostic must compute correlations *within country, within wave* and surface countries whose loading sign disagrees with the rest. Already in the validation infrastructure as `validate_transformation_grouped()` (`validation.R:349-407`); needs to be wired into the reverse-coding check.

### Inputs / outputs

| In | Out |
|---|---|
| YAML specs (Layer 1 + 2 must pass) | `audit/reports/<survey>/04-anchors.csv` (variable × wave × country: observed correlation, expected sign, status) |
| `src/config/_anchors/*.yml` (construct anchors) | `audit/reports/<survey>/04-undeclared-reversals.csv` (suspect variables) |
| Harmonized output | `audit/reports/<survey>/04-summary.md` (human-readable: list of every flagged item) |
| Raw waves | |

### Pass / fail

- **Block:** sign opposite to expected; sign flip between waves without `qc.wave_direction_flip`; raw↔harmonized correlation ≠ -1.0 for reverse functions.
- **Warning:** |r| < 0.05 (anchor weak); per-country sign disagreement (suspicious but sometimes legitimate, e.g. Vietnam).
- **Unreconciled:** variable not declared in any anchor file. Layer 4 cannot judge it. Tracked as a coverage-of-anchoring metric.

### Hooks into existing code

- New module `src/r/audit/04_anchor_diagnostic.R`.
- Reuses `validate_transformation_grouped()` for per-country handling.
- Reuses `verify_reversal()` (`src/r/utils/validation.R:52-67`) for the raw↔harmonized -1.0 check; rename to `verify_reversal_strict()` to avoid name confusion with the new Layer 4 anchor-based check.

### Survey-specific gotchas covered

- **Likert direction inconsistencies across waves**: anchor-correlation sign-flip check.
- **ABS occasional response-option flips**: per-wave anchor correlation surfaces these.
- **Country-specific value codes (Vietnam, etc.)**: per-country grouped correlation.

### What this layer does NOT do

- It cannot detect a wave where the *anchor itself* changed direction. The anchor file declares the anchor variable's direction once, globally. If the anchor's wave-specific flip is real (e.g., the anchor question was rephrased in W4), the audit will incorrectly flag every loader. Mitigation: anchor files must specify the anchor's direction *per wave* if necessary, and the framework must support per-wave anchor declarations.
- It cannot validate a construct that has only one indicator. Single-item constructs (rare in attitude scales, common in demographics) pass through Layer 4 as `unreconciled`. Layer 2 + Layer 3 are the safety net for those.

---

## Layer 5 — Cross-wave continuity

**Goal.** Surface every (country × variable) where marginal-distribution drift between consecutive waves is large enough to warrant explanation. Distinguish (a) real political change from (b) question-wording / coding break.

### What this layer does

1. **Per-(country, variable, wave-pair) drift statistic.** For every consecutive wave pair, compute total variation distance (TVD) for ordinal variables and Kolmogorov–Smirnov D for continuous. TVD = ½ Σ |p_w(k) − p_{w+1}(k)| over response categories.

2. **Threshold table** (calibration TBD per construct in Phase 3, starting values):
   - Ordinal: TVD > 0.20 = flag; > 0.30 = block-on-merge.
   - Continuous: KS D > 0.20 = flag; > 0.35 = block.

3. **Wording-change registry.** A YAML file at `src/config/_wording_changes.yml` that explicitly records waves where a question was reworded such that drift is expected. Each entry:

   ```yaml
   - id: gov_sat_national
     wave_pair: [w2, w3]
     reason: "W2 used 'satisfied with the central government'; W3 used 'satisfied with how the government works'."
     source: "ABS Wave 3 codebook p.45"
     suppress_until: 0.40   # TVD threshold above which to re-flag despite registry entry
   ```

   Drift below `suppress_until` is muted; above it, fires anyway (the wording change wasn't supposed to invert the entire distribution).

4. **Real-change vs break heuristic.** A flagged drift in *one* country is more likely a wording change (because changes apply universally); flagged drift in only some countries is more likely real (because politics differs). Report this signature alongside the drift statistic. The framework does not auto-classify — the report flags both directions.

### Inputs / outputs

| In | Out |
|---|---|
| Harmonized output | `audit/reports/<survey>/05-drift.csv` (variable × country × wave-pair: TVD/KS, threshold breach, registry match) |
| `src/config/_wording_changes.yml` | `audit/reports/<survey>/05-summary.md` |

### Pass / fail

- **Block:** drift exceeds `block` threshold AND no wording-registry entry covers it.
- **Warning:** drift exceeds flag threshold OR registry entry exists with `suppress_until` lower than observed drift.

### Hooks into existing code

- New module `src/r/audit/05_drift_check.R`.
- Reuses harmonized output from Layer 3.
- No engine-side changes needed.

### Survey-specific gotchas covered

- **Question-wording changes across waves sharing a variable name.** This is the layer that catches them.
- **Real political change.** Also flagged here, but as informational rather than blocking, with the country-pattern signature attached for the analyst's judgment.

---

## Layer 6 — Provenance and determinism

**Goal.** Every harmonized output records exactly which raw inputs, which engine version, and which spec set produced it. Re-running on identical inputs produces byte-identical outputs.

### What this layer does

1. **Input manifest.** Per harmonization run, write a manifest at `outputs/<survey>/manifest.json`:

   ```json
   {
     "run_id": "ULID",
     "timestamp_utc": "2026-05-09T13:42:11Z",
     "git_commit": "4b31f17",
     "git_dirty": false,
     "schema_version": 1,
     "inputs": [
       {"path": "data/processed/w1.rds", "sha256": "...", "n_rows": 12345},
       ...
     ],
     "specs": [
       {"path": "src/config/abs/harmonize_validated/democracy_satisfaction.yml",
        "sha256": "...", "n_variables": 2},
       ...
     ],
     "outputs": [
       {"path": "outputs/master_w1.rds", "sha256": "...", "n_rows": 12345, "n_cols": 178},
       ...
     ],
     "engine_versions": {"harmonize.R": "...", "recoding.R": "...", "validate_spec.R": "..."}
   }
   ```

   File hashes via `digest::digest(file=...)`. Engine-file hashes via the same. Spec hashes are over the parsed YAML (canonicalized) so whitespace doesn't break determinism.

2. **Per-variable provenance, embedded in the harmonized RDS.** Attach an attribute on each harmonized column:

   ```r
   attr(harmonized_var, "provenance") <- list(
     source_file = "data/abs/raw/wave2/Wave2_20250609.sav",
     source_var = "q99",
     transform = "safe_reverse_4pt",
     spec_path = "src/config/abs/harmonize_validated/democracy_satisfaction.yml",
     spec_sha = "...",
     run_id = "..."
   )
   ```

   Cost: tiny. Benefit: a downstream paper can `attributes(d$gov_sat_national)$provenance` and embed it in the methods section.

3. **Determinism check.** Run harmonization twice in CI; assert byte-identical outputs (sha256 of every output file matches). Already deterministic by construction (no `Sys.time`, `runif`, random ordering — verified in §1.1 of discovery), but assert it.

4. **Raw-input-change detection.** If a `.sav` file is modified or replaced (different sha256 than the manifest's last record), the next harmonization run flags this prominently. ABS releases sometimes drop new versions of an old wave; the framework must surface the change for human review rather than silently consume it.

### Inputs / outputs

| In | Out |
|---|---|
| Raw `.sav`/`.dta` files | `outputs/<survey>/manifest.json` (per run) |
| Processed wave RDS | RDS attribute `provenance` on every harmonized column |
| Spec YAMLs | `audit/reports/<survey>/06-determinism.json` (CI's reproducibility check) |
| Engine R files | |

### Pass / fail

- **Block:** non-deterministic output (two runs differ). Block on merges that touch engine code.
- **Warning:** raw input hash changed since previous run (does not block; alerts).

### Hooks into existing code

- Modify `harmonize_all()` (`harmonize.R:334-370`) to attach provenance attributes during assembly.
- Modify `99_create_final_dataset.R` (per-survey) to write the manifest.
- New CLI: `Rscript src/r/audit/06_check_provenance.R --survey abs`.

### Survey-specific gotchas covered

- **`create_wave_rds.R` data-corruption hazard.** Provenance recording the `.sav` source per wave RDS would make Cambodia-only-vs-all-12-countries instantly visible (raw input file path differs).

---

## Layer 7 — CI gating

**Goal.** Every PR touching a YAML, a recoding function, the engine, or the spec schema triggers the relevant audit layers. Merges block on hard-failure layers; soft-failure layers require human acknowledgment. Releases carry an audit-passed certificate.

### What this layer does

1. **GitHub Actions workflow `.github/workflows/audit.yml`** triggered on PR open/sync.
   - Path-filtered: changes under `src/config/<survey>/` trigger Layers 1, 2, 3 for that survey only. Changes under `src/r/harmonize/`, `src/r/utils/recoding.R`, or `src/r/utils/validation.R` trigger all surveys.
   - Not currently in repo. Discovery flagged that the only existing workflows are Claude-Code review actions, which do not gate on audit.
   - Restores R from `renv.lock` (must add `testthat`, `digest`, `jsonvalidate`, `arrow`).
   - Caches the renv library to keep CI under 5 min.

2. **Layer-by-layer gating policy:**

   | Layer | Severity | Behavior on failure |
   |---|---|---|
   | 1 (config integrity) | Hard | Block merge. No exceptions. |
   | 2 (codebook reconciliation) | Mixed | Block on explicit mismatches; warn on `unreconciled`. Coverage stat reported on every PR. |
   | 3 (output invariants) | Hard | Block merge unless `qc.allow_oob: true` is set with justification. |
   | 4 (reverse-coding diagnostic) | Hard | Block merge on sign-opposite-expected, or on unexplained cross-wave sign flips. Warn on `unreconciled` (anchor missing). |
   | 5 (cross-wave continuity) | Soft | Warn only. Drift is judgment-dependent. PR description must acknowledge any flagged drift. |
   | 6 (provenance) | Hard | Block on non-deterministic output. Warn on raw-input change. |
   | 7 (this layer's own self-checks) | n/a | Workflow validity. |

3. **Audit-pass certificate.** On a tagged release (`abs-2026.05`, `kgss-2026.05`, etc.):
   - All seven layers must report green.
   - Manifest from Layer 6 is uploaded as a release artifact.
   - A Markdown certificate at `audit/certificates/<survey>-<release>.md` is checked in, citing the release tag, the engine commit, the spec commit, and the manifest hash.
   - Papers' methods sections cite this certificate (`harmonized data, audit certificate abs-2026.05; available at <URL>`).

4. **Local pre-PR command.** `make audit` (or `Rscript src/r/audit/run_all.R`) runs all seven layers locally before pushing. Mirrors what CI runs. Important because R/CI start-up is slow; researchers will not iterate on CI output.

### Inputs / outputs

| In | Out |
|---|---|
| All Layer 1–6 reports | CI status (pass / fail per layer) |
| Release tag | Audit certificate, attached as a release artifact |

### Hooks into existing code

- New workflow `.github/workflows/audit.yml`.
- Replaces (or supplements) the existing `claude-code-review.yml` — these are orthogonal concerns; both can coexist.
- New CLI `src/r/audit/run_all.R` (orchestrator).

---

## Survey-specific gotchas — explicit coverage check

The brief enumerates seven traps that cross-survey work routinely walks into. Mapping each to the layer that catches it:

| Gotcha | Layer | Concrete check |
|---|---|---|
| **ABS missing-code patterns vary across waves** (7/8/9 vs 77/88/99 vs 7777/8888/9999) | 1 + 2 | Layer 1 enforces `missing_conventions` is declared per spec; Layer 2 verifies declared codes match the codebook per wave. |
| **Country-specific value codes** (e.g. party ID) | 2 + 4 | Layer 2 reconciles per-country labels where the codebook is per-country; Layer 4's per-country anchor correlation surfaces single-country direction anomalies. |
| **Question-wording changes across waves sharing a variable name** | 5 | Layer 5 drift check + wording registry. |
| **Skip-pattern / filter questions** (structural missingness) | 1 + 2 + 3 | Layer 1 enforces declaration via `missing.use_convention: structural`; Layer 2 reconciles vs codebook; Layer 3's coverage check distinguishes "missing because filtered" from "missing because lost". |
| **Likert direction inconsistencies across waves** | 4 | Layer 4 anchor-correlation cross-wave sign-flip detector. **The single most important check in this whole framework.** |
| **Translation-induced category drift** | 2 (partial) | English-only checks in v1. Document as known unverified. Stretch goal: bilingual extracted codebooks. |
| **Numeric vs ordinal treatment** (4-pt collapsed to mean) | 3 | Layer 3 type-stability invariant. |

---

## Ordering rationale

Phase 3 must order tickets so each layer's prerequisites are in place before that layer's work begins. The brief's suggested order is correct; this framework refines:

1. **Foundation (Layers 1, 6).** Schema enforcement and provenance are prerequisites for everything else. Without Layer 1 you cannot trust the YAML; without Layer 6 you cannot reproduce an audit. Both are mostly mechanical.

2. **Highest-risk silent failure (Layer 4).** The reverse-coding diagnostic is the single most valuable check in this audit. It depends on Layer 1 (schema must be clean to know what's reverse-coded) and partially on Layer 6 (provenance helps trace which raw input). Anchor-file curation is the slow part; build the framework, scaffold one construct (democratic_attitudes), prove the diagnostic on it, then expand.

3. **Output invariants (Layer 3).** Cheap, broad coverage. Most code already exists in `validation.R` — just needs to be wired in mandatory mode.

4. **Codebook reconciliation (Layer 2).** Expensive. Per-survey extraction is the slow part. Start with ABS (where SPSS metadata is best), then KGSS, then the rest. Coverage ratchets up over time.

5. **Cross-wave continuity (Layer 5).** Requires domain judgment to calibrate thresholds and seed the wording registry. Build the mechanics; tune thresholds against ABS; expand surveys.

6. **CI integration (Layer 7).** Last. Needs all earlier layers to have stable artifacts before gating on them.

---

## Out of scope (for this audit engagement)

- **Translation auditing.** Identifying whether "Strongly agree" in English maps to a different intensity anchor than its Korean / Arabic / Spanish equivalent requires bilingual codebooks and substantive cross-cultural-measurement expertise. Document as a known unverified dimension; do not attempt in this engagement.
- **Downstream paper code.** `papers/`, `results/paper3_task*.R` are out of scope. The audit covers the harmonization pipeline, not analyses that consume it.
- **Non-survey datasets.** V-Dem and external covid-economic data are scaffolds in this repo. Their harmonization is too thin to audit.
- **Composite indices and derived constructs.** `src/r/utils/composites.R` builds indices on top of harmonized variables. Auditing those requires construct-validity analysis, not data-pipeline auditing. Out of scope.
- **Performance / memory tuning.** The harmonization runs in seconds per survey on a laptop. Not a concern.

---

## What changes if 제프 disagrees with priorities

The framework's seven layers are individually executable and the gating policy in Layer 7 is per-layer. If 제프 wants to defer (say) Layer 5 indefinitely, drop it from the CI policy and the framework still works. The two layers that are non-negotiable for the stakes the brief describes are:

- **Layer 1** (schema integrity) — without it, everything downstream is unsound.
- **Layer 4** (reverse-coding diagnostic) — without it, the silent killer remains silent.

Layer 6 (provenance) is the third I would lobby for, because without it no paper citation can be reproduced — but if the project lives in 제프's head and the dataset is essentially personal, provenance can be deferred without immediate cost. (It will hurt the first time a co-author or replicator asks "which version?")

The other four layers (2, 3, 5, 7) are necessary for full coverage but each can be developed incrementally.

---

**Next deliverable.** `02-implementation-tickets.md` — decomposes the above into 1–3 hour CC sessions, with explicit file paths, acceptance criteria, and dependency ordering.
