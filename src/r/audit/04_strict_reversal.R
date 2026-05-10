#!/usr/bin/env Rscript
# src/r/audit/04_strict_reversal.R
#
# Layer 4 — Strict raw↔harmonized reversal check (audit ticket D4).
#
# For every (variable, wave) where the spec's wave-rule names a function that
# REVERSES (per src/r/utils/recoding_registry.yml `reverses: true`), the
# Pearson correlation between (raw value after missing-code masking) and
# (harmonized value) MUST equal -1.0 within rounding. Anything else means the
# recoding produced a non-cleanly-reversed mapping — most commonly an
# unexpected raw code that survived missing-code masking, or a wave whose raw
# direction differs from what the YAML claims.
#
# This is the strictest mechanical reverse-check available: cheap to run,
# broad coverage, no anchor needed. Complementary to the anchor diagnostic in
# 04_anchor_diagnostic.R (which checks SIGN against an external construct).
#
# Public API:
#   compute_strict_reversal(survey, ...)   -- returns a tibble
#   run_strict_reversal(survey, ...)       -- writes CSV + prints summary
#
# CLI:
#   Rscript src/r/audit/04_strict_reversal.R --survey abs
#   Rscript src/r/audit/04_strict_reversal.R --all-surveys
#
# Status meanings:
#   ok    — pearson <= -0.999, reversal clean
#   fail  — pearson > -0.999, reversal NOT clean (audit finding)
#   skip  — n_paired < 10, harmonized output missing, or raw RDS missing
#
# Exit code 0 if no fails; exit 1 if any fail rows present.
#
# v1: ABS-first. Other surveys (KGSS, LBS, Afro, ...) require per-survey raw
# loaders because their raw waves are not stored as one-RDS-per-wave —
# documented in `.SURVEY_RAW_LOADERS` below.
#
# See audit/01-audit-framework.md §Layer 4 (item 3) and
#     audit/02-implementation-tickets.md ticket D4.

suppressPackageStartupMessages({
  library(yaml)
  library(here)
  library(haven)
  library(dplyr)
  library(tibble)
})


# ---------------------------------------------------------------------------
# Internal helpers (also defined elsewhere; redeclared so this file works
# stand-alone without sourcing harmonize.R).
# ---------------------------------------------------------------------------
`%||%` <- function(a, b) if (!is.null(a)) a else b


# ---------------------------------------------------------------------------
# Mirror of harmonize.R::resolve_wave_rule(). Kept inline so this script does
# not depend on engine sourcing order. If the engine resolution semantics
# change, update both — they MUST agree.
# ---------------------------------------------------------------------------
.resolve_wave_rule <- function(var_spec, wave_name) {
  default_rule <- var_spec$harmonize$default %||% list(method = "identity")
  var_spec$harmonize$by_wave[[wave_name]] %||%
    var_spec$harmonize$exceptions[[wave_name]] %||%
    var_spec$harmonize[[wave_name]] %||%
    default_rule
}


# ---------------------------------------------------------------------------
# Mirror of harmonize.R::apply_missing(). Same justification as above.
# ---------------------------------------------------------------------------
.apply_missing <- function(x, missing_codes) {
  if (length(missing_codes) == 0) return(x)
  x[x %in% missing_codes] <- NA_real_
  x
}


# ---------------------------------------------------------------------------
# Resolve missing codes for a (variable, wave). Mirrors the engine's
# resolution path in harmonize.R:171-189.
# ---------------------------------------------------------------------------
.resolve_missing_codes <- function(var_spec, missing_conventions) {
  miss_convention_key <- var_spec$missing$use_convention %||% "treat_as_na"
  missing_codes <- numeric(0)

  conv <- missing_conventions[[miss_convention_key]]
  if (!is.null(conv)) {
    if (is.list(conv) && !is.null(conv$codes)) {
      missing_codes <- as.numeric(conv$codes)
    } else {
      missing_codes <- as.numeric(conv)
    }
  }

  if (!is.null(var_spec$missing$codes)) {
    missing_codes <- unique(c(missing_codes, as.numeric(var_spec$missing$codes)))
  }
  missing_codes
}


# ---------------------------------------------------------------------------
# Load the recoding registry once and cache. Returns a character vector of
# function names eligible for the STRICT reversal check.
#
# The strict check asserts pearson(raw_masked, harmonized) <= -0.999, which
# is mathematically meaningful only for *pure* reversers — i.e. functions
# that satisfy ALL of:
#   - reverses: true     (function flips direction)
#   - monotonic: true    (transform is monotone over the input domain)
#   - input_scale == output_scale  (no collapse / shift; pure n+1-x)
#
# Reversers that fail any of those (e.g. country-conditional flips like
# `reverse_trust_vietnam_w2`, scale-collapsing reversers like
# `collapse_6pt_to_4pt_reverse`, or sign-flipping binary recodes like
# `recode_binary_yes_no` that change the scale 1/2 → 0/1) are EXCLUDED from
# this check — Pearson against the raw vector is not -1.0 even when the
# function is correct. Those are validated by other layers (anchor
# diagnostic in 04_anchor_diagnostic.R; transformation Spearman check in
# validation.R::validate_transformation()).
# ---------------------------------------------------------------------------
.registry_cache <- new.env(parent = emptyenv())

load_reverser_set <- function(
  registry_path = here::here("src", "r", "utils", "recoding_registry.yml")
) {
  if (!is.null(.registry_cache$reversers)) return(.registry_cache$reversers)
  if (!file.exists(registry_path)) {
    stop(sprintf("recoding registry not found at %s", registry_path),
         call. = FALSE)
  }
  reg <- yaml::read_yaml(registry_path)

  is_strict <- function(e) {
    if (!isTRUE(e$reverses)) return(FALSE)
    if (!isTRUE(e$monotonic)) return(FALSE)
    if (isTRUE(e$requires_data)) return(FALSE)
    isf <- e$input_scale; osf <- e$output_scale
    if (is.null(isf) || is.null(osf)) return(FALSE)
    # Both scales must be 2-element numeric and identical for "pure" reversal.
    if (length(isf) != 2 || length(osf) != 2) return(FALSE)
    isf_n <- suppressWarnings(as.numeric(unlist(isf)))
    osf_n <- suppressWarnings(as.numeric(unlist(osf)))
    if (any(is.na(isf_n)) || any(is.na(osf_n))) return(FALSE)
    identical(isf_n, osf_n)
  }

  flags <- vapply(reg, is_strict, logical(1))
  reversers <- vapply(reg, function(e) e$fn, character(1))[flags]
  .registry_cache$reversers <- reversers
  reversers
}


# ---------------------------------------------------------------------------
# Per-survey raw-RDS path resolver. ABS uses one RDS per wave at
# data/processed/w<N>.rds. Other surveys generally don't — their raw waves
# come from a single .sav split by year inside the loader. For v1 this script
# is ABS-first; the registry below is the place to extend.
#
# Each entry returns a function (wave_key -> path or NULL) that the strict
# check uses to load the raw wave for that variable.
# ---------------------------------------------------------------------------
.SURVEY_RAW_LOADERS <- list(
  abs = function(wave_key) {
    # wave_key is "w1".."w6". Strip the 'w' and look up data/processed/w<N>.rds.
    if (!grepl("^w[0-9]+$", wave_key)) return(NULL)
    n <- sub("^w", "", wave_key)
    p <- here::here("data", "processed", paste0("w", n, ".rds"))
    if (file.exists(p)) p else NULL
  }
)

# Per-survey wave-key normalizer mapping spec wave keys to harmonized wave
# values. ABS spec wave keys are "w1".."w6"; harmonized RDS stores wave as
# integer 1..6. For other surveys this differs (KGSS spec "w2004" ↔
# harmonized integer 2004; KAMOS spec "w1"/"w4" ↔ harmonized integer 1/4).
.SURVEY_HARMONIZED_WAVE_KEY <- list(
  abs = function(wave_key) {
    if (!grepl("^w[0-9]+$", wave_key)) return(NA_integer_)
    as.integer(sub("^w", "", wave_key))
  }
)


# ---------------------------------------------------------------------------
# Per-survey harmonized-output loader. Returns a tibble for one (survey,
# wave) slice — at minimum a `wave` column plus the harmonized variable
# columns. For ABS we use the per-wave RDS at outputs/master_w<N>.rds; for
# other surveys we fall back to data/processed/<survey>_harmonized.rds and
# filter on the wave column.
# ---------------------------------------------------------------------------
.harmonized_cache <- new.env(parent = emptyenv())

load_harmonized_wave <- function(survey, wave_key) {
  cache_key <- paste0(survey, "::", wave_key)
  if (!is.null(.harmonized_cache[[cache_key]])) {
    return(.harmonized_cache[[cache_key]])
  }

  if (identical(survey, "abs")) {
    # ABS: per-wave file at outputs/master_w<N>.rds.
    if (!grepl("^w[0-9]+$", wave_key)) return(NULL)
    n <- sub("^w", "", wave_key)
    p <- here::here("outputs", paste0("master_w", n, ".rds"))
    if (!file.exists(p)) return(NULL)
    d <- readRDS(p)
    .harmonized_cache[[cache_key]] <- d
    return(d)
  }

  # Other surveys: read once, filter to the wave subset.
  long_path <- here::here("data", "processed",
                          paste0(survey, "_harmonized.rds"))
  if (!file.exists(long_path)) return(NULL)
  full_key <- paste0(survey, "::__full__")
  full <- .harmonized_cache[[full_key]]
  if (is.null(full)) {
    full <- readRDS(long_path)
    .harmonized_cache[[full_key]] <- full
  }
  if (!"wave" %in% names(full)) return(NULL)
  norm <- .SURVEY_HARMONIZED_WAVE_KEY[[survey]]
  if (is.null(norm)) {
    # Default: assume spec wave_key like "w2004" or "y2003" or "r5" — try
    # matching as-is or stripping the leading letter.
    norm <- function(k) {
      if (grepl("^[a-zA-Z][0-9]+$", k)) as.integer(sub("^[a-zA-Z]", "", k)) else k
    }
  }
  hw <- norm(wave_key)
  d <- full[full$wave == hw, , drop = FALSE]
  if (nrow(d) == 0) return(NULL)
  .harmonized_cache[[cache_key]] <- d
  d
}


# ---------------------------------------------------------------------------
# Mirror of harmonize.R numeric-coercion logic for raw vectors
# (handles haven_labelled from SPSS imports).
# ---------------------------------------------------------------------------
.coerce_numeric <- function(x) {
  if (inherits(x, "haven_labelled")) {
    return(as.numeric(haven::zap_labels(x)))
  }
  if (is.character(x)) return(suppressWarnings(as.numeric(x)))
  suppressWarnings(as.numeric(x))
}


# ---------------------------------------------------------------------------
# Pure correlation step. Given two numeric vectors of equal length, returns
# (n_paired, pearson) on rows where both are non-NA.
# ---------------------------------------------------------------------------
.pearson_paired <- function(a, b) {
  if (length(a) != length(b)) {
    stop(sprintf(".pearson_paired(): length mismatch %d vs %d",
                 length(a), length(b)), call. = FALSE)
  }
  ok <- !is.na(a) & !is.na(b)
  n <- sum(ok)
  if (n < 10) return(list(n = n, pearson = NA_real_))
  if (length(unique(a[ok])) < 2 || length(unique(b[ok])) < 2) {
    # Degenerate: at least one vector is constant on the paired sample.
    return(list(n = n, pearson = NA_real_))
  }
  r <- suppressWarnings(cor(a[ok], b[ok], method = "pearson"))
  list(n = n, pearson = r)
}


# ---------------------------------------------------------------------------
# Single-(variable, wave) strict reversal check. Returns a one-row tibble.
# This is the unit the orchestrator collects.
# ---------------------------------------------------------------------------
.check_one <- function(survey, var_spec, wave_key, fn_name,
                        missing_conventions) {
  var_id <- var_spec$id

  # Resolve raw-data path for this (survey, wave).
  raw_path_resolver <- .SURVEY_RAW_LOADERS[[survey]]
  if (is.null(raw_path_resolver)) {
    return(tibble(
      survey = survey, variable = var_id, wave = wave_key, fn = fn_name,
      n_paired = 0L, pearson = NA_real_, status = "skip",
      message = sprintf(
        "no raw-RDS resolver for survey '%s' (v1 supports ABS only)", survey
      )
    ))
  }
  raw_path <- raw_path_resolver(wave_key)
  if (is.null(raw_path) || !file.exists(raw_path %||% "")) {
    return(tibble(
      survey = survey, variable = var_id, wave = wave_key, fn = fn_name,
      n_paired = 0L, pearson = NA_real_, status = "skip",
      message = sprintf("raw RDS not found for wave %s", wave_key)
    ))
  }

  # Load harmonized wave slice.
  harm_df <- load_harmonized_wave(survey, wave_key)
  if (is.null(harm_df)) {
    return(tibble(
      survey = survey, variable = var_id, wave = wave_key, fn = fn_name,
      n_paired = 0L, pearson = NA_real_, status = "skip",
      message = "harmonized output missing for this wave"
    ))
  }
  if (!var_id %in% names(harm_df)) {
    return(tibble(
      survey = survey, variable = var_id, wave = wave_key, fn = fn_name,
      n_paired = 0L, pearson = NA_real_, status = "skip",
      message = sprintf("variable '%s' not in harmonized output", var_id)
    ))
  }

  # Load raw wave.
  raw_df <- tryCatch(readRDS(raw_path), error = function(e) NULL)
  if (is.null(raw_df)) {
    return(tibble(
      survey = survey, variable = var_id, wave = wave_key, fn = fn_name,
      n_paired = 0L, pearson = NA_real_, status = "skip",
      message = sprintf("failed to read raw RDS at %s", raw_path)
    ))
  }
  src <- var_spec$source[[wave_key]]
  if (is.null(src) || !src %in% names(raw_df)) {
    return(tibble(
      survey = survey, variable = var_id, wave = wave_key, fn = fn_name,
      n_paired = 0L, pearson = NA_real_, status = "skip",
      message = sprintf("source variable '%s' not in raw wave", src %||% "NULL")
    ))
  }

  # Critical row-alignment invariant: nrow(raw_df) must equal nrow(harm_df).
  # If it doesn't, the engine and audit are looking at different runs.
  if (nrow(raw_df) != nrow(harm_df)) {
    return(tibble(
      survey = survey, variable = var_id, wave = wave_key, fn = fn_name,
      n_paired = 0L, pearson = NA_real_, status = "skip",
      message = sprintf(
        "row-count mismatch: raw=%d, harmonized=%d (cannot align)",
        nrow(raw_df), nrow(harm_df)
      )
    ))
  }

  # Apply missing-code masking exactly as the engine does.
  missing_codes <- .resolve_missing_codes(var_spec, missing_conventions)
  raw_vec <- .coerce_numeric(raw_df[[src]])
  raw_masked <- .apply_missing(raw_vec, missing_codes)

  # Harmonized vector — coerce to numeric in case it's stored as integer.
  harm_vec <- suppressWarnings(as.numeric(harm_df[[var_id]]))

  cr <- .pearson_paired(raw_masked, harm_vec)
  if (is.na(cr$pearson)) {
    return(tibble(
      survey = survey, variable = var_id, wave = wave_key, fn = fn_name,
      n_paired = as.integer(cr$n), pearson = NA_real_, status = "skip",
      message = sprintf(
        "insufficient or degenerate paired data (n=%d)", cr$n
      )
    ))
  }

  if (cr$pearson <= -0.999) {
    list_status <- "ok"
    msg <- sprintf("clean reversal (r=%.4f, n=%d)", cr$pearson, cr$n)
  } else {
    list_status <- "fail"
    msg <- sprintf(
      "non-clean reversal (r=%.4f > -0.999, n=%d) — possible bug",
      cr$pearson, cr$n
    )
  }

  tibble(
    survey   = survey,
    variable = var_id,
    wave     = wave_key,
    fn       = fn_name,
    n_paired = as.integer(cr$n),
    pearson  = cr$pearson,
    status   = list_status,
    message  = msg
  )
}


# ---------------------------------------------------------------------------
# Public: compute strict-reversal results for a survey.
#
# Args:
#   survey: e.g. "abs". Must have a raw-RDS resolver in .SURVEY_RAW_LOADERS.
#   spec_files: optional character vector of YAML paths. Default discovers
#               via list_survey_specs(survey).
#   reversers: optional character vector of fn names that reverse. Default
#              loads from the recoding registry.
#
# Returns: tibble with one row per (variable, wave) where the resolved rule
# is a reverser (plus skip rows for failures-to-load).
# ---------------------------------------------------------------------------
compute_strict_reversal <- function(survey, spec_files = NULL,
                                    reversers = NULL) {
  if (is.null(reversers)) reversers <- load_reverser_set()

  if (is.null(spec_files)) {
    # Defer-load spec_discovery so callers don't have to source it.
    sd_path <- here::here("src", "r", "utils", "spec_discovery.R")
    if (exists("list_survey_specs", mode = "function")) {
      # Already loaded.
    } else {
      source(sd_path)
    }
    spec_files <- list_survey_specs(survey)
  }

  rows <- list()
  for (spec_path in spec_files) {
    spec <- yaml::read_yaml(spec_path)
    missing_conventions <- spec$missing_conventions %||% list()

    for (v in spec$variables %||% list()) {
      # Iterate every wave declared in `source:` (this is the list of waves
      # the YAML claims to harmonize). For each wave, resolve the rule and
      # check whether the named function is a reverser.
      wave_keys <- names(v$source %||% list())
      for (wave_key in wave_keys) {
        src <- v$source[[wave_key]]
        if (is.null(src)) next  # explicit YAML null → skipped wave

        rule <- .resolve_wave_rule(v, wave_key)
        method <- rule$method %||% "identity"
        if (!identical(method, "r_function")) next

        fn_name <- rule$fn %||% ""
        if (!nzchar(fn_name) || !(fn_name %in% reversers)) next

        rows[[length(rows) + 1]] <- .check_one(
          survey = survey,
          var_spec = v,
          wave_key = wave_key,
          fn_name = fn_name,
          missing_conventions = missing_conventions
        )
      }
    }
  }

  if (length(rows) == 0) {
    return(tibble(
      survey = character(0), variable = character(0), wave = character(0),
      fn = character(0), n_paired = integer(0), pearson = numeric(0),
      status = character(0), message = character(0)
    ))
  }
  bind_rows(rows)
}


# ---------------------------------------------------------------------------
# Public: run + write CSV + print summary.
# ---------------------------------------------------------------------------
run_strict_reversal <- function(survey, output_dir = NULL) {
  if (is.null(output_dir)) {
    output_dir <- here::here("audit", "reports", survey)
  }
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  results <- compute_strict_reversal(survey)

  csv_path <- file.path(output_dir, "04-strict-reversal.csv")
  write.csv(results, csv_path, row.names = FALSE)

  # Stdout summary.
  status_levels <- c("ok", "fail", "skip")
  counts <- if (nrow(results) > 0) {
    as.list(table(factor(results$status, levels = status_levels)))
  } else {
    setNames(as.list(rep(0L, length(status_levels))), status_levels)
  }
  cat(sprintf("\n[strict reversal] survey=%s\n", survey))
  cat(sprintf("  total checks: %d (ok=%d, fail=%d, skip=%d)\n",
              nrow(results),
              counts$ok %||% 0,
              counts$fail %||% 0,
              counts$skip %||% 0))
  cat(sprintf("  CSV: %s\n", csv_path))

  fails <- results[results$status == "fail", , drop = FALSE]
  if (nrow(fails) > 0) {
    cat(sprintf("\n  *** %d FAIL row(s) — non-clean reversal(s):\n",
                nrow(fails)))
    print(as.data.frame(fails[, c("variable", "wave", "fn",
                                  "n_paired", "pearson", "message")]),
          row.names = FALSE)
    cat("\n  → Each fail row is a Layer 4 audit finding. Investigate the\n")
    cat("    raw codes for that (variable, wave) — likely an unexpected\n")
    cat("    raw value survived missing-code masking, OR the raw direction\n")
    cat("    differs from what the YAML declares.\n\n")
  }

  invisible(results)
}


# ---------------------------------------------------------------------------
# Multi-survey orchestrator. Iterates supported surveys; skips those without
# a raw-RDS resolver. Returns combined tibble.
# ---------------------------------------------------------------------------
run_all_surveys <- function() {
  supported <- names(.SURVEY_RAW_LOADERS)
  unsupported_msg <- setdiff(c(
    "abs", "kgss", "lbs", "afro", "arab-barometer", "kamos",
    "kipa-corruption", "kinu", "ipus", "wvs"
  ), supported)
  if (length(unsupported_msg) > 0) {
    cat(sprintf(
      "[strict reversal] v1 supports: %s\n",
      paste(supported, collapse = ", ")
    ))
    cat(sprintf(
      "[strict reversal] not yet supported (need per-survey raw-loader): %s\n",
      paste(unsupported_msg, collapse = ", ")
    ))
  }

  all_results <- list()
  for (survey in supported) {
    all_results[[survey]] <- run_strict_reversal(survey)
  }
  bind_rows(all_results)
}


# ---------------------------------------------------------------------------
# CLI entry point.
# ---------------------------------------------------------------------------
.parse_cli_args <- function(argv) {
  out <- list(survey = NULL, all_surveys = FALSE, output_dir = NULL)
  i <- 1
  while (i <= length(argv)) {
    a <- argv[i]
    if (a == "--survey")       { out$survey      <- argv[i + 1]; i <- i + 2; next }
    if (a == "--all-surveys")  { out$all_surveys <- TRUE;        i <- i + 1; next }
    if (a == "--output-dir")   { out$output_dir  <- argv[i + 1]; i <- i + 2; next }
    if (a %in% c("-h", "--help")) {
      cat("Usage: Rscript src/r/audit/04_strict_reversal.R\n",
          "         (--survey <name> | --all-surveys)\n",
          "         [--output-dir <path>]\n",
          "\n",
          "Strict raw<->harmonized reversal check. For every (variable, wave)\n",
          "harmonized via a `reverses: true` function (per the recoding\n",
          "registry), assert pearson(raw_masked, harmonized) <= -0.999.\n",
          "\n",
          "Status meanings:\n",
          "  ok    -- clean reversal\n",
          "  fail  -- non-clean reversal (audit finding)\n",
          "  skip  -- insufficient data, harmonized missing, or raw missing\n",
          "\n",
          "Exit: 0 if no fails, 1 otherwise.\n", sep = "")
      quit(status = 0)
    }
    stop(sprintf("unknown argument: %s", a), call. = FALSE)
  }
  if (is.null(out$survey) && !out$all_surveys) {
    stop("usage: --survey <name> OR --all-surveys (see --help)", call. = FALSE)
  }
  out
}

# Only run the CLI when invoked as a script (not when sourced for testing).
if (sys.nframe() == 0L) {
  argv <- commandArgs(trailingOnly = TRUE)
  if (length(argv) > 0) {
    args <- .parse_cli_args(argv)
    results <- if (args$all_surveys) {
      run_all_surveys()
    } else {
      run_strict_reversal(args$survey, output_dir = args$output_dir)
    }
    n_fail <- sum(results$status == "fail", na.rm = TRUE)
    if (n_fail > 0) quit(status = 1) else quit(status = 0)
  }
}
