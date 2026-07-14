# Prospector Bimodality / Two-Camp Split (Pass C2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Pass C2 detector that flags survey items whose within-country response distribution is *splitting into two camps over time* — genuine polarization, distinct from C1a's mean-flat-SD-rising signal — using van der Eijk's agreement measure *A*.

**Architecture:** A new `detect_bimodality()` and its helpers live in the existing `src/scripts/prospector/polarization.R` (the dispersion/polarization family), reusing the module's `.pol_slopes()` slope machinery. Per country×wave×variable we compute van der Eijk's *A* on the ordinal response frequency vector, run the trend of `−A` through `.pol_slopes`, and classify. The ABS runner gains a `compute_freqs()` helper (parallel to its `compute_means()`) and one call. Output is `bimodality.csv`, carrying a `c1a_pattern` column joined from `polarization.csv` so a genuine two-camp split (C1a-POLARIZING ∩ C2-POLARIZING_BIMODAL) reads out of one file.

**Tech Stack:** R (tidyverse + broom only — no new package), `testthat`-free assertion style (`ok()` counter + `cat`) matching `src/scripts/prospector/test_polarization.R`, run via `Rscript`.

## Global Constraints

- No R MCP — every check runs via `Rscript` in bash.
- **No new package dependency:** `polarization.R` uses only tidyverse + broom. *A* is a self-contained port (`.vdeijk_A`), validated against closed-form anchors — do NOT add `agrmt`.
- Commit messages: **no** `Co-Authored-By` / "Generated with" attribution.
- Work stays on branch `feat/prospector-bimodality-passC2`.
- **Additive only:** do not change `detect_polarization` / `detect_sorting` behavior or the columns of `polarization.csv` / `sorting.csv`. The existing `test_polarization.R` C1a/C1b assertions and `test_signature_match.R` (69/0) must stay green.
- Classification requires `K ≥ 3` response categories and `≥ MIN_WAVES` waves; unweighted frequencies (first cut).
- ABS-only wiring (`run_abs_all_countries.R`); other runners get C2 opportunistically later.
- `bimodal_A_max` default **0.5**, `flat_threshold` default **0.05** (reuses the runner's `FLAT_THRESHOLD`).

---

## File Structure

- **Modify** `src/scripts/prospector/polarization.R` — add `.vdeijk_A()`, `.bimodality_by_wave()`, `detect_bimodality()` (below the existing `detect_sorting`).
- **Modify** `src/scripts/prospector/test_polarization.R` — append C2 tests **before** the final summary line (`cat(sprintf(...)); if (fail > 0) quit(...)`), which must stay last.
- **Modify** `src/scripts/run_abs_all_countries.R` — add `compute_freqs()` helper + a `detect_bimodality()` call after the sorting block.
- **Modify** `docs/SLOPE_PROSPECTOR.md` — document `bimodality.csv` + a C2 subsection.
- **Modify** `docs/superpowers/specs/2026-07-14-prospector-bimodality-passC2-design.md` — flip status to implemented.

**Test-insertion rule (applies to every task that edits `test_polarization.R`):** the file's last two lines are
```r
cat(sprintf("\n%d passed, %d failed\n", pass, fail)); if (fail > 0) quit(status = 1)
```
Always insert new test blocks **immediately above** that line so the summary/exit stays last.

---

## Task 1: van der Eijk's *A* statistic (`.vdeijk_A`)

**Files:**
- Modify: `src/scripts/prospector/polarization.R`
- Test: `src/scripts/prospector/test_polarization.R`

**Interfaces:**
- Produces: `.vdeijk_A(freq)` — `freq` is a numeric vector of counts over `K = length(freq)` ordered categories (positions `1..K`, zeros allowed for unoccupied interior categories). Returns *A* in `[-1, 1]` (`+1` unimodal spike, `0` uniform, `-1` split 50/50 at the two extremes); `NA_real_` if `sum(freq) == 0`.

- [ ] **Step 1: Write the failing anchor tests**

Insert above the final summary line in `test_polarization.R`:

```r
# ── Pass C2: van der Eijk's A statistic ──
ok(abs(.vdeijk_A(c(100, 0, 0))    - 1) < 1e-9, "A=+1 all mass one category (K=3)")
ok(abs(.vdeijk_A(c(0, 100, 0))    - 1) < 1e-9, "A=+1 all mass centre category (K=3)")
ok(abs(.vdeijk_A(c(50, 50, 50))   - 0) < 1e-9, "A=0 uniform (K=3)")
ok(abs(.vdeijk_A(c(50, 0, 50))    + 1) < 1e-9, "A=-1 split at extremes (K=3)")
ok(abs(.vdeijk_A(c(50, 0, 0, 50)) + 1) < 1e-9, "A=-1 split at extremes (K=4)")
ok(.vdeijk_A(c(10, 80, 10)) > 0,               "unimodal hump -> positive A")
ok(is.na(.vdeijk_A(c(0, 0, 0))),               "no responses -> NA")
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `Rscript src/scripts/prospector/test_polarization.R`
Expected: FAIL — `could not find function ".vdeijk_A"`.

- [ ] **Step 3: Implement `.vdeijk_A`**

Append to `src/scripts/prospector/polarization.R` (after `detect_sorting`):

```r
# ─────────────────────────────────────────────────────────────────────────────
# Pass C2 — bimodality / two-camp split via van der Eijk's (2001) agreement A.
#
# .vdeijk_A(freq): A over K ordered categories (positions 1..K). +1 = all mass in
# one category (perfect agreement), 0 = uniform, -1 = 50/50 at the two extremes
# (perfect bimodal polarization). The distribution is peeled into layers (subtract
# the min occupied frequency each pass); each layer's binary presence pattern gets
#   A_layer = U * (1 - (S - 1)/(K - 1)),   0 if S == K,
# where S = occupied categories and U is the unimodality term counting, over all
# triples of positions a<b<c whose OUTER categories are both occupied, a present
# middle (tu) vs an absent middle / "dip" (tdu):
#   U = ((K-2)*tu - (K-1)*tdu) / ((K-2)*(tu+tdu)),   U = 1 when tu == tdu == 0.
# Layers are mass-weighted (m * S) and averaged. Verified against the +1/0/-1
# anchors on K=3 and K=4.
# ─────────────────────────────────────────────────────────────────────────────
.vdeijk_A <- function(freq) {
  freq <- as.numeric(freq)
  K <- length(freq)
  Ntot <- sum(freq)
  if (is.na(Ntot) || Ntot == 0) return(NA_real_)

  layer_A <- function(p) {                 # p: logical presence vector, length K
    S <- sum(p)
    if (S == K) return(0)
    idx <- which(p)
    tu <- 0L; tdu <- 0L
    for (a in idx) for (cc in idx[idx > a + 1L]) {
      for (b in (a + 1L):(cc - 1L)) if (p[b]) tu <- tu + 1L else tdu <- tdu + 1L
    }
    U <- if (tu == 0L && tdu == 0L) 1
         else ((K - 2) * tu - (K - 1) * tdu) / ((K - 2) * (tu + tdu))
    U * (1 - (S - 1) / (K - 1))
  }

  total <- 0; work <- freq
  while (any(work > 0)) {
    occ <- which(work > 0)
    m   <- min(work[occ])
    total <- total + layer_A(work > 0) * (m * length(occ))
    work[occ] <- work[occ] - m
  }
  total / Ntot
}
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `Rscript src/scripts/prospector/test_polarization.R`
Expected: no `FAIL:` lines; final count unchanged from before plus the 7 new assertions.

- [ ] **Step 5: Commit**

```bash
git add src/scripts/prospector/polarization.R src/scripts/prospector/test_polarization.R
git commit -m "feat(prospector): van der Eijk agreement A statistic (Pass C2 primitive)"
```

---

## Task 2: per-wave bimodality table (`.bimodality_by_wave`)

**Files:**
- Modify: `src/scripts/prospector/polarization.R`
- Test: `src/scripts/prospector/test_polarization.R`

**Interfaces:**
- Consumes: `.vdeijk_A()`.
- Produces: `.bimodality_by_wave(freqs) -> tibble(country, wave_num, variable, A, K, n)`.
  - `freqs`: long frequency table `country, wave_num, variable, value, count` (one row per occupied response code per country×wave×variable).
  - **Integer-code guard:** variables with any non-integer `value` (normalized/continuous covariates such as `*_01`) are dropped — an ordinal lattice needs integer category codes.
  - `K` per variable is the contiguous integer span `max(value) - min(value) + 1` across ALL of that variable's rows, so a never-chosen interior category still occupies its position (frequency 0). `A` is `.vdeijk_A` on the length-K positioned vector; `n = sum(count)` for that cell.

- [ ] **Step 1: Write the failing test**

Insert above the final summary line in `test_polarization.R`:

```r
# ── Pass C2: per-wave A table ──
frq_bw <- bind_rows(
  tibble(country="Z", variable="v", wave_num=1, value=3,        count=100),           # centre spike -> A=1
  tibble(country="Z", variable="v", wave_num=2, value=c(1,5),   count=c(50,50)),       # extremes    -> A=-1
  tibble(country="Z", variable="v", wave_num=3, value=c(1,2,3), count=c(10,80,10))     # only codes 1..3 seen this wave
)
bw <- .bimodality_by_wave(frq_bw)
ok(nrow(bw) == 3,                                           "one row per country x wave x variable")
ok(all(bw$K == 5),                                          "K = observed span 1..5 across all waves (fixed per variable)")
ok(abs(bw$A[bw$wave_num==1] - 1) < 1e-9,                    "centre spike wave -> A=1")
ok(abs(bw$A[bw$wave_num==2] + 1) < 1e-9,                    "extremes wave -> A=-1")
ok(bw$n[bw$wave_num==2] == 100,                             "n = total responses in the cell")

# integer-code guard: a fractional-valued variable is dropped
frq_frac <- tibble(country="Z", variable="v01", wave_num=1:3, value=c(0, 0.5, 1), count=100)
ok(nrow(.bimodality_by_wave(frq_frac)) == 0,               "non-integer-coded variable dropped")
```

- [ ] **Step 2: Run, verify FAIL**

Run: `Rscript src/scripts/prospector/test_polarization.R`
Expected: FAIL — `could not find function ".bimodality_by_wave"`.

- [ ] **Step 3: Implement `.bimodality_by_wave`**

Append to `src/scripts/prospector/polarization.R` (after `.vdeijk_A`):

```r
# Per country x wave x variable van der Eijk A on the ordinal response frequency
# vector. K (scale length) is fixed PER VARIABLE as the contiguous integer span of
# observed codes, so an interior category unused in one wave keeps its position.
.bimodality_by_wave <- function(freqs) {
  stopifnot(all(c("country", "wave_num", "variable", "value", "count") %in% names(freqs)))
  freqs <- freqs %>%
    filter(!is.na(value), !is.na(count), count > 0) %>%
    group_by(variable) %>%
    filter(all(value == round(value))) %>%      # ordinal lattice needs integer codes
    ungroup()
  if (nrow(freqs) == 0)
    return(tibble(country = character(), wave_num = numeric(), variable = character(),
                  A = numeric(), K = integer(), n = numeric()))
  vk <- freqs %>% group_by(variable) %>%
    summarise(vmin = min(value), K = max(value) - min(value) + 1L, .groups = "drop")
  freqs %>%
    inner_join(vk, by = "variable") %>%
    group_by(country, wave_num, variable, K, vmin) %>%
    summarise(
      A = { v <- numeric(first(K)); v[value - first(vmin) + 1L] <- count; .vdeijk_A(v) },
      n = sum(count),
      .groups = "drop"
    ) %>%
    select(country, wave_num, variable, A, K, n)
}
```

- [ ] **Step 4: Run, verify PASS**

Run: `Rscript src/scripts/prospector/test_polarization.R`
Expected: no `FAIL:` lines.

- [ ] **Step 5: Commit**

```bash
git add src/scripts/prospector/polarization.R src/scripts/prospector/test_polarization.R
git commit -m "feat(prospector): per-wave bimodality (A) table builder"
```

---

## Task 3: `detect_bimodality` — slope, classify, C1a join, output

**Files:**
- Modify: `src/scripts/prospector/polarization.R`
- Test: `src/scripts/prospector/test_polarization.R`

**Interfaces:**
- Consumes: `.bimodality_by_wave()`, `.pol_slopes()` (already in the module).
- Produces: `detect_bimodality(freqs, out_dir=NULL, min_waves=3, flat_threshold=0.05, bimodal_A_max=0.5, max_categories=11) -> tibble(country, variable, A_start, A_end, pol_slope, pattern, c1a_pattern)`.
  - Computes per-cell `A` (Task 2), sets `pol = -A`, fits the per country×variable slope of `pol` via `.pol_slopes` (min-max normalized, WLS by `n`, `>= min_waves` gate), keeps `3 <= K <= max_categories` only (`max_categories` drops quasi-continuous items like 0–100 scales that are not ordered rating scales and would be slow under the triple loop).
  - `pattern`: `POLARIZING_BIMODAL` if `pol_slope > flat_threshold` AND `A_end < bimodal_A_max`; `CONVERGING_UNIMODAL` if `pol_slope < -flat_threshold`; else `OTHER`.
  - `c1a_pattern`: left-joined `pattern` from `polarization.csv` in `out_dir` if that file exists; else `NA`.
  - Writes `bimodality.csv` to `out_dir` when non-NULL.

- [ ] **Step 1: Write the failing tests**

Insert above the final summary line in `test_polarization.R`:

```r
# ── Pass C2: detect_bimodality classification ──
frq_split <- bind_rows(   # unimodal centre -> split extremes over 4 waves
  tibble(country="Z", variable="v_split", wave_num=1, value=3,            count=100),
  tibble(country="Z", variable="v_split", wave_num=2, value=c(2,3,4),     count=c(20,60,20)),
  tibble(country="Z", variable="v_split", wave_num=3, value=c(1,3,5),     count=c(30,40,30)),
  tibble(country="Z", variable="v_split", wave_num=4, value=c(1,5),       count=c(50,50))
)
frq_conv <- bind_rows(    # split extremes -> unimodal centre (reverse)
  tibble(country="Z", variable="v_conv", wave_num=1, value=c(1,5),        count=c(50,50)),
  tibble(country="Z", variable="v_conv", wave_num=2, value=c(1,3,5),      count=c(30,40,30)),
  tibble(country="Z", variable="v_conv", wave_num=3, value=c(2,3,4),      count=c(20,60,20)),
  tibble(country="Z", variable="v_conv", wave_num=4, value=3,            count=100)
)
frq_shift <- bind_rows(   # unimodal throughout but the MODE shifts (mean moves)
  tibble(country="Z", variable="v_shift2", wave_num=1, value=1, count=100),
  tibble(country="Z", variable="v_shift2", wave_num=2, value=2, count=100),
  tibble(country="Z", variable="v_shift2", wave_num=3, value=3, count=100),
  tibble(country="Z", variable="v_shift2", wave_num=4, value=4, count=100)
)
frq_bin <- bind_rows(     # K=2 -> excluded
  tibble(country="Z", variable="v_bin", wave_num=1:4, value=1, count=60),
  tibble(country="Z", variable="v_bin", wave_num=1:4, value=2, count=40)
)
frq_wide <- bind_rows(    # K=20 -> excluded by max_categories (quasi-continuous)
  tibble(country="Z", variable="v_wide", wave_num=1, value=10,          count=100),
  tibble(country="Z", variable="v_wide", wave_num=2, value=c(5,15),     count=c(50,50)),
  tibble(country="Z", variable="v_wide", wave_num=3, value=c(1,20),     count=c(50,50))
)
frq_c2 <- bind_rows(frq_split, frq_conv, frq_shift, frq_bin, frq_wide)
bm <- detect_bimodality(frq_c2, min_waves=3, flat_threshold=0.05, bimodal_A_max=0.5, max_categories=11)

ok(bm$pattern[bm$variable=="v_split"] == "POLARIZING_BIMODAL",  "unimodal->bimodal -> POLARIZING_BIMODAL")
ok(bm$pattern[bm$variable=="v_conv"]  == "CONVERGING_UNIMODAL", "bimodal->unimodal -> CONVERGING_UNIMODAL")
ok(bm$pattern[bm$variable=="v_shift2"] == "OTHER",             "shifting-but-unimodal -> OTHER (not a mean re-detect)")
ok(!("v_bin" %in% bm$variable),                                "K<3 variable excluded")
ok(!("v_wide" %in% bm$variable),                               "K>max_categories variable excluded")
ok(all(is.na(bm$c1a_pattern)),                                 "c1a_pattern NA when no polarization.csv")

# guard: with an unreachable bimodal_A_max, a rising-pol item is NOT called bimodal
bm_g <- detect_bimodality(frq_split, min_waves=3, flat_threshold=0.05, bimodal_A_max=-2)
ok(bm_g$pattern[bm_g$variable=="v_split"] == "OTHER",          "A_end guard blocks POLARIZING_BIMODAL")

# min_waves gate
frq_short <- bind_rows(
  tibble(country="Z", variable="v_sh", wave_num=1, value=3,      count=100),
  tibble(country="Z", variable="v_sh", wave_num=2, value=c(1,5), count=c(50,50))
)
ok(nrow(detect_bimodality(frq_short, min_waves=3)) == 0,       "variable with < min_waves dropped")

# c1a_pattern join when polarization.csv is present
td <- tempfile("c2_"); dir.create(td)
readr::write_csv(tibble(country="Z", variable="v_split", pattern="POLARIZING"),
                 file.path(td, "polarization.csv"))
bm_j <- detect_bimodality(frq_split, out_dir=td, min_waves=3)
ok(bm_j$c1a_pattern[bm_j$variable=="v_split"] == "POLARIZING", "c1a_pattern joined from polarization.csv")
ok(file.exists(file.path(td, "bimodality.csv")),              "bimodality.csv written to out_dir")
```

- [ ] **Step 2: Run, verify FAIL**

Run: `Rscript src/scripts/prospector/test_polarization.R`
Expected: FAIL — `could not find function "detect_bimodality"`.

- [ ] **Step 3: Implement `detect_bimodality`**

Append to `src/scripts/prospector/polarization.R` (after `.bimodality_by_wave`):

```r
# detect_bimodality — Pass C2. Flags variables whose within-country response
# distribution is SPLITTING INTO TWO CAMPS over waves (rising -A), distinct from
# C1a's mean-flat-SD-rising spread. Reuses .pol_slopes on the -A series.
#   freqs needs: country, wave_num, variable, value, count
# Writes bimodality.csv; carries c1a_pattern from polarization.csv (out_dir) when
# present so C1a-POLARIZING ∩ C2-POLARIZING_BIMODAL = a genuine two-camp split.
detect_bimodality <- function(freqs, out_dir = NULL, min_waves = 3,
                              flat_threshold = 0.05, bimodal_A_max = 0.5,
                              max_categories = 11) {
  stopifnot(all(c("country", "wave_num", "variable", "value", "count") %in% names(freqs)))

  bw <- .bimodality_by_wave(freqs %>% mutate(country = as.character(country))) %>%
    filter(K >= 3, K <= max_categories, !is.na(A)) %>%
    mutate(pol = -A)

  slopes <- .pol_slopes(bw %>% select(country, wave_num, variable, pol, n),
                        pol, min_waves) %>%
    rename(pol_slope = slope) %>%
    filter(!is.na(pol_slope))

  ends <- bw %>%
    group_by(country, variable) %>%
    arrange(wave_num, .by_group = TRUE) %>%
    summarise(A_start = first(A), A_end = last(A), .groups = "drop")

  out <- slopes %>%
    inner_join(ends, by = c("country", "variable")) %>%
    mutate(pattern = case_when(
      pol_slope >  flat_threshold & A_end < bimodal_A_max ~ "POLARIZING_BIMODAL",
      pol_slope < -flat_threshold                         ~ "CONVERGING_UNIMODAL",
      TRUE                                                ~ "OTHER"
    ))

  c1a_path <- if (!is.null(out_dir)) file.path(out_dir, "polarization.csv") else NULL
  if (!is.null(c1a_path) && file.exists(c1a_path)) {
    c1a <- readr::read_csv(c1a_path, show_col_types = FALSE) %>%
      transmute(country = as.character(country), variable, c1a_pattern = pattern)
    out <- out %>% left_join(c1a, by = c("country", "variable"))
  } else {
    out$c1a_pattern <- NA_character_
  }

  out <- out %>%
    select(country, variable, A_start, A_end, pol_slope, pattern, c1a_pattern) %>%
    arrange(desc(pol_slope))

  if (!is.null(out_dir)) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    write_csv(out, file.path(out_dir, "bimodality.csv"))
  }
  out
}
```

- [ ] **Step 4: Run, verify PASS**

Run: `Rscript src/scripts/prospector/test_polarization.R`
Expected: no `FAIL:` lines; the final summary reports all C1a/C1b/C2 assertions passing.

- [ ] **Step 5: Commit**

```bash
git add src/scripts/prospector/polarization.R src/scripts/prospector/test_polarization.R
git commit -m "feat(prospector): detect_bimodality — Pass C2 two-camp split detection"
```

---

## Task 4: Wire C2 into the ABS runner + smoke run

**Files:**
- Modify: `src/scripts/run_abs_all_countries.R`

**Interfaces:**
- Consumes: `detect_bimodality()`; the runner's existing `d` (wide respondent data with `raw_wave_cols` + `country`), `OUTPUT_DIR`, `MIN_WAVES`, `FLAT_THRESHOLD`, and the `polarization.csv` written earlier in the run.

- [ ] **Step 1: Confirm the runner's `compute_means` shape**

Run: `grep -n "compute_means\|pivot_longer\|means_long\|detect_polarization\|detect_sorting\|^vars " src/scripts/run_abs_all_countries.R`
Expected: `compute_means(data)` selects `country, wave, all_of(vars)`, pivots to long `variable`/`value`, groups by `country, wave, variable`, summarises, then `rename(wave_num = wave)`. The wide data `d` already carries a `wave` column and `vars` are harmonized (wave-agnostic) names — so `compute_freqs` needs **no** name-parsing, just a different group-by/summarise.

- [ ] **Step 2: Add a `compute_freqs()` helper right after `compute_means()`**

Immediately after the `compute_means <- function(data) { ... }` definition (the line with `means_long <- compute_means(d)` follows it), insert:

```r
# Long response-frequency table (parallels compute_means) for Pass C2 bimodality:
# same pivot to respondent-level `value`; drop missing; count per response code.
compute_freqs <- function(data) {
  data %>%
    select(country, wave, all_of(vars)) %>%
    pivot_longer(cols = all_of(vars), names_to = "variable", values_to = "value") %>%
    filter(!is.na(value)) %>%
    group_by(country, wave, variable, value) %>%
    summarise(count = n(), .groups = "drop") %>%
    rename(wave_num = wave)
}
```

- [ ] **Step 3: Add the `detect_bimodality` call after the sorting block**

After the `detect_sorting(...)` call (end of the Pass C1b block), add:

```r
# ── PASS C2: bimodality / two-camp split (van der Eijk A) ──────────────────────
cat("\n── Bimodality detection (two-camp split vs uniform spread) ──\n")
frq <- compute_freqs(d)
bim <- detect_bimodality(frq, out_dir = OUTPUT_DIR, min_waves = MIN_WAVES,
                         flat_threshold = FLAT_THRESHOLD, bimodal_A_max = 0.5)
cat(sprintf("bimodality.csv: %d POLARIZING_BIMODAL, %d CONVERGING_UNIMODAL, %d OTHER\n",
            sum(bim$pattern == "POLARIZING_BIMODAL"),
            sum(bim$pattern == "CONVERGING_UNIMODAL"),
            sum(bim$pattern == "OTHER")))
```

(Place it AFTER `detect_polarization` has written `polarization.csv`, so the `c1a_pattern` join lands.)

- [ ] **Step 4: Run the ABS prospector end-to-end**

Run: `Rscript src/scripts/run_abs_all_countries.R > /private/tmp/abs_c2.log 2>&1; tail -20 /private/tmp/abs_c2.log`
Expected: no error; the bimodality line prints nonzero counts.

- [ ] **Step 5: Sanity-check the output + the C1a∩C2 payoff**

```bash
head -1 outputs/prospecting/abs_all/bimodality.csv
cut -d, -f6 outputs/prospecting/abs_all/bimodality.csv | tail -n +2 | sort | uniq -c
# genuine two-camp splits: C1a POLARIZING AND C2 POLARIZING_BIMODAL
awk -F, 'NR>1 && $6=="POLARIZING_BIMODAL" && $7=="POLARIZING"' outputs/prospecting/abs_all/bimodality.csv | head
grep -i "error\|warning" /private/tmp/abs_c2.log || echo "clean"
```
Expected: header `country,variable,A_start,A_end,pol_slope,pattern,c1a_pattern`; a plausible spread of the three patterns; the `awk` filter lists the items where a rising SD (C1a) is confirmed as a real two-camp split (C2). No errors.

- [ ] **Step 6: Confirm existing suites still green (no regressions)**

```bash
Rscript src/scripts/prospector/test_polarization.R
Rscript src/scripts/prospector/test_signature_match.R
```
Expected: `test_polarization.R` all-pass (C1a + C1b + C2); `test_signature_match.R` `69 passed, 0 failed`.

- [ ] **Step 7: Commit**

```bash
git add src/scripts/run_abs_all_countries.R
git commit -m "feat(prospector): wire Pass C2 bimodality into the ABS runner"
```

---

## Task 5: Documentation

**Files:**
- Modify: `docs/SLOPE_PROSPECTOR.md`
- Modify: `docs/superpowers/specs/2026-07-14-prospector-bimodality-passC2-design.md`

- [ ] **Step 1: Add `bimodality.csv` to the outputs table**

In `docs/SLOPE_PROSPECTOR.md`, in the outputs table (below the `sorting.csv` row added for C1b), add:

```markdown
| `bimodality.csv` | *(Pass C add-on)* Per country×variable: response distribution splitting into two camps over waves (van der Eijk *A*) — `POLARIZING_BIMODAL` / `CONVERGING_UNIMODAL` / `OTHER`, with `c1a_pattern` joined from `polarization.csv` |
```

Update the intro line's count from "**2 dispersion outputs**" to "**3 dispersion outputs**".

- [ ] **Step 2: Add a C2 subsection under "Dispersion / polarization (Pass C)"**

After the C1b paragraph, add:

```markdown
**C2 — bimodality / two-camp split → `bimodality.csv`.** C1a's rising SD is
ambiguous: a distribution can spread *uniformly* or split into *two camps*. C2
resolves this with **van der Eijk's agreement *A*** (van der Eijk 2001) on the
ordinal response distribution per country×wave×variable: *A* = +1 (all mass in one
category), 0 (uniform), −1 (50/50 at the two extremes). `detect_bimodality` runs
the trend of `−A` through the same slope machinery and classifies
`POLARIZING_BIMODAL` (`−A` rising past `FLAT_THRESHOLD` **and** `A_end` below
`bimodal_A_max`, default 0.5 — a genuine split, not merely less-agreed),
`CONVERGING_UNIMODAL`, or `OTHER`. Requires ≥3 response categories. The output
carries `c1a_pattern` from `polarization.csv`, so **C1a `POLARIZING` ∩ C2
`POLARIZING_BIMODAL` = a real two-camp split**, vs. C1a `POLARIZING` ∩ C2 `OTHER`
= uniform spread. Unweighted frequencies, ABS-only wiring — same caveats as C1a/C1b.
```

- [ ] **Step 3: Flip the spec status to implemented**

In `docs/superpowers/specs/2026-07-14-prospector-bimodality-passC2-design.md`, change the `Status:` line to:

```markdown
Status: implemented (van der Eijk's *A*, self-contained port; ABS wired).
```

- [ ] **Step 4: Commit**

```bash
git add docs/SLOPE_PROSPECTOR.md docs/superpowers/specs/2026-07-14-prospector-bimodality-passC2-design.md
git commit -m "docs(prospector): document Pass C2 bimodality output + DSL"
```

---

## Self-Review

- **Spec coverage:**
  - Statistic (van der Eijk *A*, `−A` through `.pol_slopes`) → Task 1 + Task 3.
  - Per-cell *A*, K = contiguous span, integer-code guard, K∈[3, max_categories] gate → Task 2 + Task 3 filter.
  - Classification (`POLARIZING_BIMODAL` w/ `A_end` guard, `CONVERGING_UNIMODAL`, `OTHER`) → Task 3.
  - Output `bimodality.csv` columns + `c1a_pattern` join → Task 3.
  - Runner wiring (`compute_freqs` + call, ABS-only, after `polarization.csv`) → Task 4.
  - Testing (anchors, per-wave A, integer guard, unimodal→bimodal, reverse, shift-not-detected, K<3, K>max, min_waves, A_end guard, join) → Tasks 1–3.
  - Docs + spec status → Task 5.
  - Non-goals (weights, cross-survey, other cleavages) respected — not implemented.
- **Placeholder scan:** every code step contains runnable, complete R (`compute_freqs` included — the runner has a `wave` column, so no survey-specific parsing is needed). No TBD/TODO. Two robustness guards not in the original spec were added during planning (integer-code guard, `max_categories`) because the runner's `vars` set includes numeric non-nominal columns that can be fractional (`*_01`) or quasi-continuous — both would otherwise break or badly slow the ordinal-lattice logic.
- **Type consistency:** `.vdeijk_A(freq)->numeric`; `.bimodality_by_wave(freqs)->{country,wave_num,variable,A,K,n}`; `detect_bimodality(freqs,out_dir,min_waves,flat_threshold,bimodal_A_max,max_categories)->{country,variable,A_start,A_end,pol_slope,pattern,c1a_pattern}`; `.pol_slopes(df, <bare col>, min_waves)->{country,variable,slope}` reused exactly as `detect_polarization`/`detect_sorting` call it. `country` is coerced to character inside `detect_bimodality` before the C1a join, matching the `as.character` cast on the read-back side.
