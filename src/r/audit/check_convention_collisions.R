#!/usr/bin/env Rscript
# src/r/audit/check_convention_collisions.R
#
# Cross-cutting spec check: missing-code conventions must not delete valid
# responses.
#
# WHAT IT CATCHES
# The engine (harmonize_variable) applies the resolved missing codes to the
# RAW values before anything else. For `method: identity` waves the raw scale
# IS the harmonized scale, so any missing code that falls inside
# qc.valid_range converts real answers to NA — silently: the range check
# never sees them (already NA) and the oob log never records them (removed
# as "missing", not coerced as out-of-range). This is the class behind the
# 2026-08-07 finding: ABS 1-10 democracy ratings losing 7/8/9, KIPA 0-10
# economic evaluations losing 8/9, KINU losing region 9 (= Gangwon) and
# employment 9 (= student), ABS W1 action items losing 9 (= "Never done").
# It is also the same failure mode as the AFRO education_5cat bug fixed
# 2026-07-09 (see the header of src/r/utils/education.R).
#
# SCOPE / LIMITATION
# Only `method: identity` waves are checked, because only there does
# valid_range describe the raw domain. For r_function / recode / derive
# waves the raw scale differs from the harmonized one, so a convention code
# inside valid_range proves nothing — and, conversely, a convention code can
# collide with the FUNCTION'S expected raw input without ever touching
# valid_range (the govt_anticorrupt_effort W2 raw-0 case). Auditing fn input
# domains against conventions is future work (see JEFF_MUST_INVESTIGATE.md);
# until then, non-identity waves are this check's blind spot.
#
# EXEMPTIONS
# Some collisions are deliberate (age top-codes like 97-99 inside an
# [18, 99+] range, weight 0 inside [0, max], recode-midpoint markers).
# Declare them in src/config/_audit/convention_collision_exemptions.yml —
# same exempt-with-reason pattern as bin_width_exemptions.yml. Exempted rows
# are still printed and written to the CSV (status "exempt"), they just
# don't fail the run.
#
# Run:   Rscript src/r/audit/check_convention_collisions.R [--survey <slug>] [--quiet]
# Out:   audit/reports/convention_collisions.csv
# Exit:  0 clean (or exempt-only) | 1 unexempted error row(s) | 2 config error
#
# Wired into run_all.R as a cross-cutting module (like the recoding
# registry check), so it runs under `make audit` and `make audit-specs` /
# CI. Reads nothing but YAML — safe on a dataless checkout.

suppressPackageStartupMessages({
  library(here)
  library(yaml)
})

source(here::here("src", "r", "utils", "spec_discovery.R"))
# resolve_wave_rule() lives in the engine and is the single source of truth
# for the by_wave -> exceptions -> direct-wave -> default precedence.
# Sourcing it (rather than re-implementing) keeps this check in lockstep if
# a v4 rule format is ever added. harmonize.R defines functions only — no
# top-level side effects — so this is safe on a dataless checkout.
source(here::here("src", "r", "harmonize", "harmonize.R"))

.EXEMPTIONS_PATH <- here::here("src", "config", "_audit",
                               "convention_collision_exemptions.yml")
.REPORT_PATH <- here::here("audit", "reports", "convention_collisions.csv")

# ---------------------------------------------------------------------------
# Survey discovery: every directory under src/config with a canonical spec
# dir, skipping infrastructure dirs (leading underscore) and non-survey
# lookups.
# ---------------------------------------------------------------------------
.discover_surveys <- function() {
  root <- here::here("src", "config")
  cands <- list.dirs(root, recursive = FALSE, full.names = FALSE)
  cands <- cands[!grepl("^_", cands)]
  cands <- setdiff(cands, "lookups")
  keep <- vapply(cands, function(s) {
    ok <- tryCatch({ find_survey_spec_dir(s); TRUE }, error = function(e) FALSE)
    ok && length(list_survey_specs(s)) > 0L
  }, logical(1))
  sort(cands[keep])
}

# ---------------------------------------------------------------------------
# Spec-shape helpers. The two live formats are a list of maps each carrying
# `id:` (v2, what harmonize_spec() iterates) and a named list keyed by id
# (v1, what harmonize_all() iterates). Handle both.
# ---------------------------------------------------------------------------
.iter_variables <- function(spec) {
  vars <- spec$variables
  if (is.null(vars) || length(vars) == 0L) return(list())
  nm <- names(vars)
  if (!is.null(nm) && all(nzchar(nm))) {
    # v1 named-list format: inject the id from the name if absent
    return(lapply(seq_along(vars), function(i) {
      v <- vars[[i]]
      if (is.null(v$id)) v$id <- nm[i]
      v
    }))
  }
  vars
}

.convention_codes <- function(conventions, key) {
  if (is.null(key)) return(NULL)
  conv <- conventions[[key]]
  if (is.null(conv)) return(NA)  # declared but unresolvable (L1's job to fail)
  raw <- if (is.list(conv) && !is.null(conv$codes)) conv$codes else conv
  suppressWarnings(as.numeric(unlist(raw)))
}

.effective_codes <- function(var_spec, conventions) {
  codes <- numeric(0)
  conv <- .convention_codes(conventions, var_spec$missing$use_convention)
  if (length(conv) == 1L && is.na(conv[1]) && !is.numeric(conv)) conv <- numeric(0)
  if (!is.null(conv) && !all(is.na(conv))) codes <- c(codes, conv[!is.na(conv)])
  if (!is.null(var_spec$missing$codes)) {
    extra <- suppressWarnings(as.numeric(unlist(var_spec$missing$codes)))
    codes <- c(codes, extra[!is.na(extra)])
  }
  unique(codes)
}

# ---------------------------------------------------------------------------
# Exemptions. Schema:
#   exemptions:
#     - survey: kinu            # required
#       variable: age           # required
#       spec: demographics      # optional (basename sans .yml)
#       codes: [99]             # optional — exempt only these codes
#       reason: "..."           # required (surfaced in report)
# ---------------------------------------------------------------------------
.load_exemptions <- function(path = .EXEMPTIONS_PATH) {
  if (!file.exists(path)) return(list())
  y <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
  if (is.null(y) || is.null(y$exemptions)) return(list())
  y$exemptions
}

.match_exemption <- function(exemptions, survey, spec_name, variable, codes) {
  for (ex in exemptions) {
    if (!identical(ex$survey, survey)) next
    if (!identical(ex$variable, variable)) next
    if (!is.null(ex$spec) && !identical(ex$spec, spec_name)) next
    ex_codes <- if (is.null(ex$codes)) NULL else
      suppressWarnings(as.numeric(unlist(ex$codes)))
    if (is.null(ex_codes) || all(codes %in% ex_codes)) {
      return(ex$reason %||% "(no reason given)")
    }
  }
  NULL
}

# ---------------------------------------------------------------------------
# Locale-proof YAML reader. yaml::read_yaml() goes through readLines(), which
# mangles UTF-8 spec files (Korean notes, arrows) under a C locale and made
# an early version of this check silently skip 7 of 13 surveys. Read raw
# bytes, declare UTF-8, parse the string.
# ---------------------------------------------------------------------------
.read_spec_utf8 <- function(path) {
  txt <- readChar(path, file.info(path)$size, useBytes = TRUE)
  Encoding(txt) <- "UTF-8"
  yaml::yaml.load(txt)
}

# ---------------------------------------------------------------------------
# Core: scan one survey, return list(rows = data.frame, parse_failures = chr).
# A spec that cannot be parsed is REPORTED, never silently skipped: a check
# that can't read its inputs must not look green.
# ---------------------------------------------------------------------------
scan_survey_collisions <- function(survey, exemptions = list()) {
  rows <- list()
  parse_failures <- character(0)
  for (spec_path in list_survey_specs(survey)) {
    spec_name <- tools::file_path_sans_ext(basename(spec_path))
    spec <- tryCatch(.read_spec_utf8(spec_path), error = function(e) {
      parse_failures <<- c(parse_failures,
                           sprintf("%s/%s: %s", survey, spec_name,
                                   conditionMessage(e)))
      NULL
    })
    if (is.null(spec)) next
    conventions <- spec$missing_conventions %||% list()

    for (var_spec in .iter_variables(spec)) {
      vid <- var_spec$id %||% "(no id)"
      if (isTRUE(var_spec$qc$skip_range_check)) next
      codes <- .effective_codes(var_spec, conventions)
      if (length(codes) == 0L) next

      global_vr <- var_spec$qc$valid_range
      by_wave_vr <- var_spec$qc$valid_range_by_wave

      # identity waves: non-null source whose resolved rule is identity
      src <- var_spec$source %||% list()
      hits <- list()  # colliding-code -> waves
      for (wave in names(src)) {
        if (is.null(src[[wave]])) next
        rule <- resolve_wave_rule(var_spec, wave)
        if (!identical(rule$method %||% "identity", "identity")) next
        vr <- by_wave_vr[[wave]] %||% global_vr
        if (is.null(vr) || length(vr) < 2L) next
        lo <- suppressWarnings(as.numeric(vr[[1]]))
        hi <- suppressWarnings(as.numeric(vr[[2]]))
        if (is.na(lo) || is.na(hi)) next
        clash <- codes[codes >= lo & codes <= hi]
        for (cc in clash) {
          key <- format(cc)
          hits[[key]] <- unique(c(hits[[key]], wave))
        }
      }
      if (length(hits) == 0L) next

      clash_codes <- suppressWarnings(as.numeric(names(hits)))
      waves_str <- paste(sort(unique(unlist(hits))), collapse = ",")
      vr_str <- if (!is.null(global_vr)) {
        sprintf("[%s, %s]", global_vr[[1]], global_vr[[2]])
      } else "(by-wave)"
      reason <- .match_exemption(exemptions, survey, spec_name, vid, clash_codes)

      rows[[length(rows) + 1L]] <- data.frame(
        survey      = survey,
        spec        = spec_name,
        variable    = vid,
        codes       = paste(sort(clash_codes), collapse = ";"),
        valid_range = vr_str,
        waves       = waves_str,
        convention  = var_spec$missing$use_convention %||% "(inline codes)",
        status      = if (is.null(reason)) "error" else "exempt",
        reason      = reason %||% "",
        stringsAsFactors = FALSE
      )
    }
  }
  df <- if (length(rows) == 0L) {
    data.frame(survey = character(0), spec = character(0),
               variable = character(0), codes = character(0),
               valid_range = character(0), waves = character(0),
               convention = character(0), status = character(0),
               reason = character(0), stringsAsFactors = FALSE)
  } else do.call(rbind, rows)
  list(rows = df, parse_failures = parse_failures)
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
.main <- function() {
  args <- commandArgs(trailingOnly = TRUE)

  if ("--help" %in% args || "-h" %in% args) {
    cat("Usage: Rscript src/r/audit/check_convention_collisions.R [--survey <slug>] [--quiet]\n\n",
        "Flags variables whose resolved missing codes fall INSIDE qc.valid_range\n",
        "on method:identity waves — i.e. conventions that delete valid responses.\n",
        "Exemptions: src/config/_audit/convention_collision_exemptions.yml\n",
        "Report:     audit/reports/convention_collisions.csv\n",
        "Exit: 0 clean/exempt-only | 1 unexempted error row(s) | 2 config error\n",
        sep = "")
    quit(status = 0)
  }

  quiet <- "--quiet" %in% args
  targets <- {
    i <- match("--survey", args)
    if (!is.na(i)) {
      s <- args[i + 1L]
      if (is.na(s)) { cat("ERROR: --survey needs a value\n"); quit(status = 2) }
      ok <- tryCatch({ find_survey_spec_dir(s); TRUE }, error = function(e) FALSE)
      if (!ok) { cat(sprintf("ERROR: unknown survey '%s'\n", s)); quit(status = 2) }
      s
    } else .discover_surveys()
  }

  exemptions <- .load_exemptions()
  scans <- lapply(targets, scan_survey_collisions, exemptions = exemptions)
  all_rows <- do.call(rbind, lapply(scans, `[[`, "rows"))
  parse_failures <- unlist(lapply(scans, `[[`, "parse_failures"))

  dir.create(dirname(.REPORT_PATH), showWarnings = FALSE, recursive = TRUE)
  write.csv(all_rows, .REPORT_PATH, row.names = FALSE)

  n_err <- sum(all_rows$status == "error")
  n_ex  <- sum(all_rows$status == "exempt")

  if (!quiet) {
    cat(sprintf("=== Convention-collision check — %d survey(s) ===\n",
                length(targets)))
    if (nrow(all_rows) == 0L) {
      cat("  clean: no missing-code convention collides with a valid_range\n")
    } else {
      for (i in seq_len(nrow(all_rows))) {
        r <- all_rows[i, ]
        cat(sprintf("  %-6s %s/%s %s: codes {%s} inside %s (waves: %s; via %s)\n",
                    toupper(r$status), r$survey, r$spec, r$variable,
                    r$codes, r$valid_range, r$waves, r$convention))
        if (r$status == "exempt") cat(sprintf("         reason: %s\n", r$reason))
      }
    }
    if (length(parse_failures) > 0L) {
      cat("\n  PARSE FAILURES (specs this check could not read — NOT cleared):\n")
      for (pf in parse_failures) cat(sprintf("    %s\n", pf))
    }
    cat(sprintf("\nSummary: %d error, %d exempt, %d unparseable. Report: %s\n",
                n_err, n_ex, length(parse_failures), .REPORT_PATH))
    if (n_err > 0L) {
      cat("Each error deletes real responses. Fix by pointing the variable at a\n")
      cat("convention whose codes lie outside its scale (see treat_as_na_10pt in\n")
      cat("abs/international_relations.yml for the pattern), or exempt WITH A\n")
      cat("REASON in convention_collision_exemptions.yml if the loss is intended.\n")
    }
  }

  quit(status = if (n_err > 0L || length(parse_failures) > 0L) 1L else 0L)
}

if (sys.nframe() == 0L && !interactive()) .main()
