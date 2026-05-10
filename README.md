# survey-data-prep

Multi-survey harmonization pipeline for cross-national survey research. YAML-driven specs, shared R harmonization engine, layered audit infrastructure.

**11 surveys, ~117 production specs, ~1,000 harmonized variables.** Per-survey reference: [`docs/surveys/`](docs/surveys/) and [`CLAUDE.md`](CLAUDE.md).

| Survey | Coverage |
|---|---|
| ABS — Asian Barometer | 6 waves, 12 countries (W6), 113,945 respondents, 367 vars |
| WVS — World Values Survey | 7 waves, 108 countries, 446,767 respondents, 62 vars |
| LBS — Latinobarómetro | 24 waves 1995-2024, 19 countries, 489,771 respondents |
| Afrobarometer | 9 rounds R1-R9, 42 countries, 351,815 respondents |
| Arab Barometer | W1-W8, ~9 vars |
| KAMOS | 2 waves, 39 vars |
| KGSS | 17 years 2003-2025, 188 vars |
| KIPA Corruption | 20 years 2004-2023, 36 vars (specialty sample) |
| KINU Unification | 13 waves 2014-2024, 127 vars |
| IPUS Unification | 18 annual waves 2007-2024, 11 vars |
| V-Dem v15 | Country-year panel scaffold, 1789-2024 |

---

## Setup (one-time)

```bash
# R: restore renv lockfile (includes audit deps: testthat, jsonvalidate, arrow, digest)
Rscript -e "renv::restore()"

# Python (minimal — only used for some ad-hoc scripts):
uv sync
source .venv/bin/activate
```

R is the primary language. Python is mostly inert.

---

## What "good hygiene" means in this repo

The pipeline is YAML-driven: change a YAML, re-run the pipeline, the harmonized output changes. The audit infrastructure (`src/r/audit/`) catches silent errors that would otherwise propagate into papers — wrong reverse-coding, undeclared missing codes, stale outputs, scale drift between waves, codebook-vs-YAML mismatches.

**Hygiene = "after every change, the audit reports clean OR every remaining flag is documented in JEFF_MUST_INVESTIGATE.md."**

If you skip the audit after a change, you don't know whether you introduced a silent bug. The audit is the only mechanism that catches them.

---

## Routine maintenance — runbooks

### A. After editing one or more YAML specs for a survey

```bash
SURVEY=abs   # or wvs, lbs, afro, arab-barometer, kamos, kgss, kipa-corruption, kinu, ipus

# 1. Schema + cross-reference validation (fast, catches typos, unknown keys, missing codes)
#    The engine refuses to harmonize a spec that fails this; running it standalone first
#    surfaces the error before the longer harmonization runs.
Rscript -e 'source("src/r/utils/spec_discovery.R"); source("src/r/harmonize/validate_spec.R")
for (p in list_survey_specs("'$SURVEY'")) {
  spec <- yaml::read_yaml(p)
  tryCatch(validate_spec_full(spec, all_specs_in_survey = lapply(list_survey_specs("'$SURVEY'"), yaml::read_yaml)),
           error = function(e) cat("FAIL:", basename(p), "—", conditionMessage(e), "\n"))
}'

# 2. Re-run the harmonization pipeline (writes oob_log.csv + manifest.json)
Rscript src/r/data_prep_modules/${SURVEY}/2_harmonize_all.R    # ABS uses the root path
Rscript src/r/data_prep_modules/${SURVEY}/99_create_final_dataset.R

# 3. The 99 script auto-runs the validation invariants. Read its output:
#    "Invariants: ok=N warn=M error=K skip=J" — any new errors should be investigated.
#    Detail at audit/reports/${SURVEY}/03-invariants.csv

# 4. If the survey has a codebook extract, re-run F4 codebook reconciliation:
ls data/${SURVEY}/codebook/ 2>/dev/null && Rscript src/r/audit/02_check_codebook.R --survey ${SURVEY}

# 5. If the survey has anchor files, re-run D3 anchor diagnostic:
ls src/config/_anchors/*.yml 2>/dev/null && for a in src/config/_anchors/*.yml; do
  Rscript src/r/audit/04_anchor_diagnostic.R --survey ${SURVEY} --anchor $a
done
```

**Stop and read the output.** If anything new fails, either fix it or add it to `JEFF_MUST_INVESTIGATE.md`.

---

### B. After editing a recoding function in `src/r/utils/recoding.R`

Every spec across every survey that uses the modified function will now produce different harmonized values.

```bash
# 1. Re-run the registry drift check
Rscript src/r/audit/check_registry_complete.R

# 2. Find every spec that references this function
grep -rln "fn: <function_name>" src/config/

# 3. Re-run those surveys' pipelines (Section A above for each)

# 4. Run the strict reverse-check on ABS — verifies safe_reverse_*pt outputs
#    still satisfy Pearson(raw, harmonized) ≈ -1
Rscript src/r/audit/04_strict_reversal.R --survey abs
```

---

### C. After fixing a bug from JEFF_MUST_INVESTIGATE.md

```bash
# 1. Run Section A above for the affected survey
# 2. Verify the specific finding is gone — pull the relevant rows from
#    audit/reports/<survey>/03-invariants.csv or 02-codebook-recon.csv
# 3. In JEFF_MUST_INVESTIGATE.md, MOVE the entry from the "open" section
#    to "Resolved findings" with the resolving commit hash. Do NOT delete.
# 4. Commit the YAML/code fix AND the JEFF_MUST_INVESTIGATE.md update together.
```

---

### D. After re-extracting a codebook (rare — e.g. after a new survey wave releases)

```bash
SURVEY=abs   # whichever survey has the new codebook

# 1. Re-run the per-survey extractor
Rscript src/r/audit/extractors/${SURVEY}_codebook.R

# 2. Re-run F4 against the new codebook
Rscript src/r/audit/02_check_codebook.R --survey ${SURVEY}

# 3. Re-run F5 coverage report
Rscript src/r/audit/02_coverage_report.R --survey ${SURVEY}

# 4. Inspect the diff: codebook fail rows that didn't exist before are
#    real audit findings — either fix the YAML or update JEFF_MUST_INVESTIGATE.md.
```

---

### E. Periodic hygiene check (monthly OR before any paper submission that uses harmonized output)

Run all of these for every survey you actively use. ~10–15 min total.

```bash
for SURVEY in abs wvs lbs afro arab-barometer kamos kgss kipa-corruption kinu ipus; do
  echo "=== $SURVEY ==="
  # Determinism (does re-running produce identical output?)
  Rscript src/r/audit/06_check_determinism.R --survey $SURVEY 2>&1 | tail -3

  # Input-drift detector (did any raw .sav/.rds change since the last manifest?)
  Rscript src/r/audit/06_check_input_drift.R --survey $SURVEY 2>&1 | tail -3

  # Cross-wave drift check (re-runs against existing harmonized output)
  Rscript src/r/audit/05_drift_check.R --survey $SURVEY 2>&1 | tail -3

  # Codebook reconciliation (only where extractor exists)
  ls data/$SURVEY/codebook/ &>/dev/null && Rscript src/r/audit/02_check_codebook.R --survey $SURVEY 2>&1 | tail -3
done
```

After running: skim `audit/reports/<survey>/` for any new fail rows, update `JEFF_MUST_INVESTIGATE.md`.

---

### F. Onboarding a new survey

1. Create directory structure:
   ```
   data/<survey>/raw/
   src/config/<survey>/harmonize/
   src/r/data_prep_modules/<survey>/  (for 0_load_waves.R, 2_harmonize_all.R, 99_create_final_dataset.R)
   ```

2. Add the survey to `src/r/utils/spec_discovery.R` if its config dir name is non-standard.

3. Create the verbatim dictionary CSV at `data/<survey>/questionnaire_text/<survey>_verbatim_items.csv` (per CLAUDE.md spec — mandatory for every survey).

4. Build the per-survey wave loader and harmonization wrapper following an existing survey as template (KGSS, KAMOS, or IPUS are the cleanest).

5. Author YAML specs. Each must declare:
   - `schema_version: 1`
   - `missing_conventions:` block
   - For every variable: `missing.use_convention:` (no implicit defaults)
   - Required: `id`, `concept`, `description`, `type`, `source`, `harmonize`, `qc.valid_range`

6. Run Section A's runbook to validate.

7. (Eventually) Build a codebook extractor at `src/r/audit/extractors/<survey>_codebook.R` and run F4 reconciliation.

---

## Where things live

```
src/r/harmonize/        Engine: harmonize.R, validate_spec.R, report_harmonization.R
src/r/utils/            recoding.R, recoding_registry.yml, validation.R, spec_discovery.R, provenance.R
src/r/data_prep_modules/  Per-survey pipeline orchestrators (0/2/99 + 2.5/2.6 ABS-only)
src/r/audit/            All audit modules:
                          02_check_codebook.R       (F4) YAML vs codebook diff
                          02_coverage_report.R      (F5) per-survey codebook coverage
                          04_anchor_diagnostic.R    (D3) reverse-coding via anchor correlations
                          04_strict_reversal.R      (D4) strict raw↔harmonized r=-1 check
                          05_drift_check.R          (G1) cross-wave TVD/KS drift
                          05_threshold_calibration.R (G3) percentile thresholds
                          06_check_determinism.R    (C4) verify byte-identical reruns
                          06_check_input_drift.R    (C5) detect raw-input changes
                          check_registry_complete.R (A4 helper) recoding registry drift
                          extractors/<survey>_codebook.R  (per-survey codebook extractors)
src/config/<survey>/harmonize/   YAML specs (ABS uses harmonize_validated/)
src/config/_schema/              JSON Schema (harmonize_v1.schema.json)
src/config/_anchors/             Construct anchor files for D3 (democratic_attitudes, institutional_trust, economic_evaluations)
src/config/_wording_changes.yml  Registry of known wording/coding changes (G2)
data/<survey>/raw/               Raw survey microdata (gitignored)
data/<survey>/codebook/          Extracted parquet codebooks (F1 schema)
data/processed/                  Harmonized output (consumable by papers)
outputs/<survey>/                manifest.json + oob_log.csv per pipeline run
audit/                           Audit framework documentation:
                                   00-discovery.md, 01-audit-framework.md, 02-implementation-tickets.md
audit/reports/<survey>/          Generated audit artifacts (gitignored)
JEFF_MUST_INVESTIGATE.md         Open audit findings — read this regularly
CLAUDE.md                        Project conventions (cross-survey scale gotchas, function map, etc.)
docs/surveys/<survey>.md         Per-survey reference page
```

---

## The findings backlog

[`JEFF_MUST_INVESTIGATE.md`](JEFF_MUST_INVESTIGATE.md) tracks every open audit finding. Read it before:

- Any paper submission that uses the harmonized output
- Any major refactor of the YAML specs
- After any other contributor's PR (if applicable)

When you investigate something:
1. Move the entry from "open" to "Resolved findings" with the commit hash
2. Don't delete entries — preserve the trail

---

## Cross-survey scale gotchas (read before merging variables across surveys)

The full list is in [`CLAUDE.md`](CLAUDE.md), but the headline traps:

- **Trust scales differ:** ABS/WVS/LBS/Afro/KINU = 1-4 (higher=more trust); KAMOS = 0-10; KGSS `conf_*` = 1-3.
- **Korean unification direction is OPPOSITE between surveys:** IPUS+KINU `uni_necessity` higher=pro; KGSS `pol_unification` higher=ANTI.
- **`subjective_class_6pt` direction is OPPOSITE between KGSS and KINU.**
- **KIPA judiciary mislabel:** English SPSS labels mistranslate 사법부 (judiciary) as "legislature".

Before any cross-survey analysis, check the relevant survey's [`docs/surveys/<survey>.md`](docs/surveys/) for direction notes.

---

## Audit framework reference

The audit is a 7-layer infrastructure that runs on every harmonization. Full design in [`audit/01-audit-framework.md`](audit/01-audit-framework.md). What each layer catches:

| Layer | Catches | Module |
|---|---|---|
| 1. Configuration integrity | Schema typos, unknown keys, undeclared conventions, duplicate ids | `validate_spec.R` |
| 2. Codebook reconciliation | YAML labels/range/missing-codes mismatch source codebook | `02_check_codebook.R` (F4) |
| 3. Output invariants | Coverage loss, type drift, level set violations, range violations | `2.5_validate_harmonization.R` |
| 4. Reverse-coding | Wrong-direction harmonization, undeclared reversals | `04_anchor_diagnostic.R` (D3), `04_strict_reversal.R` (D4) |
| 5. Cross-wave continuity | Silent question-wording / scale changes between waves | `05_drift_check.R` (G1) |
| 6. Provenance | Non-deterministic outputs, untracked input changes | `06_check_determinism.R` (C4), `06_check_input_drift.R` (C5) |
| 7. CI gating | (Not implemented; see Phase H notes in `audit/02-implementation-tickets.md`) | — |

The framework's design notes, original third-party audit deliverables, and ticket queue are all in [`audit/`](audit/).

---

## When in doubt

- Audit caught something? Read the message carefully. Check whether the YAML, the recode function, or the audit itself is wrong. Real bugs go in `JEFF_MUST_INVESTIGATE.md`; false positives go to the audit module's skip list with a comment explaining why.
- Pipeline produces unexpected values? Run Section A's runbook for the affected survey first. The auto-validation step usually points at the issue.
- New survey wave dropped? Section D, then Section A.
- Lost track of state? `git log --oneline | head -20` shows the audit's commit trail; commit messages document what was changed and why.
