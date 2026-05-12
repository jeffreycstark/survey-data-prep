#!/usr/bin/env Rscript
# src/r/audit/extractors/kinu_codebook.R
#
# KINU codebook extractor — REBUILT 2026-05-12 to read from .sav labels,
# not the xlsx codebook.
#
# The prior xlsx-based extractor missed value labels that DO exist in the
# raw .sav — most prominently `cohort` code 7 ("Z generation"), which the
# xlsx omits but the .sav declares with 290 observations across 2014-2023.
# The .sav is the authoritative source for what response codes KINU's data
# actually carries; the xlsx is a (sometimes-incomplete) documentation
# snapshot.
#
# This extractor mirrors the ABS pattern at src/r/audit/extractors/abs_codebook.R:
#   1. Read the cumulative KINU .sav (haven preserves value labels as attrs).
#   2. Determine which wave each row belongs to via the `year` column
#      (values 1-13 map to KINU wave keys w2014 ... w2023, including the
#      biannual letter waves 2019a/2019b, 2020a/2020b, 2021a/2021b).
#   3. For each variable × wave where the variable has at least one
#      non-NA observation, emit one row per declared (response_code,
#      response_label) pair.
#   4. Output: one cumulative parquet at data/kinu/codebook/kinu_codebook.parquet
#      conforming to the F1 schema (data/_codebook_schema/codebook_v1.md).
#
# Differences from the prior xlsx-based extractor:
#   - Captures every value label declared in the .sav, including codes the
#     xlsx omitted.
#   - Wave attribution comes from actual non-NA observations in the .sav
#     (not from the xlsx's ○/X per-wave indicators). A variable with
#     all-NA in a wave gets no rows for that wave.
#   - question_text comes from the .sav variable label (may be terser than
#     the xlsx's full question wording — accepted tradeoff for label
#     accuracy).
#
# Output schema (per data/_codebook_schema/codebook_v1.md):
#   survey, wave, raw_var, question_text, response_code, response_label,
#   missing_code_flag, source_doc, source_page, language, notes
#
# CLI:
#   Rscript src/r/audit/extractors/kinu_codebook.R
#   Rscript src/r/audit/extractors/kinu_codebook.R --year 13   # single year

suppressPackageStartupMessages({
  library(here)
  library(haven)
  library(dplyr)
  library(tibble)
  library(stringr)
})

# ─────────────────────────────────────────────────────────────────────────
# Source file + wave-key mapping.
# ─────────────────────────────────────────────────────────────────────────

.KINU_SAV <- here::here("data", "kinu", "raw", "kinu_2014-2023_en.sav")

# year column value labels (per .sav): 1 = 2014 Sep, ..., 13 = 2023 Apr.
# Labels 14 (2024) and 15 (2025) are declared in the .sav's label set but
# do not appear in the current data.
.KINU_YEAR_TO_WAVE <- c(
  "1"  = "w2014",
  "2"  = "w2015",
  "3"  = "w2016",
  "4"  = "w2017",
  "5"  = "w2018",
  "6"  = "w2019a",   # 2019 April fielding
  "7"  = "w2019b",   # 2019 September fielding
  "8"  = "w2020a",   # 2020 June
  "9"  = "w2020b",   # 2020 November
  "10" = "w2021a",   # 2021 April
  "11" = "w2021b",   # 2021 October
  "12" = "w2022",
  "13" = "w2023"
)

# ─────────────────────────────────────────────────────────────────────────
# Missing-code heuristics — label-first, with a small numeric fallback for
# unambiguous sentinels. Mirrors the ABS extractor's conservative approach:
# don't auto-flag low positive codes (1-9) since many are legitimate
# substantive responses for KINU thermometer / scale items.
# ─────────────────────────────────────────────────────────────────────────

MISSING_LABEL_RE <- regex(
  paste(
    "don'?t know", "do not know", "no answer", "no response",
    "refus(ed|al)?", "n/?a\\b", "not applicable", "not asked",
    "inapplicable", "missing", "decline",
    sep = "|"
  ),
  ignore_case = TRUE
)

.KINU_MISSING_SENTINELS <- c(-1, 99, 999, 9999, -9)

is_missing_code <- function(code_num, label) {
  if (!is.null(label) && !is.na(label) && nzchar(label)) {
    if (str_detect(label, MISSING_LABEL_RE)) return(TRUE)
  }
  if (!is.null(code_num) && !is.na(code_num)) {
    if (code_num %in% .KINU_MISSING_SENTINELS) return(TRUE)
  }
  FALSE
}

# ─────────────────────────────────────────────────────────────────────────
# Per-wave extractor. Filters the cumulative .sav by year, inspects every
# variable's haven label attrs, emits one row per (raw_var × declared
# response_code) for every variable that has at least one non-NA
# observation in this wave.
# ─────────────────────────────────────────────────────────────────────────

extract_wave <- function(wave_key, d_full, year_int_vec, year_int) {
  mask <- !is.na(year_int_vec) & year_int_vec == year_int
  n_rows_wave <- sum(mask)
  if (n_rows_wave == 0L) {
    message(sprintf("[kinu] %s: 0 rows for year=%d — skipping", wave_key, year_int))
    return(tibble())
  }
  message(sprintf("[kinu] %s: year=%d, %d rows", wave_key, year_int, n_rows_wave))

  rows <- list()
  k <- 1L
  cols <- names(d_full)
  for (col in cols) {
    v_full <- d_full[[col]]
    var_label    <- attr(v_full, "label", exact = TRUE)
    value_labels <- attr(v_full, "labels", exact = TRUE)

    has_qtext <- !is.null(var_label) && !is.na(var_label) && nzchar(var_label)
    has_codes <- !is.null(value_labels) && length(value_labels) > 0L
    if (!has_qtext && !has_codes) next

    # Skip if no non-NA observations in this wave
    v_wave <- v_full[mask]
    v_wave_num <- suppressWarnings(haven::zap_labels(v_wave))
    if (is.list(v_wave_num)) v_wave_num <- unlist(v_wave_num)
    if (all(is.na(v_wave_num))) next

    raw_var <- tolower(col)
    qtext   <- if (has_qtext) as.character(var_label) else NA_character_

    if (!has_codes) {
      rows[[k]] <- tibble(
        survey            = "kinu",
        wave              = wave_key,
        raw_var           = raw_var,
        question_text     = qtext,
        response_code     = NA_character_,
        response_label    = NA_character_,
        missing_code_flag = FALSE,
        source_doc        = .KINU_SAV,
        source_page       = NA_character_,
        language          = "en",
        notes             = "no value labels"
      )
      k <- k + 1L
      next
    }

    label_names <- names(value_labels)
    if (is.null(label_names)) label_names <- rep(NA_character_, length(value_labels))
    code_vec    <- as.character(unname(value_labels))
    code_num    <- suppressWarnings(as.numeric(code_vec))

    block <- tibble(
      survey            = "kinu",
      wave              = wave_key,
      raw_var           = raw_var,
      question_text     = qtext,
      response_code     = code_vec,
      response_label    = as.character(label_names),
      missing_code_flag = mapply(is_missing_code, code_num,
                                 as.character(label_names),
                                 USE.NAMES = FALSE),
      source_doc        = .KINU_SAV,
      source_page       = NA_character_,
      language          = "en",
      notes             = NA_character_
    )
    rows[[k]] <- block
    k <- k + 1L
  }

  if (length(rows) == 0L) return(tibble())
  bind_rows(rows)
}

# ─────────────────────────────────────────────────────────────────────────
# CLI parser.
# ─────────────────────────────────────────────────────────────────────────

parse_cli <- function(args) {
  out <- list(year = NULL)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--year") {
      if (i + 1L > length(args)) stop("--year requires a value", call. = FALSE)
      out$year <- as.integer(args[[i + 1L]])
      i <- i + 2L
    } else if (a %in% c("-h", "--help")) {
      cat("Usage: Rscript src/r/audit/extractors/kinu_codebook.R [--year N]\n")
      cat("Default: extracts all 13 years (1..13 -> w2014..w2023).\n")
      cat("--year N restricts to a single year (1-13).\n")
      quit(status = 0)
    } else {
      stop("Unknown CLI argument: ", a, call. = FALSE)
    }
  }
  out
}

# ─────────────────────────────────────────────────────────────────────────
# main()
# ─────────────────────────────────────────────────────────────────────────

main <- function(args = commandArgs(trailingOnly = TRUE)) {
  cli <- parse_cli(args)

  if (!file.exists(.KINU_SAV)) {
    stop(sprintf("[kinu] .sav file not found: %s", .KINU_SAV), call. = FALSE)
  }

  message(sprintf("[kinu] reading %s", basename(.KINU_SAV)))
  d <- haven::read_sav(.KINU_SAV, encoding = "latin1")
  message(sprintf("[kinu] loaded: %d cols x %d rows", ncol(d), nrow(d)))

  year_int_vec <- suppressWarnings(haven::zap_labels(d$year))
  observed_years <- sort(unique(year_int_vec[!is.na(year_int_vec)]))

  if (!is.null(cli$year)) {
    if (!cli$year %in% observed_years) {
      stop(sprintf("[kinu] --year %d not present in data (observed: %s)",
                   cli$year, paste(observed_years, collapse = ", ")),
           call. = FALSE)
    }
    target_years <- cli$year
  } else {
    target_years <- observed_years
  }

  out_path <- here::here("data", "kinu", "codebook", "kinu_codebook.parquet")
  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)

  all_rows <- list()
  log_rows <- list()
  for (yr in target_years) {
    wave_key <- .KINU_YEAR_TO_WAVE[as.character(yr)]
    if (is.null(wave_key) || is.na(wave_key)) {
      message(sprintf("[kinu] year=%d has no wave-key mapping - skipping", yr))
      log_rows[[length(log_rows) + 1L]] <- tibble(
        year = yr, wave = NA_character_, rows = 0L, n_vars = 0L
      )
      next
    }
    res <- extract_wave(wave_key, d, year_int_vec, yr)
    if (nrow(res) == 0L) {
      log_rows[[length(log_rows) + 1L]] <- tibble(
        year = yr, wave = wave_key, rows = 0L, n_vars = 0L
      )
      next
    }
    all_rows[[length(all_rows) + 1L]] <- res
    log_rows[[length(log_rows) + 1L]] <- tibble(
      year = yr, wave = wave_key,
      rows = nrow(res), n_vars = length(unique(res$raw_var))
    )
  }

  if (length(all_rows) == 0L) {
    stop("[kinu] no rows extracted across any year - aborting", call. = FALSE)
  }

  combined <- bind_rows(all_rows)

  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("[kinu] arrow not installed (renv::install('arrow'))", call. = FALSE)
  }
  arrow::write_parquet(combined, out_path)

  # ─── stdout summary ────────────────────────────────────────────────
  log_df <- bind_rows(log_rows)
  cat("\n=== KINU codebook extractor (.sav-based) — per-year summary ===\n")
  for (i in seq_len(nrow(log_df))) {
    r <- log_df[i, ]
    wave_str <- if (is.na(r$wave)) "n/a" else r$wave
    cat(sprintf("  year=%2d  %-7s  rows=%6d  vars=%4d\n",
                r$year, wave_str, r$rows, r$n_vars))
  }
  cat(sprintf("\nTotal rows written: %d\n", nrow(combined)))
  cat(sprintf("Unique variables:   %d\n", length(unique(combined$raw_var))))
  cat(sprintf("Output: %s\n", out_path))

  # ─── Cohort spot-check (the original motivation for this rebuild) ──
  cohort_codes <- combined %>%
    filter(raw_var == "cohort") %>%
    distinct(response_code, response_label) %>%
    mutate(code_num = suppressWarnings(as.numeric(response_code))) %>%
    arrange(code_num) %>%
    select(response_code, response_label)
  cat("\n=== Spot-check: cohort codes (must include 7=Z generation) ===\n")
  print(as.data.frame(cohort_codes), row.names = FALSE)

  invisible(combined)
}

if (sys.nframe() == 0L) main()
