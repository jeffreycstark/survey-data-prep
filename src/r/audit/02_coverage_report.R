#!/usr/bin/env Rscript
# src/r/audit/02_coverage_report.R
#
# Layer 2 — Codebook-extraction coverage report (audit ticket F5).
#
# Companion to F4's diff engine (02_check_codebook.R). Where F4 reconciles
# YAML *claims* against codebook *contents* (label / range / missing-code
# checks), F5 asks a coarser, prior question:
#
#     For every (variable × wave × raw_var) tuple the YAMLs declare,
#     does the extracted codebook contain at least one row for that
#     raw_var in that wave?
#
# That ratio — `claims_reconciled / total_claims` — is the survey's
# codebook-extraction coverage. Tracking it over time is the single
# headline metric for Phase F: as more extractors land (F6+) and as
# existing extractors improve, coverage approaches 100% and the F4 diff
# engine has full ground truth to operate on.
#
# Coverage gaps surfaced here are concrete, addressable extraction TODOs:
# each unreconciled tuple names the (variable, wave, raw_var) triple
# whose raw_var the extractor either missed or named differently.
#
# CLI:
#   Rscript src/r/audit/02_coverage_report.R --survey kinu
#   Rscript src/r/audit/02_coverage_report.R --survey ipus
#   Rscript src/r/audit/02_coverage_report.R --all-surveys
#   Rscript src/r/audit/02_coverage_report.R --help
#
# Exit codes:
#   0 — coverage > 80% for the requested survey (or every supported survey
#       under --all-surveys)
#   1 — coverage ≤ 80% (CI gating signal) OR invalid invocation
#
# See audit/01-audit-framework.md §Layer 2 and audit/02-implementation-tickets.md ticket F5.

suppressPackageStartupMessages({
  library(yaml)
  library(here)
  library(jsonlite)
})

here::i_am("src/r/audit/02_coverage_report.R")

source(here::here("src/r/utils/spec_discovery.R"))


# ---------------------------------------------------------------------------
# Surveys recognized by --all-surveys. Mirrors src/r/audit/02_check_codebook.R.
# ---------------------------------------------------------------------------
.SUPPORTED_SURVEYS <- c(
  "abs", "wvs", "lbs", "afro", "arab-barometer",
  "kamos", "kgss", "kipa-corruption", "kinu", "ipus"
)

# Coverage threshold for CI gating. > .COVERAGE_THRESHOLD_PCT → exit 0.
.COVERAGE_THRESHOLD_PCT <- 80

`%||%` <- function(a, b) if (!is.null(a)) a else b


# ---------------------------------------------------------------------------
# Help text
# ---------------------------------------------------------------------------
.print_help <- function() {
  cat(
    "Usage: Rscript src/r/audit/02_coverage_report.R --survey <name>\n",
    "       Rscript src/r/audit/02_coverage_report.R --all-surveys\n",
    "\n",
    "For each (variable × wave × raw_var) tuple declared in the survey's\n",
    "harmonization YAMLs, checks whether the extracted codebook at\n",
    "data/<survey>/codebook/*.parquet contains at least one row for that\n",
    "raw_var in that wave. Writes audit/reports/<survey>/02-coverage.json\n",
    "and prints a markdown summary to stdout.\n",
    "\n",
    "  --survey NAME      Survey slug (one of: ",
        paste(.SUPPORTED_SURVEYS, collapse = ", "), ").\n",
    "  --all-surveys      Run for every supported survey.\n",
    "  --output-dir PATH  Override output directory (default: audit/reports/<survey>).\n",
    "  -h, --help         Show this message.\n",
    "\n",
    sprintf("Exit 0 = coverage > %d%%; Exit 1 = coverage <= %d%% or invalid args.\n",
            .COVERAGE_THRESHOLD_PCT, .COVERAGE_THRESHOLD_PCT),
    sep = ""
  )
}


# ---------------------------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------------------------
.parse_cli_args <- function(argv) {
  out <- list(survey = NULL, all_surveys = FALSE, output_dir = NULL)
  i <- 1L
  while (i <= length(argv)) {
    a <- argv[i]
    if (a %in% c("-h", "--help"))   { .print_help(); quit(status = 0) }
    if (a == "--survey")            { out$survey      <- argv[i + 1L]; i <- i + 2L; next }
    if (a == "--all-surveys")       { out$all_surveys <- TRUE;          i <- i + 1L; next }
    if (a == "--output-dir")        { out$output_dir  <- argv[i + 1L]; i <- i + 2L; next }
    stop(sprintf("unknown argument: %s (see --help)", a), call. = FALSE)
  }
  if (!out$all_surveys && (is.null(out$survey) || !nzchar(out$survey))) {
    stop("--survey <name> or --all-surveys is required (see --help)", call. = FALSE)
  }
  out
}


# ---------------------------------------------------------------------------
# Codebook loader. Soft-fail: if no codebook directory or no parquet files
# are found, return NULL plus a counters list so the orchestrator can
# emit a coverage report with `n_codebook_rows: 0` rather than aborting.
#
# Mirrors F4's loader logic but does not error on absence — F5's whole
# point is to report on coverage, including zero coverage.
# ---------------------------------------------------------------------------
.load_codebook_soft <- function(survey, codebook_dir = NULL) {
  if (is.null(codebook_dir)) {
    codebook_dir <- here::here("data", survey, "codebook")
  }
  if (!dir.exists(codebook_dir)) {
    return(list(codebook = NULL, n_files = 0L, n_rows = 0L))
  }
  files <- list.files(codebook_dir, pattern = "\\.parquet$",
                      full.names = TRUE)
  if (length(files) == 0L) {
    return(list(codebook = NULL, n_files = 0L, n_rows = 0L))
  }

  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("Package 'arrow' is required (renv::install('arrow'))",
         call. = FALSE)
  }

  pieces <- lapply(files, function(f) {
    df <- tryCatch(
      as.data.frame(arrow::read_parquet(f)),
      error = function(e) {
        warning(sprintf("[coverage] cannot read %s: %s", f,
                        conditionMessage(e)), call. = FALSE)
        NULL
      }
    )
    df
  })
  pieces <- pieces[!vapply(pieces, is.null, logical(1))]
  if (length(pieces) == 0L) {
    return(list(codebook = NULL, n_files = length(files), n_rows = 0L))
  }

  cb <- do.call(rbind, lapply(pieces, function(p) {
    # Subset to the columns we'll touch and coerce types up-front so rbind
    # is robust to per-file column ordering differences.
    keep <- c("wave", "raw_var")
    miss <- setdiff(keep, names(p))
    for (m in miss) p[[m]] <- NA_character_
    data.frame(
      wave    = as.character(p$wave),
      raw_var = as.character(p$raw_var),
      stringsAsFactors = FALSE
    )
  }))

  list(
    codebook = cb,
    n_files  = length(files),
    n_rows   = nrow(cb)
  )
}


# ---------------------------------------------------------------------------
# Build the (raw_var × wave) presence index. A simple set keyed by
# `<wave>||<raw_var>` is enough — we just want O(1) membership tests.
# Case-insensitive raw_var fallback mirrors F4 behavior.
# ---------------------------------------------------------------------------
.build_codebook_index <- function(codebook) {
  if (is.null(codebook) || nrow(codebook) == 0L) {
    return(list(
      exact = character(0),
      lower = character(0)
    ))
  }
  exact <- unique(paste(codebook$wave, codebook$raw_var, sep = "||"))
  lower <- unique(paste(tolower(codebook$wave),
                        tolower(codebook$raw_var), sep = "||"))
  list(exact = exact, lower = lower)
}

.codebook_contains <- function(idx, wave, raw_var) {
  key <- paste(wave, raw_var, sep = "||")
  if (key %in% idx$exact) return(TRUE)
  key_lc <- paste(tolower(wave), tolower(raw_var), sep = "||")
  key_lc %in% idx$lower
}


# ---------------------------------------------------------------------------
# Enumerate every (variable, wave, raw_var) claim across the survey's
# YAMLs. Skips wave entries whose source value is null/NA/empty (variable
# absent in that wave). Returns a data.frame with columns:
#   variable, wave, raw_var, spec_path
#
# Also records a side metric: n_unique_variables (distinct ids).
# ---------------------------------------------------------------------------
.enumerate_yaml_claims <- function(spec_paths) {
  rows <- list()
  ids <- character(0)
  for (sp in spec_paths) {
    spec <- tryCatch(yaml::read_yaml(sp), error = function(e) {
      warning(sprintf("[coverage] cannot read YAML %s: %s",
                      sp, conditionMessage(e)), call. = FALSE)
      NULL
    })
    if (is.null(spec) || is.null(spec$variables)) next
    for (vs in spec$variables) {
      id <- vs$id
      if (is.null(id) || !nzchar(id)) next
      ids <- c(ids, id)
      src <- vs$source
      if (is.null(src)) next
      wave_keys <- names(src)
      if (is.null(wave_keys)) next
      for (wk in wave_keys) {
        raw <- src[[wk]]
        if (is.null(raw)) next
        if (length(raw) == 1L && is.na(raw)) next
        raw_str <- as.character(raw)
        if (!nzchar(raw_str)) next
        rows[[length(rows) + 1L]] <- data.frame(
          variable  = id,
          wave      = wk,
          raw_var   = raw_str,
          spec_path = sp,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  claims <- if (length(rows) == 0L) {
    data.frame(
      variable  = character(0),
      wave      = character(0),
      raw_var   = character(0),
      spec_path = character(0),
      stringsAsFactors = FALSE
    )
  } else {
    do.call(rbind, rows)
  }
  list(
    claims = claims,
    n_unique_variables = length(unique(ids))
  )
}


# ---------------------------------------------------------------------------
# Per-wave aggregate. Returns a NAMED list (wave -> {reconciled,
# unreconciled, coverage_pct}) sorted by wave key for stable JSON output.
# ---------------------------------------------------------------------------
.coverage_by_wave <- function(claims) {
  if (nrow(claims) == 0L) return(list())
  out <- list()
  waves <- sort(unique(claims$wave))
  for (w in waves) {
    sub <- claims[claims$wave == w, , drop = FALSE]
    n_recon <- sum(sub$reconciled)
    n_total <- nrow(sub)
    n_unrec <- n_total - n_recon
    pct <- if (n_total == 0L) 0 else round(100 * n_recon / n_total, 1)
    out[[w]] <- list(
      reconciled    = as.integer(n_recon),
      unreconciled  = as.integer(n_unrec),
      coverage_pct  = pct
    )
  }
  out
}


# ---------------------------------------------------------------------------
# Public: compute the coverage report for one survey. Pure-data; no I/O.
# Returns a list shaped exactly like the JSON output (modulo a few
# debugging extras like `unreconciled_full` not written to disk).
# ---------------------------------------------------------------------------
compute_coverage <- function(survey, codebook_info = NULL,
                              spec_paths = NULL) {
  if (is.null(codebook_info)) {
    codebook_info <- .load_codebook_soft(survey)
  }

  spec_paths <- if (is.null(spec_paths)) {
    tryCatch(list_survey_specs(survey), error = function(e) {
      warning(sprintf("[coverage] cannot list specs for survey '%s': %s",
                      survey, conditionMessage(e)), call. = FALSE)
      character(0)
    })
  } else spec_paths

  enum <- .enumerate_yaml_claims(spec_paths)
  claims <- enum$claims

  idx <- .build_codebook_index(codebook_info$codebook)

  # Mark each claim as reconciled / unreconciled.
  if (nrow(claims) > 0L) {
    claims$reconciled <- vapply(seq_len(nrow(claims)), function(i) {
      .codebook_contains(idx, claims$wave[i], claims$raw_var[i])
    }, logical(1))
  } else {
    claims$reconciled <- logical(0)
  }

  total_claims      <- nrow(claims)
  claims_reconciled <- sum(claims$reconciled)
  claims_unrec      <- total_claims - claims_reconciled

  coverage_pct <- if (total_claims == 0L) 0
                  else round(100 * claims_reconciled / total_claims, 1)

  by_wave <- .coverage_by_wave(claims)

  unrec <- claims[!claims$reconciled, , drop = FALSE]
  # Stable sort: by wave then variable then raw_var.
  if (nrow(unrec) > 0L) {
    unrec <- unrec[order(unrec$wave, unrec$variable, unrec$raw_var), ,
                   drop = FALSE]
  }

  unrec_top <- if (nrow(unrec) == 0L) list() else {
    top_n <- min(20L, nrow(unrec))
    lapply(seq_len(top_n), function(i) {
      list(
        variable = unrec$variable[i],
        wave     = unrec$wave[i],
        raw_var  = unrec$raw_var[i],
        reason   = "raw_var not in codebook"
      )
    })
  }

  list(
    survey              = survey,
    computed_at         = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    n_codebook_files    = as.integer(codebook_info$n_files),
    n_codebook_rows     = as.integer(codebook_info$n_rows),
    n_yaml_specs        = as.integer(length(spec_paths)),
    n_unique_variables  = as.integer(enum$n_unique_variables),
    total_claims        = as.integer(total_claims),
    claims_reconciled   = as.integer(claims_reconciled),
    claims_unreconciled = as.integer(claims_unrec),
    coverage_pct        = coverage_pct,
    by_wave             = by_wave,
    unreconciled_top    = unrec_top,
    # not written to JSON; useful for callers running this in-process
    .all_unreconciled   = unrec
  )
}


# ---------------------------------------------------------------------------
# Markdown summary printer.
# ---------------------------------------------------------------------------
.print_markdown_summary <- function(report) {
  cat(sprintf("\n## Codebook-extraction coverage: %s\n\n", report$survey))
  cat(sprintf("- Computed at: %s\n", report$computed_at))
  cat(sprintf("- Codebook files: %d (%d rows)\n",
              report$n_codebook_files, report$n_codebook_rows))
  cat(sprintf("- YAML specs: %d (%d unique variables)\n",
              report$n_yaml_specs, report$n_unique_variables))
  cat(sprintf("- Total claims: %d\n", report$total_claims))
  cat(sprintf("- Claims reconciled: %d\n", report$claims_reconciled))
  cat(sprintf("- Claims unreconciled: %d\n", report$claims_unreconciled))
  cat(sprintf("- **Coverage: %.1f%%**\n", report$coverage_pct))

  if (length(report$by_wave) > 0L) {
    cat("\n### Per-wave coverage\n\n")
    cat("| wave | reconciled | unreconciled | coverage_pct |\n")
    cat("|---|---|---|---|\n")
    for (w in names(report$by_wave)) {
      bw <- report$by_wave[[w]]
      cat(sprintf("| %s | %d | %d | %.1f%% |\n",
                  w, bw$reconciled, bw$unreconciled, bw$coverage_pct))
    }
  }

  if (length(report$unreconciled_top) > 0L) {
    cat(sprintf("\n### Top %d unreconciled (variable, wave, raw_var)\n\n",
                length(report$unreconciled_top)))
    cat("| # | variable | wave | raw_var | reason |\n")
    cat("|---|---|---|---|---|\n")
    for (i in seq_along(report$unreconciled_top)) {
      e <- report$unreconciled_top[[i]]
      cat(sprintf("| %d | %s | %s | %s | %s |\n",
                  i, e$variable, e$wave, e$raw_var, e$reason))
    }
  }
  cat("\n")
}


# ---------------------------------------------------------------------------
# JSON writer. Strips `.all_unreconciled` (debugging-only) before write.
# ---------------------------------------------------------------------------
.write_json <- function(report, json_path) {
  out <- report
  out$.all_unreconciled <- NULL
  # Force `by_wave: {}` and `unreconciled_top: []` shapes so consumers
  # don't have to disambiguate empty lists from missing keys.
  if (length(out$by_wave) == 0L) {
    out$by_wave <- structure(list(), names = character(0))
  }
  if (length(out$unreconciled_top) == 0L) {
    out$unreconciled_top <- list()
  }
  jsonlite::write_json(
    out, json_path,
    auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null"
  )
}


# ---------------------------------------------------------------------------
# Public: orchestrator — load + compute + write JSON + print markdown.
# Returns the report list invisibly (with attribute `coverage_pct` so the
# CLI can set the exit code).
# ---------------------------------------------------------------------------
run_coverage_report <- function(survey, output_dir = NULL,
                                 codebook_info = NULL,
                                 spec_paths = NULL) {
  if (is.null(output_dir)) {
    output_dir <- here::here("audit", "reports", survey)
  }
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  cat(sprintf("\n[coverage] survey=%s\n", survey))

  report <- compute_coverage(survey, codebook_info = codebook_info,
                             spec_paths = spec_paths)

  json_path <- file.path(output_dir, "02-coverage.json")
  .write_json(report, json_path)
  cat(sprintf("  output: %s\n", json_path))

  .print_markdown_summary(report)

  attr(report, "coverage_pct") <- report$coverage_pct
  invisible(report)
}


# ---------------------------------------------------------------------------
# Aggregate printer for --all-surveys.
# ---------------------------------------------------------------------------
.print_all_surveys_summary <- function(reports) {
  if (length(reports) == 0L) return(invisible(NULL))
  cat("\n## All-surveys coverage summary\n\n")
  cat("| survey | codebook_rows | total_claims | reconciled | coverage_pct |\n")
  cat("|---|---|---|---|---|\n")
  for (r in reports) {
    cat(sprintf("| %s | %d | %d | %d | %.1f%% |\n",
                r$survey,
                r$n_codebook_rows,
                r$total_claims,
                r$claims_reconciled,
                r$coverage_pct))
  }
  cat("\n")
}


# ---------------------------------------------------------------------------
# CLI main
# ---------------------------------------------------------------------------
.main <- function(argv) {
  args <- .parse_cli_args(argv)

  if (args$all_surveys) {
    surveys <- .SUPPORTED_SURVEYS
    cat(sprintf("[coverage] running for %d surveys: %s\n",
                length(surveys), paste(surveys, collapse = ", ")))
    reports <- list()
    for (s in surveys) {
      r <- tryCatch(
        run_coverage_report(survey = s, output_dir = args$output_dir),
        error = function(e) {
          cat(sprintf("\n[coverage] survey '%s' SKIPPED: %s\n",
                      s, conditionMessage(e)))
          NULL
        }
      )
      if (!is.null(r)) reports[[length(reports) + 1L]] <- r
    }
    .print_all_surveys_summary(reports)

    if (length(reports) == 0L) quit(status = 1L)
    any_below <- any(vapply(reports, function(r) {
      r$coverage_pct <= .COVERAGE_THRESHOLD_PCT
    }, logical(1)))
    quit(status = if (any_below) 1L else 0L)
  }

  if (!(args$survey %in% .SUPPORTED_SURVEYS)) {
    warning(sprintf("survey '%s' not in supported list: %s",
                    args$survey, paste(.SUPPORTED_SURVEYS, collapse = ", ")),
            call. = FALSE)
  }

  r <- tryCatch(
    run_coverage_report(survey = args$survey, output_dir = args$output_dir),
    error = function(e) {
      cat(sprintf("\n[coverage] ERROR: %s\n", conditionMessage(e)))
      quit(status = 1L)
    }
  )
  pct <- as.numeric(attr(r, "coverage_pct") %||% 0)
  quit(status = if (pct > .COVERAGE_THRESHOLD_PCT) 0L else 1L)
}


if (sys.nframe() == 0L) {
  argv <- commandArgs(trailingOnly = TRUE)
  if (length(argv) == 0L) {
    .print_help()
    quit(status = 1L)
  }
  .main(argv)
}
