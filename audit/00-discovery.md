# Phase 1 — Discovery: Survey Harmonization Pipeline

**Auditor posture:** skeptical third-party. Where I cannot verify a control, I flag it as missing rather than presumed-OK. Where the existing pipeline is genuinely strong, I say so explicitly.

**Scope of this document:** read-only inventory only. No prescriptive design (that lives in `01-audit-framework.md`).

---

## 1.1 Repo topology

### Top-level

```
survey-data-prep/
├── CLAUDE.md                    Root project guide; per-survey docs in docs/surveys/
├── README.md                    Out-of-date in places (claims ABS=110,721 resp;
│                                CLAUDE.md / docs/surveys/abs.md say 113,945)
├── PROJECT_INDEX.md             [not inspected in this pass]
├── GEMINI.md                    [not inspected]
├── pyproject.toml / .uvrc       Python (uv-managed, py3.12)
├── renv.lock                    R env (note: testthat NOT in lockfile — see §1.4)
├── econdev-authpref.Rproj       RStudio project file
├── .github/workflows/           Two workflows; both are Claude-Code-action.
│                                NO build/test/harmonize CI exists.
├── src/                         R + Python source
├── data/                        Per-survey raw + processed
├── outputs/                     Harmonized RDS/parquet + ad-hoc report markdowns
├── scripts/                     ~25 ad-hoc/utility scripts (mix of build, test,
│                                debug, qa, prospector). Some duplication
│                                (build_master_complete.R, build_master_debug.R,
│                                 build_master_debug.R.bak, build_master_from_specs.R)
├── papers/                      One downstream paper (10_democratic_aspiration_gap)
├── results/                     Per-paper R snippets (paper3_task*.R)
├── docs/surveys/                Per-survey reference pages (12 surveys)
└── 한국행정연구원_사회통합실태조사_설문지_2022/   Untracked questionnaire dir
```

### Directory tree (depth 3, key paths)

```
src/
├── r/
│   ├── codebook/               Codebook generation tools + tests
│   ├── harmonize/              SHARED ENGINE: harmonize.R, validate_spec.R,
│   │                           report_harmonization.R, _load_harmonize.R
│   │                           (also test_harmonize.R; see §1.4)
│   ├── survey/                 Loaders, codebook tools (load_data.R, etc.)
│   ├── utils/                  recoding.R (~91 functions), validation.R,
│   │                           helpers.R, search.R, _load_functions.R, etc.
│   ├── data_prep_modules/      ABS-specific 0/2/2.5/2.6/99 scripts at root,
│   │                           plus per-survey subdirs:
│   │                           {afro, arab-barometer, ipus, kamos, kgss,
│   │                            kinu, kipa-corruption, lbs, vdem, wvs}/
│   └── models/                 [statistical models, not part of harmonization]
├── config/
│   ├── abs/
│   │   ├── harmonize/          3 files: MODEL_VARIABLE.yml, regime_nostalgia.yml,
│   │   │                       wvs_turkey_gradient.yml. NOT used in production.
│   │   └── harmonize_validated/ 28 production YAMLs.
│   ├── wvs/harmonize/          14 files
│   ├── lbs/harmonize/          9 files
│   ├── afro/harmonize/         14 files
│   ├── arab-barometer/harmonize/  9 files
│   ├── kamos/harmonize/        6 files
│   ├── kgss/harmonize/         18 files
│   ├── kipa/harmonize/         4 files     (KIPA-social, separate from corruption)
│   ├── kipa-corruption/harmonize/  4 files
│   ├── kinu/harmonize/         8 files
│   └── ipus/harmonize/         3 files
├── python/                     ingest/ export/ validation/ → all empty __init__.py.
│                               One file: utils.py. Python is currently inert.
└── scripts/                    Spec generators, prospector concept-group YAMLs,
                                build helpers (e.g. build_abs_w6.R, create_wave_rds.R)
```

### File counts by extension (excluding renv/, .venv/, .git/)

| Ext   | Count |  Notes |
|-------|-------|---------|
| .pdf  | 284   | Codebooks + technical reports (mostly in data/) |
| .sav  | 282   | Raw SPSS microdata |
| .rds  | 170   | Processed/harmonized R serialized |
| .png  | 154   | Figures |
| .csv  | 128   | Verbatim dictionaries, prospector outputs, codebook displays |
| .yml  | 125   | Harmonization specs (≈120 in src/config/) + concept_groups + CI workflows |
| .R    | 114   | All R source |
| .md   | 70    | Docs + ad-hoc reports |
| .zip  | 56    | Mostly archived raw downloads in data/ |
| .txt  | 40    | ABS labels exports + scattered notes |
| .hwp  | 28    | Korean questionnaires (KGSS, KIPA) |
| .xlsx | 24    | Wave coverage, ad-hoc notes |
| .dta  | 21    | Stata raw (small) |
| .parquet | 16 | Output parallel to .rds |
| .docx | 12    | ABS questionnaires (Word) |
| .py   | 8     | Python source — minimal use |

**Languages used.** R is the primary language (114 .R files). Python is present but inert (8 .py files; ingest/export/validation packages contain only empty `__init__.py`s). One shell script (`scripts/setup_project.sh`). No Quarto / Snakemake / make.

### Build / orchestration system

**There is no build orchestrator.** No `Makefile`, no `Snakefile`, no `_targets.R`, no top-level `run_all.sh`, no Quarto project file.

Each survey has its own three-stage pipeline run as separate `Rscript` invocations:

```
Rscript src/r/data_prep_modules/{survey}/0_load_waves.R          # build wave RDS
Rscript src/r/data_prep_modules/{survey}/2_harmonize_all.R       # apply YAMLs
Rscript src/r/data_prep_modules/{survey}/99_create_final_dataset.R
```

ABS uses the root `src/r/data_prep_modules/` (no subdir).

**This means there is no single command that, from a clean clone, deterministically reproduces the harmonized outputs.** The README's instructions are a sequence of three commands per survey, executed manually. Re-running an arbitrary subset can leave intermediate state stale (see §1.4 / determinism).

### Entry point — what reproduces the harmonized output

Per-survey, the canonical sequence is the three-script pattern above. For ABS specifically:

1. `src/scripts/create_wave_rds.R` — converts raw `.sav` files in `data/abs/raw/wave{1..6}/` to `data/processed/{w1..w6}.rds` (W6 here is **incomplete**: see §1.3 finding).
2. `src/scripts/build_abs_w6.R` — separate, more recent, multi-country W6 builder; writes `data/processed/w6.rds` from all `W6_*.sav` files in the wave6 dir.
3. `src/r/data_prep_modules/2_harmonize_all.R` — harmonizes from `data/processed/{w1..w6}.rds`, writes per-wave `outputs/master_w{1..6}.rds`.
4. `src/r/data_prep_modules/99_create_final_dataset.R` — assembles `data/processed/abs_harmonized.{rds,parquet}`.

**The `0_load_waves.R` referenced in the README is *not* a raw-data ingestor. It loads the already-converted RDS.** Conversion from `.sav` is a separate, undocumented step (the two scripts above). I flag this in §1.3.

---

## 1.2 Configuration inventory

### Total YAML count

**128 YAML files** total in the repo, of which **~120 are harmonization specs** under `src/config/<survey>/harmonize/` (or `harmonize_validated/` for ABS). The remainder are concept-group prospector configs (`src/scripts/concept_groups*.yml`), CI workflows, and Serena project metadata.

Production spec counts per survey:

| Survey            | Production dir                              | # specs |
|-------------------|---------------------------------------------|---------|
| ABS               | `src/config/abs/harmonize_validated/`       | 28      |
| KGSS              | `src/config/kgss/harmonize/`                | 18      |
| WVS               | `src/config/wvs/harmonize/`                 | 14      |
| Afrobarometer     | `src/config/afro/harmonize/`                | 14      |
| LBS               | `src/config/lbs/harmonize/`                 | 9       |
| Arab Barometer    | `src/config/arab-barometer/harmonize/`      | 9       |
| KINU              | `src/config/kinu/harmonize/`                | 8       |
| KAMOS             | `src/config/kamos/harmonize/`               | 6       |
| KIPA-social       | `src/config/kipa/harmonize/`                | 4       |
| KIPA-corruption   | `src/config/kipa-corruption/harmonize/`     | 4       |
| IPUS              | `src/config/ipus/harmonize/`                | 3       |
| ABS (legacy)      | `src/config/abs/harmonize/`                 | 3 (not prod) |

**Total: ~117 production specs across 11 surveys.** Each spec contains 1–N variable entries (the metadata CSV reports 330 ABS variables across 28 specs, so spec→variable expansion is roughly 12× on average for ABS).

### Schema status — **no formal schema validation step exists.**

There is no JSON Schema file, no `pydantic` model, no `yaml-schema` config, no `jsonschema` dependency. The only enforcement is the hand-rolled R function `validate_harmonize_spec()` in `src/r/harmonize/validate_spec.R:28`. It performs ~15 imperative checks:

- Top level: requires `missing_conventions`, `variables`.
- Per-variable: requires `id`, `concept`, `description`, `source` (≥1 wave), `type` (∈ {ordinal, nominal, continuous}), and `harmonize.default` (with method ∈ {identity, r_function, recode, derive}).
- `qc.valid_range_by_wave`: each entry must be a length-2 numeric vector.

What it does **not** do:

- Reject **unknown / mistyped** keys (no equivalent of `additionalProperties: false`). A typo in `harmnoize:` (vs `harmonize:`) silently falls through to the default-rule branch and produces all-NA without erroring.
- Constrain enum values for `qc.expected_direction` (`positive`/`negative`), the `tags:` vocabulary, the `missing.use_convention:` keys, or any other free-text field.
- Validate cross-references — e.g. that `missing.use_convention: foo` actually names a key in `missing_conventions`.
- Require a schema **version** field. There is no schema versioning, so silent format drift is uncatchable.
- Validate `harmonize.exceptions.<wave>` or `harmonize.<wave>` direct keys (the engine handles three formats — `by_wave`, `exceptions`, direct — but `validate_harmonize_spec` only checks `default`).
- Validate that the recoding function named in `fn:` exists. `check_recoding_functions()` does that, but is called separately from `harmonize_all()` only at the engine entry point — `validate_harmonize_spec()` itself is silent on missing functions.

There is a separate `validate_phrases()` function (`validate_spec.R:149`) that checks whether the source variable's question-text label contains an expected regex phrase. This is a **codebook-reconciliation** mechanism, not schema validation. It is **opt-in per variable** (only fires when `qc.validate` is set) and is not invoked in the standard `2_harmonize_all.R` entry point — only in `validate_all_specs()` and `2.5_validate_harmonization.R`, which the user runs on demand.

### Sample configs — one complex, one simple

**Simple** (`src/config/abs/harmonize_validated/democracy_satisfaction.yml`, gov_sat_national entry, lines 14–50):

```yaml
- id: gov_sat_national
  concept: government_satisfaction
  description: "Satisfaction with current government/president"
  type: ordinal
  source:
    w1: q104
    w2: q99
    w3: q95
    w4: q98
    w5: q105
    w6: q96
  scale:
    min: 1
    max: 4
    labels: {1: "Very dissatisfied", 2: "Somewhat dissatisfied",
             3: "Somewhat satisfied", 4: "Very satisfied"}
  harmonize:
    default:
      method: r_function
      fn: safe_reverse_4pt
      note: "W2-W6 coded 1=Very satisfied → 4=Very dissatisfied; reverse to low→high"
    exceptions:
      w1:
        method: r_function
        fn: collapse_middle5_to_4pt
        note: "W1 has 5pt scale with 5=Half/Half middle category; keeps 1-4, converts 5 to NA"
  qc:
    valid_range: [1, 4]
    expected_direction: positive
    validate:
      - waves: [w1, w2, w3, w4, w5, w6]
        phrase: "government|president"
```

What this entry does **not** explicitly state, despite affecting outcomes:

- That W1 needs a 5pt collapse — only the function name and the `note:` field encode that. The `scale:` block declares 1–4, contradicting the W1 raw data.
- Whether W2's "1=Very satisfied" claim was verified against the W2 codebook. The `validate.phrase` check matches "government|president" against the W2 question label, which catches *the wrong question being mapped* but **does not catch a direction flip** in the response options.
- That `safe_reverse_4pt` should fail loudly if W2's actual coding is reversed from the assumed direction. It doesn't — it just applies `5 - x` and produces a plausible-looking result either way.

**Complex** (`src/config/abs/harmonize_validated/authoritarianism.yml`): contains 19+ variables, many using `safe_reverse_4pt` as default with country/wave-specific exceptions. Single battery (`a_strongleader`, `a_singleparty`, `a_armyrule`, etc.) has 19 distinct `safe_reverse_4pt` invocations across waves, each independently subject to the direction-flip risk above. Inspected one entry (`a_strongleader`, lines 28–55) — same shape as the simple example, no per-variable safeguards beyond the shared `safe_reverse_4pt` default.

### Conventions — explicit vs implicit fields

| Field                           | Explicit?  | Notes |
|---------------------------------|------------|-------|
| Source variable per wave        | Explicit   | `source: {w1: q104, ...}` |
| Reverse-coding                  | **Implicit by function name** | Reversal is encoded as `fn: safe_reverse_4pt` rather than as a `direction:` field. Auditing direction requires reading the function name and comparing against the raw scale. |
| Missing codes                   | Mostly explicit | Per-spec `missing_conventions:` block + optional per-variable `missing.codes`. Engine merges both. But the `recoding.R` functions ALSO carry their own default `missing_codes = c(-1,0,7,8,9)`, so the source of truth is split. |
| Valid range                     | Explicit   | `qc.valid_range` or per-wave `qc.valid_range_by_wave`. **Required by warning, not by error**: if missing, engine emits `warning()` but proceeds. |
| Expected direction              | Optional, free-text | `qc.expected_direction: positive` is documented in MODEL_VARIABLE.yml but the engine and validators do not check it. It is a label, not an assertion. |
| Question wording                | Implicit / external | Lives in the verbatim CSV (`data/<survey>/questionnaire_text/*.csv`), NOT in the YAML. No automated cross-check between YAML and verbatim CSV exists. |
| Scale labels                    | Optional, declarative | `scale.labels:` is a hint, not an enforced contract. Engine never reads it. |
| Schema version                  | **Absent** | No `version:` or `schema_version:` field. Format drift is invisible. |

---

## 1.3 Source data and codebooks

### Where raw data lives

All raw microdata sit under `data/<survey>/raw/` and are excluded from git via `.gitignore` (which also excludes `data/raw/wvs_wave7/...dta` explicitly by name).

| Survey | Location | Format |
|---|---|---|
| ABS | `data/abs/raw/wave{1..6}/` | `.sav` (SPSS); W6 has 12 country-specific files plus tech reports |
| WVS | `data/wvs/raw/` | not inspected in detail this pass |
| Arab Barometer | `data/arab-barometer/raw/wave{1..3,5..8}/` | mixed |
| Afrobarometer | `data/afro/raw/` | not inspected |
| LBS | `data/lbs/raw/` | per-year files |
| KGSS, KAMOS, KIPA*, KINU, IPUS, V-Dem | `data/{survey}/raw/` | mixed `.sav`, `.dta`, `.csv` |
| External | `data/external/covid_economic/` | covariates |

**Version control.** Raw data is **not** version-controlled. There is no DVC config, no `git lfs` configuration, no manifest of expected file hashes. The `Wave Coverage.xlsx` in `data/abs/raw/` is a manual coverage record.

### Codebooks present

| Survey | Codebook PDFs in repo |
|---|---|
| ABS | Per-wave label exports (`data/abs/labels/W{1..6}_labels.txt`); per-wave questionnaire .doc/.docx/.pdf in each `wave{N}/` dir; W5 has `20230505_W5_merge_15_codebook.pdf`; W6 country-specific tech reports. **No machine-readable codebook.** |
| KGSS | `Eng_codebook_CUM0062_V3.pdf`, `2003-2025_KGSS_Codebook_kor_cumulative.pdf`, plus per-wave Korean questionnaires (.pdf, .hwp) |
| KIPA | `kipa_2021_questionnaire.pdf`, `kipa_2022_questionnaire.pdf` |
| KIPA-corruption | `kor_que_20220070.pdf` |
| KAMOS | 5 per-wave questionnaire PDFs |
| V-Dem | `v15/codebook.pdf`, `cautionary_notes.pdf`, `whats_new.pdf` |

### Verbatim dictionaries (the closest thing to a structured codebook)

Per-survey CSVs at `data/<survey>/questionnaire_text/<survey>_verbatim_items.csv`. ABS, LBS, Arab Barometer, IPUS, KINU, WVS, KIPA-corruption, and KAMOS all have these. Schema:

```
wave, question_id, harmonized_name, section, stem_text, item_text, response_scale, notes
```

These are **manually curated from the questionnaire PDFs**. They are not generated automatically and there is **no scripted check that the YAML's `source: {w1: q104}` matches the dictionary's `question_id` for the same `harmonized_name`** (or vice versa). If a researcher edits the YAML to remap `q104 → q105` and forgets to update the verbatim CSV, both files quietly diverge.

The verbatim CSV is the single source of truth for paper Appendix A. The YAML is the single source of truth for harmonization. **There is no automated reconciliation between them.** Flag.

### Per-wave canonical reference document

For each survey wave, the closest thing to a canonical reference is the questionnaire PDF in `data/<survey>/raw/wave{N}/` (or the cumulative codebook, where it exists). Mapping from PDF to YAML went through the verbatim CSV intermediary, by hand. There is no mechanical link from PDF → CSV → YAML.

For ABS specifically, the W5 PDF codebook (`20230505_W5_merge_15_codebook.pdf`) is the only wave with a labeled "codebook" file. Other waves rely on questionnaire docs + label exports + SPSS metadata.

### **Finding: stale W6 builder (data-corruption hazard).**

`src/scripts/create_wave_rds.R:9-16` lists hardcoded ABS source files including `w6 = "data/abs/raw/wave6/W6_Cambodia_Release_20240819.sav"` — Cambodia only, written out as `data/processed/w6.rds`. The newer `src/scripts/build_abs_w6.R` correctly stacks all 12 country files. **Both scripts write the same destination path.** If a user runs `create_wave_rds.R` (e.g. believing it is the canonical loader, since its name suggests it is) **after** `build_abs_w6.R`, they will silently overwrite the multi-country W6 with Cambodia-only — and the harmonization pipeline downstream will produce an "ABS W6" output that contains only Cambodia. None of the existing checks would catch this (n_rows would shift from ~12k to ~1.1k, but nothing fails on row-count drift).

Confirmed: `data/processed/w6.rds` mtime is 2025-05-03 18:56, multi-country builder is the more recent script. The Cambodia-only loader is still on disk and runnable. **Verification:** loaded `w6.rds` directly; 14,876 rows across 12 countries — the multi-country build is the current state on disk. The hazard is **dormant** (good script ran last), not active. But the broken script is still runnable and the destination path collision is unguarded.

---

## 1.4 Existing controls

### Tests

Three `testthat`-style files exist:

| File | Tests | Status |
|---|---|---|
| `src/r/harmonize/test_harmonize.R`         | 6  | Cannot run — testthat not installed |
| `src/r/utils/test_identity_functions.R`    | small | Cannot run — testthat not installed |
| `src/r/codebook/test_codebook.R`           | ~25 | Cannot run — testthat not installed |

I confirmed by running `Rscript -e 'library(testthat)'` in this repo: returns `Error in library(testthat) : there is no package called 'testthat'`. The renv lockfile does not include testthat. **There is no working test runner in this project.**

There are also two ad-hoc test scripts (`scripts/test_harmonization_working.R`, `scripts/test_harmonization_full_dataset.R`) that are not test cases but end-to-end smoke checks. They use `Rscript`-style assertions (cat/print + manual eyeballing) rather than a framework. These run but their pass/fail outcome is not machine-readable.

**Coverage of what tests do exist:** the 6 unit tests in `test_harmonize.R` cover identity, missing-code conversion, missing-source handling, two `validate_harmonize_spec` cases, and one report-generation test. They use synthetic 10-row mock waves with fabricated labels. **Nothing in the test suite touches a real spec, a real wave, a real recoding function (other than identity), or any cross-wave reverse-coding correctness check.** Even the synthetic tests cannot be executed in the current renv.

### Assertions inside harmonization scripts

The engine does emit guards:

| Where | What | Strength |
|---|---|---|
| `harmonize_variable()` (`harmonize.R:118-143`) | Pre-flight: warns when a wave is unmapped but the same source name exists in that wave's data with valid values (forgotten YAML entry → silent NA). | Soft (warning). Suppressible. |
| `harmonize.R:152-156` | Source variable doesn't exist in this wave → all NA, no error. | Silent — by design. |
| `harmonize.R:207-211` | r_function names a function that doesn't exist → `stop()`. | Hard error. |
| `harmonize.R:267` | Unknown method → `stop()`. | Hard error. |
| `harmonize.R:283-287` | No `valid_range` declared → `warning()`. | Soft. Most production specs do declare it. |
| `harmonize.R:290-311` | Out-of-range values → coerced to NA, optional logging via `oob_log` env. | Soft (silent in the data, logged externally). |
| `harmonize.R:336-346` (`harmonize_all`) | Pre-flight: every `r_function`/`derive` `fn:` resolves to a loaded function. | Hard error at top of run. **Useful.** |
| `recoding.R:6-26` (`.validate_semantic_label`) | When `validate_all:` is set in the wave rule, asserts the question label contains the expected regex. | Hard error. **But opt-in per rule and rarely used.** |

The post-hoc validators in `validation.R` (`validate_coverage`, `validate_transformation`, `validate_crosstab`, `validate_range`) are richer: they compare raw → harmonized via row-aligned correlation (Pearson + Spearman) and crosstab. These are meaningful but **only run when the user invokes `2.5_validate_harmonization.R`** — not on every harmonization run. There is no enforcement that they were executed before downstream use.

### Audit trail per variable

There is **no per-variable audit log** persisted with the output. Each `2_harmonize_all.R` run prints `cat()` messages and may write `*_oob_log.csv` (only if the caller passes `oob_log_path`). The harmonized RDS itself carries no metadata.

`outputs/master_variable_metadata.csv` exists but is shallow: 4 columns (concept, variable_id, num_waves, waves_available). Useful as an inventory; useless as a transformation log.

The various ad-hoc reports (`outputs/HARMONIZATION_RUN_SUMMARY.md`, `HARMONIZATION_VALIDATION_SUMMARY.md`, dated 2025-01-11) are point-in-time dumps; they are not regenerated each run and there is no policy to keep them current.

### Output reproducibility (input hash → output hash)

**Not implemented.**

- No input-file hash captured. No record of which `.sav` produced which `.rds`.
- No engine-version / commit-hash recorded with the output.
- No spec-set hash bundled with output.
- The harmonized `.rds` files have no provenance attributes.
- I tested the determinism question theoretically: the engine uses no `Sys.time()`, no `runif`, no random ordering — but `dplyr::bind_rows` with column-union semantics is sensitive to spec list order, and `harmonize_all()` iterates `names(spec$variables)` (preserved as YAML order). Should be deterministic in practice, but no test asserts byte-equality.

### CI / release gating

The two `.github/workflows/` files are both **Claude-Code review actions**, not build/test pipelines. They run on PR open and `@claude` mention. They do not execute the harmonization pipeline, do not run tests, do not validate YAML, and produce no artifacts or merge gates. **There is effectively no CI on this project.**

### Linting / style

`src/r/utils/lint.R` exists (not inspected); `pyproject.toml` has ruff settings. No pre-commit hook configured. No automated style check.

---

## 1.5 End-to-end trace of a single variable

**Variable chosen:** `gov_sat_national` (government / president satisfaction, ABS). Appears in W1 through W6, reverse-coded by default, with a wave-specific exception in W1 (5pt → 4pt collapse).

### Step 1 — raw data sources

The engine reads from `data/processed/{w1..w6}.rds`, **not** from the `.sav` files directly. The .sav→.rds conversion went through one of:

- `src/scripts/create_wave_rds.R` (W1–W5; W6 Cambodia-only — see §1.3 finding); OR
- `src/scripts/build_abs_w6.R` (W6 multi-country, more recent).

For W2 specifically: `data/abs/raw/wave2/Wave2_20250609.sav` → `data/processed/w2.rds` (mtime 2025-01-07; predates the W6 multi-country build).

**Unverifiable from the repo alone:**
- Which ABS release (date) is canonical for each wave. (`Wave2_20250609.sav` is dated 2025-06-09, but I cannot confirm without contacting ABS that this is the latest.)
- Whether `data/processed/w2.rds` was produced by the script in this repo or imported from elsewhere — there is no manifest.
- Whether the SPSS-to-R coercion preserved every haven attribute correctly (no test).

### Step 2 — YAML config

`src/config/abs/harmonize_validated/democracy_satisfaction.yml:14-50` defines `gov_sat_national`:

- `source.w2: q99` — claim: variable `q99` in W2 raw data is government satisfaction.
- `harmonize.default.fn: safe_reverse_4pt` — claim: W2 raw coding is 1=Very satisfied → 4=Very dissatisfied, must be flipped.
- `qc.valid_range: [1, 4]`
- `qc.validate.phrase: "government|president"` for waves W1–W6.

### Step 3 — engine invocation (W2)

`harmonize_variable(var_spec, waves, missing_conventions)` in `src/r/harmonize/harmonize.R:104`:

1. **`harmonize.R:148-155`** — extract source: `src <- "q99"`. Confirms `q99 %in% names(waves[["w2"]])`. If not, returns all-NA silently.
2. **`harmonize.R:160-167`** — type coercion: if `haven_labelled`, calls `haven::zap_labels()` → numeric.
3. **`harmonize.R:169-193`** — missing handling: pulls `treat_as_na = [-1, 0, 7, 8, 9, 97, 98, 99]` from spec. Sets matching values to NA.
4. **`harmonize.R:196`** — `resolve_wave_rule(var_spec, "w2")`: walks `harmonize.by_wave.w2 → exceptions.w2 → harmonize.w2 → default`. None of the wave-specific entries exist for W2, so falls through to `default = {method: r_function, fn: safe_reverse_4pt}`.
5. **`harmonize.R:204-219`** — invokes `safe_reverse_4pt(x, data=waves[["w2"]], var_name="q99", validate_all=NULL)`.
6. **`recoding.R:56-64` then `.safe_npt` (`recoding.R:31-44`)** — since `validate_all=NULL`, the semantic-label check is skipped. Then `case_when`: x ∈ {1,2,3,4} → `5 - x`; else NA. Reversal is applied unconditionally.
7. **`harmonize.R:270-312`** — range check vs `[1, 4]`. Since 5-x for x∈{1..4} ∈ {1..4}, no out-of-range. (If raw had any odd code that survived missing-code masking — e.g. an undocumented "5" — `case_when` returns NA at step 6 already. Range check is a redundant net here.)
8. Result: `out[["w2"]] <- x_harm` (numeric vector, length = nrow(waves[["w2"]])).

### Step 4 — final assembly

`stack_harmonized_wide()` in `2_harmonize_all.R:186-226` joins all harmonized variables column-wise within each wave. Output: `outputs/master_w2.rds`.

`99_create_final_dataset.R` (not inspected line-by-line) presumably row-binds across waves to produce `data/processed/abs_harmonized.rds`.

### Verification gaps in this trace

| Step | Claim | Verified by? |
|---|---|---|
| 1 | `data/processed/w2.rds` faithfully reflects `Wave2_20250609.sav`. | **Nothing.** No hash, no test. |
| 2 | `q99` in W2 is government satisfaction. | `validate_phrases()` could check the haven label contains `"government\|president"` — but only when run on demand. Not part of standard pipeline. |
| 2 | W2 coding is 1=Very satisfied → 4=Very dissatisfied (i.e. requires reversal). | **Nothing automated.** Comment in YAML asserts this; no anchor-correlation diagnostic confirms. If the true coding were already 1=low → 4=high, the engine would reverse it the wrong way and produce a plausible but wrong-direction variable. |
| 3 | `treat_as_na` codes for W2 are correct. | **Nothing.** ABS missing conventions vary by wave (7/8/9 in some, 97/98/99 in others, 7777/8888/9999 in W5+). Per-spec block uses `[-1, 0, 7, 8, 9, 97, 98, 99]` uniformly. If W2 uses a code not in this list (e.g. 95 for "decline to answer"), it leaks into the harmonized output as a real value 1–4 minus that code → OOR → NA via range check. The OOR log would catch this *if* `oob_log_path` is set. |
| 6 | `safe_reverse_4pt` produces correct output given correct input. | Logically yes (the function is two case_when arms). Untested at unit level (testthat not installed). |
| 7 | All values in `[1, 4]`. | Engine enforces this at the cost of silently NA-ing the offenders. The OOR log captures *that* an offense occurred but not which respondent / which raw code. |

**Bottom line for this trace:** the engine path is mechanically clean. Every claim that the *YAML itself* is correct (right variable, right direction, right missing codes) rests on the YAML author's manual codebook reading. The only automated check that can flag a wrong YAML claim is `validate_phrases()`, which does *substring* matching on the question label and does *not* verify direction.

---

## 1.6 Auditor's preliminary concerns (top 10)

Numbered from most to least urgent. Detailed framework treatment in `01-audit-framework.md`.

1. **No reverse-direction safety net.** The single most expensive class of error in cross-wave survey work — a reversed scale not flipped, or flipped the wrong way — is not caught anywhere in the pipeline. `safe_reverse_4pt` does what its name says regardless of whether the underlying raw coding is what the YAML claims. Validation infrastructure (correlation-based `validate_transformation()`, anchor diagnostics) exists in fragments but is not run automatically and has no anchor-variable layer.

2. **No machine-readable codebook.** Codebooks are PDFs and Word docs. Verbatim CSVs are hand-curated. Nothing diffs the YAML against the source codebook. Every YAML claim about scale direction, value labels, and missing codes is unverified.

3. **No CI / no test runner.** testthat is not in renv; the existing test files cannot run. The two GitHub workflows are Claude-Code reviewers, not build pipelines. There is no automated gate on PRs.

4. **Stale W6 builder is a live data-corruption hazard.** `create_wave_rds.R` writes `data/processed/w6.rds` from Cambodia alone; `build_abs_w6.R` writes the same path from all 12 countries. Whichever runs last wins. No safeguard.

5. **YAML schema is informal.** `validate_harmonize_spec()` does not reject unknown keys, has no version field, does not catch typos in `harmonize:`/`source:`/etc. A misspelled top-level key produces all-NA without complaint.

6. **No provenance.** No input hash, output hash, commit hash, or spec hash recorded with `outputs/master_w*.rds` or `data/processed/*_harmonized.rds`. A paper citing "the harmonized ABS dataset" cannot, even in principle, identify which version.

7. **Two parallel ABS spec dirs.** `src/config/abs/harmonize/` (3 files, legacy/scratch) vs `harmonize_validated/` (28 production files). The "validated" suffix is asserted, not enforced — no script reproduces the validation that earned the name. New users will not know which dir is canonical.

8. **Cross-wave continuity is unmeasured.** Marginal-distribution drift between consecutive waves (TVD/KS) is not computed anywhere. Question-wording changes that should fail validation cannot be distinguished from real political change.

9. **OOR / unmapped-wave warnings rely on R's `warning()` and `message()` channels.** Several scripts in the repo use `suppressWarnings()` or `suppressPackageStartupMessages()`. Any warning that traverses such a wrapper is silent. The `oob_log_path` mechanism is opt-in; the per-survey runners I inspected (`2_harmonize_all.R`) do not always set it.

10. **ABS post-hoc country exclusions are buried.** The `gate_contact_influential` country exclusion logic for W2 is inside the `if (sys.nframe() == 0)` block at the bottom of `2_harmonize_all.R:316-324`. It runs only when the script is invoked from the CLI. Anyone calling the helpers interactively gets unfiltered data. This is a brittle pattern with no test.

---

## What I deliberately did not do in this pass

- I did not read every YAML. I read 2 in full (`MODEL_VARIABLE.yml`, `democracy_satisfaction.yml`) and grep-sampled `authoritarianism.yml`. A full per-spec audit is Phase 2 work.
- I did not load the harmonized RDS files and inspect distributions. That belongs in the runtime audit (Layer 3 / Layer 5 of the framework).
- I did not run the harmonization end-to-end. That's a determinism check for Phase 2.
- I did not inspect the WVS/Afro/LBS/etc. per-survey loaders in detail. The patterns I saw in ABS appear to repeat (per CLAUDE.md and the `data_prep_modules/` subdirs), but I should not generalize without per-survey verification.
- I did not audit downstream paper code (`papers/`, `results/paper3_task*.R`). That's outside scope.

---

**Recommendation for next phase.** The framework in `01-audit-framework.md` should foreground (1) reverse-direction diagnostics with anchor variables, (2) machine-readable codebook reconciliation, and (3) provenance + CI. The other layers are necessary but those three are where silent errors hide.
