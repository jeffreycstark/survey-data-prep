#!/usr/bin/env Rscript
# src/r/audit/apply_source_under_adds.R
#
# Applies the SAFE_add rows from 02_under_coverage_triage.R: inserts
#       <wave>: <code>
# into each concept's source: block, in chronological wave order, recovering
# data the spec was silently not harmonizing.
#
# UNLIKE apply_source_null_fixes.R this CHANGES harmonized output (it adds
# data), so it is deliberately conservative: only verdict == "SAFE_add" rows
# (question_text-matched, default-only rule, in-range) are touched, and the
# caller MUST re-harmonize and re-validate afterward — the transformation /
# range / completeness checks are the empirical backstop that the added waves
# harmonize correctly.
#
# Insertion is indent-scoped to the source: block and placed in chronological
# order (year, then biannual letter a<b). A target var/wave already present is
# reported and skipped (never duplicated). Dry-run by default.
#
# CLI:
#   Rscript src/r/audit/apply_source_under_adds.R --survey kinu          # dry-run
#   Rscript src/r/audit/apply_source_under_adds.R --survey kinu --apply  # write
#
# Exit: 0 ok; 1 unlocated target var/block; 2 bad invocation / missing CSV.

suppressPackageStartupMessages({ library(here) })
here::i_am("src/r/audit/apply_source_under_adds.R")
source(here::here("src/r/utils/spec_discovery.R"))

.ID_LINE     <- "^(\\s*)-\\s*id:\\s*([A-Za-z0-9_.]+)\\s*$"
.SOURCE_HEAD <- "^(\\s*)source:\\s*$"
.SOURCE_LINE <- "^(\\s+)([A-Za-z0-9_]+):\\s+([A-Za-z0-9_.~]+).*$"
.indent_of   <- function(line) nchar(sub("^( *).*$", "\\1", line))

# Chronological rank for a KINU-style wave key wYYYY[a|b].
.wave_rank <- function(w) {
  yr <- as.integer(sub("^w(\\d{4}).*$", "\\1", w))
  letter <- sub("^w\\d{4}", "", w)
  yr * 10L + switch(letter, a = 1L, b = 2L, 0L)
}

# Map var_id -> spec file basename (each id is unique to one file).
.var_to_file <- function(survey) {
  m <- list()
  for (sp in list_survey_specs(survey)) {
    y <- tryCatch(yaml::read_yaml(sp), error = function(e) NULL); if (is.null(y)) next
    for (v in y$variables) m[[v$id]] <- basename(sp)
  }
  m
}

# For one file, return planned insertions: list(line_after, indent, text, var, wave).
plan_file <- function(path, adds) {
  lines <- readLines(path, warn = FALSE)
  cur_var <- NA_character_; in_source <- FALSE; src_indent <- -1L
  # Collect per-var: existing wave lines (wave -> line_no), the block's child indent.
  blocks <- list()  # var -> list(waves = named int, indent = chr, last_line = int)
  for (i in seq_along(lines)) {
    ln <- lines[i]
    m_id <- regmatches(ln, regexec(.ID_LINE, ln))[[1]]
    if (length(m_id) == 3) { cur_var <- m_id[3]; in_source <- FALSE; next }
    m_src <- regmatches(ln, regexec(.SOURCE_HEAD, ln))[[1]]
    if (length(m_src) == 2) {
      in_source <- TRUE; src_indent <- nchar(m_src[2])
      if (!is.na(cur_var)) blocks[[cur_var]] <- list(waves = integer(0), indent = NA, last = i)
      next
    }
    if (in_source && nzchar(trimws(ln)) && .indent_of(ln) <= src_indent) in_source <- FALSE
    if (!in_source || is.na(cur_var)) next
    m <- regmatches(ln, regexec(.SOURCE_LINE, ln))[[1]]
    if (length(m) != 4) next
    b <- blocks[[cur_var]]
    b$waves[m[3]] <- i
    if (is.na(b$indent)) b$indent <- m[2]
    b$last <- i
    blocks[[cur_var]] <- b
  }

  plans <- list()
  for (r in seq_len(nrow(adds))) {
    vid <- adds$var_id[r]; wv <- adds$wave[r]; code <- adds$raw_var[r]
    b <- blocks[[vid]]
    if (is.null(b)) { plans[[length(plans)+1L]] <- list(status="NO_BLOCK", var=vid, wave=wv); next }
    if (wv %in% names(b$waves)) { plans[[length(plans)+1L]] <- list(status="EXISTS", var=vid, wave=wv); next }
    indent <- if (!is.na(b$indent)) b$indent else strrep(" ", 6L)
    new_rank <- .wave_rank(wv)
    existing <- b$waves
    smaller <- existing[vapply(names(existing), function(w) .wave_rank(w) < new_rank, logical(1))]
    after_line <- if (length(smaller) > 0) max(smaller) else (min(existing) - 1L)
    plans[[length(plans)+1L]] <- list(
      status = "ok", var = vid, wave = wv,
      after_line = after_line,
      text = sprintf("%s%s: %s", indent, wv, code))
  }
  list(lines = lines, plans = plans)
}

apply_file <- function(path, plans, lines) {
  ok <- Filter(function(p) p$status == "ok", plans)
  if (length(ok) == 0) return(0L)
  # Group inserts sharing an anchor line; place each group as one chronologically
  # ordered block. Process groups bottom-to-top so earlier line numbers stay valid.
  anchors <- vapply(ok, function(p) p$after_line, numeric(1))
  for (a in sort(unique(anchors), decreasing = TRUE)) {
    grp <- ok[anchors == a]
    texts <- vapply(grp, function(p) p$text, character(1))
    waves <- vapply(grp, function(p) p$wave, character(1))
    texts <- texts[order(vapply(waves, .wave_rank, numeric(1)))]  # chronological
    lines <- append(lines, texts, after = a)
  }
  writeLines(lines, path)
  length(ok)
}

.main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  do_apply <- "--apply" %in% args
  i <- match("--survey", args)
  if (is.na(i) || i == length(args)) { cat("ERROR: pass --survey <name>\n"); quit(status = 2) }
  survey <- args[i + 1L]

  csv <- here::here("audit", "reports", survey, "02-under-triage.csv")
  if (!file.exists(csv)) { cat(sprintf("ERROR: no triage CSV at %s\n", csv)); quit(status = 2) }
  tri <- utils::read.csv(csv, stringsAsFactors = FALSE)
  safe <- tri[tri$verdict == "SAFE_add", , drop = FALSE]
  cat(sprintf("Survey %s: %d SAFE_add cells to insert\n", survey, nrow(safe)))
  if (nrow(safe) == 0) quit(status = 0)

  spec_dir <- find_survey_spec_dir(survey)
  v2f <- .var_to_file(survey)
  safe$spec_file <- vapply(safe$var_id, function(v) v2f[[v]] %||% NA_character_, character(1))
  `%||%` <- function(a, b) if (is.null(a)) b else a

  total_ok <- 0L; problems <- 0L
  for (sf in unique(safe$spec_file)) {
    path <- file.path(spec_dir, sf)
    res <- plan_file(path, safe[safe$spec_file == sf, ])
    n_ok <- sum(vapply(res$plans, function(p) p$status == "ok", logical(1)))
    for (p in res$plans) {
      if (p$status == "ok")
        cat(sprintf("  %s  +%-7s  (after line %d)  %s\n", sf, p$wave, p$after_line, trimws(p$text)))
      else { cat(sprintf("  [%s] %s %s/%s\n", p$status, sf, p$var, p$wave)); problems <- problems + 1L }
    }
    if (do_apply) total_ok <- total_ok + apply_file(path, res$plans, res$lines)
    else total_ok <- total_ok + n_ok
  }
  cat(sprintf("\n%s %d insertions across %d files%s\n",
              if (do_apply) "APPLIED" else "PLANNED",
              total_ok, length(unique(safe$spec_file)),
              if (do_apply) "" else "  (dry-run — pass --apply)"))
  quit(status = if (problems > 0) 1 else 0)
}

if (identical(environment(), globalenv()) && !interactive()) {
  .main()
}
