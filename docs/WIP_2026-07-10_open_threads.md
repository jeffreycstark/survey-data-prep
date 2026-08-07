# WIP — open threads as of 2026-07-10

Written at Jeff's request at the end of a long session. Everything below is
either **an explicit decision waiting on him** or **a known defect I chose not to
fix silently**. Nothing here is speculative: each item has evidence attached.

Repos touched: `survey-data-prep` (main @ `80a6574`, clean, pushed) and
`paper-bank` (four branches pushed, four WIP files still in the working tree).

---

## 1. Decisions waiting on Jeff

### 1.1 Paper 90c — he said delete it; I didn't

> "there should be no paper 90c. so delete it if it is a paper"

I stopped, because what's on disk contradicts that. `papers/90c-trust-decomp` is
**"Decomposing the Democratic Aspiration Gap: Trust Divergence in Hong Kong and
Comparative Perspective"** — ~12,300 words of manuscript, **23 analysis
notebooks** (robustness, discriminant validity, regime moderation, trust
disaggregation, HKG bootstrap/EFA/first-difference, leave-one-out, standardized
coefficients/attrition), **103 files tracked on `main` and on `origin/main`**,
and ~1.1 GB on disk across 618 files. The untracked ~1.1 GB of results and
figures would **not** be recoverable from git.

It also sits in his deliberate `9x` back-burner series next to
`92b_old_meaning_of_demo`, `93b_sk_satisfaction_paradox`, and
`97_south_korea_accountability_gap` — all created in commit `d303bb60`, the same
sweep that renamed `07 → 97 (back-burner)`.

**Ask:** did he mean (a) discard the *uncommitted 90c edit* — no longer relevant,
it's committed on `paper90c/fix-claassen-citation-key`; (b) actually remove the
paper — then do it on a branch with `git rm -r` so history survives, and leave
the untracked 1.1 GB for him to delete by hand; or (c) it shouldn't be a
*numbered* paper — a rename/archive, not a deletion?

### 1.2 `chore/pre-session-wip` (`eaff9b6`) — unreviewed, do not blind-merge

A snapshot of a dirty working tree, never merged. Its KIPA YAML fix was already
salvaged into `main` (`77cbca4`). What remains unreviewed:

- **deletions** of `src/r/utils/{helpers,composites,descriptive_stats,search_labels}.R`
  and `src/r/survey/{harmonize_vars,missing_report}.R`, with matching
  `_load_functions.R` de-sourcing
- edits to `harmonize.R`, `codebook_analysis.R`, `codebook_workflow.R`,
  `load_data.R`, `recoding.R`
- an **older** `src/r/lookups/README.md` that would clobber the current one

Merging it wholesale would revert work. It needs a per-file triage.

### 1.3 Questionnaire originals vs the global ignore rules

`.gitignore` globally ignores `*.pdf` (line ~202), `*.docx` (~163) and `*.zip`,
which contradicts the CLAUDE.md instruction to store originals under
`data/{survey}/questionnaires/originals/`. Consequences today:

- Afrobarometer works around it with 10 force-added PDFs.
- I force-added the GCB questionnaire originals (`.docx` + `.xlsx`) so
  `data/gcb/questionnaire_parsed/` isn't orphaned.
- The kipa_corruption `.zip` archives each bundle a questionnaire PDF next to the
  `.SAV`. Both the zip and the PDF are ignored, so **those questionnaires exist
  in the repo in neither form.**

**Ask:** carve out `!data/*/questionnaires/**` (and the kipa_corruption zips), or
keep force-adding case by case?

### 1.4 `data/kipa/raw/kipa_2025.sav` is tracked

The only `.sav` in the index, force-added at some point despite the global rule.
Left alone in case it was deliberate. `git rm --cached` if not.

---

## 2. Known defects, not fixed

### 2.1 Paper 16 — `03_robustness_checks.qmd` still fails (tidyeval, not data)

The data-prep fix is committed (`paper16/fix-data-prep`, `baf9d610`);
`01_descriptive_analysis.qmd` and `02_models.qmd` now render, and Model E fits on
19,329 respondents. `03` gets further than before but dies in the `subgroups`
chunk:

```r
subgroup_results <- subgroup_specs |>
  mutate(model = map(filter_expr, function(e) { ... filter(!!e, ...) }))
#> Error: object 'e' not found
```

`mutate()` performs quasiquotation on **its own** arguments, so `!!e` is unquoted
while `mutate` is quoting `map(...)` — before `map` has bound `e`. Remedy
(verified, not applied): run the `map()` **outside** `mutate()`, e.g.
`specs$model <- map(specs$filter_expr, function(e) ... filter(dat, !!e, ...))`.
Sanity check with the fix: All 20,115 / Female 10,992 / Higher educ. 9,632 /
Lower educ. 2,767.

### 2.2 Paper 16 — `edu_n` is no longer a year count

KGSS has **no** continuous years-of-education variable and never did. `edu_n` is
now `education_5cat_01`: five ordered categories rescaled to 0–1
(0, .25, .5, .75, 1). The subgroup cuts in `03_robustness_checks.qmd`
(`edu_n >= 0.66`, `edu_n < 0.33`) therefore select post-secondary-and-above
(n=9,632) and primary-or-less (n=2,767). They read as though written for a
continuous scale. Substantive call, not mechanical.

### 2.3 WVS `education_level` widened 3 → 6 levels

Landed in `7aaa19a`. Anything built against the old 3-level column must be
re-run. No in-repo consumer; paper 06 uses ABS, not WVS.

### 2.4 ABS label-reconciliation backlog — 18 error rows, 7 variables

Includes `econ_family_income_fair_6pt` (w4 `q159a`, stored opposite its labels).
A normal build passes these silently: the post-harmonize direction gate is
**report-only by default**. Until the backlog clears,
`HARMONIZE_AUDIT_GATE=block` cannot be turned on. See `docs/QA.md`.

### 2.5 Phase-6 cross-validation cardinality findings, untriaged

`afro` 14, `lbs` 1, `ipus` 38 (the IPUS ones are real ①+② combo codes
undocumented in the dictionary). Zero direction conflicts anywhere.

### 2.6 `gcb` has no manifest

`06_check_freshness.R --all` reports it `SKIP`, not `FRESH` — it has never been
harmonized here. Ten of eleven surveys are FRESH.

### 2.7 Deferred audit work

Phase B5/B6 (mandatory `valid_range`, `qc.validate.phrase` enforcement) pending
Jeff's review of inferred backfill values. KINU: 8 under-mapped cells deferred.

---

## 3. State of the two repos

**survey-data-prep** — `main` @ `80a6574`, clean, pushed. All 10 manifested
surveys FRESH. Test suites green: `test_education.R` (28), `test_afro_education.R`
(16), `test_freshness_check.R` (20), `test_harmonize.R`, `test_identity_functions.R`,
`test_kipa_bribery_series.R`.

**paper-bank** — four branches on origin, each **one commit off `main`, none
merged**:

| Branch | Commit | What |
|---|---|---|
| `paper16/fix-data-prep` | `baf9d610` | KGSS `sex` / `education_5cat_01`; required-vars guard |
| `paper90c/fix-claassen-citation-key` | `46755127` | `@Claassen2021-kx` → `@Claassen2022-kx` (0 → 1 bib entries) |
| `paper05/balanced-restyle` | `8588df57` | Restyle pass + pre-trim backup |
| `chore/serena-project-config` | `26f0ca69` | Serena config |

`git status` in paper-bank still shows four modified/untracked files. **That is
expected, not a failure** — the commits live on other branches, so relative to
`paper08b/aspp-intro-repair` the files still look changed. Content is safe on
origin. `git restore` the three tracked files and delete
`05-borrowed-legitimacy-balanced-pretrim.qmd` when the branches have been
reviewed. The working tree was deliberately left untouched.

Note `paper05/democratization-reframe` is unmerged, last touched 2026-06-19, and
does **not** contain `05-borrowed-legitimacy-balanced.qmd` — which is why the
restyle went to a fresh branch off `main` instead.

---

## 4. What landed this session (for context)

- `kipa_bribery_series()` — gate-corrected bribery series; the item is routed
  behind an official-contact screener in **all** of 2016–2021, not the three
  years the codebooks document.
- `06_check_freshness.R` — pre-flight staleness gate, 20 fault-injection tests.
  Caught that WVS was **unbuildable** (loader read parquet caches nothing
  produced); loader now rebuilds them from the `.sav`.
- Afrobarometer education: **16,172 degree-holders recovered.** Codes 8/9
  ("University completed", "Post-graduate") were being deleted as missing by two
  independent gates.
- `education_5cat` / `education_5cat_01` — one cross-survey education scale in
  `src/r/utils/education.R`, replacing four copy-pasted `case_when` blocks.
- ABS `education_years`: `skip_range_check: true` removed; 10 impossible cells
  NA'd (incl. two respondents with 60 years of formal education).
- KIPA processed data was **stale and lossy** — it had been nulling the top
  category of `corr_punishment_*` for 2018–2020.
