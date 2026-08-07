#!/usr/bin/env Rscript
# src/r/audit/04_anchor_coverage.R
#
# Layer 4 — Anchor-coverage meta-check (audit ticket D6; Phase 2 of the
# harmonization auditor, 2026-06-20).
#
# The silent-killer anchor diagnostic (04_anchor_diagnostic.R) can only catch a
# wrong-direction variable if that variable is a LOADER in some construct anchor
# file. Both 2026-06-20 bugs (system_deserves_support, the dem_* democracy-supply
# battery) were NOT loaders in any anchor file, so the diagnostic never evaluated
# them. This check makes that gap visible: every direction-bearing harmonized
# variable must either (a) appear as the anchor or a loader in some
# src/config/_anchors/<construct>.yml, or (b) be explicitly exempted in
# src/config/_audit/anchor_coverage_exemptions.yml. "uncovered" is a finding.
#
# Direction-bearing = type ordinal or continuous. nominal/categorical/binary
# variables have no single construct direction to anchor and are reported as
# `skip` (not counted as uncovered).
#
# This is pure metadata (specs x anchor files x exemptions) — no data load — so
# it generalizes to every survey immediately.
#
# Severity: SOFT. `uncovered` maps to warn, never fail. It is a coverage metric
# that should trend toward zero as anchor files are authored; it is not a gate.
#
# Public API:
#   build_anchor_coverage_index(anchor_files = NULL)  -> tibble(variable, construct, role, surveys)
#   read_coverage_exemptions(path = NULL)             -> list(concepts, variables)
#   compute_anchor_coverage(survey, ...)              -> tibble
#   run_anchor_coverage(survey, ...)                  -> write CSV + summary
#
# CLI:
#   Rscript src/r/audit/04_anchor_coverage.R --survey abs
#   Rscript src/r/audit/04_anchor_coverage.R --all-surveys
#
# Status meanings:
#   covered    — variable is the anchor or a loader in >=1 applicable construct
#   exempt     — listed in anchor_coverage_exemptions.yml (concept or variable)
#   uncovered  — direction-bearing but neither covered nor exempt (warn finding)
#   skip       — not direction-bearing (nominal/categorical/binary)
#
# Exit code: 0 always (soft check; never blocks). Counts surfaced in summary.

suppressPackageStartupMessages({
  library(yaml)
  library(here)
  library(dplyr)
  library(tibble)
})

`%||%` <- function(a, b) if (!is.null(a)) a else b

# Types subject to the coverage requirement.
.DIRECTION_TYPES <- c("ordinal", "continuous")


# ---------------------------------------------------------------------------
# Build the variable -> construct coverage index from all anchor files.
# A variable is "covered" for a survey if it is the anchor.variable or a
# loader id, AND (for loaders) the loader's `surveys:` gate admits this survey
# (a NULL/absent surveys field means all surveys).
# Returns a tibble: variable, construct, role ("anchor"|"loader"), surveys (list-col).
# ---------------------------------------------------------------------------
build_anchor_coverage_index <- function(anchor_files = NULL) {
  if (is.null(anchor_files)) {
    anchor_files <- list.files(here::here("src", "config", "_anchors"),
                               pattern = "\\.yml$", full.names = TRUE)
  }
  rows <- list()
  for (af in anchor_files) {
    spec <- tryCatch(yaml::read_yaml(af), error = function(e) NULL)
    if (is.null(spec)) next
    construct <- spec$construct %||% basename(af)

    av <- spec$anchor$variable %||% NULL
    if (!is.null(av)) {
      rows[[length(rows) + 1]] <- tibble(
        variable = av, construct = construct, role = "anchor",
        surveys = list(NULL))
    }
    for (ld in spec$loaders %||% list()) {
      if (is.null(ld$id)) next
      sv <- ld$surveys %||% NULL
      if (!is.null(sv)) sv <- as.character(unlist(sv))
      rows[[length(rows) + 1]] <- tibble(
        variable = ld$id, construct = construct, role = "loader",
        surveys = list(sv))
    }
  }
  if (length(rows) == 0) {
    return(tibble(variable = character(0), construct = character(0),
                  role = character(0), surveys = list()))
  }
  bind_rows(rows)
}


# ---------------------------------------------------------------------------
# Read the exemptions file. Tolerates absence (returns empty sets).
# ---------------------------------------------------------------------------
read_coverage_exemptions <- function(
  path = here::here("src", "config", "_audit", "anchor_coverage_exemptions.yml")
) {
  if (!file.exists(path)) {
    return(list(concepts = character(0), variables = list()))
  }
  y <- yaml::read_yaml(path)
  list(
    concepts = as.character(y$exempt_concepts %||% character(0)),
    variables = y$exempt_variables %||% list()
  )
}

# Is variable `id` (survey `survey`) explicitly exempted by id?
.exempt_var_reason <- function(id, survey, exempt_vars) {
  for (e in exempt_vars) {
    if (!identical(e$variable, id)) next
    sv <- e$survey %||% NULL
    if (!is.null(sv) && !(survey %in% as.character(unlist(sv)))) next
    return(e$reason %||% "exempted (no reason given)")
  }
  NA_character_
}


# ---------------------------------------------------------------------------
# Compute coverage for one survey.
# ---------------------------------------------------------------------------
compute_anchor_coverage <- function(survey, spec_files = NULL,
                                    anchor_index = NULL, exemptions = NULL) {
  if (is.null(anchor_index)) anchor_index <- build_anchor_coverage_index()
  if (is.null(exemptions))   exemptions   <- read_coverage_exemptions()

  if (is.null(spec_files)) {
    if (!exists("list_survey_specs", mode = "function")) {
      source(here::here("src", "r", "utils", "spec_discovery.R"))
    }
    spec_files <- list_survey_specs(survey)
  }

  # Pre-resolve which variables the anchor index covers FOR THIS SURVEY.
  covered_for_survey <- function(id) {
    hits <- anchor_index[anchor_index$variable == id, , drop = FALSE]
    if (nrow(hits) == 0) return(NULL)
    for (i in seq_len(nrow(hits))) {
      sv <- hits$surveys[[i]]
      if (is.null(sv) || survey %in% sv) {
        return(list(construct = hits$construct[i], role = hits$role[i]))
      }
    }
    NULL
  }

  rows <- list()
  for (spec_path in spec_files) {
    spec <- yaml::read_yaml(spec_path)
    for (v in spec$variables %||% list()) {
      if (is.null(v$id)) next
      id <- v$id
      vtype <- v$type %||% "NA"
      concept <- v$concept %||% NA_character_

      mk <- function(status, reason, covered_by = NA_character_, role = NA_character_) {
        tibble(survey = survey, variable = id, concept = concept %||% NA_character_,
               type = vtype, covered_by = covered_by, role = role,
               status = status, reason = reason)
      }

      # Non-direction types are not subject to the requirement.
      if (!(vtype %in% .DIRECTION_TYPES)) {
        rows[[length(rows) + 1]] <- mk("skip", sprintf("type=%s (no construct direction)", vtype))
        next
      }
      # Concept-level exemption.
      if (!is.na(concept) && concept %in% exemptions$concepts) {
        rows[[length(rows) + 1]] <- mk("exempt", sprintf("concept '%s' exempt (structural/demographic)", concept))
        next
      }
      # Variable-level exemption.
      vex <- .exempt_var_reason(id, survey, exemptions$variables)
      if (!is.na(vex)) {
        rows[[length(rows) + 1]] <- mk("exempt", vex)
        next
      }
      # Anchor coverage.
      cov <- covered_for_survey(id)
      if (!is.null(cov)) {
        rows[[length(rows) + 1]] <- mk("covered",
          sprintf("%s in construct '%s'", cov$role, cov$construct),
          covered_by = cov$construct, role = cov$role)
      } else {
        rows[[length(rows) + 1]] <- mk("uncovered",
          "direction-bearing but in no anchor construct and not exempt")
      }
    }
  }

  if (length(rows) == 0) {
    return(tibble(survey = character(0), variable = character(0),
                  concept = character(0), type = character(0),
                  covered_by = character(0), role = character(0),
                  status = character(0), reason = character(0)))
  }
  bind_rows(rows)
}


# ---------------------------------------------------------------------------
# Run + write CSV + summary.
# ---------------------------------------------------------------------------
run_anchor_coverage <- function(survey, output_dir = NULL) {
  if (is.null(output_dir)) output_dir <- here::here("audit", "reports", survey)
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  results <- compute_anchor_coverage(survey)
  csv_path <- file.path(output_dir, "04-anchor-coverage.csv")
  write.csv(results, csv_path, row.names = FALSE)

  status_levels <- c("covered", "exempt", "uncovered", "skip")
  counts <- if (nrow(results) > 0) {
    as.list(table(factor(results$status, levels = status_levels)))
  } else setNames(as.list(rep(0L, 4)), status_levels)

  n_dir <- (counts$covered %||% 0) + (counts$exempt %||% 0) + (counts$uncovered %||% 0)
  pct_cov <- if (n_dir > 0) 100 * ((counts$covered %||% 0) + (counts$exempt %||% 0)) / n_dir else 100

  cat(sprintf("\n[anchor coverage] survey=%s\n", survey))
  cat(sprintf("  direction-bearing vars: %d (covered=%d, exempt=%d, uncovered=%d); skip(non-dir)=%d\n",
              n_dir, counts$covered %||% 0, counts$exempt %||% 0,
              counts$uncovered %||% 0, counts$skip %||% 0))
  cat(sprintf("  coverage: %.1f%% of direction-bearing vars covered-or-exempt\n", pct_cov))
  cat(sprintf("  CSV: %s\n", csv_path))

  unc <- results[results$status == "uncovered", , drop = FALSE]
  if (nrow(unc) > 0) {
    cat(sprintf("\n  %d uncovered (warn) — author an anchor file or exempt:\n", nrow(unc)))
    by_concept <- sort(table(unc$concept), decreasing = TRUE)
    for (cn in names(by_concept)) {
      vs <- unc$variable[unc$concept == cn]
      cat(sprintf("    [%s] %s\n", cn, paste(vs, collapse = ", ")))
    }
  }
  invisible(results)
}

run_all_surveys <- function() {
  if (!exists("list_survey_specs", mode = "function")) {
    source(here::here("src", "r", "utils", "spec_discovery.R"))
  }
  supported <- c("abs", "wvs", "lbs", "afro", "arab-barometer", "kamos",
                 "kgss", "kipa_corruption", "kinu", "ipus", "gcb")
  all_results <- list()
  for (survey in supported) {
    res <- tryCatch(run_anchor_coverage(survey), error = function(e) {
      cat(sprintf("  [anchor coverage] %s: %s\n", survey, conditionMessage(e)))
      NULL
    })
    if (!is.null(res)) all_results[[survey]] <- res
  }
  bind_rows(all_results)
}


# ---------------------------------------------------------------------------
# CLI.
# ---------------------------------------------------------------------------
.parse_cli_args <- function(argv) {
  out <- list(survey = NULL, all_surveys = FALSE, output_dir = NULL)
  i <- 1
  while (i <= length(argv)) {
    a <- argv[i]
    if (a == "--survey")      { out$survey      <- argv[i + 1]; i <- i + 2; next }
    if (a == "--all-surveys") { out$all_surveys <- TRUE;        i <- i + 1; next }
    if (a == "--output-dir")  { out$output_dir  <- argv[i + 1]; i <- i + 2; next }
    if (a %in% c("-h", "--help")) {
      cat("Usage: Rscript src/r/audit/04_anchor_coverage.R\n",
          "         (--survey <name> | --all-surveys) [--output-dir <path>]\n",
          "\nMeta-check: every ordinal/continuous harmonized variable must be a\n",
          "loader/anchor in some src/config/_anchors/*.yml OR exempted in\n",
          "src/config/_audit/anchor_coverage_exemptions.yml. uncovered = warn.\n",
          "Soft check: always exits 0.\n", sep = "")
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
    if (args$all_surveys) run_all_surveys() else
      run_anchor_coverage(args$survey, output_dir = args$output_dir)
    quit(status = 0)  # soft check, never blocks
  }
}
