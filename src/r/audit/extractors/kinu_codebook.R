#!/usr/bin/env Rscript
# src/r/audit/extractors/kinu_codebook.R
#
# Phase F (audit-framework) ticket — KINU codebook extractor.
#
# Reads the cumulative KINU 2014–2024 codebook xlsx and emits a parquet
# conforming to the F1 canonical schema (`data/_codebook_schema/codebook_v1.md`),
# with one row per (raw_var × response_code × wave).
#
# The KINU xlsx ships a single sheet ("codebook 2014-24") with columns:
#   col 1  : Group              (Basic | demographics | attitudes | ...)
#   col 2  : Variable           (raw var name; e.g. uni01, at0201, gender)
#   cols 3–16 : wave indicators (14, 15, 16, 17, 18, 19a, 19b, 20a, 20b,
#                                21a, 21b, 22, 23a, 24)
#                                cell value "○" = asked, "X" = not asked
#   col 17 : Item Label         (short label)
#   col 18 : Item               (full question text — battery items only)
#   col 19 : Response           (code=label pairs, newline-separated)
#   col 20 : Comments / leading question
#
# Wave-key mapping from xlsx-header to YAML-key (consumed by the F4 diff engine):
#   14 -> w2014, 15 -> w2015, ..., 19a -> w2019a, 19b -> w2019b,
#   20a -> w2020a, 20b -> w2020b, 21a -> w2021a, 21b -> w2021b,
#   22 -> w2022, 23a -> w2023 (KINU's 2023 wave), 24 -> w2024.
#
# The Response column is parsed line-by-line: each line is `<code>=<label>`.
# Codes are kept as strings (per F1 schema). missing_code_flag is TRUE when
#   - the parsed code is < 0,
#   - the parsed code is in {88, 99} or is "9" within a 1-digit-something scale,
#   - or the label matches /(don'?t know|refus|no answer|not asked|inapplicable
#                          |missing|n\/a)/i.
#
# CLI:
#   Rscript src/r/audit/extractors/kinu_codebook.R
#   Rscript src/r/audit/extractors/kinu_codebook.R --output <path.parquet>

suppressPackageStartupMessages({
  library(here)
  library(readxl)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(yaml)
})

# ─────────────────────────────────────────────────────────────────────────
# CLI parsing — bare-bones; only --output is supported.
# ─────────────────────────────────────────────────────────────────────────

parse_cli <- function(args) {
  out <- list(output = here::here("data", "kinu", "codebook", "kinu_codebook.parquet"))
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--output") {
      if (i + 1L > length(args)) stop("--output requires a path argument", call. = FALSE)
      out$output <- args[[i + 1L]]
      i <- i + 2L
    } else {
      stop("Unknown CLI argument: ", a, call. = FALSE)
    }
  }
  out
}

# ─────────────────────────────────────────────────────────────────────────
# Wave-header → YAML wave key.
# ─────────────────────────────────────────────────────────────────────────

WAVE_HEADER_TO_KEY <- c(
  "14"  = "w2014",
  "15"  = "w2015",
  "16"  = "w2016",
  "17"  = "w2017",
  "18"  = "w2018",
  "19a" = "w2019a",
  "19b" = "w2019b",
  "20a" = "w2020a",
  "20b" = "w2020b",
  "21a" = "w2021a",
  "21b" = "w2021b",
  "22"  = "w2022",
  # KINU's 2023 wave is the spring fielding ("23a"); the YAMLs key it as
  # w2023 (no letter). Map accordingly. The fall fielding "23b" does not
  # exist in this codebook (single 23a column) — verified at runtime.
  "23a" = "w2023",
  "24"  = "w2024"
)

# ─────────────────────────────────────────────────────────────────────────
# Missing-code heuristics.
# ─────────────────────────────────────────────────────────────────────────

MISSING_LABEL_RE <- regex(
  paste(
    "don'?t know",
    "refus",
    "no answer",
    "not asked",
    "not.*ask",
    "inapplicable",
    "missing",
    "n\\s*/\\s*a\\b",
    "no response",
    sep = "|"
  ),
  ignore_case = TRUE
)

is_missing_code <- function(code_str, label, response_block) {
  # Label-based detection is the primary signal. KINU flags missing values by
  # writing labels like "n/a", "no answer", "Don't know", etc.
  if (!is.null(label) && !is.na(label) && nzchar(label)) {
    if (str_detect(label, MISSING_LABEL_RE)) return(TRUE)
  }
  # Numeric-only fallback for the unambiguous KINU-wide sentinels. The
  # `9 = n/a` and `99 = n/a` conventions documented in KINU's
  # missing_conventions almost always come with a matching label; we keep
  # 88/99 as a safety net for cases where the label is missing entirely.
  # We do NOT flag negative codes generically: thermometer items use -5..+5
  # where negative codes are substantive (e.g. -5 = "strongly dislike").
  num <- suppressWarnings(as.numeric(code_str))
  if (!is.na(num)) {
    if (num %in% c(88, 99) &&
        (is.null(label) || is.na(label) || !nzchar(label))) return(TRUE)
  }
  FALSE
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# ─────────────────────────────────────────────────────────────────────────
# Response-block parser.
#
# Input  : the raw xlsx Response cell, e.g. "1=strongly disagree\r\n2=...\r\n9=n/a"
# Output : tibble(response_code (chr), response_label (chr))
# ─────────────────────────────────────────────────────────────────────────

parse_response_block <- function(block) {
  if (is.null(block) || is.na(block) || !nzchar(str_trim(block))) {
    return(tibble(response_code = character(), response_label = character()))
  }

  # KINU's Response cells use two delimiters interchangeably:
  #   \r\n  — the canonical separator (one code=label per line)
  #   ", "  — used for short bipolar scales like "1=male, 2=female" or
  #            "1=unfriendly, 5=friendly, 9=n/a" (single line, multiple codes)
  #
  # We split on both: first on newlines, then on a comma that is followed
  # by an optional space and another `<code>=`. A comma not followed by
  # `<num>=` is a label-internal comma and must be preserved.
  #
  # The "next code" lookahead pattern: optional sign, digits or token,
  # whitespace, '='. This handles negative codes (e.g. "-1=").
  CODE_LOOKAHEAD <- "(?=\\s*-?[0-9]+\\s*=)"

  lines <- str_split(block, "\\r\\n|\\n|\\r")[[1]]
  # Split each line on commas OR whitespace that precede a new "<code>=" token.
  # The lookahead enforces that the split point is immediately followed by a
  # `<num>=` pattern, so label-internal commas/spaces are preserved unless
  # they happen to be directly before another code. Acceptable false-split
  # risk: a label ending in a bare integer followed by whitespace then another
  # code-pair (very rare in KINU).
  split_re <- paste0("[,\\s]+", CODE_LOOKAHEAD)
  lines <- unlist(lapply(lines, function(ln) str_split(ln, split_re)[[1]]))
  lines <- str_trim(lines)
  lines <- lines[nzchar(lines)]

  parsed <- vector("list", length(lines))
  for (i in seq_along(lines)) {
    ln <- lines[[i]]
    # Split only on the first '=' — labels may legitimately contain '='.
    m <- str_match(ln, "^\\s*([^=]+?)\\s*=\\s*(.*)\\s*$")
    if (is.na(m[1, 1])) {
      # Sometimes a wraparound continuation line lacks '='; skip — the diff
      # engine doesn't need partial labels and we don't want to misclassify.
      next
    }
    code  <- str_trim(m[1, 2])
    label <- str_trim(m[1, 3])
    if (!nzchar(code) || !nzchar(label)) next
    # Sanity: a code should be a short token (digits, optional sign). If the
    # captured "code" contains spaces or runs longer than 4 chars and isn't
    # numeric, the line was malformed — drop it rather than emit garbage.
    if (is.na(suppressWarnings(as.numeric(code))) && nchar(code) > 6) next
    parsed[[i]] <- tibble(response_code = code, response_label = label)
  }
  parsed <- bind_rows(parsed)
  parsed
}

# ─────────────────────────────────────────────────────────────────────────
# Main extractor.
# ─────────────────────────────────────────────────────────────────────────

extract_kinu_codebook <- function(xlsx_path) {
  if (!file.exists(xlsx_path)) {
    stop("KINU codebook xlsx not found at: ", xlsx_path, call. = FALSE)
  }

  sheets <- excel_sheets(xlsx_path)
  if (length(sheets) < 1) {
    stop("KINU xlsx has no sheets: ", xlsx_path, call. = FALSE)
  }
  if (length(sheets) > 1) {
    message(sprintf(
      "[kinu] xlsx has %d sheets; using first sheet '%s'. Other sheets: %s",
      length(sheets), sheets[1], paste(sheets[-1], collapse = ", ")
    ))
  }

  raw <- read_excel(xlsx_path, sheet = sheets[1], col_names = FALSE,
                    .name_repair = "minimal")

  # Header validation. Row 1 holds the column labels.
  header <- as.character(unlist(raw[1, ]))
  if (length(header) < 20) {
    stop(sprintf(
      "[kinu] expected >= 20 columns in xlsx; got %d. Header: %s",
      length(header), paste(header, collapse = " | ")
    ), call. = FALSE)
  }
  if (!identical(tolower(str_trim(header[[1]])), "group")) {
    stop("[kinu] expected column 1 header 'Group'; got: ", header[[1]], call. = FALSE)
  }
  if (!identical(tolower(str_trim(header[[2]])), "variable")) {
    stop("[kinu] expected column 2 header 'Variable'; got: ", header[[2]], call. = FALSE)
  }

  # Identify wave columns (3–16): every header should be a known KINU wave key.
  wave_cols <- 3:16
  wave_headers <- str_trim(header[wave_cols])
  unknown_waves <- setdiff(wave_headers, names(WAVE_HEADER_TO_KEY))
  if (length(unknown_waves) > 0) {
    stop(sprintf(
      "[kinu] unrecognized wave header(s) in xlsx columns 3–16: %s. Known: %s",
      paste(unknown_waves, collapse = ", "),
      paste(names(WAVE_HEADER_TO_KEY), collapse = ", ")
    ), call. = FALSE)
  }

  # Validate Item-Label / Item / Response column positions.
  expected_at_17 <- "item label"
  if (!identical(tolower(str_trim(header[[17]])), expected_at_17)) {
    stop("[kinu] expected column 17 header 'Item Label'; got: ", header[[17]],
         call. = FALSE)
  }
  if (!identical(tolower(str_trim(header[[18]])), "item")) {
    stop("[kinu] expected column 18 header 'Item'; got: ", header[[18]],
         call. = FALSE)
  }
  if (!identical(tolower(str_trim(header[[19]])), "response")) {
    stop("[kinu] expected column 19 header 'Response'; got: ", header[[19]],
         call. = FALSE)
  }

  # Body rows.
  body <- raw[-1, , drop = FALSE]
  names(body) <- c(
    "group", "variable",
    wave_headers,
    "item_label", "item", "response", "comments"
  )

  # Drop rows missing Variable.
  body <- body |> filter(!is.na(variable), nzchar(str_trim(variable)))
  initial_n <- nrow(body)

  # Drop rows that have no item_label AND no item — pure formatting artifacts.
  body <- body |>
    filter(
      (!is.na(item_label) & nzchar(str_trim(item_label))) |
        (!is.na(item) & nzchar(str_trim(item)))
    )
  message(sprintf("[kinu] body rows after filter: %d (was %d)",
                  nrow(body), initial_n))

  # Build question_text. KINU's "Item" column is the per-item question for
  # battery questions; "Item Label" is the short-form caption. Per F1, for
  # battery rows we may concatenate <stem> :: <item>. KINU does not give us
  # an explicit stem column, so we use Item-Label as stem and Item as item
  # whenever both are present, joined with " :: ". When Item is missing, we
  # fall back to Item-Label alone.
  body <- body |>
    mutate(
      item_label = str_trim(replace_na(as.character(item_label), "")),
      item       = str_trim(replace_na(as.character(item), "")),
      question_text = case_when(
        nzchar(item_label) & nzchar(item) & item_label != item ~
          paste0(item_label, " :: ", item),
        nzchar(item) ~ item,
        TRUE ~ item_label
      )
    )

  # Pivot wave columns long.
  long <- body |>
    select(group, variable, all_of(wave_headers), question_text, response) |>
    pivot_longer(
      cols = all_of(wave_headers),
      names_to = "wave_header",
      values_to = "asked"
    ) |>
    mutate(
      asked = str_trim(replace_na(as.character(asked), ""))
    ) |>
    # Keep only rows where the variable was actually asked in this wave.
    # KINU uses ○ (Korean circle) for "asked" and X (Latin) for "not asked";
    # treat any non-empty-non-X value as asked to be conservative.
    filter(asked != "", asked != "X", asked != "x") |>
    mutate(wave = unname(WAVE_HEADER_TO_KEY[wave_header]))

  if (any(is.na(long$wave))) {
    bad <- long |> filter(is.na(wave)) |> distinct(wave_header)
    stop("[kinu] internal: unmapped wave headers leaked through: ",
         paste(bad$wave_header, collapse = ", "), call. = FALSE)
  }

  # Parse Response blocks. Variables with no Response (e.g. id, age, dist)
  # produce zero rows — they are continuous/identifier variables and have
  # no enumerable codes for the codebook to record.
  message(sprintf("[kinu] parsing response blocks for %d (variable × wave) rows",
                  nrow(long)))

  rows_out <- vector("list", nrow(long))
  for (i in seq_len(nrow(long))) {
    block <- long$response[[i]]
    parsed <- parse_response_block(block)
    if (nrow(parsed) == 0) next
    parsed$missing_code_flag <- vapply(
      seq_len(nrow(parsed)),
      function(j) is_missing_code(parsed$response_code[[j]],
                                  parsed$response_label[[j]],
                                  block),
      logical(1)
    )
    rows_out[[i]] <- tibble(
      survey            = "kinu",
      wave              = long$wave[[i]],
      raw_var           = long$variable[[i]],
      question_text     = long$question_text[[i]],
      response_code     = parsed$response_code,
      response_label    = parsed$response_label,
      missing_code_flag = parsed$missing_code_flag,
      source_doc        = "data/kinu/raw/kinu_2014-2024_codebook_en.xlsx",
      source_page       = sheets[1],
      language          = "en",
      notes             = NA_character_
    )
  }
  out <- bind_rows(rows_out)

  # Defensive: enforce schema column types.
  out <- out |>
    mutate(
      survey            = as.character(survey),
      wave              = as.character(wave),
      raw_var           = as.character(raw_var),
      question_text     = as.character(question_text),
      response_code     = as.character(response_code),
      response_label    = as.character(response_label),
      missing_code_flag = as.logical(missing_code_flag),
      source_doc        = as.character(source_doc),
      source_page       = as.character(source_page),
      language          = as.character(language),
      notes             = as.character(notes)
    )

  out
}

# ─────────────────────────────────────────────────────────────────────────
# Coverage report against KINU YAML-referenced raw vars.
# ─────────────────────────────────────────────────────────────────────────

referenced_raw_vars <- function() {
  yaml_dir <- here::here("src", "config", "kinu", "harmonize")
  if (!dir.exists(yaml_dir)) return(character())
  files <- list.files(yaml_dir, pattern = "[.]yml$", full.names = TRUE)
  files <- files[!grepl("MODEL_VARIABLE|TEMPLATE|README", basename(files),
                         ignore.case = TRUE)]
  raws <- character()
  for (f in files) {
    spec <- tryCatch(yaml::read_yaml(f), error = function(e) NULL)
    if (is.null(spec) || is.null(spec$variables)) next
    for (v in spec$variables) {
      if (!is.null(v$source)) {
        raws <- c(raws, unlist(v$source, use.names = FALSE))
      }
    }
  }
  unique(raws)
}

# ─────────────────────────────────────────────────────────────────────────
# Output writer (parquet preferred, CSV fallback).
# ─────────────────────────────────────────────────────────────────────────

write_codebook <- function(df, out_path) {
  parent <- dirname(out_path)
  if (!dir.exists(parent)) dir.create(parent, recursive = TRUE)

  ok <- FALSE
  if (requireNamespace("arrow", quietly = TRUE)) {
    res <- tryCatch({
      arrow::write_parquet(df, out_path)
      TRUE
    }, error = function(e) {
      message("[kinu] arrow::write_parquet failed: ", conditionMessage(e))
      FALSE
    })
    if (isTRUE(res)) ok <- TRUE
  } else {
    message("[kinu] arrow not installed; falling back to CSV")
  }

  if (!ok) {
    csv_path <- sub("[.]parquet$", ".csv", out_path)
    write.csv(df, csv_path, row.names = FALSE)
    message("[kinu] wrote CSV fallback: ", csv_path)
    return(csv_path)
  }
  out_path
}

# ─────────────────────────────────────────────────────────────────────────
# main().
# ─────────────────────────────────────────────────────────────────────────

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  cli  <- parse_cli(args)

  xlsx_path <- here::here("data", "kinu", "raw", "kinu_2014-2024_codebook_en.xlsx")

  message("[kinu] reading: ", xlsx_path)
  cb <- extract_kinu_codebook(xlsx_path)

  if (nrow(cb) == 0) {
    stop("[kinu] extractor produced zero rows — refusing to write empty parquet",
         call. = FALSE)
  }

  written <- write_codebook(cb, cli$output)

  # ── Summary ───────────────────────────────────────────────────────────
  cat("\n", strrep("=", 60), "\n", sep = "")
  cat("KINU codebook extraction summary\n")
  cat(strrep("=", 60), "\n", sep = "")
  cat("Output         : ", written, "\n", sep = "")
  cat("Total rows     : ", nrow(cb), "\n", sep = "")
  cat("Unique vars    : ", length(unique(cb$raw_var)), "\n", sep = "")
  cat("Waves covered  : ",
      paste(sort(unique(cb$wave)), collapse = ", "), "\n", sep = "")
  cat("Missing-code rows: ", sum(cb$missing_code_flag), " (",
      sprintf("%.1f%%", 100 * mean(cb$missing_code_flag)), ")\n", sep = "")

  # Coverage vs YAML claims
  yaml_raws <- referenced_raw_vars()
  cb_raws   <- unique(cb$raw_var)
  matched   <- intersect(yaml_raws, cb_raws)
  missing   <- setdiff(yaml_raws, cb_raws)
  cat("\nYAML coverage check\n")
  cat("  YAML-referenced raw vars : ", length(yaml_raws), "\n", sep = "")
  cat("  Of which present in cb   : ", length(matched), "/", length(yaml_raws),
      " (", sprintf("%.1f%%", 100 * length(matched) / max(length(yaml_raws), 1L)),
      ")\n", sep = "")
  if (length(missing) > 0) {
    cat("  Missing from codebook    : ",
        paste(head(missing, 25), collapse = ", "),
        if (length(missing) > 25) sprintf(" ... +%d more", length(missing) - 25) else "",
        "\n", sep = "")
  }

  cat(strrep("=", 60), "\n", sep = "")
  invisible(cb)
}

if (sys.nframe() == 0) {
  main()
}
