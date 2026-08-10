# Bank-Wide Row Identifiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every harmonized survey file carries a stable, unique `row_uid`; native IDs become harmonized data columns; uniqueness is enforced by a build-time assert plus a new audit check.

**Architecture:** One engine change mints `row_uid = "<survey>.<wave>.<%06d>"` in `stack_harmonized_wide()`; twelve 99-scripts stop dropping it and hard-assert its integrity before saving; nine surveys gain native-ID spec entries under a no-missing-codes convention; a declarations+exemptions-driven audit check holds native keys to the measured evidence table.

**Tech Stack:** R (haven, dplyr, yaml), repo's fault-injection test convention (`src/r/audit/test_*.R`), Rscript via Bash.

**Spec:** `docs/superpowers/specs/2026-08-10-row-identifiers-design.md`

## Global Constraints

- `row_uid` format is exactly `sprintf("%s.%s.%06d", survey, wave_name, position)` — character, never numeric.
- The old `row_id` column ceases to exist anywhere; no back-compat alias.
- No respondent row is ever dropped; native values kept verbatim (AB W8 zeros stay zeros).
- ID-class spec variables must use a no-missing-codes convention (`codes: []`), never `treat_as_na`.
- Commit messages: no Co-Authored-By attribution (repo convention).
- Verification target (from spec §6): native-key dup counts must equal the evidence table exactly.

---

### Task 1: Engine — mint `row_uid`, retire `row_id`

**Files:**
- Modify: `src/r/data_prep_modules/2_harmonize_all.R:220-232` (signature + wave_df), `:306`, `:334`, `:360` (call sites)
- Modify: all 13 survey `2_harmonize_all.R` direct call sites (afro:48, ipus:41, cfps:44, gcb:40, kipa_corruption:34, arab-barometer:48, kamos:44, kinu:49, kgss:44, klosa:44, lbs:48, wvs:48 — plus each file's `ncol(df) - 2` comment mentions of row_id → row_uid)
- Modify: `src/r/audit/05_drift_check.R:520` reserved vector
- Test: `src/r/audit/test_row_uid.R` (new)

**Interfaces:**
- Produces: `stack_harmonized_wide(harmonized_results, waves, survey, run_id = ...)` — `survey` is a new REQUIRED second-position-after-waves argument (no default; every caller must name their survey). Output wave dfs contain `wave` + `row_uid` (character) and no `row_id`.

- [ ] **Step 1: Write the failing test** — `src/r/audit/test_row_uid.R`:

```r
# Fault-injection tests for engine-minted row_uid.
library(here)
source(here::here("src/r/data_prep_modules/2_harmonize_all.R"))

pass <- 0; fail <- 0
ok <- function(cond, label) {
  if (isTRUE(cond)) { pass <<- pass + 1; cat("  PASS ", label, "\n") }
  else { fail <<- fail + 1; cat("  FAIL ", label, "\n") }
}

# Synthetic two-wave survey: 3 and 2 rows.
waves <- list(w1 = data.frame(q1 = c(1, 2, 3)), w2 = data.frame(q1 = c(4, 5)))
results <- list(testspec = list(
  concept = "t",
  variables = list(v1 = list(w1 = c(1, 2, 3), w2 = c(4, 5)))))

out <- stack_harmonized_wide(results, waves, survey = "synth")

cat("=== T1: format and uniqueness ===\n")
ok(identical(out$w1$row_uid, c("synth.w1.000001", "synth.w1.000002", "synth.w1.000003")),
   "w1 row_uid exact format")
ok(identical(out$w2$row_uid, c("synth.w2.000001", "synth.w2.000002")),
   "w2 row_uid exact format")
ok(!"row_id" %in% c(names(out$w1), names(out$w2)), "row_id no longer emitted")
ok(is.character(out$w1$row_uid), "row_uid is character")

cat("=== T2: stability — same input, same ids ===\n")
out2 <- stack_harmonized_wide(results, waves, survey = "synth")
ok(identical(out$w1$row_uid, out2$w1$row_uid), "rebuild yields identical ids")

cat("=== T3: missing survey argument fails loudly ===\n")
r <- tryCatch({ stack_harmonized_wide(results, waves); "no-error" },
              error = function(e) "error")
ok(r == "error", "omitting survey is an error")

cat(sprintf("\n%d passed, %d failed\n", pass, fail))
if (fail > 0) quit(status = 1)
```

- [ ] **Step 2: Run to verify it fails** — `Rscript src/r/audit/test_row_uid.R`; expected: FAIL rows (unused `survey` argument error / row_id still emitted), exit 1.

- [ ] **Step 3: Implement.** In `src/r/data_prep_modules/2_harmonize_all.R`:

```r
# signature (line ~220):
stack_harmonized_wide <- function(harmonized_results, waves, survey,
                                  run_id = format(Sys.time(), "%Y%m%d%H%M%S")) {
  if (missing(survey) || !nzchar(survey)) {
    stop("stack_harmonized_wide(): `survey` is required — row_uid is minted here.")
  }
```

```r
# wave_df (replacing the row_id block at ~227-231):
    # Stable row identifier: <survey>.<wave>.<position-in-loaded-wave>.
    # Stability contract: unchanged raw file + loader => unchanged row_uid
    # (run manifests hash the raw inputs, so renumbering events are
    # detectable via the freshness layer). Scope: a changed wave renumbers
    # only itself.
    wave_df <- tibble(
      wave = rep(wave_name, n_rows),
      row_uid = sprintf("%s.%s.%06d", survey, wave_name, seq_len(n_rows))
    )
```

Update the three shared call sites — `:306` (inside `run_survey_harmonization`, pass its `survey` arg), `:334`/`:360` (the legacy ABS paths, pass `survey = "abs"`) — and every survey `2_harmonize_all.R` direct block to `stack_harmonized_wide(results, waves, survey = "<key>")` using each module's own survey key (afro, ipus, cfps, gcb, kipa_corruption, arab-barometer, kamos, kinu, kgss, klosa, lbs, wvs). Change `05_drift_check.R:520` to `reserved <- c("wave", "country", "row_uid")`. Update the `# subtract wave + row_id` comments to say row_uid.

- [ ] **Step 4: Run test to verify it passes** — `Rscript src/r/audit/test_row_uid.R`; expected: all PASS, exit 0. Also `make check-r` (parse gate) green.

- [ ] **Step 5: Commit** — `feat(engine): mint stable row_uid in stack_harmonized_wide; retire row_id`

### Task 2: Build-time assert in every 99-script

**Files:**
- Create: `src/r/utils/keys.R`
- Modify: all twelve 99-scripts — the eleven with `select(-row_id)` (afro, arab-barometer, cfps, ipus, kamos, kgss, kinu, kipa_corruption, klosa, lbs, wvs) plus ABS's `src/r/data_prep_modules/99_create_final_dataset.R` (`:122` var_names line references row_id)
- Test: extend `src/r/audit/test_row_uid.R`

**Interfaces:**
- Produces: `assert_row_uid(df, survey)` — stops with a clear message unless `df$row_uid` exists, is character, has zero NA and zero duplicates; invisibly returns df.
- Consumes: Task 1's `row_uid` column.

- [ ] **Step 1: Write failing test** (append to `test_row_uid.R`):

```r
cat("=== T4: assert_row_uid ===\n")
source(here::here("src/r/utils/keys.R"))
good <- data.frame(row_uid = c("s.w1.000001", "s.w1.000002"))
ok(identical(assert_row_uid(good, "s"), good), "clean frame passes through")
r <- tryCatch({ assert_row_uid(data.frame(x = 1), "s"); "no-error" }, error = function(e) "error")
ok(r == "error", "missing column stops")
r <- tryCatch({ assert_row_uid(data.frame(row_uid = c("a", "a")), "s"); "no-error" }, error = function(e) "error")
ok(r == "error", "duplicate stops")
r <- tryCatch({ assert_row_uid(data.frame(row_uid = c("a", NA)), "s"); "no-error" }, error = function(e) "error")
ok(r == "error", "NA stops")
```

- [ ] **Step 2: Run, verify FAIL** (keys.R does not exist).

- [ ] **Step 3: Implement `src/r/utils/keys.R`:**

```r
# Row-identifier integrity helpers. row_uid is the bank-wide stable row key
# (design: docs/superpowers/specs/2026-08-10-row-identifiers-design.md).

#' Hard build-time assert: row_uid present, character, unique, non-NA.
#' A broken backbone stops the pipeline; this is not report-only.
assert_row_uid <- function(df, survey) {
  if (!"row_uid" %in% names(df)) {
    stop(sprintf("[%s] row_uid column missing from final dataset", survey))
  }
  x <- df$row_uid
  if (!is.character(x)) {
    stop(sprintf("[%s] row_uid must be character, got %s", survey, class(x)[1]))
  }
  if (anyNA(x)) {
    stop(sprintf("[%s] %d NA row_uid values", survey, sum(is.na(x))))
  }
  if (anyDuplicated(x)) {
    stop(sprintf("[%s] %d duplicated row_uid values (e.g. %s)",
                 survey, sum(duplicated(x)), x[duplicated(x)][1]))
  }
  invisible(df)
}
```

- [ ] **Step 4: Wire the twelve 99-scripts.** In each: delete the `select(-row_id)` line (eleven scripts); add `source(here("src", "r", "utils", "keys.R"))` next to the existing `provenance.R` source line; insert `assert_row_uid(<survey>_harmonized, "<survey>")` immediately before the first `saveRDS`. In ABS's 99 change `:122` to `setdiff(names(...), c("wave", "row_uid"))`-style (drop the stale row_id mention).

- [ ] **Step 5: Run test suite** — `Rscript src/r/audit/test_row_uid.R` all PASS; `make check-r` green.

- [ ] **Step 6: Commit** — `feat(pipeline): keep row_uid in all twelve finals; hard integrity assert before save`

### Task 3: Native-ID spec layer (nine surveys)

**Files:**
- Create: `src/config/<survey>/harmonize/identifiers.yml` for kgss, afro, lbs, wvs, arab-barometer, kamos, kinu, ipus, kipa_corruption

**Interfaces:**
- Consumes: each survey's loaded wave frames (source column must exist in the LOADED frame — caches/mergers may rename; verify per survey, step 1).
- Produces: harmonized columns `respid` (kgss), `respno` (afro), `numentre` (lbs), `s007` (wvs), `native_id` (arab-barometer, kamos, kinu, ipus, kipa_corruption).

- [ ] **Step 1: Verify loaded-frame column names per survey** (source names in raw ≠ guaranteed in loaded frames):

```r
# per survey, e.g. kgss:
source(here::here("src/r/data_prep_modules/kgss/0_load_waves.R"))
w <- load_kgss_waves()
lapply(w, function(d) grep("RESPID|respid", names(d), value = TRUE))
```

Record the exact per-wave source names. For KAMOS additionally table the loaded wave structure first — its loader merges quarterly files into waves, so `id` may collide within a loaded wave; test `sapply(w, function(d) sum(duplicated(d$id)))` and record the result (feeds Task 4's declaration and, if colliding, the spec note).

- [ ] **Step 2: Write each `identifiers.yml` from this template** (fill the parameter table below; wave keys copied from the survey's existing spec files):

```yaml
# <SURVEY> — respondent/interview identifiers.
# IDs are DATA for raw-traceability and merges, never the uniqueness
# backbone (that is row_uid). ID variables carry NO missing codes — the
# generalized lesson of the 2026-08-09 ABS idnumber bug.
schema_version: 1

missing_conventions:
  no_missing_codes:
    codes: []
    description: "Serial IDs have no refused/DK values; every code is real."

variables:
  - id: <HARMONIZED_NAME>
    concept: identifiers
    description: "<per-table description>"
    type: nominal
    source:
      <wave>: <source-or-null per parameter table>
    missing:
      use_convention: no_missing_codes
    harmonize:
      default:
        method: identity
    qc:
      skip_range_check: true
      skip_unmapped_check: true
```

Parameter table (verdicts from the 2026-08-10 evidence runs; null waves per spec §2):

| survey | harmonized id | source (case per wave era) | null waves |
|---|---|---|---|
| kgss | `respid` | `RESPID` | none |
| afro | `respno` | `RESPNO` / `respno` (check loaded case) | r1 |
| lbs | `numentre` | `numentre` / `NUMENTRE` per year | y1995, y1996 |
| wvs | `s007` | `S007` | w3 (dup-ridden), w4, w6, w7 |
| arab-barometer | `native_id` | `id` (w5) / `ID` (w7, w8) | w1–w4 |
| kamos | `native_id` | `id` | none |
| kinu | `native_id` | `id` | none |
| ipus | `native_id` | `id` (≤2016) / `ID` (2017+) | none |
| kipa_corruption | `native_id` | `id` | w2013, w2014, w2015 |

Descriptions must state the key scope and any anomaly (e.g. afro: "unique within round+country except R8's 24 release-file duplicates — see key_uniqueness_exemptions.yml").

- [ ] **Step 3: Validate** — `make audit-specs` green (L1 schema for all surveys; also proves the new convention name parses). The convention-collision check must stay 0 errors (empty codes list cannot collide).

- [ ] **Step 4: Commit** — `feat(specs): harmonize native respondent IDs across nine surveys (identifiers.yml, no-missing-codes convention)`

### Task 4: Key declarations, exemptions, and the uniqueness check

**Files:**
- Create: `src/config/_audit/key_declarations.yml`, `src/config/_audit/key_uniqueness_exemptions.yml`
- Create: `src/r/audit/check_key_uniqueness.R`
- Modify: `src/r/audit/run_all.R` (new module runner, mirror the convention-collision wiring)
- Test: `src/r/audit/test_key_uniqueness.R`

**Interfaces:**
- Consumes: `data/processed/<survey>_harmonized.rds`, the two new yml files.
- Produces: exit 0/1 CLI; report `audit/reports/key_uniqueness.csv`; run_all module `L6 keys` (soft/report level for native keys; row_uid failures are errors).

- [ ] **Step 1: Write `key_declarations.yml`** (scope columns must exist in the processed files; KAMOS entry per Task 3's measured result):

```yaml
# Which columns claim to identify a row, per survey, and within what scope.
# Verified 2026-08-10 (see the design doc's evidence table). row_uid is
# implicitly declared for every survey and is checked as a hard error.
schema_version: 1

declarations:
  - survey: abs
    key: [country, wave, idnumber]
    note: "2 HK W5 release duplicates exempted"
  - survey: cfps
    key: [wave, pid]
  - survey: klosa
    key: [wave, pid]
  - survey: kgss
    key: [year, respid]
  - survey: kinu
    key: [wave, native_id]
  - survey: ipus
    key: [wave, native_id]
  - survey: kipa_corruption
    key: [wave, native_id]
    note: "native_id null 2013-2015; key asserted on non-null rows only; 2019's 74 release duplicates exempted"
  - survey: afro
    key: [wave, country, respno]
    note: "respno null in R1; R8's 24 release duplicates exempted"
  - survey: lbs
    key: [wave, country, numentre]
    note: "numentre null 1995/96 and NA-heavy 2004; asserted on complete rows only"
  - survey: wvs
    key: [wave, country, s007]
    note: "s007 populated w1/w2/w5 only"
  - survey: arab-barometer
    key: [wave, country, native_id]
    note: "null w1-w4; W5's 3 dups and W8's 2,400 zero-ID block exempted"
  - survey: gcb
    key: [wave, respondent_id]
    note: "dormant — no processed output yet; the check skips absent files"
  # kamos: declaration set from the Task 3 measurement (id may collide
  # across merged quarterly files within a loaded wave; if so, declare no
  # native key and record why here).
```

- [ ] **Step 2: Write `key_uniqueness_exemptions.yml`** — one entry per anomaly {survey, key_value_pattern or count, reason}, covering: ABS HK W5 `704273201`/`704273901` (kept per Jeff 2026-08-10, byte-identical release duplicates); afro R8 24 dups; kipa_corruption 2019 74 dups; arab-barometer w5 3 dups + w8 ID=0 block (2,400 rows, IDs never assigned); kamos 1 dup if the Task 3 measurement confirms it survives wave-merging.

- [ ] **Step 3: Write failing tests** `test_key_uniqueness.R` — synthetic processed frames written to a tempdir with an overridable data root (`BD`-style env var `KEYCHECK_DATA_DIR`): clean frame → exit 0; duplicated declared key, unexempted → error row + exit 1; exempted duplicate (count-scoped) → pass; exemption must NOT cover a larger duplicate count (24 exempted, 25 present → error); NA-in-key rows skipped for partial-coverage keys but counted in the report; row_uid duplicate → error regardless of declarations.

- [ ] **Step 4: Implement `check_key_uniqueness.R`** — structure mirrors `check_convention_collisions.R`: read declarations + exemptions; per survey load the processed RDS (skip-with-note if absent, like freshness's SKIP); assert row_uid (reuse `assert_row_uid` wrapped in tryCatch → error row instead of stop); build key strings on complete rows, count duplicates, subtract exemption allowances; write `audit/reports/key_uniqueness.csv`; print PASS/EXEMPT/ERROR lines and a summary; exit 1 on any error.

- [ ] **Step 5: Run tests to green**, then run the real check — expected first-run result: 0 errors, with exemption lines exactly matching the evidence table (any drift = investigate before proceeding).

- [ ] **Step 6: Wire into `run_all.R`** (data-dependent module — grouped with the L5/L6 layers that CI skips under `--specs-only`), add to the SUMMARY table.

- [ ] **Step 7: Commit** — `feat(audit): key-uniqueness check — declared native keys + hard row_uid integrity, with reasoned exemptions`

### Task 5: Documentation closure

**Files:**
- Modify: `CLAUDE.md` (one gotcha bullet), `docs/QA.md` (coverage-map line), `JEFF_MUST_INVESTIGATE.md` (resolve the idnumber entry's three open questions), each of the twelve `docs/surveys/*.md` (one line on native-ID availability)

- [ ] **Step 1: CLAUDE.md gotcha** (place next to the existing ABS idnumber bullet): every processed survey RDS carries `row_uid` (`<survey>.<wave>.<position>`, character, unique, asserted at build); stable while a wave's raw file + loader are unchanged, renumbering is wave-scoped and manifest-detectable; native IDs are data columns for raw-traceability, never sole join keys — declarations in `src/config/_audit/key_declarations.yml`.
- [ ] **Step 2: JEFF entry** — mark minting DONE (engine-level), HK duplicates kept+exempted (Jeff 2026-08-10), uniqueness check built; strike the open-questions block.
- [ ] **Step 3: docs/QA.md** — add the check to the layer map with its blind spots (native-key check runs on processed files only; partial-coverage keys asserted on complete rows).
- [ ] **Step 4: per-survey docs lines** + commit — `docs: row_uid contract and native-ID key map`

### Task 6: Full-bank rebuild and verification

- [ ] **Step 1:** Rebuild all twelve surveys (`2_harmonize_all.R` + `99_create_final_dataset.R` each; ABS's live at the module root). Every 99 must pass its new assert.
- [ ] **Step 2:** Bank-wide verification script (run once, keep in scratchpad): for each processed RDS assert row_uid unique/non-NA; recompute native-key duplicate counts and diff against the evidence table — must match EXACTLY.
- [ ] **Step 3:** Stability proof: rebuild one mid-size survey (kinu) twice; `identical(d1$row_uid, d2$row_uid)` TRUE.
- [ ] **Step 4:** `make audit-specs` green; local `Rscript src/r/audit/run_all.R --survey kinu` (or equivalent) shows the new module; freshness FRESH bank-wide; all `test_*.R` including the two new suites green.
- [ ] **Step 5:** Final commit + push — `feat(bank): stable row identifiers everywhere — rebuild, verified against the key evidence table`
