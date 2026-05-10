#!/usr/bin/env Rscript
# src/r/audit/extractors/ipus_codebook.R
#
# Phase F (audit-framework) ticket — IPUS codebook extractor.
#
# Reads each per-year IPUS codebook (xlsx / xls / pdf) and emits a parquet
# conforming to the F1 canonical schema (`data/_codebook_schema/codebook_v1.md`),
# with one row per (raw_var × response_code × wave). One parquet file per year:
# `data/ipus/codebook/w<YEAR>.parquet`.
#
# IPUS publishes its codebooks as Korean-language Excel workbooks (2007,
# 2010-2024) or PDFs (2008, 2009). The Excel formats vary across years but
# share a common pattern: one row per variable, with a single cell holding
# the response codes-and-labels jammed together as "1. label1  2. label2".
#
# Year-by-year format dialect detected at runtime:
#
#   2007 (.xls, sheet "code book", 8 cols):
#     col 2 = var name   col 6 = description    col 7 = response cell
#     col 8 = missing-codes cell (e.g. "9. 모름/무응답")
#
#   2008-2009 (.pdf, Gallup International codebook):
#     `varname (position) label` then `Value Label` rows.
#     Parsed with pdftools by regex.
#
#   2010 (.xls, multiple sheets; we use "Sheet3"):
#     Long-format ish with variable-name + description filled only on first
#     row of each variable's block; one row per (var × code) thereafter.
#     Var name col 1 (sparse), desc col 2 (sparse), code+label col 3.
#
#   2011 (.xls, sheet "코딩북", 4 cols):
#     col 1 = var name   col 2 = description   col 3 = response cell   col 4 = missing
#
#   2012 (.xlsx, sheet "코딩북", 7 cols):
#     same as 2011 but with extra trailing columns (mostly blank).
#
#   2013 (.xlsx, 5 cols):
#     col 1 = var name   col 2 = description   col 3 = response cell   col 4 = missing
#
#   2014-2024 (.xlsx, 6 cols):
#     col 1 = question number   col 2 = var name   col 3 = description
#     col 4 = response cell     col 5 = missing    col 6 = notes
#
# In all cases the response cell encodes codes-and-labels as a single string
# like "1. 매우 필요하다  2. 약간 필요하다 ...". This script splits that
# string into (response_code, response_label) pairs.
#
# CLI:
#   Rscript src/r/audit/extractors/ipus_codebook.R
#   Rscript src/r/audit/extractors/ipus_codebook.R --year 2018
#   Rscript src/r/audit/extractors/ipus_codebook.R --years 2007:2024

suppressPackageStartupMessages({
  library(here)
  library(readxl)
  library(dplyr)
  library(tibble)
  library(stringr)
  library(arrow)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# ─────────────────────────────────────────────────────────────────────────
# CLI parsing
# ─────────────────────────────────────────────────────────────────────────

parse_cli <- function(args) {
  out <- list(years = NULL)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--year") {
      if (i + 1L > length(args)) stop("--year requires a value", call. = FALSE)
      out$years <- as.integer(args[[i + 1L]])
      i <- i + 2L
    } else if (a == "--years") {
      if (i + 1L > length(args)) stop("--years requires a value", call. = FALSE)
      v <- args[[i + 1L]]
      # support "2007:2024" or "2007,2008,2010"
      if (grepl(":", v, fixed = TRUE)) {
        parts <- as.integer(strsplit(v, ":", fixed = TRUE)[[1]])
        out$years <- seq.int(parts[1], parts[2])
      } else {
        out$years <- as.integer(strsplit(v, ",", fixed = TRUE)[[1]])
      }
      i <- i + 2L
    } else {
      stop("Unknown CLI argument: ", a, call. = FALSE)
    }
  }
  out
}

# ─────────────────────────────────────────────────────────────────────────
# Missing-code heuristics
# ─────────────────────────────────────────────────────────────────────────

# Korean-language patterns for DK / refusal / no-answer / inapplicable.
MISSING_LABEL_RE <- regex(
  paste(
    "모름",          # 모름  (DK)
    "무응답",    # 무응답 (no answer)
    "없다",          # 없다 (none / no answer; early-wave sentinel)
    "거절",          # 거절 (refusal)
    "보공",          # 보공 (n/a, rare)
    # English fallbacks just in case
    "don'?t know",
    "refus",
    "no answer",
    "missing",
    "n\\s*/\\s*a\\b",
    sep = "|"
  ),
  ignore_case = TRUE
)

is_missing_code <- function(code_str, label) {
  num <- suppressWarnings(as.numeric(code_str))
  if (!is.na(num)) {
    # Standard IPUS missing sentinels per unification.yml: 5.5 (KOSSDA marker
    # for ④+⑤), 8 (없다 / "no answer" — early waves), 9, 99.
    if (isTRUE(num == 5.5)) return(TRUE)
    if (isTRUE(num == 8))   return(TRUE)
    if (isTRUE(num == 9))   return(TRUE)
    if (isTRUE(num == 99))  return(TRUE)
    if (num < 0)            return(TRUE)
  }
  if (!is.null(label) && !is.na(label) && nzchar(label)) {
    if (str_detect(label, MISSING_LABEL_RE)) return(TRUE)
  }
  FALSE
}

# ─────────────────────────────────────────────────────────────────────────
# Response-cell parser.
#
# Input:  a single string like "1. 매우 필요하다  2. 약간 필요하다  3. 반반"
#         or with newlines like "1. 5년 이내\n 2. 10년 이내\n ..."
#         May include parens or hangul circled digits inside labels.
#
# Output: tibble(response_code, response_label) — both character.
#
# Algorithm: greedy-tokenize on patterns that look like "<digit(.|))> <text>"
# at start-of-string or after whitespace. We split by looking for the next
# leading-digit anchor, then trim.
# ─────────────────────────────────────────────────────────────────────────

parse_response_cell <- function(cell) {
  if (is.null(cell) || is.na(cell) || !nzchar(str_trim(cell))) {
    return(tibble(response_code = character(), response_label = character()))
  }
  s <- str_replace_all(cell, "[\\r\\n\\t]+", " ")
  s <- str_trim(s)

  # Anchor pattern: a number (allowing decimals like 5.5) followed by either
  # ". " or ") " or "  " (multiple-space separator after a number is rare
  # but seen in early-wave codebooks). We use the strictest separator (./))
  # to avoid splitting numbers embedded inside labels (e.g. "30년 이내").
  #
  # We use str_locate_all to find each anchor's start position, then slice.
  # Anchor: ^|whitespace, then digits (optional .digits), then "." or ")".
  #
  # IMPORTANT: Some labels are themselves "5년 이내" — the "5" is followed
  # by a Korean character, not "." or ")". So requiring "." or ")" after the
  # digits keeps us from splitting on those.
  pat <- "(?:^|\\s)([0-9]+(?:\\.[0-9]+)?)\\s*[.)]\\s*"

  matches <- str_locate_all(s, pat)[[1]]
  if (nrow(matches) == 0L) {
    return(tibble(response_code = character(), response_label = character()))
  }

  # Each token spans from match start to the next match's start (or end).
  starts <- matches[, "start"]
  ends_of_anchor <- matches[, "end"]
  # next-token start
  next_start <- c(starts[-1], nchar(s) + 1L)

  out_code <- character(nrow(matches))
  out_label <- character(nrow(matches))
  for (i in seq_len(nrow(matches))) {
    # Extract just the digit portion via the regex group.
    code_match <- str_match(substr(s, starts[i], ends_of_anchor[i]),
                            "([0-9]+(?:\\.[0-9]+)?)")
    out_code[i] <- code_match[1, 2]
    label_chunk <- substr(s, ends_of_anchor[i] + 1L, next_start[i] - 1L)
    out_label[i] <- str_trim(label_chunk)
  }

  # Drop empty labels (occurs if the cell ended with "9. " and nothing else).
  keep <- nzchar(out_label) | nzchar(out_code)
  tibble(
    response_code  = out_code[keep],
    response_label = out_label[keep]
  )
}

# ─────────────────────────────────────────────────────────────────────────
# Per-year row-constructor helper.
#
# Given var_name, question_text, response_cell, missing_cell, and source
# metadata, produce a tibble of canonical-schema rows.
# ─────────────────────────────────────────────────────────────────────────

build_var_rows <- function(var, qtext, response_cell, missing_cell,
                           source_doc, source_page, wave) {
  # Combine response + missing into a single parse, but respect that the
  # missing cell is its own anchor — we add it to the response cell with a
  # leading space.
  combined <- response_cell %||% NA_character_
  if (!is.null(missing_cell) && !is.na(missing_cell) && nzchar(str_trim(missing_cell))) {
    if (is.na(combined) || !nzchar(combined)) {
      combined <- missing_cell
    } else {
      combined <- paste(combined, missing_cell, sep = "  ")
    }
  }

  parsed <- parse_response_cell(combined)
  if (nrow(parsed) == 0L) {
    return(tibble(
      survey = character(), wave = character(), raw_var = character(),
      question_text = character(), response_code = character(),
      response_label = character(), missing_code_flag = logical(),
      source_doc = character(), source_page = character(), language = character(),
      notes = character()
    ))
  }

  parsed |>
    mutate(
      survey            = "ipus",
      wave              = wave,
      raw_var           = var,
      question_text     = qtext %||% NA_character_,
      missing_code_flag = mapply(is_missing_code, response_code, response_label),
      source_doc        = source_doc,
      source_page       = source_page,
      language          = "ko",
      notes             = NA_character_
    ) |>
    select(survey, wave, raw_var, question_text, response_code, response_label,
           missing_code_flag, source_doc, source_page, language, notes)
}

# ─────────────────────────────────────────────────────────────────────────
# Detect format of a single sheet by looking for "변수명" header row.
#
# Returns a list with:
#   header_row  : index of the row containing the header
#   var_col     : column index where variable name lives
#   desc_col    : column index for description
#   content_col : column index for response cell
#   missing_col : column index for missing-code cell (NA if not present)
#
# Falls back to year-based defaults if header sniffing fails.
# ─────────────────────────────────────────────────────────────────────────

sniff_columns <- function(d, year) {
  # Look in first 5 rows for the header row.
  nr <- min(nrow(d), 8L)
  if (nr == 0L) return(NULL)

  header_row <- NA_integer_
  for (i in seq_len(nr)) {
    rowvals <- as.character(unlist(d[i, ]))
    if (any(grepl("변수명|변수설명|문항내용|보기",
                  rowvals))) {
      header_row <- i
      break
    }
  }

  rowvals <- if (!is.na(header_row)) as.character(unlist(d[header_row, ])) else character(0)

  find_col <- function(pattern) {
    idx <- which(grepl(pattern, rowvals))
    if (length(idx) == 0L) return(NA_integer_)
    idx[1]
  }

  # 변수명 sometimes appears in two places (the kinu-style "변수명(라벨)").
  # We prefer the one paired with the description col.
  var_col <- find_col("변수명")
  desc_col <- find_col("변수설명")
  if (is.na(desc_col)) desc_col <- find_col("설명")
  content_col <- find_col("문항내용|보기")
  missing_col <- find_col("결측값")

  list(
    header_row  = header_row,
    var_col     = var_col,
    desc_col    = desc_col,
    content_col = content_col,
    missing_col = missing_col
  )
}

# ─────────────────────────────────────────────────────────────────────────
# Extractors per year-format
# ─────────────────────────────────────────────────────────────────────────

# Generic Excel extractor for the standard "1 row per variable" format
# (2011-2024). Uses sniff_columns to decide column layout.
extract_year_xlsx_standard <- function(path, year, sheet, wave) {
  d <- suppressMessages(read_excel(path, sheet = sheet, col_names = FALSE))
  if (nrow(d) == 0L) return(tibble())

  cols <- sniff_columns(d, year)

  # Year-specific defaults if sniffing failed.
  if (is.null(cols) || is.na(cols$var_col) || is.na(cols$content_col)) {
    cols <- list(
      header_row  = 3L,
      var_col     = if (year >= 2014) 2L else 1L,
      desc_col    = if (year >= 2014) 3L else 2L,
      content_col = if (year >= 2014) 4L else 3L,
      missing_col = if (year >= 2014) 5L else 4L
    )
  }
  if (is.na(cols$header_row)) cols$header_row <- 3L

  start_row <- cols$header_row + 1L
  var_col <- cols$var_col
  desc_col <- cols$desc_col
  content_col <- cols$content_col
  missing_col <- cols$missing_col

  rows <- list()
  k <- 1L
  for (i in seq.int(start_row, nrow(d))) {
    var <- as.character(d[[var_col]][i])
    if (is.na(var) || !nzchar(str_trim(var))) next
    var <- str_trim(var)
    # Skip stray section-header rows like "통일의식조사 코드북".
    if (str_detect(var, "코드북|코딩북")) next

    qtext <- if (!is.na(desc_col)) as.character(d[[desc_col]][i]) else NA_character_
    response_cell <- as.character(d[[content_col]][i])
    missing_cell  <- if (!is.na(missing_col)) as.character(d[[missing_col]][i]) else NA_character_

    if (is.na(response_cell) || !nzchar(str_trim(response_cell))) next

    rows[[k]] <- build_var_rows(
      var = var, qtext = qtext,
      response_cell = response_cell, missing_cell = missing_cell,
      source_doc = path, source_page = sheet, wave = wave
    )
    k <- k + 1L
  }

  if (length(rows) == 0L) return(tibble())
  bind_rows(rows)
}

# 2007: 8-col format with var name in col 2, desc col 6, content col 7, missing col 8.
extract_2007 <- function(path, wave) {
  d <- suppressMessages(read_excel(path, sheet = "code book", col_names = FALSE))
  if (nrow(d) == 0L) return(tibble())

  rows <- list()
  k <- 1L
  for (i in 2:nrow(d)) {
    var <- as.character(d[[2]][i])
    if (is.na(var) || !nzchar(str_trim(var))) next
    var <- str_trim(var)
    qtext <- as.character(d[[6]][i])
    response_cell <- if (ncol(d) >= 7) as.character(d[[7]][i]) else NA_character_
    missing_cell  <- if (ncol(d) >= 8) as.character(d[[8]][i]) else NA_character_
    if (is.na(response_cell) || !nzchar(str_trim(response_cell))) next

    rows[[k]] <- build_var_rows(
      var = var, qtext = qtext,
      response_cell = response_cell, missing_cell = missing_cell,
      source_doc = path, source_page = "code book", wave = wave
    )
    k <- k + 1L
  }

  if (length(rows) == 0L) return(tibble())
  bind_rows(rows)
}

# 2010: long-format Sheet3 — variable + description filled only on first row
# of each block; one row per (var × code) thereafter.
# col 1 = var (sparse) | col 2 = desc (sparse) | col 3 = code+label string
# col 4 = optional notes
extract_2010 <- function(path, wave) {
  d <- suppressMessages(read_excel(path, sheet = "Sheet3", col_names = FALSE))
  if (nrow(d) == 0L) return(tibble())

  # Forward-fill var-name and description.
  current_var <- NA_character_
  current_desc <- NA_character_

  rows <- list()
  k <- 1L
  for (i in 2:nrow(d)) {  # row 1 is the header "변수 변수설명 보기 비고"
    v <- as.character(d[[1]][i])
    desc <- if (ncol(d) >= 2) as.character(d[[2]][i]) else NA_character_
    code_label_cell <- if (ncol(d) >= 3) as.character(d[[3]][i]) else NA_character_

    if (!is.na(v) && nzchar(str_trim(v))) {
      current_var <- str_trim(v)
    }
    if (!is.na(desc) && nzchar(str_trim(desc))) {
      current_desc <- str_trim(desc)
    }

    if (is.na(current_var) || is.na(code_label_cell) || !nzchar(str_trim(code_label_cell))) next

    # Each cell is one code+label, but the format is uneven: sometimes
    # "1    수  도  권" (digit followed by whitespace then label) — there is
    # no "." or ")" separator. We try the standard parser first; if that
    # yields zero rows, fall back to a "<digits><whitespace><rest>" split.
    parsed <- parse_response_cell(code_label_cell)
    if (nrow(parsed) == 0L) {
      m <- str_match(str_trim(code_label_cell),
                     "^([0-9]+(?:\\.[0-9]+)?)\\s+(.+)$")
      if (!is.na(m[1, 1])) {
        parsed <- tibble(
          response_code  = m[1, 2],
          response_label = str_trim(m[1, 3])
        )
      }
    }
    if (nrow(parsed) == 0L) next

    parsed <- parsed |>
      mutate(
        survey            = "ipus",
        wave              = wave,
        raw_var           = current_var,
        question_text     = current_desc,
        missing_code_flag = mapply(is_missing_code, response_code, response_label),
        source_doc        = path,
        source_page       = "Sheet3",
        language          = "ko",
        notes             = NA_character_
      ) |>
      select(survey, wave, raw_var, question_text, response_code, response_label,
             missing_code_flag, source_doc, source_page, language, notes)
    rows[[k]] <- parsed
    k <- k + 1L
  }

  if (length(rows) == 0L) return(tibble())
  bind_rows(rows)
}

# 2008/2009: PDF-based codebooks (Gallup International format).
#
# Per-variable block looks like:
#
#    b08 (9) 남북한 통일 가능 시기
#
#         Value     Label
#
#               1   5년 이내
#               2   10년 이내
#               ...
#               9   모름/ 무응답
#
# We split the full text into per-variable blocks anchored on
# "<varname> (<digits>) <label-line>", then within each block consume rows
# matching "^\s*<code>\s+<label>$" until the next block starts.
extract_pdf <- function(path, wave) {
  if (!requireNamespace("pdftools", quietly = TRUE)) {
    stop("pdftools not installed; cannot parse ", path, call. = FALSE)
  }
  txt <- pdftools::pdf_text(path)
  full <- paste(txt, collapse = "\n")

  # Strip page footers like "2008  년 통일의식조사 :: 한국갤럽 :: 1"
  full <- str_replace_all(full,
                          "(?m)^.* ?(ג|::).*한국갤럽.*$", "")
  full <- str_replace_all(full,
                          "(?m)^.*\\d{4}\\s*년 통일의식조사.*$",
                          "")

  # Find all variable-anchor lines. Constraint: variable names are short
  # alphanumeric tokens like "id", "ara", "siz", "sex", "age", "job", "a12",
  # "b06". We'll match: line starting with [a-z][a-z0-9_]{1,15}, then space,
  # "(", digits, ")", then optional label.
  lines <- str_split(full, "\\r?\\n")[[1]]

  # First pass: identify anchor-line indices.
  anchor_re <- "^([a-zA-Z][a-zA-Z0-9_]{0,15})\\s*\\((\\d+)\\)\\s*(.*)$"
  is_anchor <- str_detect(lines, anchor_re)
  anchor_idx <- which(is_anchor)

  if (length(anchor_idx) == 0L) {
    return(tibble())
  }

  rows <- list()
  k <- 1L
  for (j in seq_along(anchor_idx)) {
    a <- anchor_idx[j]
    next_a <- if (j < length(anchor_idx)) anchor_idx[j + 1L] - 1L else length(lines)
    block <- lines[a:next_a]

    m <- str_match(block[1], anchor_re)
    var <- m[1, 2]
    qtext <- str_trim(m[1, 4] %||% "")
    # Strip Korean decoration ▣ and surrounding whitespace.
    qtext <- str_replace_all(qtext, "[▣]", "")
    qtext <- str_squish(qtext)

    # Within the block, find code+label rows: "<code>   <label>".
    # Skip "Value Label" header lines.
    code_rows <- list()
    cr_k <- 1L
    for (line in block[-1]) {
      if (str_detect(line, "^\\s*Value\\s+Label\\s*$")) next
      if (!nzchar(str_trim(line))) next
      mm <- str_match(line,
                      "^\\s*([+\\-]?[0-9]+(?:\\.[0-9]+)?)\\s+(.+?)\\s*$")
      if (is.na(mm[1, 1])) next
      code_rows[[cr_k]] <- tibble(
        response_code  = mm[1, 2],
        response_label = str_squish(mm[1, 3])
      )
      cr_k <- cr_k + 1L
    }

    if (length(code_rows) == 0L) next
    parsed <- bind_rows(code_rows)

    parsed <- parsed |>
      mutate(
        survey            = "ipus",
        wave              = wave,
        raw_var           = var,
        question_text     = qtext,
        missing_code_flag = mapply(is_missing_code, response_code, response_label),
        source_doc        = path,
        source_page       = NA_character_,
        language          = "ko",
        notes             = NA_character_
      ) |>
      select(survey, wave, raw_var, question_text, response_code, response_label,
             missing_code_flag, source_doc, source_page, language, notes)
    rows[[k]] <- parsed
    k <- k + 1L
  }

  if (length(rows) == 0L) return(tibble())
  bind_rows(rows)
}

# ─────────────────────────────────────────────────────────────────────────
# Top-level dispatcher: given a year, find the codebook file and dispatch
# to the right extractor.
# ─────────────────────────────────────────────────────────────────────────

extract_year <- function(year) {
  raw_dir <- here::here("data", "ipus", "raw", as.character(year))
  if (!dir.exists(raw_dir)) {
    return(list(year = year, status = "missing", reason = "no raw dir", data = NULL))
  }

  candidates <- list.files(
    raw_dir,
    pattern = sprintf("^ipus_%d_codebook\\.(xlsx|xls|pdf)$", year),
    full.names = TRUE,
    ignore.case = TRUE
  )
  if (length(candidates) == 0L) {
    return(list(year = year, status = "missing",
                reason = "no codebook file", data = NULL))
  }
  path <- candidates[1]
  wave <- paste0("w", year)

  res <- tryCatch({
    if (grepl("\\.pdf$", path, ignore.case = TRUE)) {
      extract_pdf(path, wave)
    } else if (year == 2007) {
      extract_2007(path, wave)
    } else if (year == 2010) {
      extract_2010(path, wave)
    } else {
      # Standard year — sniff the sheet to use.
      sheets <- readxl::excel_sheets(path)
      sheet <- sheets[1]
      extract_year_xlsx_standard(path, year, sheet = sheet, wave = wave)
    }
  }, error = function(e) {
    structure(list(error = conditionMessage(e)), class = "extractor_error")
  })

  if (inherits(res, "extractor_error")) {
    return(list(year = year, status = "error", reason = res$error, data = NULL))
  }
  if (is.null(res) || nrow(res) == 0L) {
    return(list(year = year, status = "empty",
                reason = "extractor produced 0 rows", data = NULL))
  }
  list(year = year, status = "ok", reason = NULL, data = res)
}

# ─────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────

main <- function(args = commandArgs(trailingOnly = TRUE)) {
  cli <- parse_cli(args)

  if (is.null(cli$years)) {
    # Default: discover via filesystem.
    raw_root <- here::here("data", "ipus", "raw")
    files <- list.files(
      raw_root,
      pattern = "^ipus_\\d{4}_codebook\\.(xlsx|xls|pdf)$",
      recursive = TRUE,
      full.names = FALSE,
      ignore.case = TRUE
    )
    yrs <- as.integer(str_match(files, "ipus_(\\d{4})")[, 2])
    cli$years <- sort(unique(yrs[!is.na(yrs)]))
  }

  if (length(cli$years) == 0L) {
    stop("No years to process.", call. = FALSE)
  }

  out_dir <- here::here("data", "ipus", "codebook")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  log_rows <- list()
  for (yr in cli$years) {
    res <- extract_year(yr)
    if (res$status == "ok") {
      out_path <- file.path(out_dir, sprintf("w%d.parquet", yr))
      arrow::write_parquet(res$data, out_path)
      log_rows[[length(log_rows) + 1L]] <- tibble(
        year = yr, status = "ok",
        rows = nrow(res$data),
        n_vars = length(unique(res$data$raw_var)),
        path = out_path,
        reason = NA_character_
      )
    } else {
      log_rows[[length(log_rows) + 1L]] <- tibble(
        year = yr, status = res$status,
        rows = 0L, n_vars = 0L,
        path = NA_character_,
        reason = res$reason %||% NA_character_
      )
    }
  }

  log_df <- bind_rows(log_rows)

  # ─── stdout summary ────────────────────────────────────────────────
  cat("\n=== IPUS codebook extractor — per-year summary ===\n")
  for (i in seq_len(nrow(log_df))) {
    r <- log_df[i, ]
    if (r$status == "ok") {
      cat(sprintf("  %d  %-6s  rows=%5d  vars=%4d  -> %s\n",
                  r$year, r$status, r$rows, r$n_vars, basename(r$path)))
    } else {
      cat(sprintf("  %d  %-6s  reason=%s\n",
                  r$year, r$status, r$reason %||% ""))
    }
  }

  ok <- log_df |> filter(status == "ok")
  cat(sprintf("\nTotal OK years: %d / %d\n", nrow(ok), nrow(log_df)))
  cat(sprintf("Total rows written: %d\n", sum(ok$rows)))

  # Spot-check: uni03 / a14 / b08 across years.
  cat("\n=== Spot-check: unification-timing var presence ===\n")
  for (i in seq_len(nrow(ok))) {
    r <- ok[i, ]
    d <- arrow::read_parquet(r$path)
    expected <- if (r$year %in% c(2007, 2009, 2010)) "a14" else
                if (r$year == 2008) "b08" else "uni03"
    has_it <- expected %in% d$raw_var
    if (has_it) {
      sub <- d |> filter(raw_var == expected)
      n_codes <- nrow(sub)
      has_imp <- any(str_detect(sub$response_label %||% "",
                                "불가능"), na.rm = TRUE)  # 불가능
      cat(sprintf("  %d  %-7s  codes=%d  has_불가능=%s\n",
                  r$year, expected, n_codes, has_imp))
    } else {
      cat(sprintf("  %d  %-7s  MISSING\n", r$year, expected))
    }
  }

  invisible(log_df)
}

if (sys.nframe() == 0L) {
  main()
}
