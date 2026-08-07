# Phase 3 — Implementation Tickets

Decomposes the seven-layer framework in `01-audit-framework.md` into discrete CC sessions of ~1–3 hours each. Each ticket is sized so a fresh CC session, given only the ticket text plus the framework doc, can complete it without further design decisions from 제프.

**Ordering policy** (per brief):
1. Foundation: schema + provenance (Phases A–C)
2. Highest-risk silent failure: reverse-coding (Phase D)
3. Output invariants (Phase E)
4. Codebook reconciliation (Phase F)
5. Cross-wave continuity (Phase G)
6. CI integration (Phase H)

**Sequencing legend.** `→` = strict dependency; `‖` = can run in parallel.

**Effort legend.** S = ≤1 hr, M = 1–2 hr, L = 2–3 hr.

---

## Phase A — Cleanup & shared infrastructure

Quick wins, hazard cleanup, and the two cross-cutting utilities (CC1, CC2) that every later layer consumes.

### A1 — Fix the W6 builder collision (S)

**Goal.** Eliminate the live hazard that `src/scripts/create_wave_rds.R` will silently overwrite the multi-country `data/processed/w6.rds` with Cambodia-only data if rerun.

**Files touched.**
- `src/scripts/create_wave_rds.R` — modify W6 entry to either (a) delegate to `build_abs_w6.R`, or (b) refuse to write w6.rds if the existing file has > 5,000 rows (sanity guard).

**Acceptance.**
- Running `Rscript src/scripts/create_wave_rds.R` from a clean state with the multi-country w6.rds present does NOT shrink it to Cambodia-only.
- Running the same script with no w6.rds present produces a multi-country w6.rds (calls `build_abs_w6.R` internally).
- A short comment at the top of the script explains the W6 special case.

**Dependencies.** None. Run first.

---

### A2 — Add audit dependencies to `renv.lock` (S)

**Goal.** Install the R packages every later ticket needs.

**Files touched.**
- `renv.lock` (regenerated)
- `DESCRIPTION` if one exists (none currently — skip)

**Packages.** `testthat`, `digest`, `jsonvalidate`, `arrow` (for parquet codebook outputs), `tinytest` (lightweight alternative if `testthat` causes renv issues).

**Acceptance.**
- `Rscript -e 'library(testthat); library(digest); library(jsonvalidate); library(arrow)'` runs without error.
- Existing tests in `src/r/harmonize/test_harmonize.R` execute (even if some fail — this ticket does not fix the tests, only enables them to run).

**Dependencies.** None.

---

### A3 — Promote spec-discovery utility (CC1) (M)

**Goal.** One canonical function that, given a survey name, returns the spec directory and the list of production YAML paths. Handles the ABS-special-case (`harmonize_validated/` instead of `harmonize/`).

**Files touched.**
- New: `src/r/utils/spec_discovery.R` exposing `find_survey_spec_dir(survey)` and `list_survey_specs(survey)`.
- Modify: `src/r/data_prep_modules/2_harmonize_all.R` to source the new file instead of defining `list_survey_specs()` inline (lines 237–242).
- Modify: `src/r/harmonize/validate_spec.R` `validate_all_specs()` to use the same utility (currently hardcodes `src/config/abs/harmonize_validated`, line 319).

**Acceptance.**
- `find_survey_spec_dir("abs")` → `"src/config/abs/harmonize_validated"`.
- `find_survey_spec_dir("kgss")` → `"src/config/kgss/harmonize"`.
- `find_survey_spec_dir("ipus")` → `"src/config/ipus/harmonize"`.
- `find_survey_spec_dir("nonexistent")` → informative error.
- `list_survey_specs("abs")` returns 28 files, excludes `MODEL_VARIABLE.yml`, returns absolute paths.
- All existing entry points (`2_harmonize_all.R`, `validate_all_specs()`) still work.

**Dependencies.** None.

---

### A4 — Build the recoding-function registry (CC2) (L)

**Goal.** Hand-curated YAML cataloguing every function in `src/r/utils/recoding.R` (~91 functions) with properties that later layers need: input scale, output scale, whether it reverses, whether it requires `data`, whether it is monotonic.

**Files touched.**
- New: `src/r/utils/recoding_registry.yml` — one entry per function:

  ```yaml
  - fn: safe_reverse_4pt
    input_scale: [1, 4]
    output_scale: [1, 4]
    reverses: true
    monotonic: true
    requires_data: false
    notes: "Generic 4-point reversal; (n+1)-x"
  ```

- Modify: `src/r/harmonize/validate_spec.R` `check_recoding_functions()` to also verify the registry contains every function referenced — and that every registry entry resolves to a loaded function (catches drift in both directions).

**Acceptance.**
- Registry has one entry per function defined in `recoding.R`. Verify by counting: registry entries == number of `^(safe_|recode_|collapse_|no_verify|reverse_|harmonize_|extract_|middle_)` definitions in `recoding.R` (~91, expected).
- `Rscript src/r/audit/check_registry_complete.R` (a new short helper) prints "OK" or lists drift.
- The `reverses` flag is correctly set for every function whose name contains "reverse" or whose body uses `(n+1) - x`. Manual review by 제프 on the curated values.

**Dependencies.** A2.

**Note.** This is the slowest ticket in Phase A because it requires reading every function and recording its semantics. Estimate honestly — if 91 functions × 90 sec each = 2.5 hours. Could be split into A4a (auto-generate skeleton entries from function names) and A4b (manual review and fill).

---

## Phase B — Layer 1: Configuration integrity

Replaces `validate_harmonize_spec()` with a JSON Schema. Authors hard requirements that the engine enforces.

### B1 — Author the JSON Schema v1 (L)

**Goal.** A single JSON Schema describing the shape every harmonization YAML must conform to.

**Files touched.**
- New: `src/config/_schema/harmonize_v1.schema.json`.

**Schema must cover.**
- Top-level required keys: `schema_version` (literal `1`), `missing_conventions`, `variables`.
- `additionalProperties: false` at every level (catches typos like `harmnoize:`).
- `missing_conventions`: object whose values are either an array of integers OR an object with `codes:` (array) and optional `description:`.
- `variables`: array, each item has required `id` (snake_case string), `concept`, `description`, `type` (enum: ordinal, nominal, continuous), `source` (object: wave-name → string-or-null), `harmonize` (object: requires `default`, optional `by_wave`/`exceptions`/wave-keys; each rule has `method` enum: identity / r_function / recode / derive / null).
- `qc`: optional object; if present, `valid_range` (length-2 numeric) OR `valid_range_by_wave` (object: wave → length-2 numeric); optional `expected_direction` (enum: positive / negative / none); optional `validate` (array of {waves, phrase}); optional skip-flags (`skip_range_check`, `skip_coverage_check`, etc.).

**Acceptance.**
- `jsonvalidate::json_validate(yaml_to_json(spec), schema)` returns TRUE for a known-good spec (`src/config/abs/harmonize_validated/democracy_satisfaction.yml` after adding `schema_version: 1`).
- Returns FALSE with informative error for a synthetic spec containing `harmnoize:` (typo).
- Returns FALSE for a spec missing `schema_version`.
- Returns FALSE for a spec where `harmonize.default.method: identty` (typo'd enum).

**Dependencies.** A2.

---

### B2 — Backfill `schema_version: 1` in every existing spec (M)

**Goal.** Add the mandatory version field to all ~117 production YAMLs.

**Files touched.**
- Every YAML under `src/config/<survey>/harmonize{,_validated}/` (excluding templates).

**Approach.** Write a one-off R script that iterates the spec list (using the utility from A3), reads the YAML, prepends `schema_version: 1\n` if not present, writes back. Preserve original formatting where possible.

**Acceptance.**
- Every production YAML has `schema_version: 1` as the top-level first key.
- `git diff --stat` shows ~117 files changed, each with +1 line.
- Engine still produces identical harmonized output (run determinism check from C4 once available; for now, spot-check ABS).

**Dependencies.** A3 (spec discovery), B1 (schema must accept `schema_version`).

---

### B3 — Replace `validate_harmonize_spec()` with schema-based validator (L)

**Goal.** Retire the imperative R validator. R becomes a thin caller of `jsonvalidate`.

**Files touched.**
- Modify: `src/r/harmonize/validate_spec.R` — replace `validate_harmonize_spec()` body with a `jsonvalidate::json_validate()` call against `harmonize_v1.schema.json`. Preserve the function's signature and error-message contract so callers don't break.
- Modify: `src/r/data_prep_modules/2_harmonize_all.R` `harmonize_spec()` (line 38) — same call site, no change needed.

**Acceptance.**
- All existing test cases in `src/r/harmonize/test_harmonize.R` for `validate_harmonize_spec` still pass after migration to the new validator.
- A typo'd YAML (e.g. `vaild_range:` instead of `valid_range:`) is rejected.
- Error messages are at least as informative as the current ones (cite the offending path: `variables[2].qc.vaild_range: unknown property`).

**Dependencies.** A2, B1, B2.

---

### B4 — Cross-reference validators (M)

**Goal.** Schema cannot express cross-references (e.g. "this `use_convention:` value must be a key in `missing_conventions:`"). Add R-side post-schema checks.

**Files touched.**
- Modify: `src/r/harmonize/validate_spec.R` — add `validate_cross_references()` called immediately after `validate_harmonize_spec()`.

**Checks.**
- Every `missing.use_convention: <key>` resolves to a key in `missing_conventions:`.
- Every `harmonize.<rule>.fn: <name>` resolves to an entry in the recoding registry (CC2).
- No two specs in the same survey declare the same `id:`.
- For each `id:` declared in multiple specs (cross-survey), the `type:` and `expected_direction:` are consistent.

**Acceptance.**
- Synthetic spec with `use_convention: nonexistent` fails with "no such convention".
- Synthetic spec with `fn: safe_reverse_99pt` (not in registry) fails with "unknown function".
- Two specs in `src/config/abs/harmonize_validated/` declaring the same `id:` produces an error.

**Dependencies.** A4 (registry), B3.

---

### B5 — Make `valid_range` mandatory for non-skipped variables (L)

**Goal.** Eliminate the soft-warning fallback at `harmonize.R:282-288`. Engine errors out unless `qc.valid_range` (or `valid_range_by_wave`) is present, OR `qc.skip_range_check: true`, OR `type: nominal`.

**Files touched.**
- Modify: `src/r/harmonize/harmonize.R:282-288` — change `warning()` to `stop()`.
- Modify: `src/config/_schema/harmonize_v1.schema.json` — add a conditional that requires `valid_range` for non-nominal, non-skipped variables.
- Audit: every existing YAML; backfill missing `valid_range` entries. Use the recoding registry's output_scale to pre-fill suggestions.

**Acceptance.**
- Engine refuses to harmonize a spec with a missing `valid_range` (unless skipped).
- All existing production specs pass; gaps are filled in with literature-reasonable bounds.
- A list of every backfilled variable is included in the PR description.

**Dependencies.** A4, B3.

---

### B6 — Require `qc.validate.phrase` for `safe_reverse_*` rules (M)

**Goal.** Every reverse-coding rule must commit, in the YAML, to an expected substring in the source variable's question label. This forces the YAML author to declare what they think the question is — which Layer 2 then mechanically verifies.

**Files touched.**
- Modify: `src/config/_schema/harmonize_v1.schema.json` — conditional: if `harmonize.<rule>.fn` matches `safe_reverse_*`, then `qc.validate` must include the affected wave and a `phrase`.
- Audit: every existing YAML using `safe_reverse_*`; backfill.

**Acceptance.**
- Schema rejects a `safe_reverse_4pt` rule with no `qc.validate.phrase`.
- All existing production specs pass.
- Backfilled phrases are reviewed by 제프 for accuracy (not auto-generated from the source variable name).

**Dependencies.** B5.

---

## Phase C — Layer 6: Provenance and determinism

Manifest writing, per-variable provenance, determinism check, raw-input drift detection.

### C1 — Build the manifest writer (M)

**Goal.** Function that, given a list of input paths, spec paths, output paths, writes a `manifest.json` capturing sha256 of every artifact plus metadata.

**Files touched.**
- New: `src/r/utils/provenance.R` exposing `write_manifest(survey, inputs, specs, outputs, output_path)`.

**Manifest schema** (per `01-audit-framework.md` §Layer 6): `run_id`, `timestamp_utc`, `git_commit`, `git_dirty`, `schema_version`, `inputs[]`, `specs[]`, `outputs[]`, `engine_versions{}`.

**Acceptance.**
- Manifest written to `outputs/<survey>/manifest.json` on every run.
- Re-running with no changes produces a manifest where every `sha256` is identical to the previous run (timestamps and run_id excepted).
- `git_dirty: true` if `git status --porcelain` is non-empty.

**Dependencies.** A2 (digest package).

---

### C2 — Wire manifest writing into per-survey final-dataset scripts (M)

**Goal.** Every survey's `99_create_final_dataset.R` calls `write_manifest()` at the end.

**Files touched.**
- `src/r/data_prep_modules/99_create_final_dataset.R` (ABS).
- `src/r/data_prep_modules/<survey>/99_create_final_dataset.R` for each of: wvs, lbs, afro, arab-barometer, kamos, kgss, kipa_corruption, kinu, ipus.

**Acceptance.**
- Every per-survey pipeline run produces `outputs/<survey>/manifest.json`.
- Running the same pipeline twice without modifications produces manifests with identical input/spec/output hashes.

**Dependencies.** C1.

---

### C3 — Attach per-variable provenance attributes (M)

**Goal.** Each harmonized column carries an R `attr()` recording its source file, source variable name, transformation applied, and run_id.

**Files touched.**
- Modify: `src/r/harmonize/harmonize.R` `harmonize_variable()` — at the end of each wave's processing, attach `attr(x_harm, "provenance") <- list(...)`.
- Modify: `src/r/data_prep_modules/2_harmonize_all.R` `stack_harmonized_wide()` — preserve attributes on assembly.

**Acceptance.**
- `attributes(d$gov_sat_national)$provenance` returns a list with `source_file`, `source_var`, `transform`, `spec_path`, `run_id`.
- `attributes(d$gov_sat_national)$provenance$transform` is `"safe_reverse_4pt"` for W2–W6 and `"collapse_middle5_to_4pt"` for W1.

**Dependencies.** C1.

---

### C4 — Determinism check script (S)

**Goal.** A script that runs the full harmonization pipeline twice and asserts byte-identical outputs.

**Files touched.**
- New: `src/r/audit/06_check_determinism.R` — runs pipeline, captures sha256 of every output, runs again, diffs.

**Acceptance.**
- `Rscript src/r/audit/06_check_determinism.R --survey abs` exits 0 if outputs match across two runs, exits 1 with a list of differing files otherwise.
- Confirmed currently passing for ABS.

**Dependencies.** C1, C2.

---

### C5 — Raw-input drift detector (S)

**Goal.** Compare current raw-file hashes against the most recent manifest; alert if changed.

**Files touched.**
- New: `src/r/audit/06_check_input_drift.R`.

**Acceptance.**
- Run after a hypothetical replacement of `data/abs/raw/wave3/ABS3 merge20250609.sav` with a newer file → script reports the change and the prior hash.
- Run with no changes → script reports "no drift".

**Dependencies.** C1.

---

## Phase D — Layer 4: Reverse-coding diagnostics (the silent killer)

Anchor-construct files, cross-wave correlation engine, strict reverse check, undeclared-reversal scanner, per-country handling.

### D1 — Anchor-file schema and authoring guide (M)

**Goal.** Define the YAML format for `src/config/_anchors/<construct>.yml`. Document semantics in a README.

**Files touched.**
- New: `src/config/_anchors/_schema/anchor_v1.schema.json`.
- New: `src/config/_anchors/README.md` — explains how to author an anchor file, what an anchor is, and how the diagnostic uses it.

**Anchor file shape.**

```yaml
schema_version: 1
construct: democratic_attitudes
anchor:
  variable: dem_sat_national
  expected_direction: positive   # globally
  per_wave: {}                   # optional overrides if anchor's own direction is wave-specific
loaders:
  - id: gov_sat_national
    expected_sign: positive
    justification: "Government satisfaction is part of the democratic-performance evaluation cluster (Mishler & Rose 2001)."
  - id: dem_best_form
    expected_sign: positive
    justification: "Support for democracy as best system covaries with satisfaction with how it works."
  - id: a_strongleader
    expected_sign: negative
    justification: "Support for strong-leader rule should anti-correlate with satisfaction with democracy."
```

**Acceptance.**
- Schema validates an example anchor file.
- README is read by a research-naive CC session and produces a competent draft of a new construct anchor file (manually testable).

**Dependencies.** B1, B3 (so the anchor schema can be a sibling pattern).

---

### D2 — Pilot anchor: democratic_attitudes (L)

**Goal.** Hand-curate the first construct's anchor file. Use it to prove the Layer 4 diagnostic works before scaling out.

**Files touched.**
- New: `src/config/_anchors/democratic_attitudes.yml`.

**Scope.** Cover ~10–15 ABS variables that should covary with `dem_sat_national`: gov_sat_national, dem_best_form, dem_always_preferable, dem_vs_econ, a_strongleader, a_singleparty, a_armyrule, a_expertrule, etc.

**Acceptance.**
- Anchor file validates against the schema (D1).
- Each loader has a one-sentence justification citing literature or codebook.
- 제프 reviews the expected_sign assignments before merging.

**Dependencies.** D1.

---

### D3 — Cross-wave anchor-correlation engine (L)

**Goal.** Script that consumes harmonized output + an anchor file and produces a CSV of (variable × wave × country: observed_correlation, expected_sign, status).

**Files touched.**
- New: `src/r/audit/04_anchor_diagnostic.R`.
- Output: `audit/reports/<survey>/04-anchors.csv`.

**Acceptance.**
- Running on ABS + democratic_attitudes anchor produces a CSV with one row per (variable in anchor file × wave × country).
- For known-good variables (e.g. `dem_sat_national` on itself), correlation = 1.0.
- For known-reversed variables (e.g. `a_strongleader` after harmonization), correlation has the expected sign.
- Sign-disagreement cases are flagged with status `error` and listed in the run's stdout.

**Dependencies.** A3, C2 (so harmonized output exists with provenance), D2.

---

### D4 — Strict raw↔harmonized reverse check (M)

**Goal.** For every variable where `fn:` matches `safe_reverse_*pt`, assert the Pearson correlation between raw (after missing-code masking) and harmonized is -1.0 within rounding.

**Files touched.**
- New: `src/r/audit/04_strict_reversal.R` (or merge into D3 as a sub-check).
- Reuses: `verify_reversal()` (`src/r/utils/validation.R:52`); rename to `verify_reversal_strict()` to disambiguate.

**Acceptance.**
- Script reports a list of (variable, wave) pairs where the strict check failed.
- Currently expected to be empty; if not, that's a Phase 1 finding worth pursuing as a real bug.
- Catches the case where a raw variable had unexpected codes that survived missing-code masking and produced a non-cleanly-reversed mapping.

**Dependencies.** A4, C2.

---

### D5 — Undeclared-reversal scan (M)

**Goal.** For variables harmonized via `method: identity`, compute their anchor correlation. If it's the *opposite* of the expected sign, the YAML may have forgotten a reverse.

**Files touched.**
- Extend `src/r/audit/04_anchor_diagnostic.R` to include identity-method variables in its sweep.
- Output: `audit/reports/<survey>/04-undeclared-reversals.csv`.

**Acceptance.**
- For every identity-method variable in the anchor file, the script reports observed sign vs expected sign.
- Disagreement with |r| ≥ 0.10 is flagged as `suspect_undeclared_reversal`.
- 제프 reviews the suspect list — known false positives (e.g. genuinely orthogonal items) are added to a `qc.anchor_disagreement_ok: true` flag in their YAML, which the audit respects.

**Dependencies.** D3.

---

### D6 — Per-country sign-disagreement (M)

**Goal.** Within each wave, compute anchor correlation per country. Surface countries whose loading sign disagrees with the rest of the sample.

**Files touched.**
- Extend `src/r/audit/04_anchor_diagnostic.R`.
- Reuses: `validate_transformation_grouped()` (`src/r/utils/validation.R:349`).

**Acceptance.**
- For each (variable × wave), the script reports per-country correlation alongside the pooled correlation.
- Countries whose sign disagrees with the pooled-majority sign are flagged.
- Known cases (Vietnam in W2/W3 for trust variables — see `recoding.R:66-104`) are handled either by being explicitly excluded from the anchor diagnostic OR by an existing per-country recode that fixes the sign before the diagnostic runs. Verify the latter is true.

**Dependencies.** D3.

---

### D7 — Wave-flip declaration support (S)

**Goal.** Add a YAML field that lets a researcher declare "yes, the direction of this variable is intentionally different in W3 than W2 — don't flag it."

**Files touched.**
- Modify: `src/config/_schema/harmonize_v1.schema.json` — add optional `qc.wave_direction_flip: [<wave>, ...]`.
- Modify: `src/r/audit/04_anchor_diagnostic.R` — respect this flag in cross-wave sign-flip detection.

**Acceptance.**
- A spec with `qc.wave_direction_flip: [w3]` does not produce a sign-flip error between w2 and w3.
- Without the flag, the same variable does produce the error.

**Dependencies.** D3, B3.

---

### D8 — Anchor: institutional_trust (L)

**Goal.** Second construct anchor file. Covers `trust_*` variables in ABS, KAMOS, KGSS (`conf_*`), KINU, etc.

**Files touched.**
- New: `src/config/_anchors/institutional_trust.yml`.

**Acceptance.**
- File covers ≥ 10 trust variables across ≥ 3 surveys.
- Diagnostic (D3) runs cleanly against ABS first; cross-survey aggregation deferred to a later ticket.

**Dependencies.** D3.

---

### D9 — Anchor: economic_evaluations (M)

**Goal.** Third construct: `econ_*` variables across surveys.

**Files touched.**
- New: `src/config/_anchors/economic_evaluations.yml`.

**Dependencies.** D3.

---

### D10 — Anchor: authoritarianism (M)

**Goal.** Fourth construct: `a_strongleader`, `a_singleparty`, `a_armyrule`, `a_expertrule`, plus KGSS / WVS analogues.

**Files touched.**
- New: `src/config/_anchors/authoritarianism.yml`.

**Dependencies.** D3.

---

## Phase E — Layer 3: Output invariants

Mostly wiring existing validation code from `src/r/utils/validation.R` into the mandatory post-pipeline path.

### E1 — Always-on out-of-range logging (M)

**Goal.** Every per-survey `2_harmonize_all.R` passes a non-null `oob_log_path`. Out-of-range coercions land in a CSV by default.

**Files touched.**
- `src/r/data_prep_modules/2_harmonize_all.R` and the 9 per-survey copies under `src/r/data_prep_modules/<survey>/`.

**Acceptance.**
- After each per-survey run, `outputs/<survey>/oob_log.csv` exists (possibly empty if no OOR events).
- Reviewed against current state: `outputs/kipa_corruption_oob_log.csv` exists, others do not — only KIPA wired this in. Generalize.

**Dependencies.** A3.

---

### E2 — Promote `run_validation()` to mandatory post-step (L)

**Goal.** The validation pipeline at `src/r/data_prep_modules/2.5_validate_harmonization.R` runs automatically as part of every `99_create_final_dataset.R` invocation. Currently on-demand only.

**Files touched.**
- Each survey's `99_create_final_dataset.R` — append a call to `run_validation(save_report = TRUE)`.
- Modify `2.5_validate_harmonization.R` `load_harmonized_data()` (line 84) to be survey-parametric — currently hardcoded to ABS path.
- Modify the script to handle non-ABS wave-name conventions (`y2018`, `r5`, etc. — currently assumes `w<N>` with integer N at line 184).

**Acceptance.**
- Running the full ABS pipeline produces `outputs/abs/harmonization_validation_report.md` automatically.
- Same for KGSS, LBS, etc.
- The report flags any error or warning prominently.

**Dependencies.** A3, E1.

---

### E3 — Type-stability invariant (M)

**Goal.** A check that `type: ordinal` variables are integer-valued in the output (or NA).

**Files touched.**
- New: `src/r/audit/03_type_stability.R` (or extend `validation.R`).

**Acceptance.**
- For each variable, the harmonized column's storage matches its declared `type:`. Ordinal → integer; continuous → numeric (any); nominal → integer or character.
- Mismatches reported per (variable, survey).

**Dependencies.** E2.

---

### E4 — Level-preservation check (M)

**Goal.** For each variable with a declared `scale.min`/`scale.max`, the observed unique values in the harmonized output ⊆ {min..max}.

**Files touched.**
- Extend `src/r/audit/03_invariants.R`.

**Acceptance.**
- For ordinal variables with scale 1–4, no observed value outside {1, 2, 3, 4, NA}.
- For ordinal variables with sparse observed levels (e.g. only {1, 4} present), warn but don't block — flag for human review.
- Output: `audit/reports/<survey>/03-level-preservation.csv`.

**Dependencies.** E2.

---

### E5 — Structured CSV / JSON output for invariants (M)

**Goal.** Replace the markdown-only output of `generate_validation_report()` with parallel structured output that downstream tools (CI, Layer 7) can consume.

**Files touched.**
- Modify: `src/r/utils/validation.R` `generate_validation_report()` to also write `audit/reports/<survey>/03-invariants.csv` alongside the markdown.

**Acceptance.**
- After E2 runs, both `harmonization_validation_report.md` (human) and `03-invariants.csv` (machine) exist.
- CSV columns: `var_id`, `wave`, `check`, `status`, `value`, `threshold`, `message`.

**Dependencies.** E2.

---

## Phase F — Layer 2: Codebook reconciliation

Most expensive layer. Per-survey extraction is hand-built. Start with ABS, expand by demand.

### F1 — Define extracted-codebook schema (S)

**Goal.** A canonical parquet schema for `data/<survey>/codebook/<wave>.parquet` that all per-survey extractors target.

**Files touched.**
- New: `data/_codebook_schema/codebook_v1.md` documenting columns: `wave`, `raw_var`, `question_text`, `response_label`, `response_code`, `missing_code_flag`, `source_doc`, `source_page`.

**Acceptance.**
- Document is concise, includes a sample row.
- Reviewed by 제프 before any per-survey extractor is built.

**Dependencies.** A2 (arrow package).

---

### F2 — SPSS-metadata extractor for ABS (L)

**Goal.** Read each ABS `.sav` file's haven labels and emit `data/abs/codebook/w<N>.parquet`.

**Files touched.**
- New: `src/r/audit/02_extract_codebook_abs.R`.

**Acceptance.**
- Produces 6 parquet files (one per wave) with rows per (raw_var × response_code).
- Spot-check 10 random rows against the source `.sav` via `haven::read_sav()` — labels match.
- Coverage report: what fraction of variables in W2's `.sav` got their value labels extracted? Expected > 80%.

**Dependencies.** F1.

---

### F3 — Verbatim CSV → codebook fallback merger (M)

**Goal.** Where SPSS metadata is missing or empty, fall back to the hand-curated verbatim CSV at `data/<survey>/questionnaire_text/<survey>_verbatim_items.csv`.

**Files touched.**
- New: `src/r/audit/02_merge_verbatim.R` (per-survey).

**Acceptance.**
- After running, codebook coverage for ABS goes up — verify the delta.
- Any conflict between SPSS metadata and verbatim CSV (different labels for same code) is logged for manual review, not silently resolved.

**Dependencies.** F2.

---

### F4 — YAML vs codebook diff engine (L)

**Goal.** The actual reconciliation. For every (variable × wave), check that YAML claims (label, range, missing codes) match the extracted codebook.

**Files touched.**
- New: `src/r/audit/02_check_codebook.R`.
- Output: `audit/reports/<survey>/02-codebook-recon.csv` per `01-audit-framework.md` §Layer 2.

**Acceptance.**
- For ABS, a baseline run completes and produces a CSV with status per (variable × wave): `pass`, `fail`, or `unreconciled`.
- Sample failure case (intentionally edit one YAML's `valid_range: [1, 4]` to `[1, 5]`) is detected.

**Dependencies.** F2, F3.

---

### F5 — Per-survey extraction-coverage report (S)

**Goal.** What fraction of YAML claims have a backing codebook entry? Tracks progress over time.

**Files touched.**
- New: `src/r/audit/02_coverage_report.R`.

**Acceptance.**
- Output: `audit/reports/<survey>/02-coverage.json` with `total_claims`, `claims_reconciled`, `claims_unreconciled`.
- For the initial ABS run, coverage is reported (probably 60–80% depending on .sav metadata richness).

**Dependencies.** F4.

---

### F6 — KGSS codebook extraction (L)

**Goal.** Repeat F2–F5 for KGSS. KGSS has rich cumulative codebooks (PDF and Korean), but `.sav` metadata is decent.

**Files touched.**
- New: `src/r/audit/02_extract_codebook_kgss.R`.
- Output: `data/kgss/codebook/w<year>.parquet`.

**Dependencies.** F2 (pattern), F4.

---

### F7+ — Remaining-survey extraction (deferred)

WVS, LBS, Afro, Arab Barometer, KAMOS, KIPA*, KINU, IPUS each get their own extractor ticket as priority demands. Per-survey effort: M–L. Defer until ABS and KGSS prove the pattern.

---

## Phase G — Layer 5: Cross-wave continuity

Drift statistics, wording-change registry, threshold calibration.

### G1 — Drift-statistic computation (L)

**Goal.** Per (variable × country × wave-pair), compute TVD (ordinal) or KS-D (continuous).

**Files touched.**
- New: `src/r/audit/05_drift_check.R`.
- Output: `audit/reports/<survey>/05-drift.csv`.

**Acceptance.**
- For ABS, a baseline run produces a CSV with one row per (variable × country × wave-pair).
- TVD calculation is correct: hand-verify on `gov_sat_national` for Korea between W2 and W3 (compare to a manual histogram-difference computation).

**Dependencies.** E2 (stable harmonized output).

---

### G2 — Wording-change registry schema and seed (M)

**Goal.** YAML registry of known wording changes; the drift check respects it.

**Files touched.**
- New: `src/config/_wording_changes.yml`.
- New: `src/config/_wording_changes_v1.schema.json`.

**Initial seed.**
- `dem_sat_national` W2/W3 reversal (per CLAUDE.md scale-direction notes).
- `dem_vs_equality` W3 "both equally" remap.
- KIPA judiciary mislabel (per project memory; treat as a documented wording inconsistency in the English label).

**Acceptance.**
- Schema validates the file.
- 제프 reviews the seed entries.

**Dependencies.** G1.

---

### G3 — Threshold calibration (M)

**Goal.** Calibrate TVD/KS thresholds against the observed distribution of drifts in the existing harmonized output. Set initial `flag` and `block` thresholds.

**Files touched.**
- New: `src/r/audit/05_calibration.R` produces a histogram of all observed TVDs across all (variable × country × wave-pair) tuples for ABS.
- Modify: `src/r/audit/05_drift_check.R` to use the calibrated thresholds.

**Acceptance.**
- Calibration plot saved to `audit/reports/abs/05-calibration.png`.
- Initial thresholds set conservatively (flag at the 95th percentile of observed drifts; block at the 99th).

**Dependencies.** G1.

---

### G4 — Real-change vs break heuristic (M)

**Goal.** Surface, alongside each flagged drift, whether it is universal (all countries shift similarly → likely wording change) or country-specific (likely real political event).

**Files touched.**
- Extend `src/r/audit/05_drift_check.R`.

**Acceptance.**
- The CSV from G1 gains a column `country_pattern: universal | country_specific | mixed`.
- Sample case: gov_sat_national W3→W4 across all countries should pattern-classify; if all countries shift by similar magnitude, label `universal`.

**Dependencies.** G1.

---

## Phase H — Layer 7: CI integration

Local orchestrator, GitHub Actions workflow, gating policy, release certificates.

### H1 — Local audit orchestrator (M)

**Goal.** A single command that runs all seven layers locally and produces a summary.

**Files touched.**
- New: `src/r/audit/run_all.R` — orchestrates Layers 1–6 (Layer 7 is the CI itself; not run locally).
- Optionally: `Makefile` with `make audit` target if 제프 wants the convention.

**Acceptance.**
- `Rscript src/r/audit/run_all.R --survey abs` runs all layers in sequence; produces `audit/reports/abs/SUMMARY.md`.
- Total runtime < 5 min for ABS.

**Dependencies.** B3, C2, D3, E2, F4, G1 — i.e. all the layers' core scripts must exist before this can orchestrate them.

---

### H2 — GitHub Actions audit workflow (M)

**Goal.** `.github/workflows/audit.yml` triggered on PR open/sync, running Layers 1, 3, 4, 6 (the hard-fail layers) and warning on Layers 2, 5.

**Files touched.**
- New: `.github/workflows/audit.yml`.

**Acceptance.**
- A PR that touches `src/config/abs/harmonize_validated/democracy_satisfaction.yml` triggers the workflow.
- Workflow restores R from `renv.lock`, caches the renv library, runs `Rscript src/r/audit/run_all.R --survey abs`.
- A PR with a typo in a YAML fails; a clean PR passes.
- Total CI runtime < 10 min.

**Dependencies.** H1.

---

### H3 — Per-layer gating policy (S)

**Goal.** CI exit codes per layer are mapped to PR status checks. Layer 1, 3, 4, 6 failures block merge; Layer 2, 5 warnings comment but don't block.

**Files touched.**
- Modify: `.github/workflows/audit.yml`.

**Acceptance.**
- A PR introducing a Layer 1 schema violation cannot be merged.
- A PR introducing a Layer 5 drift warning can be merged but the warning is visible in the PR comment.

**Dependencies.** H2.

---

### H4 — Audit-pass certificate generator (M)

**Goal.** On a tagged release, generate a Markdown certificate that downstream papers can cite.

**Files touched.**
- New: `src/r/audit/generate_certificate.R`.
- New: `.github/workflows/release-certificate.yml` triggered on `v*` tag.

**Acceptance.**
- Tagging `abs-2026.05.09` triggers the workflow; produces `audit/certificates/abs-2026.05.09.md`.
- Certificate cites: release tag, engine commit, spec commit, manifest sha256, all-layers-pass status.
- File is committed back to the repo by the CI bot OR attached as a release artifact.

**Dependencies.** H1, H3.

---

## Critical-path summary

The shortest path to "the silent killer is no longer silent" is:

```
A1 → A2 → A3 → A4 → B1 → B2 → B3 → D1 → D2 → D3
```

Ten tickets, sized M/L/L/L/L/M/L/M/L/L = ~22 hours of focused work. After that, undeclared reverse-coding errors and cross-wave sign flips are mechanically detectable on the democratic-attitudes battery in ABS, with the framework in place to extend to other constructs and surveys.

The shortest path to "papers can cite a reproducible audit certificate" extends that with C1 → C2 → C3 → C4 → H1 → H2 → H4, another ~14 hours.

Other layers (E, F, G) are necessary for full coverage but each can be developed by demand once the foundation is in place.

---

## Tickets that depend on judgment from 제프

Three places where CC cannot proceed without input:

1. **A4 (recoding registry).** The auto-generated skeleton needs human review for the `reverses` and `monotonic` flags. ~30 min of 제프's time.

2. **D2 / D8 / D9 / D10 (anchor files).** The `expected_sign` per variable is a literature-grounded judgment. CC can draft from concept names; 제프 reviews. ~15–30 min per construct.

3. **G2 (wording-change seed).** The initial set of known wording changes is undocumented in the repo (some are in CLAUDE.md, some in scattered YAML notes). 제프's institutional memory is the source. ~30 min to enumerate.

Schedule those reviews into Phase A and Phase D explicitly — without them, those layers stall.

---

## Tickets explicitly NOT included

- **Translation auditing.** Stretch goal in `01-audit-framework.md`. Not ticketed.
- **Composite-index auditing.** Out of scope.
- **Differential audit (old vs new harmonized output diff).** Phase 4 stretch goal in the brief.
- **Pre-commit hook.** Phase 4 stretch goal.
- **Zenodo DOI integration for certificates.** Phase 4 stretch goal.

These are mentioned in the framework but deliberately left out of Phase 3 to keep the audit's first-pass scope manageable.
