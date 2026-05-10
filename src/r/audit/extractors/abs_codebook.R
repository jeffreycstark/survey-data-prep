#!/usr/bin/env Rscript
# src/r/audit/extractors/abs_codebook.R
#
# Phase F (audit-framework) ticket — ABS codebook extractor (Tier 2).
#
# Reads each ABS wave's SPSS .sav file and emits a parquet conforming to the
# F1 canonical schema (`data/_codebook_schema/codebook_v1.md`), with one row
# per (raw_var × response_code × wave). One parquet file per wave:
# `data/abs/codebook/w<N>.parquet`.
#
# Tier 2 path: ABS .sav files carry rich SPSS metadata that haven::read_sav()
# preserves as variable-label attributes (the question text) and value-label
# attributes (response codes mapped to human-readable labels). This is the
# cheapest extraction route — no PDF parsing, no questionnaire scraping.
#
# W1-W5 are single merged .sav files. W6 is special: ABS releases each W6
# country in a separate .sav file. For codebook v1 we use ONE canonical W6
# file (Korea). Variables and labels are shared across W6 country files in
# principle; in practice slight differences may exist that a future Tier 2.5
# ticket can address by union/diff across all 12 W6 country files. Korea is
# chosen as canonical because it is well-curated and broadly representative.
#
# CLI:
#   Rscript src/r/audit/extractors/abs_codebook.R
#   Rscript src/r/audit/extractors/abs_codebook.R --wave w3
#
# Default extracts all 6 waves. --wave runs a single wave.

suppressPackageStartupMessages({
  library(here)
  library(haven)
  library(dplyr)
  library(tibble)
  library(stringr)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

here::i_am("src/r/audit/extractors/abs_codebook.R")

# ─────────────────────────────────────────────────────────────────────────
# Source paths
# ─────────────────────────────────────────────────────────────────────────

.ABS_SAV <- list(
  w1 = "data/abs/raw/wave1/Wave1_20170906.sav",
  w2 = "data/abs/raw/wave2/Wave2_20250609.sav",
  w3 = "data/abs/raw/wave3/ABS3 merge20250609.sav",
  w4 = "data/abs/raw/wave4/W4_v15_merged20250609_release.sav",
  w5 = "data/abs/raw/wave5/20230505_W5_merge_15.sav",
  # W6: 12 country files; we use Korea as canonical for codebook v1.
  # See header comment for rationale.
  w6 = "data/abs/raw/wave6/W6_Korea_Release_20241220.sav"
)

# ─────────────────────────────────────────────────────────────────────────
# Missing-code heuristics for ABS.
#
# ABS does not use a single missing convention across all waves. Codes that
# function as missing in at least one wave include:
#   -1, -2 — system missing / not applicable
#    0     — not applicable / inapplicable in some batteries
#    7     — "do not understand the question"
#    8     — "can't choose"
#    9     — "decline to answer"
#    77, 88, 99           — older convention, same meaning
#    97, 98, 99           — newer convention (W5/W6), same meaning
#    7777, 8888, 9999     — extended convention seen in a handful of vars
#
# We flag a code as missing if either:
#   (a) the response_label matches a missing-pattern regex (preferred), or
#   (b) the numeric code is in the conservative ABS missing-code set above.
#
# Caveat: codes 0/7/8/9 are sometimes legitimate substantive responses
# (e.g. q98 has 7=DK label, but a 0-10 democracy thermometer legitimately
# uses 0 as a substantive code labeled "Complete dictatorship"). The
# label-based check catches those: a 0 labeled "Complete dictatorship" will
# NOT match the missing regex and stays substantive, while a 0 labeled
# "Not applicable" will. The numeric fallback only fires when the label is
# missing entirely (rare for ABS — almost every code is labeled).
# ─────────────────────────────────────────────────────────────────────────

MISSING_LABEL_RE <- regex(
  paste(
    "don'?t know",
    # ABS labels both "Do not understand" (W3-W6) and "Don't understand"
    # (W2) — match either via optional contraction. Non-greedy gap allows
    # "Don't understand the question" / "Don't understand question".
    "do(?:n'?t| not)? understand",
    "can'?t choose",
    "decline to answer",
    "no answer",
    "not applicable",
    "inapplicable",
    "missing",
    "not.*ask",
    "refus",
    "no response",
    "n\\s*/\\s*a\\b",
    sep = "|"
  ),
  ignore_case = TRUE
)

ABS_MISSING_CODE_SET <- c(-2, -1, 7777, 8888, 9999)

is_missing_code <- function(code_num, label) {
  # Label-based detection first (most reliable for ABS — almost every code is
  # labeled, and ABS uses standardized DK/refusal/NA wording).
  if (!is.null(label) && !is.na(label) && nzchar(label)) {
    if (str_detect(label, MISSING_LABEL_RE)) return(TRUE)
  }
  # Numeric fallback for the unambiguous ABS-wide sentinels. We deliberately
  # do NOT include 0, 7, 8, 9, 77, 88, 99, 97, 98 here even though those are
  # missing codes for many variables — for democracy thermometers and some
  # demographic items those codes are legitimate substantive responses, and
  # the label-based check catches the missing cases without false positives.
  if (!is.null(code_num) && !is.na(code_num)) {
    if (code_num %in% ABS_MISSING_CODE_SET) return(TRUE)
  }
  FALSE
}

# ─────────────────────────────────────────────────────────────────────────
# Single-wave extractor.
#
# Iterates every column in d. For each column:
#   - If both var-label and value-labels are NULL: skip (admin/derived col
#     with no metadata).
#   - If only var-label: emit one row with NA response_code/response_label
#     (variable exists but has free-form responses, e.g. age, year).
#   - If value-labels present: emit one row per (raw_var × code).
#
# Variable names are lowercased for consistency with YAML `source:` keys
# (which are lowercase by convention).
# ─────────────────────────────────────────────────────────────────────────

extract_wave <- function(wave_key, sav_path) {
  if (!file.exists(sav_path)) {
    stop(sprintf("[abs] %s: SPSS file not found at %s", wave_key, sav_path),
         call. = FALSE)
  }

  message(sprintf("[abs] %s: reading %s", wave_key, sav_path))
  d <- tryCatch(
    haven::read_sav(sav_path),
    error = function(e) {
      message(sprintf("[abs] %s: read_sav failed: %s", wave_key,
                      conditionMessage(e)))
      NULL
    }
  )
  if (is.null(d)) return(tibble())

  message(sprintf("[abs] %s: %d cols × %d rows", wave_key, ncol(d), nrow(d)))

  rows <- list()
  k <- 1L
  cols <- names(d)
  for (col in cols) {
    v <- d[[col]]
    var_label    <- attr(v, "label", exact = TRUE)
    value_labels <- attr(v, "labels", exact = TRUE)

    has_qtext  <- !is.null(var_label) && !is.na(var_label) && nzchar(var_label)
    has_codes  <- !is.null(value_labels) && length(value_labels) > 0L

    if (!has_qtext && !has_codes) next

    raw_var <- tolower(col)
    qtext   <- if (has_qtext) as.character(var_label) else NA_character_

    if (!has_codes) {
      # Variable has metadata but no code-level labels (free-form numeric:
      # age, year, idnumber, weight, ...). Emit one row carrying just the
      # question text — F4 / F5 still need to know the variable exists in
      # this wave's source.
      rows[[k]] <- tibble(
        survey            = "abs",
        wave              = wave_key,
        raw_var           = raw_var,
        question_text     = qtext,
        response_code     = NA_character_,
        response_label    = NA_character_,
        missing_code_flag = FALSE,
        source_doc        = sav_path,
        source_page       = NA_character_,
        language          = "en",
        notes             = "no value labels"
      )
      k <- k + 1L
      next
    }

    # value_labels is a named numeric (or character) vector. names() = label,
    # value = code.
    label_names <- names(value_labels)
    if (is.null(label_names)) label_names <- rep(NA_character_, length(value_labels))

    code_vec <- as.character(unname(value_labels))
    code_num <- suppressWarnings(as.numeric(code_vec))

    block <- tibble(
      survey            = "abs",
      wave              = wave_key,
      raw_var           = raw_var,
      question_text     = qtext,
      response_code     = code_vec,
      response_label    = as.character(label_names),
      missing_code_flag = mapply(is_missing_code, code_num,
                                  as.character(label_names),
                                  USE.NAMES = FALSE),
      source_doc        = sav_path,
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
# Output writer.
# ─────────────────────────────────────────────────────────────────────────

write_codebook <- function(df, out_path) {
  parent <- dirname(out_path)
  if (!dir.exists(parent)) dir.create(parent, recursive = TRUE)

  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("[abs] arrow not installed (renv::install('arrow'))", call. = FALSE)
  }
  arrow::write_parquet(df, out_path)
  out_path
}

# ─────────────────────────────────────────────────────────────────────────
# CLI parser.
# ─────────────────────────────────────────────────────────────────────────

parse_cli <- function(args) {
  out <- list(wave = NULL)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--wave") {
      if (i + 1L > length(args)) stop("--wave requires a value", call. = FALSE)
      out$wave <- args[[i + 1L]]
      i <- i + 2L
    } else if (a %in% c("-h", "--help")) {
      cat("Usage: Rscript src/r/audit/extractors/abs_codebook.R [--wave w<N>]\n")
      cat("Default: extracts all 6 waves (w1..w6).\n")
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

  wave_keys <- if (is.null(cli$wave)) names(.ABS_SAV) else cli$wave
  unknown <- setdiff(wave_keys, names(.ABS_SAV))
  if (length(unknown) > 0L) {
    stop(sprintf("[abs] unknown wave(s): %s. Known: %s",
                 paste(unknown, collapse = ", "),
                 paste(names(.ABS_SAV), collapse = ", ")), call. = FALSE)
  }

  out_dir <- here::here("data", "abs", "codebook")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  log_rows <- list()
  for (wk in wave_keys) {
    sav_path <- here::here(.ABS_SAV[[wk]])
    res <- tryCatch(
      extract_wave(wk, sav_path),
      error = function(e) {
        message(sprintf("[abs] %s: extractor errored: %s", wk,
                        conditionMessage(e)))
        tibble()
      }
    )
    if (nrow(res) == 0L) {
      log_rows[[length(log_rows) + 1L]] <- tibble(
        wave = wk, status = "empty", rows = 0L, n_vars = 0L,
        path = NA_character_
      )
      next
    }
    out_path <- file.path(out_dir, sprintf("%s.parquet", wk))
    write_codebook(res, out_path)
    log_rows[[length(log_rows) + 1L]] <- tibble(
      wave = wk, status = "ok",
      rows = nrow(res),
      n_vars = length(unique(res$raw_var)),
      path = out_path
    )
  }

  log_df <- bind_rows(log_rows)

  # ─── stdout summary ───────────────────────────────────────────────
  cat("\n=== ABS codebook extractor — per-wave summary ===\n")
  for (i in seq_len(nrow(log_df))) {
    r <- log_df[i, ]
    if (r$status == "ok") {
      cat(sprintf("  %s  %-5s  rows=%6d  vars=%4d  -> %s\n",
                  r$wave, r$status, r$rows, r$n_vars, basename(r$path)))
    } else {
      cat(sprintf("  %s  %-5s\n", r$wave, r$status))
    }
  }

  ok <- log_df |> filter(status == "ok")
  cat(sprintf("\nTotal OK waves: %d / %d\n", nrow(ok), nrow(log_df)))
  cat(sprintf("Total rows written: %d\n", sum(ok$rows)))

  # ─── Spot-check ───────────────────────────────────────────────────
  # Per acceptance criteria: q98 (W2/W3 democracy_satisfaction sources),
  # q104 (W1 government satisfaction), q34 (W4/W6 vote-choice in Cambodia
  # — but our W6 here is Korea, so q34 may differ), and se14a (W5 hh
  # income). The first three should have value labels populated.
  cat("\n=== Spot-check ===\n")
  spot <- list(
    list(wave = "w2", var = "q98"),
    list(wave = "w3", var = "q98"),
    list(wave = "w1", var = "q104"),
    list(wave = "w4", var = "q34"),
    list(wave = "w6", var = "q34"),
    list(wave = "w5", var = "se14a")
  )
  for (s in spot) {
    pq <- file.path(out_dir, sprintf("%s.parquet", s$wave))
    if (!file.exists(pq)) {
      cat(sprintf("  %s/%s: SKIP (parquet not present)\n", s$wave, s$var))
      next
    }
    d <- as.data.frame(arrow::read_parquet(pq))
    sub <- d[d$raw_var == s$var, , drop = FALSE]
    if (nrow(sub) == 0L) {
      cat(sprintf("  %s/%-7s MISSING\n", s$wave, s$var))
    } else {
      n_codes <- sum(!is.na(sub$response_code))
      cat(sprintf("  %s/%-7s rows=%d coded=%d  q='%s'\n",
                  s$wave, s$var, nrow(sub), n_codes,
                  substr(sub$question_text[1], 1, 60)))
    }
  }

  # Targeted W5 SE14A 5-category structure check (justification for the
  # commit b6b315e collapse_5pt_to_4pt_then_reverse fix).
  pq5 <- file.path(out_dir, "w5.parquet")
  if (file.exists(pq5)) {
    d5 <- as.data.frame(arrow::read_parquet(pq5))
    se14 <- d5[d5$raw_var == "se14a", , drop = FALSE]
    se14_subst <- se14[!se14$missing_code_flag &
                         !is.na(suppressWarnings(as.numeric(se14$response_code))), ,
                       drop = FALSE]
    cat(sprintf(
      "\n  W5 SE14A substantive codes: %d (expected 5: 1=save_a_lot..5=great_difficulties)\n",
      nrow(se14_subst)
    ))
    if (nrow(se14_subst) > 0L) {
      for (i in seq_len(nrow(se14_subst))) {
        cat(sprintf("    code=%s  label='%s'\n",
                    se14_subst$response_code[i],
                    substr(se14_subst$response_label[i], 1, 70)))
      }
    }
  }

  invisible(log_df)
}

if (sys.nframe() == 0L) {
  main()
}
