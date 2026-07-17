# KLoSA Harmonization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harmonize a focused RD variable set from raw KLoSA waves W1–W9 into a person-wave dataset (`data/processed/klosa_harmonized.rds`) plus a cross-wave instrument-stability audit, serving Paper 9 ("Does a pension buy a citizen?").

**Architecture:** Reuse the shared harmonization engine unchanged. A per-survey module (`0_load_waves` → `2_harmonize_all` → `99_create_final_dataset`) drives YAML specs in `src/config/klosa/harmonize/`. Because KLoSA is a genuine panel, the harmonized `pid` column rides through the normal per-wave stacking, yielding long person-wave rows suitable for pooled RD with individual-clustered SEs. **No engine code changes.**

**Tech Stack:** R (`renv`), `haven` (SPSS I/O), `yaml`, `dplyr`, `here`, `arrow`. Run everything via `Rscript` (no R MCP).

## Global Constraints

- Survey slug is `klosa` everywhere (config dir, `outputs/klosa/`, `data/klosa/`, manifest, validation `survey=` argument).
- Waves: harmonize **W1–W9** (biennial). Wave-list keys are `w1..w9`; raw column prefixes are zero-padded `w01..w09`. Wave→year map: `w1=2006, w2=2008, w3=2010, w4=2012, w5=2014, w6=2016, w7=2018, w8=2020, w9=2022`.
- Final dataset stores `wave` = integer 1..9 and `year` = 2006..2022. Analysis window is `wave >= 2`; W1 is a pure no-pension placebo.
- `haven::read_sav()` — the KLoSA English files use `_e` suffix; read normally (no forced `latin1`). If value labels come back mojibake, retry with `encoding = "UTF-8"`.
- Every YAML variable MUST declare `missing.use_convention` (engine hard-errors otherwise) and a `qc.valid_range` (or `qc.skip_range_check: true` for IDs/amounts) — a missing range only warns but leaves bad data.
- KLoSA is **standalone**: it cannot row-bind with the political-attitude surveys. Record this caveat in docs + CLAUDE.md.
- Treatment (CORRECTED by Task 2 — supersedes the original "G→E relocation" story): harmonize BOTH modules, G-block is the named default. Default `basic_pension_receipt`=`G111` / `_amount`=`G112` / `_couple`=`G113`, present **W2–W9** (consistent; spans the diff-in-disc window). Alternate `basic_pension_receipt_eblock`=`E111` / `_amount_eblock`=`E113`, **W5–W9** only. They agree ~92%+ where both exist. ⚠️ G111 is screener-gated (NA=didn't apply) → KIPA-style conditional-vs-population denominator; document it. Exact per-wave names + codings come from `outputs/klosa/variable_map.csv`.
- Commit messages: **no** `Co-Authored-By` / "Generated with" attribution (repo rule).
- Work stays on branch `feat/klosa-harmonization`.

---

## File Structure

| File | Responsibility |
|---|---|
| `data/klosa/raw/w0N_e.sav` (W1–W9, +`w05_new_e.sav`) | Staged raw inputs (copied from Downloads zip). `w05_new_e.sav` (W5 refresher cohort) is staged but intentionally **not** loaded by `0_load_waves.R` — excluded, documented in `docs/surveys/klosa.md` "Known limitations" |
| `src/r/data_prep_modules/klosa/00_probe_variables.R` | Discovery: read wave metadata, resolve every source var + value scale + missing codes → `outputs/klosa/variable_map.csv` |
| `src/r/data_prep_modules/klosa/0_load_waves.R` | `load_klosa_waves()` → `list(w1=…, …, w9=…)` |
| `src/r/data_prep_modules/klosa/2_harmonize_all.R` | Runner: `run_klosa_harmonization()`; writes `outputs/klosa/master_wN.rds` |
| `src/r/data_prep_modules/klosa/99_create_final_dataset.R` | Stack → add year, derive indices → `data/processed/klosa_harmonized.rds` + parquet; manifest; validation; post-harmonize gate |
| `src/config/klosa/harmonize/identifiers.yml` | `pid`, `hhid`, weights |
| `src/config/klosa/harmonize/demographics.yml` | sex, birth_year, age, education, marital, region, urban_rural, hh_size, home ownership |
| `src/config/klosa/harmonize/participation.yml` | 6 membership items + none + frequencies (the outcome) |
| `src/config/klosa/harmonize/pension_basic.yml` | receipt / amount / self-or-couple / application (treatment) — the G→E mapping |
| `src/config/klosa/harmonize/pension_other.yml` | National Pension receipt+amount (confound) |
| `src/config/klosa/harmonize/income_assets.yml` | household income + asset components (means-test ingredients) |
| `src/config/klosa/harmonize/health.yml` | self-rated health, ADL/IADL |
| `src/config/klosa/harmonize/work.yml` | employment / retirement status |
| `src/r/data_prep_modules/klosa/audit_instrument_stability.R` | Cross-wave stem+scale comparison for participation + treatment → `outputs/klosa/instrument_stability_audit.md` |
| `data/klosa/questionnaire_text/klosa_verbatim_items.csv` | Mandatory verbatim dictionary (one row per harmonized_name × wave) |
| `docs/surveys/klosa.md` | Per-survey doc |

**Discovery-first note (not a placeholder):** exact per-wave raw variable names and value codes are only knowable by reading the codebooks. **Task 1 produces `outputs/klosa/variable_map.csv`, and the spec-writing tasks (3–6) fill their `source:` blocks and `recode` mappings from it.** This mirrors the repo's own "extract → generate YAML → review" workflow and executes C Desktop's "check the codebooks before writing anything."

---

### Task 1: Stage raw data + scaffold directories

**Files:**
- Create: `data/klosa/raw/` (populated), `src/config/klosa/harmonize/`, `data/klosa/questionnaire_text/`, `src/r/data_prep_modules/klosa/`, `outputs/klosa/`

- [ ] **Step 1: Extract the raw waves from the Downloads zip into the repo**

```bash
cd /Users/jeffreystark/Development/Research/survey-data-prep
mkdir -p data/klosa/raw data/klosa/questionnaire_text src/config/klosa/harmonize src/r/data_prep_modules/klosa outputs/klosa
unzip -o "$HOME/Downloads/KLoSA 1-9th wave (SPSS).zip" \
  'w0[1-9]_e.sav' 'w05_new_e.sav' -d data/klosa/raw
ls -1 data/klosa/raw
```

- [ ] **Step 2: Verify all 9 waves are present and readable by haven**

Run:
```bash
Rscript -e 'library(haven); fs <- sprintf("data/klosa/raw/w0%d_e.sav", 1:9); stopifnot(all(file.exists(fs))); for (f in fs) { d <- read_sav(f, n_max=0); cat(basename(f), ncol(d), "cols\n") }'
```
Expected: prints `w01_e.sav … w09_e.sav` each with a column count in the thousands, no error.

- [ ] **Step 3: Add a raw-data README + .gitignore for the large .sav files**

The repo commits specs/scripts, not multi-hundred-MB raw SPSS. Create `data/klosa/raw/README.md`:
```markdown
# KLoSA raw waves
Source: KLoSA 1–9th wave English SPSS release (`~/Downloads/KLoSA 1-9th wave (SPSS).zip`).
Files `w01_e.sav … w09_e.sav` (+ `w05_new_e.sav`) are the main respondent files.
Not committed (size). Re-extract with the unzip command in the Task-1 plan step.
```
Check whether `data/` .sav files are already git-ignored:
```bash
git check-ignore data/klosa/raw/w01_e.sav || echo "NOT IGNORED — add pattern"
```
If not ignored, append `data/klosa/raw/*.sav` to the repo `.gitignore`.

- [ ] **Step 4: Commit the scaffold**

```bash
git add src/config/klosa src/r/data_prep_modules/klosa data/klosa/raw/README.md .gitignore
git commit -m "chore(klosa): scaffold dirs and stage raw waves W1-W9"
```

---

### Task 2: Discovery probe — resolve every source variable, value scale, and missing convention

**Files:**
- Create: `src/r/data_prep_modules/klosa/00_probe_variables.R`
- Produces: `outputs/klosa/variable_map.csv` (columns: `concept, target_id, w1..w9 source var, value_labels_w?, notes`) and console stability summaries.

**Interfaces:**
- Produces `outputs/klosa/variable_map.csv` — consumed by Tasks 3–6 to fill YAML `source:` blocks and `recode` mappings.

- [ ] **Step 1: Write the probe script**

```r
# src/r/data_prep_modules/klosa/00_probe_variables.R
# Discovery pass: locate every RD variable across W1-W9, dump value scales,
# and resolve missing-code conventions. Executes "check the codebooks first".
suppressMessages({library(haven); library(dplyr); library(here); library(purrr); library(tidyr)})

waves <- sprintf("w%d", 1:9)
paths <- setNames(here("data","klosa","raw", sprintf("w0%d_e.sav", 1:9)), waves)
meta  <- map(paths, ~ read_sav(.x, n_max = 0))

# variable table per wave (name, label)
var_tab <- imap_dfr(meta, function(d, wv) tibble(
  wave = wv, var = names(d),
  label = map_chr(d, ~ { l <- attr(.x, "label"); if (is.null(l)) "" else l })))

# helper: value labels for one var in one wave
vlabs <- function(wv, v) {
  d <- meta[[wv]]; if (!v %in% names(d)) return("(absent)")
  l <- attr(d[[v]], "labels"); if (is.null(l)) "(none)" else paste(sprintf("%s=%s", l, names(l)), collapse=" | ")
}

# 1) treatment: G111/G112/G113 (W1-W4) vs E111/E113 (W5-W9). Print label + value scale.
cat("\n===== TREATMENT (basic pension) =====\n")
for (i in 1:9) { wv <- waves[i]; for (v in sprintf("w0%d%s", i, c("G111","G112","G113","E111","E113"))) {
  lab <- var_tab %>% filter(wave==wv, var==v) %>% pull(label)
  cat(sprintf("  %-12s [%s] %s\n", v, if(length(lab)) lab else "ABSENT", vlabs(wv, v))) } }

# 2) National Pension confound: E033/E035
cat("\n===== NATIONAL PENSION (confound) =====\n")
for (i in 1:9) { wv<-waves[i]; for (v in sprintf("w0%d%s", i, c("E033","E035"))) {
  lab <- var_tab %>% filter(wave==wv, var==v) %>% pull(label); cat(sprintf("  %-10s [%s] %s\n", v, if(length(lab)) lab else "ABSENT", vlabs(wv,v))) } }

# 3) participation battery A033m01-08 + A035_01-07, with value scale in W1 and W9
cat("\n===== PARTICIPATION (outcome) value scales W1 vs W9 =====\n")
for (v_suffix in c(sprintf("A033m%02d",1:8), sprintf("A035_%02d",1:7))) {
  v1 <- sprintf("w01%s", v_suffix); v9 <- sprintf("w09%s", v_suffix)
  cat(sprintf("  %-10s  W1[%s] %s\n             W9[%s] %s\n", v_suffix,
      if (v1 %in% names(meta$w1)) "ok" else "ABSENT", vlabs("w1", v1),
      if (v9 %in% names(meta$w9)) "ok" else "ABSENT", vlabs("w9", v9))) }

# 4) identifiers / demographics / weights — grep labels
cat("\n===== ID / WEIGHT / DEMOGRAPHIC candidates (W4) =====\n")
print(var_tab %>% filter(wave=="w4",
  grepl("^w04(pid|hhid|hid)|weight|^w04A002|birth|^w04A00[0-9]|marital|educat|region|resident|household size|self-?rated health|ADL|IADL|econom.*activ|work", var, ignore.case=TRUE) |
  grepl("weight|birth|marital|education|region|household member|self-rated health|activities of daily", label, ignore.case=TRUE)) %>%
  select(var, label), n = 80, width = 200)

# 5) build the resolved map (fill after eyeballing above); write a starter CSV
resolved <- tibble(
  concept = c("treatment","treatment","confound","outcome"),
  target_id = c("basic_pension_receipt","basic_pension_amount","natl_pension_receipt","participation_civic"),
  rule = c("G111(w1-4)->E111(w5-9)","G112(w1-4)->E113(w5-9)","E033 all waves","A033m06 all waves"))
write.csv(resolved, here("outputs","klosa","variable_map.csv"), row.names = FALSE)
cat("\nStarter variable_map.csv written — extend it with the resolved names above.\n")
```

- [ ] **Step 2: Run the probe and read the output**

Run: `Rscript src/r/data_prep_modules/klosa/00_probe_variables.R 2>&1 | tee outputs/klosa/probe_console.txt`
Expected: prints treatment value scales showing `G111`/`G112` populated & labeled "Basic Old-Age Pension" in W1–W4 and `E111`/`E113` labeled "Basic Pension (Ex Basic Old-Age Pension)" in W5–W9; participation A033/A035 value scales for W1 and W9; a candidate list of id/weight/demographic vars.

- [ ] **Step 3: Record the three load-time facts the specs depend on**

From the probe console, write into `outputs/klosa/variable_map.csv` (extend the CSV) the resolved answers to §7 of the spec:
1. exact `pid` and household-id variable names (and whether `pid` is identical across W1–W9);
2. the weight variable name(s) and whether they live in `w0N` (if absent there, note "weights in Lt0N — out of scope unless needed");
3. the numeric **missing codes** used by KLoSA (from the value-label dumps, e.g. `-9`, `-8` and any item-specific "Refuse"/"Don't know"/"Not applicable" codes) → this becomes `missing_conventions.treat_as_na.codes`.

- [ ] **Step 4: Commit the probe + map**

```bash
git add src/r/data_prep_modules/klosa/00_probe_variables.R outputs/klosa/variable_map.csv outputs/klosa/probe_console.txt
git commit -m "feat(klosa): variable discovery probe + resolved variable map"
```

---

### Task 3: Wave loader

**Files:**
- Create: `src/r/data_prep_modules/klosa/0_load_waves.R`

**Interfaces:**
- Produces: `load_klosa_waves()` → named `list(w1=df, …, w9=df)`; each df is the raw wave with zero-padded `w0N…` columns. Consumed by Tasks 7–8.

- [ ] **Step 1: Write the loader (mirror the KGSS loader pattern)**

```r
# src/r/data_prep_modules/klosa/0_load_waves.R
# KLoSA: load raw main wave files W1-W9 -> named list(w1..w9)
library(here); library(haven)

load_klosa_waves <- function() {
  cat("\n── Loading KLoSA raw waves ──\n")
  waves <- list()
  for (i in 1:9) {
    wv <- sprintf("w%d", i)
    f  <- here("data","klosa","raw", sprintf("w0%d_e.sav", i))
    if (!file.exists(f)) stop("File not found: ", f)
    df <- read_sav(f)
    cat(sprintf("  %s: %s rows, %d cols\n", wv, format(nrow(df), big.mark=","), ncol(df)))
    waves[[wv]] <- df
  }
  waves
}

if (!interactive() && identical(environment(), globalenv())) {
  w <- load_klosa_waves()
  cat("\nLoaded:", paste(names(w), collapse=", "), "\n")
}
```

- [ ] **Step 2: Verify the loader returns 9 waves with `pid` present**

Run (substitute the real pid name from `variable_map.csv` if not `pid`):
```bash
Rscript -e 'source("src/r/data_prep_modules/klosa/0_load_waves.R"); w <- load_klosa_waves(); stopifnot(length(w)==9); pid <- "pid"; cat("pid present per wave:", paste(sapply(w, function(d) pid %in% names(d)), collapse=" "), "\n")'
```
Expected: 9 waves load; `pid present per wave: TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE TRUE` (if the id var differs, use the resolved name).

- [ ] **Step 3: Commit**

```bash
git add src/r/data_prep_modules/klosa/0_load_waves.R
git commit -m "feat(klosa): wave loader for W1-W9"
```

---

### Task 4: `identifiers.yml` + `demographics.yml`

**Files:**
- Create: `src/config/klosa/harmonize/identifiers.yml`, `src/config/klosa/harmonize/demographics.yml`

**Interfaces:**
- Consumes: `variable_map.csv` (Task 2) for exact source names + missing codes.
- Produces harmonized ids/covariates: `pid`, `hhid`, `weight` (if in main file), `sex`, `birth_year`, `age`, `education`, `marital_status`, `region`, `urban_rural`, `hh_size`, `home_owner`.

- [ ] **Step 1: Write `identifiers.yml`** — `pid` and `hhid` with `qc.skip_range_check: true`. Fill `<PID_VAR>`/`<HHID_VAR>`/missing codes from `variable_map.csv`.

```yaml
schema_version: 1
missing_conventions:
  treat_as_na:
    codes: [-9, -8]   # REPLACE with the codes resolved in Task 2
    description: "KLoSA missing codes (resolve in probe): e.g. -9 no response, -8 don't know"
variables:
  - id: pid
    concept: identifiers
    description: "KLoSA stable personal ID (constant across waves; panel linkage key)"
    type: nominal
    source: {w1: w01pid, w2: w02pid, w3: w03pid, w4: w04pid, w5: w05pid, w6: w06pid, w7: w07pid, w8: w08pid, w9: w09pid}
    missing: {use_convention: treat_as_na}
    harmonize: {default: {method: identity}}
    qc: {skip_range_check: true}
  - id: hhid
    concept: identifiers
    description: "Household ID within wave"
    type: nominal
    source: {w1: w01hhid, w2: w02hhid, w3: w03hhid, w4: w04hhid, w5: w05hhid, w6: w06hhid, w7: w07hhid, w8: w08hhid, w9: w09hhid}
    missing: {use_convention: treat_as_na}
    harmonize: {default: {method: identity}}
    qc: {skip_range_check: true}
```
(If Task 2 shows the pid var is literally `pid` in every file, the `w0Npid` names still resolve because each wave df carries its own `pid`; adjust source values to the resolved names.)

- [ ] **Step 2: Write `demographics.yml`** — one variable block per covariate, following the KGSS `demographics.yml` shape (see `src/config/kgss/harmonize/demographics.yml`). Fully-worked example for the running variable:

```yaml
  - id: age
    concept: demographics
    description: "Respondent age in years at interview (running variable for the RD; integer years only)"
    type: continuous
    note: "Forcing variable. A002_age = survey year minus birth year (A002y). No birth month located -> integer granularity; flag as an RD limitation."
    source: {w1: w01A002_age, w2: w02A002_age, w3: w03A002_age, w4: w04A002_age, w5: w05A002_age, w6: w06A002_age, w7: w07A002_age, w8: w08A002_age, w9: w09A002_age}
    missing: {use_convention: treat_as_na}
    harmonize: {default: {method: identity}}
    qc: {valid_range: [40, 120]}
```
Repeat the block for `birth_year` (source `w0NA002y`, range `[1900, 1985]`), `sex`, `education`, `marital_status`, `region`, `urban_rural`, `hh_size`, `home_owner`, using the resolved source names + value scales from `variable_map.csv`. Use `method: recode` where a raw scale must be normalized (e.g. sex coded 1/5 → 1/2), else `method: identity`.

- [ ] **Step 3: Harmonize just these two specs and check output**

Run:
```bash
Rscript -e '
source("src/r/data_prep_modules/2_harmonize_all.R")
source("src/r/data_prep_modules/klosa/0_load_waves.R")
w <- load_klosa_waves()
specs <- c("src/config/klosa/harmonize/identifiers.yml","src/config/klosa/harmonize/demographics.yml")
res <- harmonize_all_specs(w, specs=specs, silent=TRUE)
wide <- stack_harmonized_wide(res, w)
d <- wide$w5
cat("w5 cols:", paste(setdiff(names(d), c("wave","row_id")), collapse=", "), "\n")
cat("age range:", paste(range(d$age, na.rm=TRUE), collapse="-"), "\n")
cat("pid non-NA:", sum(!is.na(d$pid)), "/", nrow(d), "\n")'
```
Expected: columns include `pid, hhid, age, sex, education, …`; age range roughly 45–110; `pid` non-NA ≈ all rows. No validation errors printed.

- [ ] **Step 4: Commit**

```bash
git add src/config/klosa/harmonize/identifiers.yml src/config/klosa/harmonize/demographics.yml
git commit -m "feat(klosa): identifiers + demographics specs"
```

---

### Task 5: `participation.yml` (outcome battery)

**Files:**
- Create: `src/config/klosa/harmonize/participation.yml`

**Interfaces:**
- Produces per-type membership `part_religious, part_social_club, part_leisure, part_alumni, part_volunteer, part_civic` (each 0/1), `part_none` (0/1), and per-type frequency `partfreq_*`. `participation_count`/`participation_any` are derived later (Task 7 §99).

- [ ] **Step 1: Confirm the membership coding from the probe output**

From Task 2 Step 2 console, read the value scale of `A033m01`. KLoSA multi-response membership items are typically `0=no / 1=yes` (or `1=yes` with blank=no). Note the exact coding; it drives the `recode`/`identity` choice below.

- [ ] **Step 2: Write `participation.yml`** — worked example for the civic item (the "buy a citizen" outcome) and one frequency item; replicate for the other five group types.

```yaml
schema_version: 1
missing_conventions:
  treat_as_na:
    codes: [-9, -8]   # match identifiers.yml (resolved in Task 2)
    description: "KLoSA missing codes"
variables:
  - id: part_civic
    concept: participation
    description: "Participates in political parties / NGOs / interest groups (1=yes, 0=no). The narrow civic-participation outcome."
    type: binary
    source: {w1: w01A033m06, w2: w02A033m06, w3: w03A033m06, w4: w04A033m06, w5: w05A033m06, w6: w06A033m06, w7: w07A033m06, w8: w08A033m06, w9: w09A033m06}
    missing: {use_convention: treat_as_na}
    harmonize:
      default: {method: recode, mapping: {1: 1, 0: 0}}   # ADJUST to real coding (e.g. {1:1, 5:0})
    qc: {valid_range: [0, 1]}
  - id: partfreq_civic
    concept: participation
    description: "Frequency of participation in political/NGO/interest groups (raw KLoSA frequency scale)"
    type: ordinal
    note: "Confirm scale direction + range from probe; A035_06 pairs with A033m06."
    source: {w1: w01A035_06, w2: w02A035_06, w3: w03A035_06, w4: w04A035_06, w5: w05A035_06, w6: w06A035_06, w7: w07A035_06, w8: w08A035_06, w9: w09A035_06}
    missing: {use_convention: treat_as_na}
    harmonize: {default: {method: identity}}
    qc: {valid_range: [1, 9]}   # set to the real range from probe
```
Add blocks for `part_religious` (A033m01), `part_social_club` (m02), `part_leisure` (m03), `part_alumni` (m04), `part_volunteer` (m05), `part_none` (m08), and their `A035_0N` frequencies.

- [ ] **Step 3: Harmonize and verify the battery exists in W1 (placebo) and is 0/1**

Run:
```bash
Rscript -e '
source("src/r/data_prep_modules/2_harmonize_all.R"); source("src/r/data_prep_modules/klosa/0_load_waves.R")
w <- load_klosa_waves()
res <- harmonize_all_specs(w, specs="src/config/klosa/harmonize/participation.yml", silent=TRUE)
wide <- stack_harmonized_wide(res, w)
for (wv in c("w1","w5","w9")) { d<-wide[[wv]]; cat(wv,"part_civic table:\n"); print(table(d$part_civic, useNA="ifany")) }'
```
Expected: `part_civic` present and coded {0,1,NA} in all three waves — including W1 (2006), confirming the outcome exists in the placebo wave.

- [ ] **Step 4: Commit**

```bash
git add src/config/klosa/harmonize/participation.yml
git commit -m "feat(klosa): social/civic participation outcome battery"
```

---

### Task 6: `pension_basic.yml` (treatment — both blocks, G-block default) + `pension_other.yml` (confound)

**⚠️ CORRECTED by Task 2 — the original "G→E relocation" design was wrong.** The G-block (`G111`/`G112`/`G113`) is present and consistent **W2–W9**; the E-block income line (`E111`/`E113`) exists **only W5–W9**; they agree ~92%+ where both exist. Decision (Jeff): harmonize BOTH, G-block is the **named default**. Use `outputs/klosa/variable_map.csv` for exact per-wave names + codings.

**Files:**
- Create: `src/config/klosa/harmonize/pension_basic.yml`, `src/config/klosa/harmonize/pension_other.yml`

**Interfaces:**
- Produces default (G-block, W2–W9): `basic_pension_receipt` (0/1), `basic_pension_amount` (10k-won), `basic_pension_couple` (0/1). Alternate (E-block, W5–W9): `basic_pension_receipt_eblock` (0/1), `basic_pension_amount_eblock` (10k-won). Confound: `natl_pension_receipt` (0/1), `natl_pension_amount`.

- [ ] **Step 1: Write `pension_basic.yml`** — G-block default across W2–W9 (`w1: null` = pure placebo), plus the E-block alternate for W5–W9. Both documented with the screener/denominator caveat.

```yaml
schema_version: 1
missing_conventions:
  treat_as_na:
    codes: [-9, -8]   # confirmed by Task 2
    description: "KLoSA missing codes: -9 DK, -8 Refuse"
variables:
  - id: basic_pension_receipt
    concept: pension_basic
    description: "Received Basic (Old-Age) Pension — G-block default (1=currently receiving, 0=not). Treatment/first-stage."
    type: binary
    note: >
      NAMED DEFAULT = G-block G111, present W2-W9 (consistent across the 2014
      reform; the item keeps the 'Basic Old-Age Pension' label post-2014 but
      tracks the renamed Basic Pension). G111 categories: 1=currently receiving,
      3=will receive at pension age, 5=not entitled. ⚠️ SCREENER: G111 is asked
      of applicants only, so its NA is a SKIP (didn't apply), NOT a refusal —
      mean(x, na.rm=TRUE) is conditional-on-application (~92%), NOT a population
      rate. Population reading treats skip->0 (paper-side choice; document KIPA-
      style, cf. src/r/lookups/kipa_bribery_series.R). Cross-check: E-block
      basic_pension_receipt_eblock agrees ~92%+ where both exist (W5-W9). W1
      (2006) predates any pension -> null placebo.
    source:
      w1: null
      w2: w02G111
      w3: w03G111
      w4: w04G111
      w5: w05G111
      w6: w06G111
      w7: w07G111
      w8: w08G111
      w9: w09G111
    missing: {use_convention: treat_as_na}
    harmonize:
      default: {method: recode, mapping: {1: 1, 3: 0, 5: 0}}   # 1=receiving->1; 3,5->0; -8/-9 masked by convention -> NA (=skip)
    qc:
      valid_range: [0, 1]
      skip_unmapped_check: true   # W1 intentionally unmapped (placebo)
  - id: basic_pension_receipt_eblock
    concept: pension_basic
    description: "Received Basic Pension — E-block income-module alternate (W5-W9), 1=received in last year, 0=blank/not received."
    type: binary
    note: >
      ALTERNATE (robustness/cross-check), W5-W9 only. E111 is a checkbox: 1=Check
      (received, paired 1:1 with non-NA E113 amount), blank=not received. Recode
      1->1 and treat blank as 0 (blank=not-received inference; true item-
      nonresponse is indistinguishable). Not present pre-2014 -> W1-W4 null.
    source: {w1: null, w2: null, w3: null, w4: null, w5: w05E111, w6: w06E111, w7: w07E111, w8: w08E111, w9: w09E111}
    missing: {use_convention: treat_as_na}
    harmonize: {default: {method: recode, mapping: {1: 1}}}   # blank(NA)->stays NA; paper reads NA as 0 (documented)
    qc: {valid_range: [0, 1], skip_unmapped_check: true}
  - id: basic_pension_amount
    concept: pension_basic
    description: "Monthly average Basic (Old-Age) Pension benefit — G-block default (unit: 10,000 KRW). The dose."
    type: continuous
    note: "G-block default G112, W2-W9 (paired with basic_pension_receipt). Enables the dose (not on/off) framing across the whole panel."
    source: {w1: null, w2: w02G112, w3: w03G112, w4: w04G112, w5: w05G112, w6: w06G112, w7: w07G112, w8: w08G112, w9: w09G112}
    missing: {use_convention: treat_as_na}
    harmonize: {default: {method: identity}}
    qc: {valid_range: [0, 300], skip_unmapped_check: true}   # 10k-won units; widen if probe shows higher
  - id: basic_pension_amount_eblock
    concept: pension_basic
    description: "Monthly average Basic Pension — E-block income-module alternate (W5-W9), unit 10,000 KRW."
    type: continuous
    note: "Paired with basic_pension_receipt_eblock. W5 median ~9 (10k-won, ~90,000 KRW/mo) rising to ~25 by W9. Absent pre-2014."
    source: {w1: null, w2: null, w3: null, w4: null, w5: w05E113, w6: w06E113, w7: w07E113, w8: w08E113, w9: w09E113}
    missing: {use_convention: treat_as_na}
    harmonize: {default: {method: identity}}
    qc: {valid_range: [0, 300], skip_unmapped_check: true}
  - id: basic_pension_couple
    concept: pension_basic
    description: "Benefit is for the couple vs. the individual (1=couple, 0=individual). Affects the means test. G-block only (no E-block equivalent)."
    type: binary
    note: "G113, W2-W9. Raw: 1=Provided to the individual, 5=Provided to the couple. No E-block 'self or couple' flag exists."
    source: {w1: null, w2: w02G113, w3: w03G113, w4: w04G113, w5: w05G113, w6: w06G113, w7: w07G113, w8: w08G113, w9: w09G113}
    missing: {use_convention: treat_as_na}
    harmonize: {default: {method: recode, mapping: {1: 0, 5: 1}}}   # 1=individual->0, 5=couple->1
    qc: {valid_range: [0, 1], skip_unmapped_check: true}
```

- [ ] **Step 2: Write `pension_other.yml`** — National Pension receipt (`E033`) + amount (`E035`), all waves, so the age-linked contributory pension is not conflated with Basic Pension at 65.

```yaml
schema_version: 1
missing_conventions:
  treat_as_na: {codes: [-9, -8], description: "KLoSA missing codes"}
variables:
  - id: natl_pension_receipt
    concept: pension_other
    description: "Received National Pension benefit in the last year (1=yes, 0=no). Age-60/65 contributory confound — keep distinct from Basic Pension."
    type: binary
    note: "E033 is 4-category: 1=only monthly benefit, 2=only lump-sum, 3=received both, 4=no. Recode 'received any' = {1,2,3}->1, 4->0."
    source: {w1: w01E033, w2: w02E033, w3: w03E033, w4: w04E033, w5: w05E033, w6: w06E033, w7: w07E033, w8: w08E033, w9: w09E033}
    missing: {use_convention: treat_as_na}
    harmonize: {default: {method: recode, mapping: {1: 1, 2: 1, 3: 1, 4: 0}}}
    qc: {valid_range: [0, 1]}
  - id: natl_pension_amount
    concept: pension_other
    description: "Monthly average National Pension benefit (unit: 10,000 KRW)"
    type: continuous
    source: {w1: w01E035, w2: w02E035, w3: w03E035, w4: w04E035, w5: w05E035, w6: w06E035, w7: w07E035, w8: w08E035, w9: w09E035}
    missing: {use_convention: treat_as_na}
    harmonize: {default: {method: identity}}
    qc: {valid_range: [0, 1000]}
```

- [ ] **Step 3: Harmonize and verify the relocation produces sensible per-wave receipt rates**

Run:
```bash
Rscript -e '
source("src/r/data_prep_modules/2_harmonize_all.R"); source("src/r/data_prep_modules/klosa/0_load_waves.R")
w <- load_klosa_waves()
res <- harmonize_all_specs(w, specs=c("src/config/klosa/harmonize/pension_basic.yml","src/config/klosa/harmonize/pension_other.yml"), silent=TRUE)
wide <- stack_harmonized_wide(res, w)
for (wv in names(wide)) { d<-wide[[wv]]; cat(sprintf("%s  basic_receipt: mean=%.3f n=%d | amount median=%s\n", wv, mean(d$basic_pension_receipt==1, na.rm=TRUE), sum(!is.na(d$basic_pension_receipt)), median(d$basic_pension_amount, na.rm=TRUE))) }'
```
Expected: `w1` basic_receipt all-NA (n=0, placebo); `w2`–`w4` show a modest receipt rate (Basic Old-Age Pension, from 2008); `w5`–`w9` show a higher rate (Basic Pension, broader ≈ bottom-70% of 65+). A non-zero, monotone-ish jump across the 2014 boundary is the sanity check that the G→E mapping is wired correctly (NOT a stale/empty column).

- [ ] **Step 4: Commit**

```bash
git add src/config/klosa/harmonize/pension_basic.yml src/config/klosa/harmonize/pension_other.yml
git commit -m "feat(klosa): basic-pension treatment (G->E relocation) + national-pension confound"
```

---

### Task 7: `income_assets.yml`, `health.yml`, `work.yml` (means-test ingredients + controls)

**Files:**
- Create: `src/config/klosa/harmonize/income_assets.yml`, `health.yml`, `work.yml`

**Interfaces:**
- Produces `hh_income_total`, `assets_financial`, `assets_realestate` (means-test ingredients), `srh` (self-rated health), `adl_limit`, `iadl_limit`, `work_status`.

- [ ] **Step 1: Write the three specs** from `variable_map.csv`, each following the demographics shape. Income/asset items use `method: identity` with a generous `qc.valid_range` (KRW 10k-won units); self-rated health uses `method: identity` (note the direction — KLoSA SRH is usually 1=very good … 5=very poor; record it). Example block:

```yaml
  - id: hh_income_total
    concept: income_assets
    description: "Total household income last year (unit: 10,000 KRW). Ingredient for the bottom-70% means-test approximation (paper-side)."
    type: continuous
    source: {w1: w01hhinc, w2: w02hhinc, w3: w03hhinc, w4: w04hhinc, w5: w05hhinc, w6: w06hhinc, w7: w07hhinc, w8: w08hhinc, w9: w09hhinc}   # REPLACE with resolved names
    missing: {use_convention: treat_as_na}
    harmonize: {default: {method: identity}}
    qc: {valid_range: [0, 1000000]}
```

- [ ] **Step 2: Harmonize the three specs and check ranges are non-degenerate**

Run:
```bash
Rscript -e '
source("src/r/data_prep_modules/2_harmonize_all.R"); source("src/r/data_prep_modules/klosa/0_load_waves.R")
w <- load_klosa_waves()
res <- harmonize_all_specs(w, specs=list.files("src/config/klosa/harmonize", pattern="income_assets|health|work", full.names=TRUE), silent=TRUE)
wide <- stack_harmonized_wide(res, w); d <- wide$w5
for (v in c("hh_income_total","srh","work_status")) cat(v, ": ", paste(range(d[[v]], na.rm=TRUE), collapse="-"), " nNA=", sum(is.na(d[[v]])), "\n")'
```
Expected: each variable present with a plausible, non-degenerate range and a sane NA count.

- [ ] **Step 3: Commit**

```bash
git add src/config/klosa/harmonize/income_assets.yml src/config/klosa/harmonize/health.yml src/config/klosa/harmonize/work.yml
git commit -m "feat(klosa): income/assets means-test ingredients + health/work controls"
```

---

### Task 8: Harmonization runner `2_harmonize_all.R`

**Files:**
- Create: `src/r/data_prep_modules/klosa/2_harmonize_all.R`

**Interfaces:**
- Produces `run_klosa_harmonization()` and, when run directly, `outputs/klosa/master_w1.rds … master_w9.rds`.

- [ ] **Step 1: Write the runner (mirror `src/r/data_prep_modules/kgss/2_harmonize_all.R`)**

```r
# src/r/data_prep_modules/klosa/2_harmonize_all.R
library(here); library(yaml); library(dplyr)
source(here::here("src/r/data_prep_modules/2_harmonize_all.R"))
source(here::here("src/r/data_prep_modules/klosa/0_load_waves.R"))

run_klosa_harmonization <- function(output_format = "wide", silent = FALSE) {
  run_survey_harmonization("klosa", load_klosa_waves, output_format, silent)
}

if (sys.nframe() == 0) {
  cat(strrep("=", 70), "\nKLoSA HARMONIZATION PIPELINE\n", strrep("=", 70), "\n\n", sep="")
  waves <- load_klosa_waves()
  specs <- list_survey_specs("klosa")
  cat(sprintf("Found %d specs: %s\n\n", length(specs), paste(basename(specs), collapse=", ")))
  oob_log_path <- here::here("outputs","klosa","oob_log.csv")
  dir.create(dirname(oob_log_path), showWarnings = FALSE, recursive = TRUE)
  results <- harmonize_all_specs(waves, specs = specs, oob_log_path = oob_log_path)
  harmonized_wide <- stack_harmonized_wide(results, waves)
  output_dir <- here::here("outputs","klosa"); dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
  for (wv in names(harmonized_wide)) {
    f <- file.path(output_dir, paste0("master_", wv, ".rds")); saveRDS(harmonized_wide[[wv]], f)
    cat(sprintf("  Saved %s: %s rows, %d vars\n", basename(f), format(nrow(harmonized_wide[[wv]]), big.mark=","), ncol(harmonized_wide[[wv]])-2))
  }
  cat("\n✅ KLoSA harmonization complete\n")
}
```

- [ ] **Step 2: Run the full harmonization**

Run: `Rscript src/r/data_prep_modules/klosa/2_harmonize_all.R 2>&1 | tail -30`
Expected: all specs process; `master_w1.rds … master_w9.rds` saved; any out-of-range coercions are logged (inspect `outputs/klosa/oob_log.csv` — should be empty or small/explainable). No spec validation failures.

- [ ] **Step 3: Commit**

```bash
git add src/r/data_prep_modules/klosa/2_harmonize_all.R
git commit -m "feat(klosa): harmonization runner"
```

---

### Task 9: Final dataset `99_create_final_dataset.R` (stack, derive, QA)

**Files:**
- Create: `src/r/data_prep_modules/klosa/99_create_final_dataset.R`

**Interfaces:**
- Produces `data/processed/klosa_harmonized.rds` + `.parquet`, `outputs/klosa/manifest.json`; derives `participation_count`, `participation_any`, `education_5cat`.

- [ ] **Step 1: Write the final-dataset script (adapt the KGSS `99_create_final_dataset.R`, changing survey slug, the wave→year map, and the derivations)**

```r
# src/r/data_prep_modules/klosa/99_create_final_dataset.R
library(here); library(dplyr); library(arrow)
source(here::here("src","r","utils","provenance.R"))
source(here::here("src","r","utils","spec_discovery.R"))
source(here::here("src","r","utils","education.R"))

YEAR_MAP <- c(w1=2006, w2=2008, w3=2010, w4=2012, w5=2014, w6=2016, w7=2018, w8=2020, w9=2022)

output_dir <- here("outputs","klosa")
wave_files <- sort(list.files(output_dir, pattern="^master_w[1-9]\\.rds$", full.names=TRUE))
if (length(wave_files) == 0) stop("No master files in outputs/klosa/. Run 2_harmonize_all.R first.")

wave_list <- list()
for (f in wave_files) {
  wv <- gsub("master_|\\.rds", "", basename(f)); df <- readRDS(f)
  df$country <- "KOR"; df$year <- YEAR_MAP[[wv]]; df$wave <- as.integer(gsub("w","",wv))
  wave_list[[wv]] <- df
}
klosa <- bind_rows(wave_list) %>% select(-row_id)
klosa <- klosa %>% mutate(across(where(~ inherits(.x, "haven_labelled")),
                                 ~ as.numeric(haven::zap_labels(.x))))

# DERIVED participation indices (count of the 6 substantive group memberships)
memb <- intersect(c("part_religious","part_social_club","part_leisure","part_alumni","part_volunteer","part_civic"), names(klosa))
if (length(memb) > 0) {
  klosa <- klosa %>% mutate(
    participation_count = rowSums(across(all_of(memb)), na.rm = TRUE),
    participation_any   = as.integer(participation_count > 0))
}
# DERIVED shared 5-category education (if a KLoSA education ladder exists)
# NOTE: add an edu5_from_klosa() mapping in src/r/utils/education.R keyed to the
# KLoSA education codes resolved in Task 2 before enabling this block.
if ("education" %in% names(klosa) && exists("edu5_from_klosa")) {
  klosa <- klosa %>% mutate(education_5cat = edu5_from_klosa(education),
                            education_5cat_01 = edu5_to_01(education_5cat))
}

# SUMMARY
print(klosa %>% group_by(wave, year) %>% summarise(n=n(), .groups="drop") %>% as.data.frame())
cat(sprintf("Total: %s person-waves, %d distinct pid\n",
            format(nrow(klosa), big.mark=","), dplyr::n_distinct(klosa$pid)))

dir.create(here("data","processed"), showWarnings=FALSE, recursive=TRUE)
rds_path <- here("data","processed","klosa_harmonized.rds")
pq_path  <- here("data","processed","klosa_harmonized.parquet")
saveRDS(klosa, rds_path); arrow::write_parquet(klosa, pq_path)
saveRDS(klosa, here("outputs","klosa","klosa_harmonized.rds"))
cat(sprintf("✅ klosa_harmonized: %s rows, %d cols\n", format(nrow(klosa), big.mark=","), ncol(klosa)))

# MANIFEST (freshness — Layer 6d)
write_manifest(survey="klosa",
  inputs  = here("data","klosa","raw", sprintf("w0%d_e.sav", 1:9)),
  specs   = list_survey_specs("klosa"),
  outputs = c(rds_path, pq_path, here("outputs","klosa","klosa_harmonized.rds")),
  output_path = here("outputs","klosa","manifest.json"))

# OUTPUT INVARIANTS
source(here("src","r","data_prep_modules","2.5_validate_harmonization.R"))
tryCatch(run_validation(survey="klosa", save_report=TRUE, verbose=FALSE),
         error=function(e) message("validation step failed: ", e$message))

# LAYER-4 DIRECTION GATE (report-only by default)
source(here::here("src","r","audit","99_post_harmonize_gate.R"))
run_post_harmonize_gate("klosa", quiet_checks = TRUE)
```

- [ ] **Step 2: Run it and verify the person-wave structure + placebo**

Run: `Rscript src/r/data_prep_modules/klosa/99_create_final_dataset.R 2>&1 | tail -40`
Then check:
```bash
Rscript -e 'd <- readRDS("data/processed/klosa_harmonized.rds"); cat("rows:", nrow(d), "distinct pid:", dplyr::n_distinct(d$pid), "\n"); cat("waves:", paste(sort(unique(d$wave)), collapse=","), "\n"); print(tapply(d$basic_pension_receipt, d$wave, function(x) mean(x==1, na.rm=TRUE))); cat("W1 (placebo) basic receipt all-NA:", all(is.na(d$basic_pension_receipt[d$wave==1])), "\n")'
```
Expected: rows = sum of wave n's; `distinct pid` < rows (panel recurrence confirms linkage works); waves `1,2,…,9`; per-wave receipt means rise across the 2014 boundary; **W1 basic receipt all-NA = TRUE** (placebo intact).

- [ ] **Step 3: Commit**

```bash
git add src/r/data_prep_modules/klosa/99_create_final_dataset.R
git commit -m "feat(klosa): final person-wave dataset + derivations + QA hooks"
```

---

### Task 10: Instrument-stability audit (headline deliverable)

**Files:**
- Create: `src/r/data_prep_modules/klosa/audit_instrument_stability.R`
- Produces: `outputs/klosa/instrument_stability_audit.md`

**Interfaces:**
- Consumes the raw waves (label metadata). Produces a per-item stem-text + response-scale comparison across W1–W9 for the participation battery and the treatment, with an explicit PASS/CHANGED verdict per item and the G→E relocation documented.

- [ ] **Step 1: Write the audit script**

```r
# src/r/data_prep_modules/klosa/audit_instrument_stability.R
# Cross-wave stem-text + response-scale stability for the participation battery
# and the Basic Pension treatment. Answers: "is the instrument asked identically
# across the 2014 split?" (C Desktop's check-first question).
suppressMessages({library(haven); library(here); library(purrr); library(dplyr)})
waves <- sprintf("w%d", 1:9)
meta  <- map(setNames(here("data","klosa","raw", sprintf("w0%d_e.sav",1:9)), waves), ~ read_sav(.x, n_max=0))
lab  <- function(wv,v){ d<-meta[[wv]]; if(!v %in% names(d)) return(NA_character_); l<-attr(d[[v]],"label"); if(is.null(l)) "" else l }
vsc  <- function(wv,v){ d<-meta[[wv]]; if(!v %in% names(d)) return("(absent)"); l<-attr(d[[v]],"labels"); if(is.null(l)) "(none)" else paste(sprintf("%s=%s",l,names(l)),collapse=", ") }

# battery of (target, per-wave source suffix). Treatment encodes the G->E move.
items <- list(
  part_civic     = sprintf("A033m06"),
  part_religious = sprintf("A033m01"),
  partfreq_civic = sprintf("A035_06"),
  basic_receipt  = c(w1=NA, w2="G111", w3="G111", w4="G111", w5="E111", w6="E111", w7="E111", w8="E111", w9="E111"))

con <- file(here("outputs","klosa","instrument_stability_audit.md"), "w")
writeLines(c("# KLoSA instrument-stability audit (W1–W9)", "",
  "Verdict per item: **STABLE** if stem label + response scale are constant across present waves; **CHANGED** otherwise (with the wave where it moves).",""), con)
for (nm in names(items)) {
  spec <- items[[nm]]
  src_by_wave <- if (length(spec)==1) setNames(sprintf("w0%d%s", 1:9, spec), waves) else
                 setNames(ifelse(is.na(spec), NA, sprintf("w0%d%s", 1:9, spec)), waves)
  labels <- map_chr(waves, ~ if (is.na(src_by_wave[[.x]])) NA else lab(.x, src_by_wave[[.x]]))
  scales <- map_chr(waves, ~ if (is.na(src_by_wave[[.x]])) "(unmapped)" else vsc(.x, src_by_wave[[.x]]))
  present <- !is.na(labels)
  stable  <- length(unique(na.omit(labels)))<=1 && length(unique(scales[present]))<=1
  writeLines(c(sprintf("## %s — %s", nm, if (stable) "STABLE" else "CHANGED"), "",
    "| wave | source | label | response scale |","|---|---|---|---|",
    paste0("| ", waves, " | ", ifelse(is.na(src_by_wave),"—",src_by_wave), " | ",
           ifelse(is.na(labels),"—",labels), " | ", scales, " |"), ""), con)
}
close(con)
cat("Wrote outputs/klosa/instrument_stability_audit.md\n")
```

- [ ] **Step 2: Run the audit and read the verdicts**

Run: `Rscript src/r/data_prep_modules/klosa/audit_instrument_stability.R && sed -n '1,60p' outputs/klosa/instrument_stability_audit.md`
Expected: a markdown table per item; `part_*` items should read STABLE (or flag the exact wave they change); `basic_receipt` shows the label switching from "Basic Old-Age Pension" (W2–W4, G111) to "Basic Pension (Ex …)" (W5–W9, E111) — documented, not silent.

- [ ] **Step 3: Commit**

```bash
git add src/r/data_prep_modules/klosa/audit_instrument_stability.R outputs/klosa/instrument_stability_audit.md
git commit -m "feat(klosa): cross-wave instrument-stability audit (participation + treatment)"
```

---

### Task 11: Verbatim question dictionary

**Files:**
- Create: `data/klosa/questionnaire_text/klosa_verbatim_items.csv`

**Interfaces:**
- Standard 8-column format (matches `data/abs/questionnaire_text/abs_verbatim_items.csv`): `wave, question_id, harmonized_name, section, stem_text, item_text, response_scale, notes`. One row per harmonized_name × wave.

- [ ] **Step 1: Generate the dictionary scaffold from the harmonized specs + the audit**

Write `src/r/data_prep_modules/klosa/build_verbatim_scaffold.R` that, for each harmonized variable and each wave it maps, emits a row with `question_id` = the resolved raw var, `item_text` = the SPSS variable label (from the audit metadata), `response_scale` = the value-label string, and `notes` = "" (or the relocation note for the treatment). Write to the CSV.

- [ ] **Step 2: Run it and confirm the schema**

Run:
```bash
Rscript src/r/data_prep_modules/klosa/build_verbatim_scaffold.R
Rscript -e 'd <- read.csv("data/klosa/questionnaire_text/klosa_verbatim_items.csv"); cat("cols:", paste(names(d), collapse=","), "\nrows:", nrow(d), "\n"); stopifnot(all(c("wave","question_id","harmonized_name","section","stem_text","item_text","response_scale","notes") %in% names(d)))'
```
Expected: 8 columns exactly; one row per harmonized_name × mapped wave.

- [ ] **Step 3: Flag verbatim-backfill dependency in notes**

The repo standard prefers verbatim text from the **official KLoSA questionnaire** (not SPSS labels). If the English KLoSA questionnaire PDFs are not on disk, set `notes = "item_text from SPSS label; backfill verbatim from official questionnaire"` for affected rows and record the dependency in `docs/surveys/klosa.md` (a possible future Jeff download). The SPSS-label version is sufficient for the instrument-stability verdict.

- [ ] **Step 4: Commit**

```bash
git add src/r/data_prep_modules/klosa/build_verbatim_scaffold.R data/klosa/questionnaire_text/klosa_verbatim_items.csv
git commit -m "feat(klosa): verbatim question dictionary (scaffold from labels; verbatim backfill flagged)"
```

---

### Task 12: Documentation + registry

**Files:**
- Create: `docs/surveys/klosa.md`
- Modify: `CLAUDE.md` (survey-at-a-glance table + cross-survey gotchas), `README`/`docs/STRUCTURE.md` if they enumerate surveys

- [ ] **Step 1: Write `docs/surveys/klosa.md`** — coverage (vars, W1–W9, n, biennial 2006–2022), standalone/non-poolable caveat, the trust/participation scale notes, the G→E treatment relocation, the integer-age RD limitation, run commands (`0_load` implicit → `2_harmonize_all.R` → `99_create_final_dataset.R`), and the verbatim-backfill dependency.

- [ ] **Step 2: Add the CLAUDE.md survey-table row + gotchas**

Add to the "Surveys at a glance" table a `KLoSA | Complete | <n> vars, W1–W9 …` row linking `docs/surveys/klosa.md`, and to the cross-survey gotchas: (a) KLoSA is standalone (aging panel; no political items; cannot row-bind); (b) Basic Pension treatment relocates G-block→E-block at 2014; (c) KLoSA age is integer-years only.

- [ ] **Step 3: Verify links + run the freshness check**

Run:
```bash
Rscript src/r/audit/06_check_freshness.R --survey klosa 2>&1 | tail -5
grep -c "klosa" CLAUDE.md docs/surveys/klosa.md
```
Expected: freshness check reports klosa FRESH (manifest matches outputs); grep finds the new references.

- [ ] **Step 4: Commit**

```bash
git add docs/surveys/klosa.md CLAUDE.md docs/STRUCTURE.md
git commit -m "docs(klosa): survey doc + CLAUDE.md registry row and gotchas"
```

---

## Self-Review

**Spec coverage** (each spec §): purpose → Tasks 4–9 produce the RD variable set; standalone status → Task 12; source/waves W1–W9 → Tasks 1–3, YEAR_MAP in Task 9; architecture (no engine change, pid rides through) → Tasks 8–9; concept groups §5 → Tasks 4–7; treatment relocation §6.1 → Task 6 (per-wave source) + Task 10 (audit); dose/amount §6.2 → `basic_pension_amount` in Task 6; NP separation §6.3 → `pension_other.yml` Task 6; §7 load-time checks → Task 2 probe; deliverables §8 (module, specs, raw staged, processed rds, verbatim dict, stability audit, docs, QA) → Tasks 1–12; out-of-scope §9 respected (no EXIT/str/Lt, no wide restructure, RD stays paper-side); risks §10 surfaced (integer age note Task 4; relocation asserts Task 6/10; means-test ingredients only Task 7).

**Placeholder scan:** the `<PID_VAR>`, `-9/-8`, and `# ADJUST from probe` markers are **data-dependencies resolved by Task 2's probe**, not lazy placeholders — every one names the exact probe output that fills it and the mechanism is fully specified. This is the repo's mandated codebook-first workflow.

**Type consistency:** harmonized names are consistent across tasks — `basic_pension_receipt`/`_amount`/`_couple`, `natl_pension_receipt`/`_amount`, `part_civic`/`part_religious`/… + derived `participation_count`/`participation_any`, `hh_income_total`, `srh`. `load_klosa_waves()` (Task 3) is consumed verbatim by Tasks 8–9. `YEAR_MAP` keys `w1..w9` match the loader's list names. `run_post_harmonize_gate("klosa")` / `run_validation(survey="klosa")` / `write_manifest(survey="klosa")` all use the same slug.
