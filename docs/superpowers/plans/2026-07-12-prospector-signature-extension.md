# Prospector Signature Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the Slope Prospector's narrative-signature detector with a larger signature catalog and a richer matching vocabulary (level, magnitude, shape, break-timing, within-group splits), without breaking the 8 existing signatures.

**Architecture:** Extract signature detection out of the `slope_prospector.R` monolith into a small tested unit under `src/scripts/prospector/`. Signatures become YAML data (`signatures.yml`); a condition evaluator reads a precomputed country×group *feature frame*. A bare `"FALLING"` slot normalizes to `list(dir="FALLING")`, so every current signature parses unchanged.

**Tech Stack:** R (tidyverse, yaml, broom, strucchange), `testthat`-free assertion style matching `src/r/audit/test_*.R` (base `stopifnot` + `cat`), run via `Rscript`.

## Global Constraints

- No R MCP — every check runs via `Rscript` in bash.
- Commit messages: **no** `Co-Authored-By` / "Generated with" attribution.
- Work stays on branch `feat/prospector-signature-extension`.
- Do not modify prospector stages other than signature detection (section 10) and the globals block; leave slope estimation, normalization, outliers, divergence, clustering, dashboards untouched.
- Existing artifact contracts are additive-only: never drop a column from `narrative_patterns.csv`, `slope_groups.csv`, `structural_breaks.csv`, or `acceleration.csv`.
- `harmonized_data$mean_value` is already normalized to [0,1] per variable by the time the feature builder sees it — endpoint level uses that normalized scale.
- Concept-group direction values are exactly `RISING` / `FALLING` / `FLAT`; group coherence flags are exactly `COHERENT_RISING` / `COHERENT_FALLING` / `DIVERGENT`.

---

## File Structure

- Create `src/scripts/prospector/signatures.yml` — signature registry (data).
- Create `src/scripts/prospector/signature_match.R` — registry loader + condition evaluator (`load_signatures`, `normalize_condition`, `eval_simple_condition`, `eval_within`, `eval_ordered`, `match_signatures`).
- Create `src/scripts/prospector/signature_features.R` — feature builders (`augment_breaks_with_location`, `build_group_features`).
- Create `src/scripts/prospector/test_signature_match.R` — fault-injection + behavior-lock tests.
- Modify `src/scripts/slope_prospector.R` — delete inline `NARRATIVE_PATTERNS` (lines 86-139); replace section 10 (lines 605-659) with a `source()` + `match_signatures()` call; add new tunable globals near line 47.

---

## PHASE 0 — Extract & externalize (zero behavior change)

### Task 0.1: Signature registry YAML + loader

**Files:**
- Create: `src/scripts/prospector/signatures.yml`
- Create: `src/scripts/prospector/signature_match.R`
- Test: `src/scripts/prospector/test_signature_match.R`

**Interfaces:**
- Produces: `load_signatures(path) -> named list`, each element `list(label=, description=, required=<named list>, supporting=<named list>)` — structurally identical to the old `NARRATIVE_PATTERNS`.

- [ ] **Step 1: Write `signatures.yml` with the 8 existing signatures**

Copy the exact directions from `slope_prospector.R:86-139`:

```yaml
# Signature registry for the Slope Prospector.
# A slot value is a direction (RISING/FALLING/FLAT), a list of allowed
# directions, or (Phase 2) a condition map {dir:, magnitude:, shape:, level:}.
signatures:
  output_legitimacy:
    label: "Output Legitimacy Signature"
    description: "Economic satisfaction rising while democratic quality assessment is flat/falling"
    required: { economic_present: RISING, democratic_satisfaction: RISING }
    supporting: { democracy_assessment_empirical: [FALLING, FLAT] }
  demobilization:
    label: "Demobilization Sequence"
    description: "Contacting/protest collapsing while authoritarian support rises"
    required: { political_action_contacting_protest: FALLING, authoritarian_support: RISING }
  aspiration_gap:
    label: "Democratic Aspiration Gap"
    description: "Normative democratic preference stable while empirical assessment falls"
    required: { democracy_assessment_empirical: FALLING }
    supporting: { democracy_support_normative: [RISING, FLAT] }
  hollow_citizenship:
    label: "Hollow Citizenship"
    description: "Voting stable/rising while contacting and protest fall sharply"
    required: { political_action_contacting_protest: FALLING }
    supporting: { political_action_voting: [RISING, FLAT] }
  trust_collapse:
    label: "Trust Collapse"
    description: "Both executive and intermediary institutions losing trust together"
    required: { institutional_trust_executive: FALLING, institutional_trust_intermediary: FALLING }
  selective_legitimation:
    label: "Selective Legitimation"
    description: "Executive trust rising while courts, parties, media fall"
    required: { institutional_trust_executive: RISING, institutional_trust_intermediary: FALLING }
  economic_pessimism:
    label: "Economic Pessimism Decoupling"
    description: "Present economic conditions stable while outlook deteriorates"
    required: { economic_outlook: FALLING }
    supporting: { economic_present: [RISING, FLAT] }
  corruption_normalization:
    label: "Corruption Normalization"
    description: "Witnessed corruption falls while perceived systemic corruption stays high"
    required: { corruption: FLAT }
```

- [ ] **Step 2: Write the failing loader test**

Create `test_signature_match.R`:

```r
suppressMessages(library(tidyverse)); library(yaml)
here_dir <- file.path("src", "scripts", "prospector")
source(file.path(here_dir, "signature_match.R"))
pass <- 0L; fail <- 0L
ok <- function(cond, msg) { if (isTRUE(cond)) { pass <<- pass + 1L } else { fail <<- fail + 1L; cat("FAIL:", msg, "\n") } }

sigs <- load_signatures(file.path(here_dir, "signatures.yml"))
ok(length(sigs) == 8, "8 signatures loaded")
ok(identical(sigs$aspiration_gap$required$democracy_assessment_empirical, "FALLING"), "aspiration_gap required dir")
ok(setequal(unlist(sigs$output_legitimacy$supporting$democracy_assessment_empirical), c("FALLING","FLAT")), "output_legitimacy supporting vector")
```

- [ ] **Step 3: Run it, verify it fails**

Run: `Rscript src/scripts/prospector/test_signature_match.R`
Expected: FAIL — `could not find function "load_signatures"`.

- [ ] **Step 4: Implement `load_signatures`**

Create `signature_match.R`:

```r
# Signature registry loader + condition evaluator for the Slope Prospector.
library(yaml)

load_signatures <- function(path) {
  raw <- yaml.load_file(path)
  raw$signatures
}
```

- [ ] **Step 5: Run test, verify PASS**

Run: `Rscript src/scripts/prospector/test_signature_match.R`
Expected: prints no `FAIL:` lines for these three assertions.

- [ ] **Step 6: Commit**

```bash
git add src/scripts/prospector/signatures.yml src/scripts/prospector/signature_match.R src/scripts/prospector/test_signature_match.R
git commit -m "feat(prospector): externalize signature registry to signatures.yml"
```

### Task 0.2: Condition normalizer + simple evaluator + `match_signatures` (direction-only)

**Files:**
- Modify: `src/scripts/prospector/signature_match.R`
- Test: `src/scripts/prospector/test_signature_match.R`

**Interfaces:**
- Consumes: `load_signatures()` output; a `features` tibble with columns `country, group, group_direction`.
- Produces:
  - `normalize_condition(slot) -> list` with a `dir` element (Phase 0) plus optional `magnitude/shape/level` (Phase 2).
  - `eval_simple_condition(cond, feat_row) -> logical(1)`.
  - `match_signatures(features, sigs, var_slopes=NULL) -> tibble(country, pattern_id, label, description)`.

- [ ] **Step 1: Write failing tests for normalize + match**

Append to `test_signature_match.R`:

```r
# normalize_condition
ok(identical(normalize_condition("FALLING"), list(dir = "FALLING")), "string -> dir list")
ok(setequal(normalize_condition(list("RISING","FLAT"))$dir, c("RISING","FLAT")), "unnamed list -> dir vector")
ok(identical(normalize_condition(list(dir="RISING", level="ENDS_HIGH"))$level, "ENDS_HIGH"), "named cond passthrough")

# match_signatures on a synthetic feature frame
feats <- tribble(
  ~country, ~group,                              ~group_direction,
  "X",      "institutional_trust_executive",     "FALLING",
  "X",      "institutional_trust_intermediary",  "FALLING",
  "Y",      "institutional_trust_executive",     "RISING",
  "Y",      "institutional_trust_intermediary",  "FALLING"
)
m <- match_signatures(feats, sigs)
ok("trust_collapse" %in% m$pattern_id[m$country=="X"], "X fires trust_collapse")
ok(!("trust_collapse" %in% m$pattern_id[m$country=="Y"]), "Y does not fire trust_collapse")
ok("selective_legitimation" %in% m$pattern_id[m$country=="Y"], "Y fires selective_legitimation")
```

- [ ] **Step 2: Run, verify FAIL**

Run: `Rscript src/scripts/prospector/test_signature_match.R`
Expected: FAIL — `could not find function "normalize_condition"`.

- [ ] **Step 3: Implement normalizer + evaluator + matcher**

Append to `signature_match.R`:

```r
# A slot is: a scalar direction, an unnamed list/vector of directions, or a
# named condition map {dir=, magnitude=, shape=, level=}.
normalize_condition <- function(slot) {
  if (is.character(slot)) return(list(dir = slot))
  if (is.list(slot) && is.null(names(slot))) return(list(dir = unlist(slot)))
  if (is.list(slot)) {
    if (!is.null(slot$dir))       slot$dir       <- unlist(slot$dir)
    if (!is.null(slot$magnitude)) slot$magnitude <- unlist(slot$magnitude)
    if (!is.null(slot$shape))     slot$shape     <- unlist(slot$shape)
    if (!is.null(slot$level))     slot$level     <- unlist(slot$level)
    return(slot)
  }
  list(dir = as.character(slot))
}

# Evaluate one condition against one feature-frame row (a 1-row tibble/list).
# Every sub-key present in the condition AND available in the row must hold.
eval_simple_condition <- function(cond, row) {
  c <- normalize_condition(cond)
  checks <- c(
    if (!is.null(c$dir))       row$group_direction %in% c$dir,
    if (!is.null(c$magnitude) && !is.null(row$magnitude_tier)) row$magnitude_tier %in% c$magnitude,
    if (!is.null(c$shape)     && !is.null(row$shape))          row$shape          %in% c$shape,
    if (!is.null(c$level)     && !is.null(row$ends_level))     row$ends_level     %in% c$level
  )
  length(checks) > 0 && all(checks)
}

.row_for <- function(features, cty, grp) {
  r <- features[features$country == cty & features$group == grp, , drop = FALSE]
  if (nrow(r) == 0) return(NULL)
  as.list(r[1, ])
}

# required: group must be present AND condition holds.
# supporting: if group absent, don't penalise; if present, condition must hold.
.eval_required <- function(reqs, features, cty) {
  if (length(reqs) == 0) return(TRUE)
  all(vapply(names(reqs), function(g) {
    row <- .row_for(features, cty, g); !is.null(row) && eval_simple_condition(reqs[[g]], row)
  }, logical(1)))
}
.eval_supporting <- function(sups, features, cty) {
  if (length(sups) == 0) return(TRUE)
  all(vapply(names(sups), function(g) {
    row <- .row_for(features, cty, g); is.null(row) || eval_simple_condition(sups[[g]], row)
  }, logical(1)))
}

match_signatures <- function(features, sigs, var_slopes = NULL) {
  countries <- unique(features$country)
  out <- purrr::map_dfr(countries, function(cty) {
    purrr::map_dfr(names(sigs), function(pid) {
      s <- sigs[[pid]]
      req <- .eval_required(s$required %||% list(), features, cty)
      sup <- .eval_supporting(s$supporting %||% list(), features, cty)
      lvl <- .eval_required(s$level %||% list(), features, cty)      # Phase 2, treated as required
      if (req && sup && lvl)
        tibble(country = cty, pattern_id = pid, label = s$label, description = s$description)
      else tibble()
    })
  })
  if (nrow(out) == 0) return(tibble(country=character(), pattern_id=character(),
                                    label=character(), description=character()))
  dplyr::arrange(out, country, pattern_id)
}
```

- [ ] **Step 4: Run test, verify PASS**

Run: `Rscript src/scripts/prospector/test_signature_match.R`
Expected: no `FAIL:` lines.

- [ ] **Step 5: Commit**

```bash
git add src/scripts/prospector/signature_match.R src/scripts/prospector/test_signature_match.R
git commit -m "feat(prospector): condition evaluator + match_signatures (direction-only, backward-compatible)"
```

### Task 0.3: Behavior-lock against the current ABS run

**Files:**
- Test: `src/scripts/prospector/test_signature_match.R`

**Interfaces:**
- Consumes: existing `outputs/prospecting/abs_all/slope_groups.csv` (has `country, group, group_direction`) and `outputs/prospecting/abs_all/narrative_patterns.csv` (the golden).

- [ ] **Step 1: Write the golden-equivalence test**

Append to `test_signature_match.R`:

```r
gold_dir <- file.path("outputs", "prospecting", "abs_all")
if (file.exists(file.path(gold_dir, "slope_groups.csv"))) {
  sg   <- readr::read_csv(file.path(gold_dir, "slope_groups.csv"), show_col_types = FALSE)
  gold <- readr::read_csv(file.path(gold_dir, "narrative_patterns.csv"), show_col_types = FALSE)
  feats_real <- sg %>% dplyr::select(country, group, group_direction) %>%
    dplyr::mutate(country = as.character(country))
  got <- match_signatures(feats_real, sigs) %>%
    dplyr::mutate(country = as.character(country)) %>%
    dplyr::arrange(country, pattern_id)
  gold2 <- gold %>% dplyr::mutate(country = as.character(country)) %>%
    dplyr::select(country, pattern_id) %>% dplyr::arrange(country, pattern_id)
  ok(identical(got$pattern_id, gold2$pattern_id) &&
     identical(got$country, gold2$country), "behavior-lock: matches current narrative_patterns.csv")
} else {
  cat("SKIP behavior-lock (no abs_all run present)\n")
}
cat(sprintf("\n%d passed, %d failed\n", pass, fail)); if (fail > 0) quit(status = 1)
```

- [ ] **Step 2: Run — this passes NOW (golden was produced by the code we are about to replace)**

Run: `Rscript src/scripts/prospector/test_signature_match.R`
Expected: `... passed, 0 failed`. If the behavior-lock line FAILS here, the evaluator diverges from current logic — fix `signature_match.R` before touching the monolith.

- [ ] **Step 3: Commit the locked baseline**

```bash
git add src/scripts/prospector/test_signature_match.R
git commit -m "test(prospector): behavior-lock signature matcher against abs_all golden"
```

### Task 0.4: Wire the module into `slope_prospector.R`, delete inline patterns

**Files:**
- Modify: `src/scripts/slope_prospector.R`

**Interfaces:**
- Consumes: `match_signatures`, `load_signatures`; the existing `group_coherence` tibble (has `country, group, group_direction`).

- [ ] **Step 1: Capture a pre-change golden copy (safety net)**

```bash
cp outputs/prospecting/abs_all/narrative_patterns.csv /private/tmp/np_before.csv
```

- [ ] **Step 2: Delete the inline `NARRATIVE_PATTERNS` block**

Remove `slope_prospector.R` lines 86-139 (the whole `NARRATIVE_PATTERNS <- list(...)` definition).

- [ ] **Step 3: Add a source() near the other config, after the globals block (~line 48)**

```r
source(file.path("src", "scripts", "prospector", "signature_features.R"))
source(file.path("src", "scripts", "prospector", "signature_match.R"))
SIGNATURES_PATH <- file.path("src", "scripts", "prospector", "signatures.yml")
```

(`signature_features.R` is created empty-of-behavior in Phase 2; add a placeholder file now containing only a comment so the `source()` succeeds: `# feature builders — populated in Phase 2`.)

- [ ] **Step 4: Replace section 10 body (lines ~605-659) with the module call**

```r
# ── 10. NARRATIVE PATTERN TAGGING ──────────────────────────────────────────
narrative_results <- tibble()
if (DO_NARRATIVE && nrow(group_coherence) > 0) {
  cat("\n── Narrative pattern detection ──\n")
  sigs <- load_signatures(SIGNATURES_PATH)
  features <- group_coherence %>%
    mutate(country = as.character(country))   # Phase 2 enriches this frame
  narrative_results <- match_signatures(features, sigs)
  cat(sprintf("%d narrative pattern matches found\n", nrow(narrative_results)))
  write_csv(narrative_results, file.path(OUTPUT_DIR, "narrative_patterns.csv"))
  cat(sprintf("── Saved: %s/narrative_patterns.csv ──\n", OUTPUT_DIR))
}
```

- [ ] **Step 5: Re-run the ABS prospector and diff**

```bash
Rscript src/scripts/run_abs_all_countries.R > /private/tmp/abs_rerun.log 2>&1
diff <(sort /private/tmp/np_before.csv) <(sort outputs/prospecting/abs_all/narrative_patterns.csv) && echo "IDENTICAL"
```
Expected: `IDENTICAL`. (Country codes are integers in the file; sorting both sides handles ordering.)

- [ ] **Step 6: Run the unit tests again**

Run: `Rscript src/scripts/prospector/test_signature_match.R`
Expected: `... passed, 0 failed`.

- [ ] **Step 7: Commit**

```bash
git add src/scripts/slope_prospector.R src/scripts/prospector/signature_features.R
git commit -m "refactor(prospector): move narrative detection into prospector/ module (no behavior change)"
```

---

## PHASE 1 — Six new current-engine signatures

### Task 1.1: Add Phase-1 signatures + firing tests

**Files:**
- Modify: `src/scripts/prospector/signatures.yml`
- Test: `src/scripts/prospector/test_signature_match.R`

**Interfaces:** unchanged (all use `dir` conditions on existing concept groups).

- [ ] **Step 1: Write failing firing/non-firing tests**

Append to `test_signature_match.R` (before the final summary line — move the summary/`quit` to the very end):

```r
sigs <- load_signatures(file.path(here_dir, "signatures.yml"))  # reload with new entries
feq <- function(...) tribble(~country, ~group, ~group_direction, ...) %>% mutate(country=as.character(country))

# authoritarian_drift: normative FALLING + authoritarian RISING
f1 <- feq("A","democracy_support_normative","FALLING", "A","authoritarian_support","RISING")
ok("authoritarian_drift" %in% match_signatures(f1, sigs)$pattern_id, "authoritarian_drift fires")

# diffuse_specific_decoupling: satisfaction FALLING, normative FLAT (supporting)
f2 <- feq("B","democratic_satisfaction","FALLING", "B","democracy_support_normative","FLAT")
ok("diffuse_specific_decoupling" %in% match_signatures(f2, sigs)$pattern_id, "diffuse_specific fires")
# negative control: normative FALLING violates supporting
f2b <- feq("C","democratic_satisfaction","FALLING", "C","democracy_support_normative","FALLING")
ok(!("diffuse_specific_decoupling" %in% match_signatures(f2b, sigs)$pattern_id), "diffuse_specific blocked by falling normative")

# accountable_dissatisfaction (health): satisfaction + exec trust FALLING, normative RISING
f3 <- feq("D","democratic_satisfaction","FALLING", "D","institutional_trust_executive","FALLING",
          "D","democracy_support_normative","RISING")
ok("accountable_dissatisfaction" %in% match_signatures(f3, sigs)$pattern_id, "accountable_dissatisfaction fires")
```

- [ ] **Step 2: Run, verify FAIL** (new pattern ids absent)

Run: `Rscript src/scripts/prospector/test_signature_match.R`
Expected: FAIL lines for the new signatures.

- [ ] **Step 3: Append the six signatures to `signatures.yml`**

```yaml
  authoritarian_drift:
    label: "Authoritarian Drift"
    description: "Normative democratic support falling while support for authoritarian alternatives rises"
    required: { democracy_support_normative: FALLING, authoritarian_support: RISING }
  diffuse_specific_decoupling:
    label: "Diffuse-Specific Decoupling"
    description: "Satisfaction with democratic performance falls while diffuse commitment to democracy holds"
    required: { democratic_satisfaction: FALLING }
    supporting: { democracy_support_normative: [RISING, FLAT] }
  rule_of_law_erosion:
    label: "Rule-of-Law Erosion"
    description: "Equal-treatment / rule-of-law perceptions fall alongside weakening accountability"
    required: { rule_of_law: FALLING }
    supporting: { accountability_perceptions: [FALLING, FLAT] }
  alienation_withdrawal:
    label: "Alienation Withdrawal"
    description: "Political efficacy falls and non-electoral participation collapses together"
    required: { political_efficacy: FALLING, political_action_contacting_protest: FALLING }
  output_trust_legitimation:
    label: "Output Trust Legitimation"
    description: "Economic conditions and executive trust rise while empirical democratic quality is flat/falling"
    required: { economic_present: RISING, institutional_trust_executive: RISING }
    supporting: { democracy_assessment_empirical: [FALLING, FLAT] }
  accountable_dissatisfaction:
    label: "Accountable Dissatisfaction"
    description: "Satisfaction and executive trust fall while diffuse democratic commitment holds — accountability working"
    required: { democratic_satisfaction: FALLING, institutional_trust_executive: FALLING }
    supporting: { democracy_support_normative: [RISING, FLAT] }
```

- [ ] **Step 4: Run tests, verify PASS**

Run: `Rscript src/scripts/prospector/test_signature_match.R`
Expected: `... passed, 0 failed`. The behavior-lock test still passes (new signatures only ADD matches; verify the golden test was written to check the 8 original ids are a subset — if it uses `identical`, update it to assert the 8 golden ids are all present via `all(gold2$pattern_id %in% got$pattern_id)` and that no golden row is lost).

- [ ] **Step 5: Re-run ABS to see the new catalog fire, sanity-check counts**

```bash
Rscript src/scripts/run_abs_all_countries.R > /private/tmp/abs_p1.log 2>&1
cut -d, -f2 outputs/prospecting/abs_all/narrative_patterns.csv | sort | uniq -c
```
Expected: the 8 original ids plus some of the 6 new ids; no crash.

- [ ] **Step 6: Commit**

```bash
git add src/scripts/prospector/signatures.yml src/scripts/prospector/test_signature_match.R
git commit -m "feat(prospector): add six Phase-1 theoretical signatures"
```

---

## PHASE 2 — Richer primitives

### Task 2.1: Break-location detection (`strucchange::breakpoints`)

**Files:**
- Create: `src/scripts/prospector/signature_features.R` (replace placeholder)
- Test: `src/scripts/prospector/test_signature_match.R`

**Interfaces:**
- Produces: `augment_breaks_with_location(eligible, sig_breaks) -> tibble(country, variable, break_wave)`.
  - `eligible`: country×variable×wave rows (normalized `mean_value`, `wave_num`), ≥4 waves.
  - `sig_breaks`: the `significant_breaks` tibble (country, variable) to restrict work to real breaks.

- [ ] **Step 1: Write failing break-location test**

Append to `test_signature_match.R`:

```r
source(file.path(here_dir, "signature_features.R"))
# synthetic: flat at 0.2 for waves 1-3, jump to 0.8 waves 4-6 -> break near wave 3/4
synth <- tidyr::expand_grid(country="Z", variable="v", wave_num=1:6) %>%
  mutate(mean_value = if_else(wave_num <= 3, 0.2, 0.8))
sb <- tibble(country="Z", variable="v")
bl <- augment_breaks_with_location(synth, sb)
ok(nrow(bl) == 1 && !is.na(bl$break_wave) && bl$break_wave %in% c(3,4), "break located at wave 3 or 4")
```

- [ ] **Step 2: Run, verify FAIL**

Run: `Rscript src/scripts/prospector/test_signature_match.R`
Expected: FAIL — `could not find function "augment_breaks_with_location"`.

- [ ] **Step 3: Implement break-location**

Write `signature_features.R`:

```r
# Feature builders for the Slope Prospector signature matcher.
suppressMessages({ library(tidyverse); library(strucchange) })

# Estimate the wave at which each significant break occurs.
augment_breaks_with_location <- function(eligible, sig_breaks) {
  targets <- eligible %>% semi_join(sig_breaks, by = c("country","variable"))
  if (nrow(targets) == 0)
    return(tibble(country=character(), variable=character(), break_wave=numeric()))
  targets %>%
    group_by(country, variable) %>%
    group_modify(~ {
      ts <- .x %>% arrange(wave_num)
      wave <- tryCatch({
        bp <- strucchange::breakpoints(mean_value ~ wave_num, data = ts, h = 2)
        idx <- bp$breakpoints
        if (length(idx) == 0 || all(is.na(idx))) NA_real_ else ts$wave_num[idx[1]]
      }, error = function(e) NA_real_)
      tibble(break_wave = wave)
    }) %>%
    ungroup()
}
```

- [ ] **Step 4: Run test, verify PASS**

Run: `Rscript src/scripts/prospector/test_signature_match.R`
Expected: no `FAIL:` lines.

- [ ] **Step 5: Commit**

```bash
git add src/scripts/prospector/signature_features.R src/scripts/prospector/test_signature_match.R
git commit -m "feat(prospector): estimate structural-break wave via strucchange::breakpoints"
```

### Task 2.2: `build_group_features` — magnitude, shape, ends_level, broke_at_wave

**Files:**
- Modify: `src/scripts/prospector/signature_features.R`
- Test: `src/scripts/prospector/test_signature_match.R`

**Interfaces:**
- Produces: `build_group_features(group_coherence, harmonized_data, acceleration, breaks_located, group_lookup, thr) -> tibble` — `group_coherence` columns plus `magnitude_tier, shape, ends_level, broke_at_wave`.
  - `thr = list(FAST=, ENDS_LOW=, ENDS_HIGH=, SHAPE_QUORUM=)`.
  - `group_lookup`: tibble(group, variable) as built in `slope_prospector.R:436-438`.

- [ ] **Step 1: Write failing feature-frame test**

Append to `test_signature_match.R`:

```r
thr <- list(FAST = 0.15, ENDS_LOW = 0.33, ENDS_HIGH = 0.66, SHAPE_QUORUM = 0.5)
gl  <- tibble(group = "g", variable = c("a","b"))
gc  <- tibble(country="Z", group="g", group_direction="RISING", mean_slope=0.20,
              sd_slope=0, n_vars=2, coherence_flag="COHERENT_RISING")
# endpoints: both members end high (0.8)
hd  <- tidyr::expand_grid(country="Z", variable=c("a","b"), wave_num=1:3) %>%
  mutate(mean_value = if_else(wave_num==3, 0.8, 0.3))
acc <- tibble(country="Z", variable=c("a","b"),
              early_slope=c(-0.1,-0.1), late_slope=c(0.3,0.3),
              acceleration=c(0.4,0.4), direction_change=c(TRUE,TRUE))
bl  <- tibble(country="Z", variable=c("a","b"), break_wave=c(2,2))
gf  <- build_group_features(gc, hd, acc, bl, gl, thr)
ok(gf$magnitude_tier == "FAST", "magnitude FAST (|0.20|>0.15)")
ok(gf$ends_level == "HIGH", "ends_level HIGH (0.8>0.66)")
ok(gf$shape == "REVERSED_UP", "shape REVERSED_UP (down then up)")
ok(gf$broke_at_wave == 2, "broke_at_wave = 2 (modal)")
```

- [ ] **Step 2: Run, verify FAIL**

Run: `Rscript src/scripts/prospector/test_signature_match.R`
Expected: FAIL — `could not find function "build_group_features"`.

- [ ] **Step 3: Implement `build_group_features`**

Append to `signature_features.R`:

```r
build_group_features <- function(group_coherence, harmonized_data, acceleration,
                                 breaks_located, group_lookup, thr) {
  gc <- group_coherence %>% mutate(country = as.character(country))

  # magnitude
  gc <- gc %>% mutate(magnitude_tier = if_else(abs(mean_slope) > thr$FAST, "FAST", "SLOW"))

  # endpoint level: last-wave normalized value per member, averaged per group
  last_vals <- harmonized_data %>%
    mutate(country = as.character(country)) %>%
    group_by(country, variable) %>%
    slice_max(wave_num, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(country, variable, end_val = mean_value) %>%
    inner_join(group_lookup, by = "variable") %>%
    group_by(country, group) %>%
    summarise(end_level = mean(end_val, na.rm = TRUE), .groups = "drop") %>%
    mutate(ends_level = case_when(end_level > thr$ENDS_HIGH ~ "HIGH",
                                  end_level < thr$ENDS_LOW  ~ "LOW",
                                  TRUE                      ~ "MID"))

  # shape: aggregate acceleration over group members with a quorum
  shape_tbl <- acceleration %>%
    mutate(country = as.character(country)) %>%
    inner_join(group_lookup, by = "variable") %>%
    group_by(country, group) %>%
    summarise(
      n = n(),
      rev_up   = mean(direction_change & early_slope <= 0 & late_slope > 0),
      rev_down = mean(direction_change & early_slope >= 0 & late_slope < 0),
      accel    = mean(!direction_change & abs(late_slope) > abs(early_slope)),
      decel    = mean(!direction_change & abs(late_slope) < abs(early_slope)),
      .groups = "drop"
    ) %>%
    mutate(shape = case_when(
      rev_up   >= thr$SHAPE_QUORUM ~ "REVERSED_UP",
      rev_down >= thr$SHAPE_QUORUM ~ "REVERSED_DOWN",
      accel    >= thr$SHAPE_QUORUM ~ "ACCELERATING",
      decel    >= thr$SHAPE_QUORUM ~ "DECELERATING",
      TRUE                         ~ "STEADY"
    )) %>%
    select(country, group, shape)

  # broke_at_wave: modal member break wave
  broke_tbl <- breaks_located %>%
    mutate(country = as.character(country)) %>%
    inner_join(group_lookup, by = "variable") %>%
    filter(!is.na(break_wave)) %>%
    group_by(country, group) %>%
    summarise(broke_at_wave = as.numeric(names(sort(table(break_wave), decreasing = TRUE))[1]),
              .groups = "drop")

  gc %>%
    left_join(last_vals  %>% select(country, group, ends_level), by = c("country","group")) %>%
    left_join(shape_tbl,  by = c("country","group")) %>%
    left_join(broke_tbl,  by = c("country","group")) %>%
    mutate(ends_level = replace_na(ends_level, "MID"),
           shape      = replace_na(shape, "STEADY"))
}
```

- [ ] **Step 4: Run test, verify PASS**

Run: `Rscript src/scripts/prospector/test_signature_match.R`
Expected: no `FAIL:` lines.

- [ ] **Step 5: Commit**

```bash
git add src/scripts/prospector/signature_features.R src/scripts/prospector/test_signature_match.R
git commit -m "feat(prospector): build enriched country×group feature frame"
```

### Task 2.3: `within` and `ordered` evaluators

**Files:**
- Modify: `src/scripts/prospector/signature_match.R`
- Test: `src/scripts/prospector/test_signature_match.R`

**Interfaces:**
- Consumes: `var_slopes` tibble `country, variable, direction` (from `slopes` in `slope_prospector.R:282-286`); feature frame with `broke_at_wave, group_direction`.
- Produces: `eval_within(within_spec, var_slopes, cty) -> logical`; `eval_ordered(ordered_spec, features, cty) -> logical`; both wired into `match_signatures`.

- [ ] **Step 1: Write failing within/ordered tests**

Append to `test_signature_match.R`:

```r
vs <- tibble(country="W", variable=c("efficacy_ability_participate","efficacy_no_influence"),
             direction=c("RISING","RISING"))
within_spec <- list(political_efficacy = list(efficacy_ability_participate="RISING",
                                              efficacy_no_influence="RISING"))
ok(eval_within(within_spec, vs, "W"), "within fires when all sub-vars match")
vs2 <- vs %>% mutate(direction = c("RISING","FALLING"))
ok(!eval_within(within_spec, vs2, "W"), "within blocked when one sub-var mismatches")

fo <- tribble(~country,~group,~group_direction,~broke_at_wave,
  "S","political_action_contacting_protest","FALLING",3,
  "S","authoritarian_support","RISING",4)
ordered_spec <- list(list(group="political_action_contacting_protest", dir="FALLING"),
                     list(group="authoritarian_support", dir="RISING"))
ok(eval_ordered(ordered_spec, fo, "S"), "ordered fires when protest breaks before authoritarian rise")
fo2 <- fo %>% mutate(broke_at_wave = c(5,4))  # protest breaks AFTER
ok(!eval_ordered(ordered_spec, fo2, "S"), "ordered blocked when order reversed")
```

- [ ] **Step 2: Run, verify FAIL**

Run: `Rscript src/scripts/prospector/test_signature_match.R`
Expected: FAIL — `could not find function "eval_within"`.

- [ ] **Step 3: Implement the two evaluators and wire them in**

Append to `signature_match.R`:

```r
# within: every named sub-variable in the group must match its direction.
eval_within <- function(within_spec, var_slopes, cty) {
  if (is.null(within_spec) || length(within_spec) == 0) return(TRUE)
  vs <- var_slopes[var_slopes$country == cty, , drop = FALSE]
  all(vapply(names(within_spec), function(grp) {
    reqs <- within_spec[[grp]]
    all(vapply(names(reqs), function(v) {
      d <- vs$direction[vs$variable == v]
      length(d) == 1 && d %in% unlist(reqs[[v]])
    }, logical(1)))
  }, logical(1)))
}

# ordered: list in temporal order; each group's break wave must be non-NA,
# its group_direction must match dir, and break waves must be non-decreasing.
eval_ordered <- function(ordered_spec, features, cty) {
  if (is.null(ordered_spec) || length(ordered_spec) == 0) return(TRUE)
  rows <- lapply(ordered_spec, function(item) .row_for(features, cty, item$group))
  if (any(vapply(rows, is.null, logical(1)))) return(FALSE)
  waves <- vapply(rows, function(r) as.numeric(r$broke_at_wave %||% NA), numeric(1))
  if (any(is.na(waves))) return(FALSE)
  dirs_ok <- all(mapply(function(item, r) r$group_direction %in% unlist(item$dir),
                        ordered_spec, rows))
  dirs_ok && all(diff(waves) >= 0)
}
```

Then extend `match_signatures` — change its per-signature block to also evaluate `within` and `ordered`:

```r
      wth <- eval_within(s$within, var_slopes, cty)
      ord <- eval_ordered(s$ordered, features, cty)
      if (req && sup && lvl && wth && ord)
        tibble(country = cty, pattern_id = pid, label = s$label, description = s$description)
      else tibble()
```

(`var_slopes` is already a `match_signatures` parameter; defaults to `NULL`. Guard: if a signature has a `within` clause but `var_slopes` is NULL, `eval_within` sees zero rows and returns FALSE — acceptable.)

- [ ] **Step 4: Run tests, verify PASS**

Run: `Rscript src/scripts/prospector/test_signature_match.R`
Expected: no `FAIL:` lines.

- [ ] **Step 5: Commit**

```bash
git add src/scripts/prospector/signature_match.R src/scripts/prospector/test_signature_match.R
git commit -m "feat(prospector): within-group and ordered-sequence condition evaluators"
```

### Task 2.4: Add Phase-2 signatures + wire enriched features into the prospector

**Files:**
- Modify: `src/scripts/prospector/signatures.yml`, `src/scripts/slope_prospector.R`
- Test: `src/scripts/prospector/test_signature_match.R`

**Interfaces:**
- Consumes: `build_group_features`, `augment_breaks_with_location`, plus `slopes`, `harmonized_data`, `acceleration`, `significant_breaks`, `group_lookup`, `group_coherence` (all live in `slope_prospector.R`).

- [ ] **Step 1: Add the six Phase-2 signatures to `signatures.yml`**

```yaml
  coup_honeymoon:
    label: "Coup Honeymoon"
    description: "Support for authoritarian alternatives spikes then reverts"
    required: { authoritarian_support: { shape: REVERSED_UP } }
  authoritarian_ascendant:
    label: "Authoritarian Ascendant"
    description: "Support for authoritarian alternatives rising and now at a high level"
    required: { authoritarian_support: { dir: RISING, level: ENDS_HIGH } }
  accelerating_trust_collapse:
    label: "Accelerating Trust Collapse"
    description: "Executive trust falling fast to a floor while intermediary trust also falls"
    required:
      institutional_trust_executive:    { dir: FALLING, magnitude: FAST }
      institutional_trust_intermediary: FALLING
    level: { institutional_trust_executive: ENDS_LOW }
  true_demobilization_sequence:
    label: "True Demobilization Sequence"
    description: "Non-electoral participation breaks downward before authoritarian support breaks upward"
    ordered:
      - { group: political_action_contacting_protest, dir: FALLING }
      - { group: authoritarian_support,               dir: RISING }
  selective_accountability:
    label: "Selective Accountability"
    description: "Elections seen as offering real choice while courts are seen as powerless"
    within:
      accountability_perceptions: { gov_elections_real_choice: RISING, gov_courts_powerless: RISING }
  efficacy_trap:
    label: "Efficacy Trap"
    description: "Citizens feel more able to participate yet more convinced they have no influence"
    within:
      political_efficacy: { efficacy_ability_participate: RISING, efficacy_no_influence: RISING }
```

Note: `level` here maps `institutional_trust_executive` to a bare `ENDS_LOW`; `.eval_required` calls `eval_simple_condition`, whose `dir` branch would test `group_direction %in% "ENDS_LOW"`. Fix by making the `level` clause use a `level:` sub-key. Update Task 0.2's `match_signatures` `lvl` line to build condition maps: replace `.eval_required(s$level ...)` with a dedicated `.eval_level(s$level, features, cty)` that wraps each value as `list(level = value)`:

```r
.eval_level <- function(levels, features, cty) {
  if (length(levels) == 0) return(TRUE)
  all(vapply(names(levels), function(g) {
    row <- .row_for(features, cty, g)
    !is.null(row) && eval_simple_condition(list(level = levels[[g]]), row)
  }, logical(1)))
}
```
and call `lvl <- .eval_level(s$level %||% list(), features, cty)`.

- [ ] **Step 2: Write failing acceptance tests (Thailand coup_honeymoon, Eswatini collapse)**

Append synthetic-but-realistic frames:

```r
sigs <- load_signatures(file.path(here_dir, "signatures.yml"))
# coup honeymoon: authoritarian_support shape REVERSED_UP
fh <- tibble(country="TH", group="authoritarian_support", group_direction="FLAT",
             magnitude_tier="SLOW", shape="REVERSED_UP", ends_level="MID", broke_at_wave=NA_real_)
ok("coup_honeymoon" %in% match_signatures(fh, sigs)$pattern_id, "coup_honeymoon fires on REVERSED_UP")

# accelerating trust collapse
fc <- tribble(~country,~group,~group_direction,~magnitude_tier,~shape,~ends_level,~broke_at_wave,
  "SWZ","institutional_trust_executive","FALLING","FAST","STEADY","LOW",8,
  "SWZ","institutional_trust_intermediary","FALLING","SLOW","STEADY","LOW",8)
ok("accelerating_trust_collapse" %in% match_signatures(fc, sigs)$pattern_id, "accelerating_trust_collapse fires")
# negative control: magnitude SLOW
fc2 <- fc %>% mutate(magnitude_tier = if_else(group=="institutional_trust_executive","SLOW",magnitude_tier))
ok(!("accelerating_trust_collapse" %in% match_signatures(fc2, sigs)$pattern_id), "blocked when exec not FAST")
```

- [ ] **Step 3: Run, verify FAIL**, then apply the Step-1 `.eval_level` fix and confirm the `level`/`shape`/`magnitude` branches work.

Run: `Rscript src/scripts/prospector/test_signature_match.R`

- [ ] **Step 4: Wire enriched features into `slope_prospector.R` section 10**

Replace the `features <- group_coherence %>% ...` line from Task 0.4 Step 4 with:

```r
  breaks_located <- augment_breaks_with_location(eligible_for_breaks, significant_breaks)
  thr <- list(FAST = FAST_THRESHOLD, ENDS_LOW = ENDS_LOW, ENDS_HIGH = ENDS_HIGH,
              SHAPE_QUORUM = SHAPE_QUORUM)
  acc_for_feat <- if (exists("acceleration")) acceleration else
                  tibble(country=character(), variable=character(),
                         early_slope=numeric(), late_slope=numeric(),
                         acceleration=numeric(), direction_change=logical())
  features <- build_group_features(group_coherence, harmonized_data, acc_for_feat,
                                   breaks_located, group_lookup, thr)
  var_slopes <- slopes %>% mutate(country = as.character(country)) %>%
                select(country, variable, direction)
  narrative_results <- match_signatures(features, sigs, var_slopes = var_slopes)
```

(`group_lookup` exists only inside the `if (file.exists(CONCEPT_GROUPS_PATH))` block at line 436; section 10 already runs under `nrow(group_coherence) > 0`, which implies that block ran. If R scoping drops it, hoist `group_lookup` to a script-level variable in section 8.)

- [ ] **Step 5: Add the tunable globals near line 47**

```r
if (!exists("FAST_THRESHOLD")) FAST_THRESHOLD <- 0.15   # |mean_slope| above = "FAST"
if (!exists("ENDS_LOW"))       ENDS_LOW       <- 0.33   # normalized endpoint below = "LOW"
if (!exists("ENDS_HIGH"))      ENDS_HIGH      <- 0.66   # normalized endpoint above = "HIGH"
if (!exists("SHAPE_QUORUM"))   SHAPE_QUORUM   <- 0.5    # member share to assign a group shape
```

- [ ] **Step 6: Run the full ABS prospector; confirm new columns/patterns and no crash**

```bash
Rscript src/scripts/run_abs_all_countries.R > /private/tmp/abs_p2.log 2>&1
cut -d, -f2 outputs/prospecting/abs_all/narrative_patterns.csv | sort | uniq -c
grep -i "error" /private/tmp/abs_p2.log || echo "no errors"
```
Expected: original + Phase-1 + some Phase-2 ids; Thailand (8) should fire `coup_honeymoon` (military_rule REVERSED_UP at W4). No errors.

- [ ] **Step 7: Run the unit test suite once more**

Run: `Rscript src/scripts/prospector/test_signature_match.R`
Expected: `... passed, 0 failed`.

- [ ] **Step 8: Commit**

```bash
git add src/scripts/prospector/signatures.yml src/scripts/prospector/signature_match.R src/scripts/slope_prospector.R src/scripts/prospector/test_signature_match.R
git commit -m "feat(prospector): Phase-2 signatures + wire enriched feature frame into detection"
```

### Task 2.5: Re-run other barometers + update docs

**Files:**
- Modify: `docs/SLOPE_PROSPECTOR.md`

- [ ] **Step 1: Re-run Afro and LBS to confirm cross-survey stability**

```bash
Rscript src/scripts/run_afro_prospector.R > /private/tmp/afro_p2.log 2>&1
Rscript src/scripts/run_lbs_prospector.R  > /private/tmp/lbs_p2.log 2>&1
grep -i "error" /private/tmp/afro_p2.log /private/tmp/lbs_p2.log || echo "no errors"
```
Expected: no errors. Afro should still fire `trust_collapse` (GMB/SDN/SWZ) and may now add `accelerating_trust_collapse` for SWZ.

- [ ] **Step 2: Update the narrative-patterns table in `docs/SLOPE_PROSPECTOR.md`**

Replace the 8-row pattern table with the full catalog (14) and add a short "Signature DSL" subsection documenting the condition keys (`dir`, `magnitude`, `shape`, `level`, `within`, `ordered`) and the tunable globals. Point readers to `src/scripts/prospector/signatures.yml` as the editable registry.

- [ ] **Step 3: Commit**

```bash
git add docs/SLOPE_PROSPECTOR.md
git commit -m "docs(prospector): document extended signature catalog and DSL"
```

---

## Self-Review

- **Spec coverage:** approach (declarative condition objects, backward-compat) → Tasks 0.1–0.2; module extraction → 0.4; feature frame (magnitude/shape/level/break-wave) → 2.1–2.2; the four primitives → 2.2 (features) + 2.3 (within/ordered) + 0.2 (simple dir/magnitude/shape/level); Phase-1 six signatures → 1.1; Phase-2 six signatures → 2.4; break-detector upgrade → 2.1; tests incl. behavior-lock → 0.3 and per-primitive → 2.1–2.3; tunable globals → 2.4 Step 5; non-goal (cross-survey portability) respected (Afro/LBS only re-run, not retuned) → 2.5. All spec sections covered.
- **Placeholder scan:** every code step contains runnable R; no TBD/TODO; the one forward-reference (`.eval_level` fix) is given as literal code in Task 2.4 Step 1.
- **Type consistency:** `match_signatures(features, sigs, var_slopes=NULL)` signature is stable from 0.2 onward; `features` always carries `country, group, group_direction` (+ enriched cols from 2.2); `var_slopes` is `country, variable, direction`; `break_wave` (per variable, from 2.1) vs `broke_at_wave` (per group, from 2.2) are distinct-by-design and used consistently.
