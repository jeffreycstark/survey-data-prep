#!/usr/bin/env Rscript
# src/r/audit/02_under_coverage_triage.R
#
# Triages the `under`-coverage cells from 02_source_coverage_reconcile.R into
# an add-list: for each (concept x wave) where a raw code carries data in a wave
# the concept does not map, decide whether adding the mapping is SAFE to
# automate or needs human REVIEW.
#
# A cell is SAFE_add only when all three hold:
#   1. text_match  — the codebook question_text for that raw code in the
#                    candidate wave equals its question_text in the waves the
#                    concept already maps (guards against a code reused for a
#                    different question that year).
#   2. default-only rule — the concept's harmonize block has no wave-specific
#                    rule; adding a wave just inherits the default transform.
#   3. range_ok    — the candidate wave's non-missing response codes fall
#                    within the concept's declared qc.valid_range (so the
#                    transform won't emit out-of-range values). If the concept
#                    declares no valid_range, this check is vacuous (pass).
#
# Otherwise:
#   SKIP_text_mismatch        — question differs; do NOT add.
#   REVIEW_wave_specific_rule — concept has per-wave rules; a human must decide
#                               which rule the new wave needs.
#   REVIEW_range              — candidate codes fall outside valid_range, or no
#                               non-missing codes were extracted for that wave.
#
# Read-only. Writes audit/reports/<survey>/02-under-triage.csv. The SAFE_add
# rows are what apply_source_under_adds.R consumes.
#
# CLI:
#   Rscript src/r/audit/02_under_coverage_triage.R --survey kinu
#
# Survey-generic given the reconciler CSV + an extracted codebook parquet.

suppressPackageStartupMessages({
  library(here); library(arrow); library(yaml); library(dplyr); library(stringr)
})
here::i_am("src/r/audit/02_under_coverage_triage.R")
source(here::here("src/r/utils/spec_discovery.R"))

`%||%` <- function(a, b) if (is.null(a)) b else a
.norm  <- function(x) str_squish(tolower(as.character(x)))

triage_under_coverage <- function(survey) {
  recon_csv <- here::here("audit", "reports", survey, "02-source-coverage.csv")
  if (!file.exists(recon_csv)) {
    stop(sprintf("No reconciler CSV at %s — run 02_source_coverage_reconcile.R first", recon_csv),
         call. = FALSE)
  }
  under <- subset(utils::read.csv(recon_csv, stringsAsFactors = FALSE), direction == "under")

  cb <- as.data.frame(arrow::read_parquet(
    list.files(here::here("data", survey, "codebook"), pattern = "[.]parquet$", full.names = TRUE)[1]
  ))
  # Cumulative surveys store one parquet; per-wave surveys store many. Union them.
  files <- list.files(here::here("data", survey, "codebook"), pattern = "[.]parquet$", full.names = TRUE)
  cb <- bind_rows(lapply(files, function(f) as.data.frame(arrow::read_parquet(f))))

  qtext <- cb %>% distinct(raw_var, wave, question_text)
  coderange <- cb %>%
    mutate(mflag = ifelse(is.na(missing_code_flag), FALSE, as.logical(missing_code_flag))) %>%
    filter(!mflag) %>%
    group_by(raw_var, wave) %>%
    summarise(cmin = suppressWarnings(min(as.numeric(response_code), na.rm = TRUE)),
              cmax = suppressWarnings(max(as.numeric(response_code), na.rm = TRUE)),
              .groups = "drop") %>%
    filter(is.finite(cmin), is.finite(cmax))

  # Per-concept: mapped waves, rule shape, valid_range.
  vinfo <- list()
  for (sp in list_survey_specs(survey)) {
    y <- tryCatch(read_yaml(sp), error = function(e) NULL); if (is.null(y)) next
    for (v in y$variables) {
      if (is.null(v$source)) next
      mapped <- names(Filter(function(z) !is.null(z) && nzchar(as.character(z)), v$source))
      wave_specific <- setdiff(names(v$harmonize %||% list()), "default")
      vr <- v$qc$valid_range
      vinfo[[v$id]] <- list(
        mapped = mapped, rule_default_only = length(wave_specific) == 0,
        wave_specific = paste(wave_specific, collapse = ","),
        vrmin = if (!is.null(vr)) vr[1] else NA_real_,
        vrmax = if (!is.null(vr)) vr[2] else NA_real_)
    }
  }

  rows <- lapply(seq_len(nrow(under)), function(i) {
    vid <- under$var_id[i]; wv <- under$wave[i]; rv <- under$raw_var[i]
    vi <- vinfo[[vid]]
    cand_text <- .norm(qtext$question_text[qtext$raw_var == rv & qtext$wave == wv][1])
    ref_text  <- .norm(qtext$question_text[qtext$raw_var == rv & qtext$wave %in% vi$mapped])
    text_match <- length(cand_text) > 0 && cand_text %in% ref_text
    cr <- coderange[coderange$raw_var == rv & coderange$wave == wv, ]
    range_ok <- if (is.na(vi$vrmin)) NA else
      (nrow(cr) > 0 && cr$cmin[1] >= vi$vrmin && cr$cmax[1] <= vi$vrmax)
    verdict <- if (!isTRUE(text_match)) "SKIP_text_mismatch"
      else if (!vi$rule_default_only) "REVIEW_wave_specific_rule"
      else if (isTRUE(range_ok) || is.na(range_ok)) "SAFE_add"
      else "REVIEW_range"
    data.frame(
      survey = survey, var_id = vid, wave = wv, raw_var = rv,
      text_match = isTRUE(text_match),
      rule = ifelse(vi$rule_default_only, "default", vi$wave_specific),
      cand_range = if (nrow(cr) > 0) sprintf("%g-%g", cr$cmin[1], cr$cmax[1]) else "none",
      valid_range = if (is.na(vi$vrmin)) "none" else sprintf("%g-%g", vi$vrmin, vi$vrmax),
      verdict = verdict, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

.main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  i <- match("--survey", args)
  if (is.na(i) || i == length(args)) { cat("ERROR: pass --survey <name>\n"); quit(status = 2) }
  survey <- args[i + 1L]
  res <- triage_under_coverage(survey)
  out <- here::here("audit", "reports", survey, "02-under-triage.csv")
  utils::write.csv(res, out, row.names = FALSE)
  cat(sprintf("\n=== under-coverage triage: %s (%d cells) ===\n", survey, nrow(res)))
  print(table(res$verdict))
  cat(sprintf("\nSAFE_add: %d | CSV: %s\n", sum(res$verdict == "SAFE_add"), out))
  nonsafe <- subset(res, verdict != "SAFE_add")
  if (nrow(nonsafe) > 0) {
    cat("\nNeeds review:\n")
    print(nonsafe[, c("var_id", "wave", "raw_var", "verdict")], row.names = FALSE)
  }
  quit(status = 0)
}

if (identical(environment(), globalenv()) && !interactive()) {
  .main()
}
