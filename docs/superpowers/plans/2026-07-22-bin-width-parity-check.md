# Bin-Width Parity Check (Layer 4, Check D) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A deterministic Layer-4 audit check that flags variables whose per-wave recodes produce structurally different bin widths (the ABS W5 6→4pt trust pole-merge class), wired into `run_all.R` (hard) and the post-harmonize gate (report-only by default).

**Architecture:** Static evaluation — no raw data. For each survey × variable × wave, resolve the wave rule the way the engine does, derive a "bin signature" (how many source categories land in each target value) from the YAML mapping / registry-declared input domain, and compare signatures across waves. Spec: `docs/superpowers/specs/2026-07-22-bin-width-parity-check-design.md`.

**Tech Stack:** R (yaml, here, dplyr already in renv). Run everything with `Rscript`. All paths repo-relative to `/Users/jeffreystark/Development/Research/survey-data-prep`.

## Global Constraints

- Branch: `feat/audit-bin-width-parity` (already created).
- Commit messages: NO Co-Authored-By attribution (user rule).
- Statuses emitted by the check: `ok`, `ok_exempt`, `parity_error`, `warn`, `no_registry_entry`, `skip` — exactly these strings; `run_all.R` counts them from CSV.
- Signature serialization: target bins sorted numerically DESCENDING, `"<target>:<width>"` joined with `|` — ABS W5 trust must serialize as `4:2|3:1|2:1|1:2`.
- CSV columns, in order: `survey, variable, wave, method, fn, signature, n_bins, max_width, status, message`.
- CSV output path: `audit/reports/<survey>/04-bin-width-parity.csv`.
- The check script must be side-effect-free when `source()`d (CLI code behind `if (sys.nframe() == 0L)`), because `99_post_harmonize_gate.R` sources it.
- Exemptions file ships EMPTY (user decision 2026-07-22: the 13 ABS trust findings stay visible).

---

### Task 1: Core signature + parity functions with tests

**Files:**
- Create: `src/r/audit/04_bin_width_parity.R`
- Create: `src/r/audit/test_bin_width_parity.R`

**Interfaces:**
- Produces: `bin_signature(rule, scale, registry)` → list(`status` ("pending"|"skip"|"no_registry_entry"), `signature` (chr or NA), `n_bins` (int), `max_width` (int), `fn` (chr or NA), `method` (chr), `message` (chr)). `status="pending"` means "signature computed, parity not yet judged".
- Produces: `compute_bin_width_for_var(var_spec, survey, registry, exempt_ids)` → data.frame with the 10 CSV columns, one row per wave with non-null source.
- Consumes: `src/r/utils/recoding.R` fns (sourced), registry entries shaped like `list(fn=, input_scale=, output_scale=, reverses=, monotonic=, requires_data=, notes=)`.

- [ ] **Step 1: Write the check's core file** (compute layer only; survey-level wrapper and CLI come in Task 2 — leave the file ending after `compute_bin_width_for_var`):

```r
#!/usr/bin/env Rscript
# src/r/audit/04_bin_width_parity.R
#
# Layer 4 — Check D: bin-width parity across waves.
#
# Motivating bug: ABS W5 fielded the institutional-trust battery on a
# 6-point bipolar scale; safe_6pt_to_4pt collapses to the 4-point target by
# merging BOTH poles (native 6,5 -> 4; 2,1 -> 1). W5's top bin therefore
# absorbs two native categories while every other wave's absorbs one —
# top-box shares inflate ~2.4-4.6x in all 13 trust items, in every country
# (confirmed 2026-07-21; see docs/superpowers/specs/
# 2026-07-22-bin-width-parity-check-design.md). Direction-based layers
# (label recon, strict reversal, battery coherence) pass this legitimately:
# the mapping is directionally correct. This check tests the SHAPE of the
# mapping instead — the number of source categories feeding each target bin
# must be constant across waves, or the variable's levels are not
# cross-wave comparable.
#
# STATIC evaluation only: signatures come from YAML recode mappings and
# from calling registry-declared data-independent fns over their declared
# input domain (the engine passes no substantive extra args — see
# harmonize.R r_function dispatch — so defaults mirror production).
# An empirical raw->harmonized crosstab arm (would catch raw domains wider
# than the registry declares) is DEFERRED: it needs per-survey raw loaders,
# which exist only for ABS today (04_strict_reversal.R .SURVEY_RAW_LOADERS).
#
# Statuses:
#   ok                — signature agrees with the variable's modal signature
#                       (or nothing to compare / uniform collapse everywhere)
#   ok_exempt         — variable listed in bin_width_exemptions.yml
#   parity_error      — signature deviates from modal AND a width >= 2 bin is
#                       involved (the ABS-W5 class; audit finding)
#   warn              — signatures differ but all widths are 1 (cardinality/
#                       domain drift, not a width artefact)
#   no_registry_entry — r_function fn absent from recoding_registry.yml
#   skip              — statically unevaluable (derive, requires_data fn,
#                       null source, no numeric scale, fn errored on domain)
#
# Public API:
#   compute_bin_width_parity(survey, ...)  -- returns a data.frame
#   run_bin_width_parity(survey, ...)      -- writes CSV + prints summary
# CLI:
#   Rscript src/r/audit/04_bin_width_parity.R --survey abs
#   Rscript src/r/audit/04_bin_width_parity.R --all-surveys
# Exit: 0 if no parity_error rows, 1 otherwise (hard check).

suppressPackageStartupMessages({
  library(yaml)
  library(here)
})

source(here::here("src", "r", "utils", "spec_discovery.R"))
source(here::here("src", "r", "utils", "recoding.R"))

`%||%` <- function(a, b) if (!is.null(a)) a else b

# ---------------------------------------------------------------------------
# Mirror of harmonize.R::resolve_wave_rule(). Same inline-mirror convention
# as 04_strict_reversal.R — if engine resolution semantics change, update
# both; they MUST agree.
# ---------------------------------------------------------------------------
.resolve_wave_rule <- function(var_spec, wave_name) {
  default_rule <- var_spec$harmonize$default %||% list(method = "identity")
  var_spec$harmonize$by_wave[[wave_name]] %||%
    var_spec$harmonize$exceptions[[wave_name]] %||%
    var_spec$harmonize[[wave_name]] %||%
    default_rule
}

# ---------------------------------------------------------------------------
# Signature helpers. A signature is a named integer vector: names = target
# values, values = how many source categories map there. Serialized with
# targets sorted DESCENDING: ABS W5 trust = "4:2|3:1|2:1|1:2".
# ---------------------------------------------------------------------------
.sig_string <- function(widths) {
  t_num <- as.numeric(names(widths))
  ord <- order(-t_num)
  paste(sprintf("%s:%d", names(widths)[ord], as.integer(widths[ord])),
        collapse = "|")
}

.sig_result <- function(status, method, fn, message = "",
                        widths = NULL) {
  list(
    status = status,
    signature = if (is.null(widths)) NA_character_ else .sig_string(widths),
    n_bins = if (is.null(widths)) NA_integer_ else length(widths),
    max_width = if (is.null(widths)) NA_integer_ else max(as.integer(widths)),
    fn = fn %||% NA_character_,
    method = method,
    message = message
  )
}

# ---------------------------------------------------------------------------
# bin_signature(): derive one wave's signature from its resolved rule.
#   rule     — list from .resolve_wave_rule()
#   scale    — var_spec$scale (list with min/max), may be NULL
#   registry — named list: fn name -> registry entry
# ---------------------------------------------------------------------------
bin_signature <- function(rule, scale, registry) {
  method <- rule$method %||% "identity"

  if (method == "identity") {
    lo <- suppressWarnings(as.numeric(scale$min %||% NA))
    hi <- suppressWarnings(as.numeric(scale$max %||% NA))
    if (is.na(lo) || is.na(hi) || hi < lo) {
      return(.sig_result("skip", method, NA_character_,
                         "identity without numeric scale min/max"))
    }
    targets <- seq(lo, hi)
    widths <- stats::setNames(rep(1L, length(targets)), targets)
    return(.sig_result("pending", method, NA_character_, widths = widths))
  }

  if (method == "recode") {
    mapping <- rule$mapping
    if (is.null(mapping) || length(mapping) == 0) {
      return(.sig_result("skip", method, NA_character_,
                         "recode without mapping"))
    }
    to <- vapply(mapping, function(v) {
      if (is.null(v)) NA_real_ else suppressWarnings(as.numeric(v))
    }, numeric(1))
    to <- to[!is.na(to)]  # null-mapped (-> NA) inputs are not a bin
    if (length(to) == 0) {
      return(.sig_result("skip", method, NA_character_,
                         "recode maps every input to NA"))
    }
    tab <- table(to)
    widths <- stats::setNames(as.integer(tab), names(tab))
    return(.sig_result("pending", method, NA_character_, widths = widths))
  }

  if (method == "r_function") {
    fn_name <- rule$fn %||% NA_character_
    entry <- registry[[fn_name]]
    if (is.null(entry)) {
      return(.sig_result("no_registry_entry", method, fn_name,
                         sprintf("fn '%s' not in recoding_registry.yml",
                                 fn_name)))
    }
    if (isTRUE(entry$requires_data)) {
      return(.sig_result("skip", method, fn_name,
                         "requires_data fn — not statically evaluable"))
    }
    isc <- suppressWarnings(as.numeric(unlist(entry$input_scale)))
    if (length(isc) != 2 || any(is.na(isc))) {
      return(.sig_result("skip", method, fn_name,
                         "no numeric input_scale in registry"))
    }
    if (!exists(fn_name, mode = "function")) {
      return(.sig_result("skip", method, fn_name,
                         sprintf("fn '%s' not loaded from recoding.R",
                                 fn_name)))
    }
    f <- get(fn_name, mode = "function")
    domain <- seq(isc[1], isc[2])
    out <- tryCatch(
      suppressWarnings(as.numeric(f(domain))),
      error = function(e) e
    )
    if (inherits(out, "error")) {
      return(.sig_result("skip", method, fn_name,
                         sprintf("fn errored on declared domain %s..%s: %s",
                                 isc[1], isc[2], conditionMessage(out))))
    }
    keep <- !is.na(out)  # domain values the fn sends to NA are not a bin
    if (!any(keep)) {
      return(.sig_result("skip", method, fn_name,
                         "fn maps entire declared domain to NA"))
    }
    tab <- table(out[keep])
    widths <- stats::setNames(as.integer(tab), names(tab))
    return(.sig_result("pending", method, fn_name, widths = widths))
  }

  .sig_result("skip", method, rule$fn %||% NA_character_,
              sprintf("method '%s' out of scope for static bin analysis",
                      method))
}

# ---------------------------------------------------------------------------
# Parity judgment over one variable's computed rows.
#   Uniform signatures (or <2 usable waves) -> ok.
#   Deviant waves -> parity_error when any usable wave has max_width >= 2,
#   else warn (all-1:1 domain/cardinality drift).
# ---------------------------------------------------------------------------
.judge_parity <- function(df) {
  pending <- df$status == "pending"
  if (!any(pending)) return(df)
  sigs <- df$signature[pending]
  if (length(unique(sigs)) <= 1L) {
    df$status[pending] <- "ok"
    return(df)
  }
  tab <- table(sigs)
  modal <- names(tab)[which.max(tab)]
  any_wide <- any(df$max_width[pending] >= 2L, na.rm = TRUE)
  deviant_status <- if (any_wide) "parity_error" else "warn"
  is_deviant <- pending & df$signature != modal
  df$status[pending & df$signature == modal] <- "ok"
  df$status[is_deviant] <- deviant_status
  df$message[is_deviant] <- sprintf(
    "signature %s deviates from modal %s", df$signature[is_deviant], modal)
  df
}

# ---------------------------------------------------------------------------
# compute_bin_width_for_var(): all waves of one variable -> judged rows.
#   exempt_ids — character vector of exempted variable ids for this survey.
# ---------------------------------------------------------------------------
compute_bin_width_for_var <- function(var_spec, survey, registry,
                                      exempt_ids = character(0)) {
  var_id <- var_spec$id %||% "?"
  waves <- names(var_spec$source %||% list())
  rows <- lapply(waves, function(wv) {
    src <- var_spec$source[[wv]]
    if (is.null(src)) {
      sig <- .sig_result("skip", "none", NA_character_,
                         "null source for this wave")
    } else {
      rule <- .resolve_wave_rule(var_spec, wv)
      sig <- bin_signature(rule, var_spec$scale, registry)
    }
    data.frame(
      survey = survey, variable = var_id, wave = wv,
      method = sig$method, fn = sig$fn, signature = sig$signature,
      n_bins = sig$n_bins, max_width = sig$max_width,
      status = sig$status, message = sig$message,
      stringsAsFactors = FALSE
    )
  })
  df <- do.call(rbind, rows)
  if (is.null(df)) {
    return(data.frame(
      survey = character(0), variable = character(0), wave = character(0),
      method = character(0), fn = character(0), signature = character(0),
      n_bins = integer(0), max_width = integer(0), status = character(0),
      message = character(0), stringsAsFactors = FALSE
    ))
  }
  df <- .judge_parity(df)
  if (var_id %in% exempt_ids) {
    computed <- df$status %in% c("ok", "parity_error", "warn")
    df$message[computed] <- paste0(
      "exempt (bin_width_exemptions.yml); computed status was ",
      df$status[computed])
    df$status[computed] <- "ok_exempt"
  }
  df
}
```

- [ ] **Step 2: Write the failing tests** — create `src/r/audit/test_bin_width_parity.R`:

```r
#!/usr/bin/env Rscript
# src/r/audit/test_bin_width_parity.R
#
# Fault-injection tests for Check D (bin-width parity).
# Run:  Rscript src/r/audit/test_bin_width_parity.R
# Exit: 0 if all pass, 1 otherwise.

suppressPackageStartupMessages({ library(here) })
source(here::here("src", "r", "audit", "04_bin_width_parity.R"))

.pass <- 0L; .fail <- 0L
ok <- function(cond, msg) {
  if (isTRUE(cond)) { .pass <<- .pass + 1L; cat(sprintf("  PASS  %s\n", msg)) }
  else              { .fail <<- .fail + 1L; cat(sprintf("  FAIL  %s\n", msg)) }
}

# Synthetic registry (real fns from recoding.R are already sourced).
REG <- list(
  safe_6pt_to_4pt = list(fn = "safe_6pt_to_4pt", input_scale = c(1, 6),
                         output_scale = c(1, 4), reverses = TRUE,
                         monotonic = TRUE, requires_data = FALSE),
  safe_reverse_4pt = list(fn = "safe_reverse_4pt", input_scale = c(1, 4),
                          output_scale = c(1, 4), reverses = TRUE,
                          monotonic = TRUE, requires_data = FALSE),
  cond_flip = list(fn = "cond_flip", input_scale = c(1, 4),
                   output_scale = c(1, 4), reverses = TRUE,
                   monotonic = FALSE, requires_data = TRUE)
)

mkvar <- function(id, source, exceptions = list(),
                  scale = list(min = 1, max = 4)) {
  list(id = id, type = "ordinal", source = source, scale = scale,
       harmonize = list(default = list(method = "identity"),
                        exceptions = exceptions))
}

cat("=== D1: ABS-W5-class seam -> parity_error on the collapsing wave ===\n")
vs <- mkvar("toy_trust",
            source = list(w1 = "q1", w2 = "q1", w5 = "q1"),
            exceptions = list(
              w5 = list(method = "r_function", fn = "safe_6pt_to_4pt")))
df <- compute_bin_width_for_var(vs, "toy", REG)
ok(df$status[df$wave == "w5"] == "parity_error", "w5 flagged parity_error")
ok(df$signature[df$wave == "w5"] == "4:2|3:1|2:1|1:2",
   "w5 signature is 4:2|3:1|2:1|1:2")
ok(all(df$status[df$wave %in% c("w1", "w2")] == "ok"),
   "identity waves stay ok")
ok(all(df$signature[df$wave %in% c("w1", "w2")] == "4:1|3:1|2:1|1:1"),
   "identity signature is 4:1|3:1|2:1|1:1")

cat("\n=== D2: uniform collapse in ALL waves -> ok (comparability kept) ===\n")
vs <- mkvar("toy_uniform",
            source = list(w1 = "q1", w2 = "q1"),
            exceptions = list(
              w1 = list(method = "r_function", fn = "safe_6pt_to_4pt"),
              w2 = list(method = "r_function", fn = "safe_6pt_to_4pt")))
df <- compute_bin_width_for_var(vs, "toy", REG)
ok(all(df$status == "ok"), "uniform 6->4 collapse everywhere is ok")

cat("\n=== D3: pure reversal vs identity -> identical signatures, ok ===\n")
vs <- mkvar("toy_reverse",
            source = list(w1 = "q1", w2 = "q1"),
            exceptions = list(
              w2 = list(method = "r_function", fn = "safe_reverse_4pt")))
df <- compute_bin_width_for_var(vs, "toy", REG)
ok(all(df$status == "ok"), "reversal has all-1 widths -> no finding")

cat("\n=== D4: requires_data fn -> skip; lone remaining wave -> ok ===\n")
vs <- mkvar("toy_cond",
            source = list(w1 = "q1", w2 = "q1"),
            exceptions = list(
              w2 = list(method = "r_function", fn = "cond_flip")))
df <- compute_bin_width_for_var(vs, "toy", REG)
ok(df$status[df$wave == "w2"] == "skip", "requires_data fn skips")
ok(df$status[df$wave == "w1"] == "ok", "single usable wave is ok")

cat("\n=== D5: method:recode merged bin -> parity_error (no registry) ===\n")
vs <- mkvar("toy_recode",
            source = list(w1 = "q1", w2 = "q1"),
            exceptions = list(
              w2 = list(method = "recode",
                        mapping = list(`1` = 1, `2` = 1, `3` = 2, `4` = 3))))
df <- compute_bin_width_for_var(vs, "toy", REG)
ok(df$status[df$wave == "w2"] == "parity_error",
   "explicit merged mapping flagged")
ok(df$signature[df$wave == "w2"] == "3:1|2:1|1:2",
   "recode signature counts widths from mapping")

cat("\n=== D6: midpoint-drop recode (5 -> NA) -> NOT an error ===\n")
vs <- mkvar("toy_middrop",
            source = list(w1 = "q1", w2 = "q1"),
            exceptions = list(
              w1 = list(method = "recode",
                        mapping = list(`1` = 1, `2` = 2, `3` = 3, `4` = 4,
                                       `5` = NULL))))
df <- compute_bin_width_for_var(vs, "toy", REG)
ok(all(df$status == "ok"),
   "dropping a midpoint to NA keeps all widths 1 -> ok")

cat("\n=== D6b: all-width-1 cardinality drift -> warn, not error ===\n")
vs <- mkvar("toy_drift",
            source = list(w1 = "q1", w2 = "q1"),
            exceptions = list(
              w1 = list(method = "recode",
                        mapping = list(`1` = 1, `2` = 2, `3` = 3))))
df <- compute_bin_width_for_var(vs, "toy", REG)
ok(df$status[df$wave == "w1"] == "warn",
   "3-target vs 4-target with all widths 1 warns")
ok(df$status[df$wave == "w2"] == "ok", "modal wave stays ok")

cat("\n=== D7: unknown fn -> no_registry_entry ===\n")
vs <- mkvar("toy_unknown",
            source = list(w1 = "q1", w2 = "q1"),
            exceptions = list(
              w2 = list(method = "r_function", fn = "not_a_real_fn")))
df <- compute_bin_width_for_var(vs, "toy", REG)
ok(df$status[df$wave == "w2"] == "no_registry_entry",
   "missing registry entry surfaced")

cat("\n=== D8: exemption downgrades computed statuses to ok_exempt ===\n")
vs <- mkvar("toy_trust",
            source = list(w1 = "q1", w5 = "q1"),
            exceptions = list(
              w5 = list(method = "r_function", fn = "safe_6pt_to_4pt")))
df <- compute_bin_width_for_var(vs, "toy", REG, exempt_ids = "toy_trust")
ok(all(df$status == "ok_exempt"), "exempted variable rows are ok_exempt")
ok(grepl("parity_error", df$message[df$wave == "w5"]),
   "exempt row message preserves the computed status")

cat(sprintf("\n%d passed, %d failed\n", .pass, .fail))
quit(status = if (.fail > 0L) 1L else 0L)
```

- [ ] **Step 3: Run tests, verify D1–D8 all pass** (the implementation from Step 1 already exists, so the "failing" state to verify is: comment nothing out — just run once and fix any real defects until green):

Run: `Rscript src/r/audit/test_bin_width_parity.R`
Expected: `... passed, 0 failed`, exit 0. If any FAIL, fix `04_bin_width_parity.R` (not the test) until green.

- [ ] **Step 4: Commit**

```bash
git add src/r/audit/04_bin_width_parity.R src/r/audit/test_bin_width_parity.R
git commit -m "feat(audit): Check D core — per-wave bin signatures + parity judgment"
```

---

### Task 2: Exemptions scaffold, survey-level API, CLI

**Files:**
- Create: `src/config/_audit/bin_width_exemptions.yml`
- Modify: `src/r/audit/04_bin_width_parity.R` (append below `compute_bin_width_for_var`)
- Modify: `src/r/audit/test_bin_width_parity.R` (append section D9)

**Interfaces:**
- Produces: `compute_bin_width_parity(survey, registry_path, exemptions_path)` → data.frame (10 CSV columns).
- Produces: `run_bin_width_parity(survey, output_dir = NULL)` → writes `audit/reports/<survey>/04-bin-width-parity.csv`, prints summary, invisibly returns the data.frame. Task 3 (`run_all.R`) and Task 4 (gate) call these.
- Consumes: `list_survey_specs(survey)` from `src/r/utils/spec_discovery.R` (already sourced in Task 1).

- [ ] **Step 1: Create the exemptions scaffold** at `src/config/_audit/bin_width_exemptions.yml`:

```yaml
# Bin-width parity exemptions
# -----------------------------------------------------------------------------
# The bin-width parity check (src/r/audit/04_bin_width_parity.R, Check D)
# flags variables whose waves pack DIFFERENT numbers of source categories
# into the same harmonized bin — the ABS W5 6->4pt trust pole-merge class,
# which mechanically inflates the collapsing wave's top-box shares and means
# even though every direction check passes.
#
# Exemption is a deliberate editorial act: a variable listed here has a
# KNOWN, DOCUMENTED cross-wave binning seam that we accept (e.g. the seam is
# described in the survey docs page and flagged in the verbatim dictionary
# notes). Prefer FIXING the seam (native-scale companion columns, or a
# uniform mapping) over exempting it. Do NOT exempt to silence a finding you
# have not triaged.
#
# The 13 ABS W5 trust items are deliberately NOT exempted (decision
# 2026-07-22): they stay visible, like the ABS label-recon backlog, until
# the seam itself is fixed/documented.
#
# Form: exempt_variables, each entry {variable, reason, survey (optional —
# omit to match the id in every survey)}.

schema_version: 1

exempt_variables: []
```

- [ ] **Step 2: Append survey-level API + CLI** to `src/r/audit/04_bin_width_parity.R`:

```r
# ---------------------------------------------------------------------------
# Registry + exemptions loaders.
# ---------------------------------------------------------------------------
load_bin_width_registry <- function(
  registry_path = here::here("src", "r", "utils", "recoding_registry.yml")
) {
  if (!file.exists(registry_path)) {
    stop(sprintf("recoding registry not found at %s", registry_path),
         call. = FALSE)
  }
  reg <- yaml::read_yaml(registry_path)
  stats::setNames(reg, vapply(reg, function(e) e$fn, character(1)))
}

load_bin_width_exemptions <- function(
  survey,
  exemptions_path = here::here("src", "config", "_audit",
                               "bin_width_exemptions.yml")
) {
  if (!file.exists(exemptions_path)) return(character(0))
  ex <- yaml::read_yaml(exemptions_path)
  entries <- ex$exempt_variables %||% list()
  ids <- vapply(entries, function(e) {
    if (!is.null(e$survey) && !identical(e$survey, survey)) NA_character_
    else e$variable %||% NA_character_
  }, character(1))
  ids[!is.na(ids)]
}

# ---------------------------------------------------------------------------
# compute_bin_width_parity(): whole survey -> judged rows.
# ---------------------------------------------------------------------------
compute_bin_width_parity <- function(
  survey,
  registry_path = here::here("src", "r", "utils", "recoding_registry.yml"),
  exemptions_path = here::here("src", "config", "_audit",
                               "bin_width_exemptions.yml")
) {
  registry <- load_bin_width_registry(registry_path)
  exempt_ids <- load_bin_width_exemptions(survey, exemptions_path)
  spec_files <- list_survey_specs(survey)
  out <- list()
  for (sf in spec_files) {
    spec <- tryCatch(yaml::read_yaml(sf), error = function(e) NULL)
    if (is.null(spec) || is.null(spec$variables)) next
    for (vs in spec$variables) {
      out[[length(out) + 1L]] <-
        compute_bin_width_for_var(vs, survey, registry, exempt_ids)
    }
  }
  if (length(out) == 0L) {
    return(data.frame(
      survey = character(0), variable = character(0), wave = character(0),
      method = character(0), fn = character(0), signature = character(0),
      n_bins = integer(0), max_width = integer(0), status = character(0),
      message = character(0), stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, out)
}

# ---------------------------------------------------------------------------
# run_bin_width_parity(): CSV + human summary. Returns df invisibly.
# ---------------------------------------------------------------------------
run_bin_width_parity <- function(survey, output_dir = NULL) {
  if (is.null(output_dir)) {
    output_dir <- here::here("audit", "reports", survey)
  }
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }
  results <- compute_bin_width_parity(survey)
  csv_path <- file.path(output_dir, "04-bin-width-parity.csv")
  utils::write.csv(results, csv_path, row.names = FALSE)

  n <- function(s) sum(results$status == s)
  cat(sprintf("\n[bin-width parity] survey=%s\n", survey))
  cat(sprintf(
    "  rows=%d: ok=%d, ok_exempt=%d, parity_error=%d, warn=%d, no_registry_entry=%d, skip=%d\n",
    nrow(results), n("ok"), n("ok_exempt"), n("parity_error"), n("warn"),
    n("no_registry_entry"), n("skip")))
  err <- results[results$status == "parity_error", , drop = FALSE]
  if (nrow(err) > 0L) {
    cat(sprintf("  %d parity_error row(s) — waves whose binning diverges:\n",
                nrow(err)))
    show <- utils::head(err, 20L)
    for (i in seq_len(nrow(show))) {
      cat(sprintf("    %-32s %-6s %s (%s)\n", show$variable[i],
                  show$wave[i], show$signature[i], show$fn[i]))
    }
    if (nrow(err) > 20L) cat(sprintf("    ... and %d more\n", nrow(err) - 20L))
  }
  cat(sprintf("  CSV: %s\n", csv_path))
  invisible(results)
}

# ---------------------------------------------------------------------------
# CLI.
# ---------------------------------------------------------------------------
.parse_cli_args <- function(argv) {
  out <- list(survey = NULL, all_surveys = FALSE)
  i <- 1L
  while (i <= length(argv)) {
    a <- argv[i]
    if (a == "--survey")      { out$survey <- argv[i + 1]; i <- i + 2; next }
    if (a == "--all-surveys") { out$all_surveys <- TRUE;   i <- i + 1; next }
    if (a %in% c("-h", "--help")) {
      cat("Usage: Rscript src/r/audit/04_bin_width_parity.R\n",
          "         (--survey <name> | --all-surveys)\n",
          "\nCheck D: cross-wave bin-width parity. parity_error = a wave's\n",
          "recode packs more source categories into a target bin than its\n",
          "sibling waves (ABS W5 6->4 trust class). Exemptions:\n",
          "src/config/_audit/bin_width_exemptions.yml. Exit 1 on any\n",
          "parity_error.\n", sep = "")
      quit(status = 0)
    }
    stop(sprintf("unknown argument: %s", a), call. = FALSE)
  }
  if (is.null(out$survey) && !out$all_surveys) {
    stop("usage: --survey <name> OR --all-surveys (see --help)", call. = FALSE)
  }
  out
}

if (sys.nframe() == 0L) {
  argv <- commandArgs(trailingOnly = TRUE)
  if (length(argv) > 0) {
    args <- .parse_cli_args(argv)
    surveys <- if (args$all_surveys) {
      list.dirs(here::here("src", "config"), recursive = FALSE,
                full.names = FALSE) |>
        setdiff(c("_anchors", "_audit"))
    } else args$survey
    any_err <- FALSE
    for (s in surveys) {
      res <- tryCatch(run_bin_width_parity(s), error = function(e) {
        cat(sprintf("[bin-width parity] %s CRASHED: %s\n",
                    s, conditionMessage(e)))
        NULL
      })
      if (!is.null(res) && any(res$status == "parity_error")) any_err <- TRUE
    }
    quit(status = if (any_err) 1L else 0L)
  }
}
```

- [ ] **Step 3: Append test section D9** (exemptions file plumbing + ABS integration) to `src/r/audit/test_bin_width_parity.R`, ABOVE the final `cat/quit` lines:

```r
cat("\n=== D9: survey-level API on real ABS specs ===\n")
abs_df <- compute_bin_width_parity("abs")
ok(nrow(abs_df) > 0, "abs sweep produced rows")
TRUST13 <- c("trust_president", "trust_courts", "trust_national_government",
             "trust_political_parties", "trust_parliament",
             "trust_civil_service", "trust_military", "trust_police",
             "trust_local_government", "trust_election_commission",
             "trust_newspapers", "trust_ngos", "trust_television")
err_vars <- unique(abs_df$variable[abs_df$status == "parity_error"])
ok(all(TRUST13 %in% err_vars),
   "all 13 W5 trust-battery items flagged parity_error")
trust_err <- abs_df[abs_df$status == "parity_error" &
                    abs_df$variable %in% TRUST13, ]
ok(all(trust_err$wave == "w5"), "trust flags are w5 rows only")
ok(all(trust_err$signature == "4:2|3:1|2:1|1:2"),
   "trust w5 signatures all 4:2|3:1|2:1|1:2")

cat("\n=== D10: exemption file round-trip via tempfile ===\n")
tmp_ex <- tempfile(fileext = ".yml")
writeLines(c(
  "schema_version: 1",
  "exempt_variables:",
  "  - variable: trust_military",
  "    survey: abs",
  "    reason: test"), tmp_ex)
ids <- load_bin_width_exemptions("abs", tmp_ex)
ok(identical(ids, "trust_military"), "survey-matched exemption loads")
ok(length(load_bin_width_exemptions("kgss", tmp_ex)) == 0,
   "survey-restricted exemption does not leak to other surveys")
```

- [ ] **Step 4: Run tests**

Run: `Rscript src/r/audit/test_bin_width_parity.R`
Expected: all pass (D1–D10), exit 0. D9's "all 13" assertion is the real-ABS regression fixture; if it fails, debug the check (spec parsing, registry lookup), not the fixture.

- [ ] **Step 5: Smoke-test the CLI**

Run: `Rscript src/r/audit/04_bin_width_parity.R --survey abs; echo "exit=$?"`
Expected: summary block listing the 13 trust parity_error rows (w5, signature `4:2|3:1|2:1|1:2`), CSV written to `audit/reports/abs/04-bin-width-parity.csv`, `exit=1` (hard check with findings present).

- [ ] **Step 6: Commit**

```bash
git add src/r/audit/04_bin_width_parity.R src/r/audit/test_bin_width_parity.R src/config/_audit/bin_width_exemptions.yml
git commit -m "feat(audit): Check D survey API + CLI + empty exemptions scaffold; ABS regression fixture (13 W5 trust items)"
```

---

### Task 3: run_all.R wiring (hard module + SUMMARY column)

**Files:**
- Modify: `src/r/audit/run_all.R` — three places: (a) new module runner after `.run_layer_4_coverage` (~line 625), (b) `results$L4_binwidth <- ...` in the per-survey assembly (~line 761), (c) SUMMARY table header/separator/row (~lines 823–837).

**Interfaces:**
- Consumes: `audit/reports/<survey>/04-bin-width-parity.csv` statuses (`ok`, `ok_exempt`, `parity_error`, `warn`, `no_registry_entry`, `skip`); existing helpers `.run_external`, `.count_csv_statuses`, `.count_get`, `.top_fail_rows`, `.log_module`, `.cell`.
- Produces: `results$L4_binwidth` module list consumed by the generic fail digest (it iterates `names(r)` — no digest change needed).

- [ ] **Step 1: Add the module runner** directly after the closing brace of `.run_layer_4_coverage`:

```r
# ---------------------------------------------------------------------------
# Module 4f: Layer 4 bin-width parity (Check D) — HARD. parity_error = a
# wave whose recode packs more source categories into a target bin than its
# sibling waves (the ABS W5 6->4 trust seam: top-box inflated ~2.4-4.6x with
# every direction check passing). Deterministic, zero statistical inference,
# so errors count as fails; acknowledged seams are exempted in
# src/config/_audit/bin_width_exemptions.yml.
# ---------------------------------------------------------------------------
.run_layer_4_binwidth <- function(survey, verbose = FALSE) {
  .log_module(survey, "L4 bin-width parity (Check D)")
  rr <- .run_external("src/r/audit/04_bin_width_parity.R",
                      c("--survey", survey), verbose = verbose)
  csv_path <- here::here("audit/reports", survey, "04-bin-width-parity.csv")
  counts <- .count_csv_statuses(csv_path)
  ok   <- .count_get(counts, "ok") + .count_get(counts, "ok_exempt")
  err  <- .count_get(counts, "parity_error")
  wrn  <- .count_get(counts, "warn") + .count_get(counts, "no_registry_entry")
  skip <- .count_get(counts, "skip")
  status <- if (err > 0L) "fail"
            else if (wrn > 0L) "warn"
            else if (ok == 0L && skip > 0L) "skip" else "ok"
  first_fails <- character(0)
  fails_df <- .top_fail_rows(csv_path, fail_statuses = "parity_error")
  if (nrow(fails_df) > 0L) {
    first_fails <- vapply(seq_len(nrow(fails_df)), function(i) {
      r <- fails_df[i, ]
      sprintf("%s/%s: bin signature %s diverges from sibling waves",
              r$variable %||% "?", r$wave %||% "?", r$signature %||% "?")
    }, character(1))
  }
  list(
    module = "L4 binwidth",
    status = status, exit = rr$status,
    ok = as.integer(ok), fail = as.integer(err), skip = as.integer(skip),
    first_fails = first_fails,
    summary = sprintf("%d ok, %d err, %d warn", ok, err, wrn)
  )
}
```

- [ ] **Step 2: Register the module** — in the per-survey assembly, after `results$L4_coverage <- .run_layer_4_coverage(survey, verbose)` add:

```r
  results$L4_binwidth <- .run_layer_4_binwidth(survey, verbose)
```

- [ ] **Step 3: Extend the SUMMARY table** — header row gains `L4 binwidth` after `L4 coverage`; separator row gains one segment; the row `sprintf` gains one `%s` fed with `.cell(r$L4_binwidth)` after `.cell(r$L4_coverage)`:

```r
  w("| Survey | L1 schema | L3 invariants | L2 codebook | L4 anchors | L4 strict | L4 labels | L4 battery | L4 coverage | L4 binwidth | L5 drift | L6 determ | L6 input |")
  w("|--------|-----------|---------------|-------------|------------|-----------|-----------|------------|-------------|-------------|----------|-----------|----------|")
```

and in the loop:

```r
    w(sprintf("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |",
              s,
              .cell(r$L1),
              .cell(r$L3),
              .cell(r$L2_codebook),
              .cell(r$L4_anchor),
              .cell(r$L4_strict),
              .cell(r$L4_labels),
              .cell(r$L4_battery),
              .cell(r$L4_coverage),
              .cell(r$L4_binwidth),
              .cell(r$L5_drift),
              .cell(r$L6_determ),
              .cell(r$L6_input)))
```

- [ ] **Step 4: Verify on one small survey**

Run: `Rscript src/r/audit/run_all.R --survey kamos --quick 2>&1 | tail -25`
Expected: run completes; `audit/SUMMARY.md` per-survey table now has an `L4 binwidth` column with a real cell for kamos (OK/warn/FAIL + counts, not `?`).

Run: `Rscript src/r/audit/run_all.R --survey abs --quick 2>&1 | tail -25`
Expected: `L4 binwidth` cell shows `FAIL` with 13 err variables' rows counted (13 err rows = 13 w5 rows); the "Top audit findings" digest includes `[abs] L4 binwidth` lines. Exit code 1 (fails present — ABS already exits 1 from the label backlog).

- [ ] **Step 5: Commit**

```bash
git add src/r/audit/run_all.R
git commit -m "feat(audit): wire Check D into run_all as hard L4 binwidth module + SUMMARY column"
```

---

### Task 4: Post-harmonize gate wiring

**Files:**
- Modify: `src/r/audit/99_post_harmonize_gate.R` — source block (~line 46), `run_post_harmonize_gate` body (~lines 74–125), CLI fail-closed condition (~line 166).

**Interfaces:**
- Consumes: `run_bin_width_parity(survey)` (returns df with `status` column) from the sourced check file.
- Produces: gate result list gains `n_binwidth` and `binwidth` fields.

- [ ] **Step 1: Source the new check** — after the existing three `source()` lines add:

```r
source(here::here("src", "r", "audit", "04_bin_width_parity.R"))
```

(The file is CLI-guarded per Global Constraints, so sourcing is side-effect free.)

- [ ] **Step 2: Run the check in the gate** — after the `ac <- .gate_check(...)` block add:

```r
  bw <- .gate_check("bin-width parity", function()
    run_quiet(function() run_bin_width_parity(survey)))
```

after the `n_unc` line add:

```r
  n_bw <- if (is.null(bw)) NA_integer_ else sum(bw$status == "parity_error")
```

extend the gate print line to include it (replace the existing `cat(sprintf("\n[gate] %s: ...` call):

```r
  cat(sprintf("\n[gate] %s: label-recon errors=%s | battery hints=%s | uncovered=%s | bin-width errors=%s\n",
              survey,
              ifelse(is.na(n_err), "check-crashed", n_err),
              ifelse(is.na(n_hint), "check-crashed", n_hint),
              ifelse(is.na(n_unc), "check-crashed", n_unc),
              ifelse(is.na(n_bw), "check-crashed", n_bw)))
```

after the label-recon blocking `if/else if` block (the one ending `...no label-reconciliation errors...`), add a parallel block:

```r
  if (!is.na(n_bw) && n_bw > 0) {
    bw_vars <- unique(bw$variable[bw$status == "parity_error"])
    cat(sprintf("[gate] waves with divergent bin widths (levels not cross-wave comparable): %s\n",
                paste(bw_vars, collapse = ", ")))
    cat(sprintf("[gate] details: audit/reports/%s/04-bin-width-parity.csv\n",
                survey))
    if (blocking) {
      stop(sprintf(
        "[gate] BLOCKING: %d bin-width parity error(s) in '%s' — fix the mapping or exempt in bin_width_exemptions.yml",
        n_bw, survey), call. = FALSE)
    } else {
      cat("[gate] report-only: not failing the pipeline (set HARMONIZE_AUDIT_GATE=block to enforce)\n")
    }
  }
```

and extend the returned list:

```r
  invisible(list(
    survey = survey, blocking = blocking,
    n_errors = n_err, n_hints = n_hint, n_uncovered = n_unc,
    n_binwidth = n_bw,
    high_confidence = high_conf,
    label_recon = lr, battery = bc, coverage = ac, binwidth = bw
  ))
```

- [ ] **Step 3: Fail closed in CLI blocking mode** — the CLI currently computes `failed <- is.null(res) || is.na(res$n_errors) || res$n_errors > 0`. Replace with:

```r
    failed <- is.null(res) || is.na(res$n_errors) || res$n_errors > 0 ||
              is.na(res$n_binwidth) || res$n_binwidth > 0
```

- [ ] **Step 4: Verify gate behavior**

Run: `Rscript src/r/audit/99_post_harmonize_gate.R --survey kamos 2>&1 | tail -12`
Expected: gate completes report-only, prints `bin-width errors=<n>` in the summary line, exit 0.

Run: `Rscript src/r/audit/test_phase5_gate.R`
Expected: all existing gate tests still pass (they exercise `run_post_harmonize_gate`; the new check runs inside it). If a test asserts on the exact `[gate]` summary-line format, update that assertion to the new line format — that is the only permitted test edit.

- [ ] **Step 5: Commit**

```bash
git add src/r/audit/99_post_harmonize_gate.R src/r/audit/test_phase5_gate.R
git commit -m "feat(audit): post-harmonize gate runs Check D (report-only default, blocks under HARMONIZE_AUDIT_GATE=block)"
```

---

### Task 5: All-survey sweep, triage, pin regression set

**Files:**
- Modify: `src/r/audit/test_bin_width_parity.R` (pin exact ABS parity_error variable set)
- Possibly modify: `src/config/_audit/bin_width_exemptions.yml` (verified-legitimate seams only)
- Possibly modify: `JEFF_MUST_INVESTIGATE.md` (suspicious new findings)

- [ ] **Step 1: Sweep every survey**

Run: `Rscript src/r/audit/04_bin_width_parity.R --all-surveys 2>&1 | tee /tmp/binwidth_sweep.txt`
Expected: one summary block per survey; ABS shows the 13 trust items; note every OTHER `parity_error` and `warn` row.

- [ ] **Step 2: Triage each non-trust finding.** For every `parity_error` outside the 13 ABS trust items: open the variable's YAML spec and the registry entry, and decide (a) genuine artefact of this class → leave visible AND append a dated entry to `JEFF_MUST_INVESTIGATE.md` describing variable, waves, signatures, and downstream risk (mirror the existing entry format in that file); or (b) legitimate, already-documented seam (e.g. a wave genuinely fielded a different instrument and the survey docs page says so) → add to `bin_width_exemptions.yml` with a `reason:` citing the documenting file. Do NOT exempt anything whose documentation you cannot point to.

- [ ] **Step 3: Pin the exact ABS regression set** — in `test_bin_width_parity.R` D9, after the `all(TRUST13 %in% err_vars)` assertion, add (filling `EXPECTED_ABS_ERR` with the post-triage sweep result):

```r
EXPECTED_ABS_ERR <- sort(c(TRUST13))  # extend with any triaged-and-kept non-trust findings
ok(identical(sort(err_vars), EXPECTED_ABS_ERR),
   "ABS parity_error set exactly matches pinned expectation")
```

- [ ] **Step 4: Run tests**

Run: `Rscript src/r/audit/test_bin_width_parity.R`
Expected: all pass, exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/r/audit/test_bin_width_parity.R src/config/_audit/bin_width_exemptions.yml JEFF_MUST_INVESTIGATE.md
git commit -m "feat(audit): Check D all-survey sweep triaged; ABS regression set pinned"
```

(Include only files actually changed by triage.)

---

### Task 6: QA.md documentation

**Files:**
- Modify: `docs/QA.md`

- [ ] **Step 1: Add Check D to the fault-injection verification table.** Locate the table containing the row `| ABS econ_family_income_fair_6pt stored opposite labels | label reconciliation | ... |` (~line 122) and add:

```markdown
| ABS W5 trust 6→4pt pole-merge (top-box inflated ~2.4–4.6×, direction correct) | bin-width parity (Check D) | **caught, still open** — 13 trust items flagged `parity_error` at w5; left visible by decision 2026-07-22 |
```

- [ ] **Step 2: Add a Check D section.** After the battery-coherence (Check B) / anchor-coverage (Check C1) descriptions, add:

```markdown
### Bin-width parity (Check D) — `04_bin_width_parity.R`

**What it provably catches:** a wave whose recode packs a DIFFERENT number of
source categories into a target bin than the variable's other waves — e.g.
the ABS W5 6→4pt trust collapse (native "Trust fully" + "Trust a lot" both →
4), which inflates W5 top-box shares ~2.4–4.6× in all 13 trust items while
every direction check passes, because the mapping is directionally correct.
Verified by fault injection in `test_bin_width_parity.R` (synthetic seam,
recode-mapping seam, and the real-ABS 13-item regression fixture).

**How:** static only. Signatures come from YAML `recode` mappings, identity
over the declared scale, or calling registry-declared `requires_data: false`
fns over their `input_scale` domain. No raw data is read.

**What it does NOT catch:**
- collapses applied uniformly in EVERY wave (comparability preserved by
  construction — deliberately not a finding);
- `requires_data: true` fns and `derive` methods (skipped, visible as `skip`
  rows);
- raw domains wider than the registry's declared `input_scale` (would need
  the deferred empirical raw→harmonized crosstab arm);
- fns missing from the registry (surfaced as `no_registry_entry`, warn-class;
  registry↔code drift itself is `check_registry_complete.R`'s job).

**Enforcement:** hard module in `run_all.R` (`L4 binwidth` column); in the
post-harmonize gate it is report-only by default and blocks only under
`HARMONIZE_AUDIT_GATE=block`, same as label reconciliation. Acknowledged
seams go in `src/config/_audit/bin_width_exemptions.yml` with a reason; the
13 ABS W5 trust findings are deliberately NOT exempted.
```

- [ ] **Step 3: Update QA.md's "default run does not verify" caveat** (~line 103) if it enumerates the hard checks — add bin-width parity to the list of checks whose errors only fail `run_all`'s tally, not a normal pipeline run.

- [ ] **Step 4: Commit**

```bash
git add docs/QA.md
git commit -m "docs(QA): document Check D bin-width parity — catches, misses, enforcement"
```

---

### Task 7: Full verification pass

- [ ] **Step 1: Run the complete new test file**: `Rscript src/r/audit/test_bin_width_parity.R` → all pass.
- [ ] **Step 2: Run neighboring audit test suites** (regression safety): `Rscript src/r/audit/test_phase2_checks.R && Rscript src/r/audit/test_phase3_checks.R && Rscript src/r/audit/test_phase5_gate.R` → all pass.
- [ ] **Step 3: Run `Rscript src/r/audit/run_all.R --survey abs --quick`** → SUMMARY.md has the L4 binwidth FAIL cell (13 err) and digest lines; no module crashes.
- [ ] **Step 4: `git log --oneline main..HEAD`** → 6–7 clean commits; working tree clean.
