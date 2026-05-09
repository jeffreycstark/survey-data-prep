#!/usr/bin/env Rscript
# src/r/audit/04_anchor_diagnostic.R
#
# Layer 4 — Anchor-correlation diagnostic ("the silent killer").
#
# Reads a construct anchor file (src/config/_anchors/<construct>.yml) and the
# survey's harmonized output, then computes per-(variable × wave × country)
# Pearson + Spearman correlations between each loader and the construct's
# anchor variable. Compares observed sign to the loader's declared
# expected_sign and surfaces sign disagreements as the highest-priority
# audit finding (a sign disagreement = the YAML's reverse-coding decision
# probably produced a wrong-direction variable).
#
# Public API:
#   compute_anchor_correlations(anchor_spec, harmonized, survey, ...)
#   run_anchor_diagnostic(anchor_file, survey, harmonized = NULL,
#                         output_dir = "audit/reports/<survey>")
#
# CLI:
#   Rscript src/r/audit/04_anchor_diagnostic.R \
#     --survey abs --anchor src/config/_anchors/democratic_attitudes.yml
#
# See audit/01-audit-framework.md §Layer 4 and audit/02-implementation-tickets.md ticket D3.

suppressPackageStartupMessages({
  library(yaml)
  library(dplyr)
  library(tibble)
  library(purrr)
})

# ---------------------------------------------------------------------------
# Internal: %||% (also defined in src/r/harmonize/harmonize.R; redeclared
# here so this script works even when harmonize.R has not been sourced).
# ---------------------------------------------------------------------------
`%||%` <- function(a, b) if (!is.null(a)) a else b


# ---------------------------------------------------------------------------
# Wave-key normalization.
#
# Anchor files write wave keys as "w1", "w2", "y2003", "r5", etc. (matching
# the heterogeneous wave conventions across surveys). The harmonized output
# stores `wave` as integer (1..6 for ABS) or string (per-survey). To compare
# them, we map both sides to a canonical key by stripping leading
# non-digit chars and prepending the original prefix back if non-empty.
#
# For the per-survey conventions used today:
#   ABS: anchor "w1".."w6" ↔ harmonized integer 1..6
#   KGSS: anchor "w2003".."w2025" ↔ harmonized "w2003".."w2025"
#   Afro: anchor "r1".."r9" ↔ harmonized "r1".."r9"
#   LBS: anchor "y1995".."y2024" ↔ harmonized "y1995".."y2024"
#
# Strategy: define a single canonicalizer that returns a normalized key
# usable as a join column. ABS integer wave 1 → "w1"; the anchor's "w1" is
# already canonical, so they meet at "w1".
# ---------------------------------------------------------------------------
normalize_wave_key <- function(x, survey = NULL) {
  if (length(x) == 0) return(character(0))
  # Coerce to character; if numeric/integer, prepend ABS-style "w".
  if (is.numeric(x)) {
    # Integer waves come from ABS. Other surveys store waves as strings.
    return(paste0("w", as.integer(x)))
  }
  s <- as.character(x)
  # Already-canonical strings ("w1", "y2003", "r5") pass through unchanged.
  s
}


# ---------------------------------------------------------------------------
# Internal: normalize a `surveys:` field that may be scalar or array.
# ---------------------------------------------------------------------------
.normalize_surveys_field <- function(x) {
  if (is.null(x)) return(NULL)
  as.character(x)
}


# ---------------------------------------------------------------------------
# Internal: normalize a `waves:` field that may be scalar or array.
# ---------------------------------------------------------------------------
.normalize_waves_field <- function(x) {
  if (is.null(x)) return(NULL)
  as.character(x)
}


# ---------------------------------------------------------------------------
# Internal: classify a Pearson correlation against a min_correlation floor.
# Returns "positive", "negative", or "weak". "na" handled separately
# (insufficient data).
# ---------------------------------------------------------------------------
.classify_observed_sign <- function(r, min_corr) {
  if (is.na(r)) return("na")
  if (abs(r) < min_corr) return("weak")
  if (r > 0) return("positive") else "negative"
}


# ---------------------------------------------------------------------------
# Internal: compose anchor's per-wave direction with loader's expected_sign.
#
# A loader's expected_sign is theory-relative-to-anchor. If the anchor's
# direction in this wave is `negative` (per `anchor.per_wave`), then a
# loader with expected_sign="positive" should have a *negative* observed
# correlation in this wave. Composition rule: positive · negative = negative.
# ---------------------------------------------------------------------------
.compose_expected_sign <- function(loader_sign, anchor_dir_for_wave) {
  if (loader_sign == "either") return("either")
  if (anchor_dir_for_wave == "none") return(loader_sign)  # no anchor flip
  if (anchor_dir_for_wave == "positive") return(loader_sign)
  # anchor direction is negative → flip
  if (loader_sign == "positive") "negative" else "positive"
}


# ---------------------------------------------------------------------------
# Internal: anchor wave-direction lookup (with global fallback).
# ---------------------------------------------------------------------------
.anchor_direction_for_wave <- function(anchor_block, wave_key) {
  per_wave <- anchor_block$per_wave %||% list()
  per_wave[[wave_key]] %||% (anchor_block$expected_direction %||% "positive")
}


# ---------------------------------------------------------------------------
# Internal: compute correlation status from loader's expected_sign and
# observed_sign, given a min_correlation floor.
# ---------------------------------------------------------------------------
.compute_status <- function(expected, observed, abs_r) {
  if (observed == "na") {
    return(list(status = "weak",
                message = "insufficient data for correlation"))
  }
  if (expected == "either") {
    if (observed == "weak") {
      return(list(status = "weak",
                  message = sprintf("either-sign loader weak (|r|=%.3f)", abs_r)))
    }
    return(list(status = "ok",
                message = sprintf("either-sign loader observed=%s (|r|=%.3f)",
                                  observed, abs_r)))
  }
  if (observed == "weak") {
    return(list(status = "weak",
                message = sprintf("loader weak: |r|=%.3f below floor", abs_r)))
  }
  if (observed == expected) {
    return(list(status = "ok",
                message = sprintf("sign matches expectation (%s, |r|=%.3f)",
                                  expected, abs_r)))
  }
  list(status = "sign_disagreement",
       message = sprintf(
         "expected=%s observed=%s (|r|=%.3f) — possible reverse-coding bug",
         expected, observed, abs_r
       ))
}


# ---------------------------------------------------------------------------
# Public: parse + lightly validate an anchor file.
#
# Does NOT enforce the JSON Schema — that's a separate concern owned by D1's
# schema validator. We do enough structural checks to fail loud here when
# the file is so malformed that the diagnostic can't proceed.
# ---------------------------------------------------------------------------
read_anchor_file <- function(anchor_file) {
  if (!file.exists(anchor_file)) {
    stop(sprintf("anchor file not found: %s", anchor_file), call. = FALSE)
  }
  spec <- yaml::read_yaml(anchor_file)
  if (is.null(spec$construct) || is.null(spec$anchor) || is.null(spec$loaders)) {
    stop(sprintf(
      "anchor file '%s' missing one of: construct, anchor, loaders",
      anchor_file
    ), call. = FALSE)
  }
  if (is.null(spec$anchor$variable)) {
    stop(sprintf("anchor file '%s' has no anchor.variable", anchor_file), call. = FALSE)
  }
  spec$anchor$expected_direction <- spec$anchor$expected_direction %||% "positive"
  spec
}


# ---------------------------------------------------------------------------
# Internal: cached harmonized loader.
#
# `compute_anchor_correlations()` accepts a pre-loaded data frame, but the
# CLI orchestrator loads from disk and may be called multiple times in a
# session. Cache the result keyed by survey name to avoid re-reading.
# ---------------------------------------------------------------------------
.harmonized_cache <- new.env(parent = emptyenv())

load_harmonized_for_survey <- function(survey, harmonized_path = NULL,
                                        force_reload = FALSE) {
  cache_key <- paste0(survey, "::", harmonized_path %||% "<default>")
  if (!force_reload && !is.null(.harmonized_cache[[cache_key]])) {
    return(.harmonized_cache[[cache_key]])
  }

  if (is.null(harmonized_path)) {
    # Default per-survey paths. ABS has a long-format harmonized output
    # at data/processed/abs_harmonized.rds. Other surveys store similarly.
    candidates <- switch(
      survey,
      abs = c(
        "data/processed/abs_harmonized.rds",
        "outputs/abs/harmonized.rds"
      ),
      c(
        sprintf("data/processed/%s_harmonized.rds", survey),
        sprintf("outputs/%s/harmonized.rds", survey)
      )
    )
    harmonized_path <- candidates[file.exists(candidates)][1]
    if (is.na(harmonized_path)) {
      stop(sprintf(
        "load_harmonized_for_survey('%s'): no harmonized .rds found at any of: %s",
        survey, paste(candidates, collapse = ", ")
      ), call. = FALSE)
    }
  }

  if (!file.exists(harmonized_path)) {
    stop(sprintf("harmonized file not found: %s", harmonized_path), call. = FALSE)
  }

  d <- readRDS(harmonized_path)
  # Ensure data has wave + country columns. Country is optional (some
  # single-country surveys have none); wave is mandatory.
  if (!"wave" %in% names(d)) {
    stop(sprintf(
      "harmonized file '%s' has no 'wave' column", harmonized_path
    ), call. = FALSE)
  }

  .harmonized_cache[[cache_key]] <- d
  d
}


# ---------------------------------------------------------------------------
# Internal: pure correlation row builder.
#
# Given a vector of loader values and a vector of anchor values (already
# subset to the same wave/country), returns a one-row tibble with n,
# pearson, spearman, and the absolute pearson value.
# ---------------------------------------------------------------------------
.compute_corr_row <- function(loader_vec, anchor_vec) {
  loader_num <- suppressWarnings(as.numeric(loader_vec))
  anchor_num <- suppressWarnings(as.numeric(anchor_vec))
  ok <- !is.na(loader_num) & !is.na(anchor_num)
  n <- sum(ok)
  if (n < 5) {
    return(tibble(n = n, pearson = NA_real_, spearman = NA_real_))
  }
  # If either vector is constant, correlation is undefined — return NA.
  if (length(unique(loader_num[ok])) < 2 || length(unique(anchor_num[ok])) < 2) {
    return(tibble(n = n, pearson = NA_real_, spearman = NA_real_))
  }
  pearson <- suppressWarnings(
    cor(loader_num[ok], anchor_num[ok], method = "pearson")
  )
  spearman <- suppressWarnings(
    cor(loader_num[ok], anchor_num[ok], method = "spearman")
  )
  tibble(n = n, pearson = pearson, spearman = spearman)
}


# ---------------------------------------------------------------------------
# Internal: per-loader, per-wave correlation sweep.
# Returns a tibble with rows for each (country) plus one pooled row per wave.
# ---------------------------------------------------------------------------
.sweep_loader <- function(harmonized, anchor_var, loader_id, anchor_block,
                          loader, construct, survey, all_waves,
                          loader_min_corr) {
  wave_filter <- .normalize_waves_field(loader$waves)
  effective_waves <- if (is.null(wave_filter)) all_waves else
                     intersect(all_waves, wave_filter)

  if (length(effective_waves) == 0) {
    return(tibble())
  }

  has_country <- "country" %in% names(harmonized)

  rows <- list()
  for (wave_key in effective_waves) {
    wave_data <- harmonized[harmonized$.wave_key == wave_key, , drop = FALSE]
    if (nrow(wave_data) == 0) next
    if (!loader_id %in% names(wave_data)) next
    if (!anchor_var %in% names(wave_data)) next

    anchor_dir_for_wave <- .anchor_direction_for_wave(anchor_block, wave_key)
    expected_sign <- .compose_expected_sign(
      loader$expected_sign, anchor_dir_for_wave
    )

    # Per-country rows.
    country_levels <- if (has_country) {
      sort(unique(wave_data$country[!is.na(wave_data$country)]))
    } else {
      integer(0)
    }

    for (cc in country_levels) {
      sub <- wave_data[!is.na(wave_data$country) & wave_data$country == cc, ,
                       drop = FALSE]
      cr <- .compute_corr_row(sub[[loader_id]], sub[[anchor_var]])
      observed <- .classify_observed_sign(cr$pearson, loader_min_corr)
      st <- .compute_status(expected_sign, observed, abs(cr$pearson))
      rows[[length(rows) + 1]] <- tibble(
        construct = construct,
        survey = survey,
        variable = loader_id,
        wave = wave_key,
        country = as.character(cc),
        n = cr$n,
        pearson = cr$pearson,
        spearman = cr$spearman,
        expected_sign = expected_sign,
        observed_sign = observed,
        status = st$status,
        message = st$message
      )
    }

    # Pooled-by-country row (single sample across all countries in this wave).
    pooled <- .compute_corr_row(wave_data[[loader_id]], wave_data[[anchor_var]])
    observed_pooled <- .classify_observed_sign(pooled$pearson, loader_min_corr)
    st_pooled <- .compute_status(expected_sign, observed_pooled, abs(pooled$pearson))
    rows[[length(rows) + 1]] <- tibble(
      construct = construct,
      survey = survey,
      variable = loader_id,
      wave = wave_key,
      country = "<pooled>",
      n = pooled$n,
      pearson = pooled$pearson,
      spearman = pooled$spearman,
      expected_sign = expected_sign,
      observed_sign = observed_pooled,
      status = st_pooled$status,
      message = st_pooled$message
    )
  }
  if (length(rows) == 0) return(tibble())
  bind_rows(rows)
}


# ---------------------------------------------------------------------------
# Public: pure compute step.
#
# Args:
#   anchor_spec: parsed anchor list (output of read_anchor_file).
#   harmonized: data frame with at minimum `wave` (and ideally `country`)
#               plus the anchor and loader columns.
#   survey: survey name (string). Used to filter loaders whose `surveys:`
#           field excludes this survey.
#   default_min_correlation: floor used when a loader does not declare its
#                            own min_correlation. Default 0.05 (matches
#                            anchor_v1.schema.json default).
#
# Returns: tibble described in the ticket.
# ---------------------------------------------------------------------------
compute_anchor_correlations <- function(anchor_spec, harmonized, survey,
                                         default_min_correlation = 0.05) {
  anchor_block <- anchor_spec$anchor
  anchor_var <- anchor_block$variable
  construct <- anchor_spec$construct

  # Add a normalized wave-key column (canonical "w1", "y2003", "r5", ...).
  if (!".wave_key" %in% names(harmonized)) {
    harmonized$.wave_key <- normalize_wave_key(harmonized$wave, survey = survey)
  }

  # Anchor variable must be present.
  if (!anchor_var %in% names(harmonized)) {
    stop(sprintf(
      "anchor variable '%s' not present in harmonized output for survey '%s'",
      anchor_var, survey
    ), call. = FALSE)
  }

  all_waves <- sort(unique(harmonized$.wave_key))

  # ----- Anchor self-correlation (sanity row per wave + per-country) ------
  anchor_self_loader <- list(
    id = anchor_var,
    expected_sign = "positive",
    justification = "anchor on itself",
    surveys = NULL,
    waves = NULL
  )
  anchor_rows <- .sweep_loader(
    harmonized = harmonized,
    anchor_var = anchor_var,
    loader_id = anchor_var,
    anchor_block = anchor_block,
    loader = anchor_self_loader,
    construct = construct,
    survey = survey,
    all_waves = all_waves,
    loader_min_corr = default_min_correlation
  )

  # ----- Per-loader sweeps -------------------------------------------------
  loader_rows_list <- list()
  for (loader in anchor_spec$loaders) {
    surveys_filter <- .normalize_surveys_field(loader$surveys)
    if (!is.null(surveys_filter) && !(survey %in% surveys_filter)) {
      # Loader explicitly excluded from this survey: emit a single skip row.
      loader_rows_list[[length(loader_rows_list) + 1]] <- tibble(
        construct = construct,
        survey = survey,
        variable = loader$id,
        wave = NA_character_,
        country = NA_character_,
        n = 0L,
        pearson = NA_real_,
        spearman = NA_real_,
        expected_sign = loader$expected_sign,
        observed_sign = "na",
        status = "skip",
        message = sprintf(
          "loader excluded — anchor restricts to {%s}",
          paste(surveys_filter, collapse = ", ")
        )
      )
      next
    }

    if (!loader$id %in% names(harmonized)) {
      loader_rows_list[[length(loader_rows_list) + 1]] <- tibble(
        construct = construct,
        survey = survey,
        variable = loader$id,
        wave = NA_character_,
        country = NA_character_,
        n = 0L,
        pearson = NA_real_,
        spearman = NA_real_,
        expected_sign = loader$expected_sign,
        observed_sign = "na",
        status = "unreconciled",
        message = "loader id not in harmonized output"
      )
      next
    }

    loader_min_corr <- loader$min_correlation %||% default_min_correlation
    rows <- .sweep_loader(
      harmonized = harmonized,
      anchor_var = anchor_var,
      loader_id = loader$id,
      anchor_block = anchor_block,
      loader = loader,
      construct = construct,
      survey = survey,
      all_waves = all_waves,
      loader_min_corr = loader_min_corr
    )
    if (nrow(rows) > 0) {
      loader_rows_list[[length(loader_rows_list) + 1]] <- rows
    }
  }

  bind_rows(anchor_rows, bind_rows(loader_rows_list))
}


# ---------------------------------------------------------------------------
# Public: orchestrator — load + compute + write CSV + summarize.
# ---------------------------------------------------------------------------
run_anchor_diagnostic <- function(anchor_file, survey, harmonized = NULL,
                                   harmonized_path = NULL,
                                   output_dir = NULL) {
  if (is.null(output_dir)) {
    output_dir <- file.path("audit", "reports", survey)
  }
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  anchor_spec <- read_anchor_file(anchor_file)

  if (is.null(harmonized)) {
    harmonized <- load_harmonized_for_survey(survey, harmonized_path)
  }

  results <- compute_anchor_correlations(anchor_spec, harmonized, survey)

  csv_path <- file.path(output_dir, "04-anchors.csv")
  write.csv(results, csv_path, row.names = FALSE)

  # ----- Stdout summary ----------------------------------------------------
  status_counts <- if (nrow(results) > 0) {
    as.list(table(factor(results$status,
                         levels = c("ok", "weak", "sign_disagreement",
                                    "unreconciled", "skip"))))
  } else {
    list(ok = 0, weak = 0, sign_disagreement = 0, unreconciled = 0, skip = 0)
  }
  cat(sprintf("\n[anchor diagnostic] construct=%s survey=%s\n",
              anchor_spec$construct, survey))
  cat(sprintf("  rows: %d (ok=%d, weak=%d, sign_disagreement=%d, unreconciled=%d, skip=%d)\n",
              nrow(results),
              status_counts$ok %||% 0,
              status_counts$weak %||% 0,
              status_counts$sign_disagreement %||% 0,
              status_counts$unreconciled %||% 0,
              status_counts$skip %||% 0))
  cat(sprintf("  CSV: %s\n", csv_path))

  disagreements <- results[results$status == "sign_disagreement", , drop = FALSE]
  if (nrow(disagreements) > 0) {
    cat(sprintf("\n  *** %d SIGN DISAGREEMENT row(s) — possible reverse-coding bug(s):\n",
                nrow(disagreements)))
    print(as.data.frame(disagreements[, c("variable", "wave", "country",
                                          "n", "pearson",
                                          "expected_sign", "observed_sign")]),
          row.names = FALSE)
    cat("\n  → Each row above is a Layer 4 audit finding. Compare against the\n")
    cat("    YAML's `fn:` field for that variable. If `fn: safe_reverse_*pt`,\n")
    cat("    the reversal direction may be wrong. If `method: identity`, the\n")
    cat("    YAML may have forgotten a needed reverse.\n\n")
  }

  invisible(results)
}


# ---------------------------------------------------------------------------
# CLI entry point.
# ---------------------------------------------------------------------------
.parse_cli_args <- function(argv) {
  out <- list(survey = NULL, anchor = NULL, harmonized = NULL, output_dir = NULL)
  i <- 1
  while (i <= length(argv)) {
    a <- argv[i]
    if (a == "--survey")      { out$survey     <- argv[i + 1]; i <- i + 2; next }
    if (a == "--anchor")      { out$anchor     <- argv[i + 1]; i <- i + 2; next }
    if (a == "--harmonized")  { out$harmonized <- argv[i + 1]; i <- i + 2; next }
    if (a == "--output-dir")  { out$output_dir <- argv[i + 1]; i <- i + 2; next }
    if (a %in% c("-h", "--help")) {
      cat("Usage: Rscript src/r/audit/04_anchor_diagnostic.R\n",
          "         --survey <name> --anchor <path>\n",
          "         [--harmonized <path>] [--output-dir <path>]\n", sep = "")
      quit(status = 0)
    }
    stop(sprintf("unknown argument: %s", a), call. = FALSE)
  }
  if (is.null(out$survey) || is.null(out$anchor)) {
    stop("usage: --survey <name> --anchor <anchor_file.yml>", call. = FALSE)
  }
  out
}

# Only run the CLI when invoked as a script (not when sourced for testing).
if (sys.nframe() == 0L) {
  argv <- commandArgs(trailingOnly = TRUE)
  if (length(argv) > 0) {
    args <- .parse_cli_args(argv)
    run_anchor_diagnostic(
      anchor_file = args$anchor,
      survey = args$survey,
      harmonized = NULL,
      harmonized_path = args$harmonized,
      output_dir = args$output_dir
    )
  }
}
