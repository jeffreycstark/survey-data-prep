#!/usr/bin/env Rscript
# src/r/audit/03_oob_triage.R
#
# Layer 3b — Out-of-range triage (Check E).
#
# THE GAP THIS CLOSES
# -------------------
# The harmonize engine already detects out-of-range values: after each wave's
# recode, anything outside `qc.valid_range` is counted, appended to
# `outputs/<survey>/oob_log.csv`, and coerced to NA
# (src/r/harmonize/harmonize.R:279-321).
#
# Nothing ever read that log. `run_all.R` did not tally it, the post-harmonize
# gate did not look at it, and it is gitignored — so the only signal at build
# time was a message() that scrolled past. On introduction (2026-07-31) the
# committed logs held 90 events across 7 surveys covering ~24,000 silently
# deleted respondent-values, including:
#
#   wvs  freedom_vs_equality w2  8,787 x code 3   [valid 1-2]
#   afro corr_perc_mp        w9  4,800 x code 94  [valid 0-3]
#   lbs  education_level  y2004  2,491 x code 0   [valid 1-7]
#   afro dem_satisfaction    w9    932 x code 0   [valid 1-4]
#
# The last one is the known class: `JEFF_MUST_INVESTIGATE.md` records the same
# 932 R9 respondents as "previously silently NA-coerced by the engine's
# valid_range [1,4]" — found by a human reading data, not by a check firing.
#
# The engine's default action is to DESTROY the evidence: an undeclared code is
# indistinguishable from item nonresponse once it is NA. So the log is the only
# record, and this layer is what reads it.
#
# WHAT IT CHECKS
# --------------
# Each (variable x wave) row of the log is classified, then graded. The
# classifier is deterministic and evidence-based — it prefers what the survey's
# own specs declare over any hardcoded guess about what a code "usually" means.
#
#   sentinel_leak      The stray code is declared as a missing code SOMEWHERE in
#                      this survey's specs, just not on this variable (or it is
#                      a classic multi-digit sentinel: 99, 998, 9999, negatives).
#                      Outcome is benign — the value ends up NA either way — but
#                      the spec under-declares.                          -> warn
#                      e.g. afro 94 = "Question not asked", declared in seven
#                      afro specs but not the one owning corr_perc_*.
#
#   scale_extension    The stray sits immediately outside the declared range
#                      (valid_max+1 / valid_min-1) and is not a sentinel: the
#                      wave's response set is WIDER than the spec believes, and
#                      a whole substantive category is being deleted. This is
#                      the IPUS uni_view / Afro dem_country_not_democracy class.
#                                              -> error at >= escalate_n, else warn
#
#   zero_leak          Code 0 where the scale starts at 1. Genuinely ambiguous —
#                      could be a missing sentinel, could be a substantive
#                      "none"/"not applicable" category. Needs a human.
#                                              -> error at >= escalate_n, else warn
#
#   out_of_frame_code  The stray is an order of magnitude outside the frame
#                      (>= 10x valid_max), i.e. the wave is coded on a DIFFERENT
#                      code frame than the spec assumes.                -> error
#                      e.g. arab-barometer dem_feature_1st w2 uses 4-5 digit
#                      codes where the spec declares 1-10.
#
#   outlier_tail       A continuous/count variable with a spread of values past
#                      its bound (age 115-130, hh_size 21-93). Dirty raw data;
#                      coercion to NA is almost certainly right.          -> warn
#
#   unclassified       None of the above.       -> error at >= bulk_n, else warn
#
# Volume escalation exists because bulk deletion is never benign regardless of
# class: one stray 6 in a 1-5 item is a typo, 8,787 of them is a lost response
# category.
#
# TWO WAYS AN EVENT IS CLEARED
# ----------------------------
#   1. `qc.coverage_missing_codes[_by_wave]` in the variable's own spec — the
#      repo's EXISTING first-class "this drop is deliberate" declaration, which
#      validate_coverage() already honours (.vvw_collect_coverage_codes in
#      validation.R). That is why lbs age y2010 reports "Coverage OK (100.0%)"
#      despite 2,483 deletions: someone triaged it and wrote the intent down.
#      Matching events become `ok_declared`.
#
#      This layer shipped without reading that field and consequently re-raised
#      three already-documented drops as errors (lbs age y2010, lbs
#      education_level y2004, afro dem_satisfaction w9). An audit that re-opens
#      settled decisions trains people to ignore it, so intent declared in the
#      spec outranks the grade.
#
#      SPANS ARE NOT CLEARED. The engine logs only n/min/max, so matching
#      endpoints cannot prove every value in between is declared; such events
#      are capped at `warn` with the reason recorded, never cleared outright.
#
#   2. src/config/_audit/oob_exemptions.yml — the `allow_oob` concept from
#      audit/01-audit-framework.md Layer 3, for events that are acceptable but
#      have no natural home in a spec. Downgrades error -> ok_exempt and
#      requires a written reason.
#
# Reads only the log + YAML specs. No data load, no raw .sav, so it is fast and
# safe to run anywhere. It does NOT re-derive the events — it audits the record
# the engine already wrote, which means it is only as fresh as the last build
# (pair it with 06_check_freshness.R).
#
# Output: audit/reports/<survey>/03-oob.csv, one row per (variable, wave), the
# path designated for this in audit/01-audit-framework.md Layer 3.
#
# Usage:
#   Rscript src/r/audit/03_oob_triage.R --survey afro
#   Rscript src/r/audit/03_oob_triage.R --all-surveys
#   Rscript src/r/audit/03_oob_triage.R --survey abs --quiet
#
# Exit codes: 0 clean (warn/ok/skip allowed) | 1 at least one error row
#             | 2 config error (unreadable exemptions / malformed log)

suppressPackageStartupMessages({
  library(here)
  library(yaml)
})

here::i_am("src/r/audit/03_oob_triage.R")

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

#' Safe named lookup. `[[` on a named ATOMIC vector errors on an absent name
#' ("subscript out of bounds") rather than returning NULL, so a variable absent
#' from the spec context would crash the whole triage instead of falling back.
.get_named <- function(x, nm, default) {
  if (is.null(x) || length(x) == 0L) return(default)
  if (is.null(names(x)) || !(nm %in% names(x))) return(default)
  v <- x[[nm]]
  if (is.null(v) || length(v) == 0L) default else v
}

# Kept in sync with run_all.R's .SUPPORTED_SURVEYS (Layer 7 enforces this).
.OOB_SURVEYS <- c(
  "abs", "wvs", "lbs", "afro", "arab-barometer",
  "kamos", "kgss", "kipa_corruption", "kinu", "ipus", "gcb", "klosa"
)

.EXEMPTIONS_PATH <- "src/config/_audit/oob_exemptions.yml"

# Classic sentinels that are recognisable without consulting a spec. Split by
# digit-width because the single-digit ones (7/8/9) are ambiguous: 9 outside a
# 1-4 scale is Don't-know, but 7 immediately outside a 1-6 scale is far more
# likely a real 7th category. Contiguity is therefore tested BEFORE the
# single-digit set (see classify_oob_event).
# Deliberately excludes survey-specific sentinels (Afro's 94 = "Question not
# asked", 9994 = "Not asked in country"). Those must be earned from the survey's
# own specs via declared_elsewhere, not assumed here — otherwise a genuinely
# undeclared code gets excused by a hardcoded guess.
.SENTINELS_MULTI  <- c(-9:-1, 77, 88, 97, 98, 99,
                       777, 888, 997, 998, 999,
                       7777, 8888, 9997, 9998, 9999)
.SENTINELS_SINGLE <- c(7, 8, 9)

# A code only counts as evidence from OTHER variables' declarations if it is
# sentinel-SHAPED: negative, or high enough that it is unlikely to be an ordinary
# response category. Without this the evidence base is polluted — abs declares
# {0, 3, 5, 6, 7, 8, 9, 10, 11} as bespoke missing codes on one variable or
# another, which would let any of those excuse a stray on every OTHER variable in
# the survey. It did exactly that on first run: abs hh_generations' 107 code-10
# values (still a live error) and afro dem_satisfaction's 932 code-0 responses
# were both classed sentinel_leak. Small positive codes must instead be earned by
# the universal rules — contiguity and .SENTINELS_SINGLE — because that is
# precisely the shape of a real category. (Classing dem_satisfaction correctly as
# zero_leak is this constant's doing; the spec's coverage_missing_codes
# declaration is what then clears it to ok_declared. Two separate mechanisms.)
#
# WHY 20, and where that stops being safe. Measured over the 1,041 non-continuous
# variables that declare a valid_range: 1,018 (97.8%) top out at <= 11, so for
# almost the whole corpus a code >= 20 cannot be an in-scale response. Only 13
# exceed 20 — four year-valued (int_year x3, gcb fieldwork_year) plus:
#
#   abs  religion 1-9999   abs  problem_most_important 1-996
#   kinu leader/party_warmth_* 0-100 (x4)  ipus religion 1-98
#   kgss income 0-87       kgss religion 1-77
#
# On THOSE nine the bar does almost no work: any value that could be an
# out-of-range stray there is already >= 20 by construction, so their evidence
# base is effectively unfiltered and a substantive out-of-range code would be
# excused as sentinel_leak (-> warn). The bar is absolute rather than relative to
# each variable's own scale, which is the simplification that buys this.
#
# No live event hits that gap today: none of those nine appears in any oob log.
# The only wide-scale variable that does is abs int_year (one stray 2000 against
# [2001, 2025]), and it is unaffected — 2000 is declared missing nowhere in abs,
# so it never reaches the evidence base at all. Latent limitation, not an active
# bug. Making the bar relative (some multiple of valid_max) is the fix if a live
# case ever appears; test_oob_triage.R pins the current behaviour either way.
.SENTINEL_SHAPE_MIN <- 20

# Remedy text per class — what the person triaging should actually do.
.REMEDY <- c(
  sentinel_leak     = "declare the code in this variable's missing.codes / use_convention",
  scale_extension   = "add a per-wave recode mapping, or widen valid_range if the category is substantive",
  zero_leak         = "decide whether 0 is missing (declare it) or substantive (map it)",
  out_of_frame_code = "this wave uses a different code frame — add a per-wave recode",
  outlier_tail      = "dirty raw data; confirm coercion is correct, then exempt",
  unclassified      = "inspect the raw codebook for this variable x wave"
)


# ---------------------------------------------------------------------------
# Spec context: per-variable declared type, and the missing codes this survey
# declares ANYWHERE. The latter is what makes sentinel classification evidence-
# based rather than a hardcoded guess.
# ---------------------------------------------------------------------------

#' Collect declared types and missing codes from a survey's production specs.
#'
#' @param survey Survey slug, or NULL to return an empty context.
#' @param spec_dir Optional explicit directory (tests pass a fixture dir).
#' @return list(types = named character, var_missing = named list of numeric,
#'   survey_missing = numeric)
load_spec_context <- function(survey = NULL, spec_dir = NULL) {
  empty <- list(types = character(0), var_missing = list(),
                survey_missing = numeric(0))

  if (is.null(spec_dir)) {
    if (is.null(survey)) return(empty)
    sd_path <- here::here("src", "r", "utils", "spec_discovery.R")
    if (file.exists(sd_path)) {
      suppressWarnings(source(sd_path, local = TRUE))
      spec_dir <- tryCatch(find_survey_spec_dir(survey), error = function(e) NULL)
    }
    if (is.null(spec_dir)) return(empty)
  }
  if (!dir.exists(spec_dir)) return(empty)

  files <- list.files(spec_dir, pattern = "\\.ya?ml$", full.names = TRUE)
  files <- files[!grepl("MODEL_VARIABLE|TEMPLATE|README", basename(files),
                        ignore.case = TRUE)]

  types <- character(0)
  var_missing <- list()
  survey_missing <- numeric(0)
  declared_drops <- list()

  extract_codes <- function(conv) {
    if (is.null(conv)) return(numeric(0))
    if (is.list(conv) && !is.null(conv$codes)) {
      return(suppressWarnings(as.numeric(unlist(conv$codes))))
    }
    suppressWarnings(as.numeric(unlist(conv)))
  }

  for (f in files) {
    spec <- tryCatch(yaml::read_yaml(f), error = function(e) NULL)
    if (is.null(spec) || is.null(spec$variables)) next

    conventions <- spec$missing_conventions %||% list()
    for (conv in conventions) {
      survey_missing <- c(survey_missing, extract_codes(conv))
    }

    for (v in spec$variables) {
      id <- v$id %||% next
      types[[id]] <- tolower(as.character(v$type %||% "ordinal"))

      codes <- numeric(0)
      key <- v$missing$use_convention %||% NULL
      if (!is.null(key) && !is.null(conventions[[key]])) {
        codes <- c(codes, extract_codes(conventions[[key]]))
      }
      if (!is.null(v$missing$codes)) {
        codes <- c(codes, suppressWarnings(as.numeric(unlist(v$missing$codes))))
      }
      var_missing[[id]] <- unique(codes[!is.na(codes)])
      survey_missing <- c(survey_missing, codes)

      # `qc.coverage_missing_codes[_by_wave]` is the repo's EXISTING first-class
      # statement of "this drop is intentional" — validate_coverage() already
      # honours it (.vvw_collect_coverage_codes in validation.R), which is why
      # lbs age y2010 reports "Coverage OK (100.0%)" despite 2,483 deletions.
      # Check E must honour the same declaration or it re-raises work that has
      # already been triaged and documented in the spec.
      glob <- suppressWarnings(as.numeric(unlist(v$qc$coverage_missing_codes)))
      byw  <- lapply(v$qc$coverage_missing_codes_by_wave %||% list(),
                     function(z) suppressWarnings(as.numeric(unlist(z))))
      if (length(glob) > 0L || length(byw) > 0L) {
        declared_drops[[id]] <- list(global = glob[!is.na(glob)], by_wave = byw)
      }
    }
  }

  list(
    types = types,
    var_missing = var_missing,
    survey_missing = sort(unique(survey_missing[!is.na(survey_missing)])),
    declared_drops = declared_drops
  )
}


#' Is this event a drop the spec already declared intentional?
#'
#' @return "full"    every resolvable stray value is declared;
#'         "partial" the event is a SPAN and both endpoints are declared, but
#'                   the engine's log records only n/min/max so the interior
#'                   values cannot be verified;
#'         "none"    not declared.
.declared_drop_status <- function(declared, variable, wave, obs_min, obs_max) {
  d <- .get_named(declared, variable, NULL)
  if (is.null(d)) return("none")
  codes <- c(d$global %||% numeric(0),
             .get_named(d$by_wave, wave, numeric(0)))
  codes <- codes[!is.na(codes)]
  if (length(codes) == 0L) return("none")

  if (isTRUE(obs_min == obs_max)) {
    return(if (obs_min %in% codes) "full" else "none")
  }
  if (obs_min %in% codes && obs_max %in% codes) return("partial")
  "none"
}


# ---------------------------------------------------------------------------
# Classifier
# ---------------------------------------------------------------------------

#' Classify a single out-of-range event.
#'
#' Deterministic: same inputs always give the same class. No statistical
#' inference, which is why error rows are allowed to fail a run (same standard
#' as Check D, bin-width parity).
#'
#' @param obs_min,obs_max Observed bounds of the coerced values.
#' @param valid_min,valid_max The declared range they fell outside of.
#' @param var_type Declared YAML type ("continuous", "ordinal", ...).
#' @param declared_elsewhere Numeric codes this survey declares as missing on
#'   OTHER variables — the evidence base for `sentinel_leak`.
#' @return Character class name.
classify_oob_event <- function(obs_min, obs_max, valid_min, valid_max,
                               var_type = "ordinal",
                               declared_elsewhere = numeric(0)) {

  if (any(is.na(c(obs_min, obs_max, valid_min, valid_max)))) return("unclassified")

  var_type <- tolower(as.character(var_type %||% "ordinal"))
  is_cont  <- var_type %in% c("continuous", "count", "numeric")
  single   <- isTRUE(obs_min == obs_max)
  vals     <- unique(c(obs_min, obs_max))

  in_sentinel_multi <- all(vals %in% c(.SENTINELS_MULTI, declared_elsewhere))
  scale_span <- max(abs(valid_max), 1)

  # 1. Evidence-based / multi-digit sentinels. Applies to spans too: if both
  #    endpoints are sentinels the whole event is sentinel noise.
  if (in_sentinel_multi) return("sentinel_leak")

  # 2. Spread over a continuous variable = dirty raw tail, not a code problem.
  if (!single && is_cont) return("outlier_tail")

  if (single) {
    v <- obs_min
    # 3. Zero where the scale starts at 1 — ambiguous enough to need a human,
    #    checked before the continuous branch so a bulk of zeros in an age
    #    column still escalates.
    if (v == 0 && valid_min >= 1) return("zero_leak")
    # 4. Contiguous with the declared range = the response set is wider than
    #    the spec believes. Tested BEFORE single-digit sentinels so a genuine
    #    7th category on a 1-6 scale is not written off as Don't-know.
    #    Gated to non-continuous types: "one category wider" is meaningless on a
    #    measured quantity, where a value just past the bound is dirty data
    #    (wvs age 15 against a floor of 16 is a 15-year-old, not a lost
    #    response option).
    if (!is_cont && (v == valid_max + 1 || v == valid_min - 1)) {
      return("scale_extension")
    }
    # 5. Single-digit classic sentinel (9 outside a 1-4 scale).
    if (v %in% .SENTINELS_SINGLE) return("sentinel_leak")
    if (is_cont) return("outlier_tail")
    if (abs(v) >= 10 * scale_span) return("out_of_frame_code")
    return("unclassified")
  }

  # Spans on non-continuous variables.
  if (obs_min == valid_max + 1 && obs_max <= valid_max + 3) return("scale_extension")
  if (obs_max == valid_min - 1 && obs_min >= valid_min - 3) return("scale_extension")
  if (obs_min >= 10 * scale_span) return("out_of_frame_code")
  "unclassified"
}


#' Grade a classified event into ok/warn/error.
grade_oob_event <- function(class, n_oob, escalate_n = 30L, bulk_n = 50L) {
  n_oob <- suppressWarnings(as.numeric(n_oob))
  if (is.na(n_oob)) n_oob <- 0
  switch(
    class,
    sentinel_leak     = "warn",
    outlier_tail      = "warn",
    out_of_frame_code = "error",
    scale_extension   = if (n_oob >= escalate_n) "error" else "warn",
    zero_leak         = if (n_oob >= escalate_n) "error" else "warn",
    unclassified      = if (n_oob >= bulk_n) "error" else "warn",
    "warn"
  )
}


# ---------------------------------------------------------------------------
# Exemptions
# ---------------------------------------------------------------------------

#' Load exemptions. Entries: {variable, reason, survey (opt), wave (opt)}.
#' A reasonless entry is a config error — the same rule Layer 7 applies, so an
#' exemption can never be a silent mute.
load_oob_exemptions <- function(path = here::here(.EXEMPTIONS_PATH)) {
  if (!file.exists(path)) return(list(entries = list(), error = NULL))
  y <- tryCatch(yaml::read_yaml(path), error = function(e) e)
  if (inherits(y, "error")) {
    return(list(entries = list(),
                error = sprintf("unreadable exemptions file: %s", conditionMessage(y))))
  }
  entries <- y$exempt_events %||% list()
  for (i in seq_along(entries)) {
    e <- entries[[i]]
    if (is.null(e$variable) || !nzchar(as.character(e$variable))) {
      return(list(entries = list(),
                  error = sprintf("exemption %d has no `variable`", i)))
    }
    if (is.null(e$reason) || !nzchar(trimws(as.character(e$reason)))) {
      return(list(entries = list(),
                  error = sprintf("exemption for `%s` has no `reason`", e$variable)))
    }
  }
  list(entries = entries, error = NULL)
}

.match_exemption <- function(entries, survey, variable, wave) {
  for (e in entries) {
    if (as.character(e$variable) != variable) next
    if (!is.null(e$survey) && as.character(e$survey) != survey) next
    if (!is.null(e$wave) && !(wave %in% as.character(e$wave))) next
    return(trimws(as.character(e$reason)))
  }
  NA_character_
}


# ---------------------------------------------------------------------------
# Core: triage a log data.frame
# ---------------------------------------------------------------------------

.OOB_LOG_COLS <- c("variable", "wave", "n_oob", "obs_min", "obs_max",
                   "valid_min", "valid_max")

#' Triage an out-of-range log.
#'
#' @param log_df data.frame with the engine's oob_log columns.
#' @param spec_ctx Output of load_spec_context().
#' @param exemptions List of exemption entries.
#' @param survey Survey slug (for exemption matching).
#' @return data.frame with class/status/remedy columns appended.
triage_oob_log <- function(log_df, spec_ctx = NULL, exemptions = list(),
                           survey = NA_character_,
                           escalate_n = 30L, bulk_n = 50L) {

  spec_ctx <- spec_ctx %||% list(types = character(0), var_missing = list(),
                                 survey_missing = numeric(0))

  empty <- data.frame(
    survey = character(0), variable = character(0), wave = character(0),
    n_oob = integer(0), obs_min = numeric(0), obs_max = numeric(0),
    valid_min = numeric(0), valid_max = numeric(0),
    class = character(0), status = character(0),
    remedy = character(0), exempt_reason = character(0),
    stringsAsFactors = FALSE
  )
  if (is.null(log_df) || nrow(log_df) == 0L) return(empty)

  missing_cols <- setdiff(.OOB_LOG_COLS, names(log_df))
  if (length(missing_cols) > 0L) {
    stop(sprintf("oob log is missing column(s): %s",
                 paste(missing_cols, collapse = ", ")), call. = FALSE)
  }

  out <- vector("list", nrow(log_df))
  for (i in seq_len(nrow(log_df))) {
    r <- log_df[i, ]
    vid  <- as.character(r$variable)
    wave <- as.character(r$wave)

    vtype <- .get_named(spec_ctx$types, vid, "ordinal")
    # Codes declared missing on OTHER variables in this survey. The engine
    # applies this variable's own codes BEFORE the range check
    # (harmonize.R:200), so anything reaching the log is by construction not
    # declared here — subtracting its own set keeps the evidence honest.
    own <- .get_named(spec_ctx$var_missing, vid, numeric(0))
    elsewhere_all <- setdiff(spec_ctx$survey_missing, own)
    elsewhere <- elsewhere_all[elsewhere_all < 0 |
                               abs(elsewhere_all) >= .SENTINEL_SHAPE_MIN]

    cls <- classify_oob_event(
      obs_min = as.numeric(r$obs_min), obs_max = as.numeric(r$obs_max),
      valid_min = as.numeric(r$valid_min), valid_max = as.numeric(r$valid_max),
      var_type = vtype, declared_elsewhere = elsewhere
    )
    status <- grade_oob_event(cls, r$n_oob, escalate_n, bulk_n)
    reason <- NA_character_

    # Spec-declared intent outranks the grade: the spec already says this drop
    # is deliberate, and validate_coverage() already honours the same field.
    dstat <- .declared_drop_status(spec_ctx$declared_drops, vid, wave,
                                   as.numeric(r$obs_min), as.numeric(r$obs_max))
    if (dstat == "full") {
      status <- "ok_declared"
      reason <- "declared intentional drop (qc.coverage_missing_codes)"
    } else if (dstat == "partial" && status == "error") {
      status <- "warn"
      reason <- paste("span endpoints declared intentional; interior values",
                      "unverifiable (engine logs only n/min/max)")
    }

    if (is.na(reason)) {
      reason <- .match_exemption(exemptions, survey, vid, wave)
      if (!is.na(reason) && status == "error") status <- "ok_exempt"
    }

    out[[i]] <- data.frame(
      survey = survey, variable = vid, wave = wave,
      n_oob = as.integer(r$n_oob),
      obs_min = as.numeric(r$obs_min), obs_max = as.numeric(r$obs_max),
      valid_min = as.numeric(r$valid_min), valid_max = as.numeric(r$valid_max),
      class = cls, status = status,
      remedy = unname(.REMEDY[cls] %||% ""),
      exempt_reason = reason,
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, out)
}


# ---------------------------------------------------------------------------
# Per-survey runner
# ---------------------------------------------------------------------------

.oob_log_path <- function(survey) here::here("outputs", survey, "oob_log.csv")

#' Run the triage for one survey and write audit/reports/<survey>/03-oob.csv.
#'
#' @return list(status, n_error, n_warn, n_ok, n_rows, rows, message)
run_oob_triage <- function(survey, log_path = NULL, exemptions = NULL,
                           spec_ctx = NULL, write_report = TRUE,
                           escalate_n = 30L, bulk_n = 50L) {

  log_path <- log_path %||% .oob_log_path(survey)

  # A MISSING log is not a pass: it means the pipeline never ran with logging
  # wired, so nothing is known. An EMPTY log (header only) is a real clean bill.
  if (!file.exists(log_path)) {
    return(list(status = "skip", n_error = 0L, n_warn = 0L, n_ok = 0L,
                n_rows = 0L, rows = NULL,
                message = sprintf("no oob log at %s — pipeline not run with logging",
                                  log_path)))
  }

  log_df <- tryCatch(
    utils::read.csv(log_path, stringsAsFactors = FALSE),
    error = function(e) e
  )
  if (inherits(log_df, "error")) {
    return(list(status = "config_error", n_error = 0L, n_warn = 0L, n_ok = 0L,
                n_rows = 0L, rows = NULL,
                message = sprintf("unreadable log: %s", conditionMessage(log_df))))
  }

  if (is.null(exemptions)) {
    ex <- load_oob_exemptions()
    if (!is.null(ex$error)) {
      return(list(status = "config_error", n_error = 0L, n_warn = 0L, n_ok = 0L,
                  n_rows = 0L, rows = NULL, message = ex$error))
    }
    exemptions <- ex$entries
  }

  if (is.null(spec_ctx)) spec_ctx <- load_spec_context(survey)

  rows <- tryCatch(
    triage_oob_log(log_df, spec_ctx, exemptions, survey, escalate_n, bulk_n),
    error = function(e) e
  )
  if (inherits(rows, "error")) {
    return(list(status = "config_error", n_error = 0L, n_warn = 0L, n_ok = 0L,
                n_rows = 0L, rows = NULL, message = conditionMessage(rows)))
  }

  if (write_report) {
    rep_dir <- here::here("audit", "reports", survey)
    dir.create(rep_dir, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(rows, file.path(rep_dir, "03-oob.csv"), row.names = FALSE)
  }

  n_error <- sum(rows$status == "error")
  n_warn  <- sum(rows$status == "warn")
  n_ok    <- sum(rows$status %in% c("ok_exempt", "ok_declared"))

  status <- if (n_error > 0L) "fail" else if (n_warn > 0L) "warn" else "ok"

  list(
    status = status,
    n_error = as.integer(n_error), n_warn = as.integer(n_warn),
    n_ok = as.integer(n_ok), n_rows = nrow(rows), rows = rows,
    message = if (nrow(rows) == 0L) "no out-of-range events" else
      sprintf("%d event(s): %d error, %d warn, %d declared/exempt",
              nrow(rows), n_error, n_warn, n_ok)
  )
}


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

.print_survey_result <- function(survey, res, quiet = FALSE) {
  cat(sprintf("\n=== %s — %s\n", survey, res$message))
  if (is.null(res$rows) || nrow(res$rows) == 0L) return(invisible(NULL))

  show <- res$rows
  if (quiet) show <- show[show$status == "error", , drop = FALSE]
  if (nrow(show) == 0L) return(invisible(NULL))

  show <- show[order(factor(show$status,
                            levels = c("error", "warn", "ok_declared", "ok_exempt")),
                     -show$n_oob), , drop = FALSE]
  for (i in seq_len(nrow(show))) {
    r <- show[i, ]
    code <- if (r$obs_min == r$obs_max) format(r$obs_min) else
      sprintf("%s..%s", r$obs_min, r$obs_max)
    cat(sprintf("  %-9s %-28s %-8s %7d x %-10s [valid %s-%s]  %s\n",
                toupper(r$status), r$variable, r$wave, r$n_oob, code,
                r$valid_min, r$valid_max, r$class))
    if (r$status == "error") cat(sprintf("            -> %s\n", r$remedy))
  }
  invisible(NULL)
}

.main <- function() {
  args <- commandArgs(trailingOnly = TRUE)

  if ("--help" %in% args || "-h" %in% args) {
    cat("Usage: Rscript src/r/audit/03_oob_triage.R [--survey <slug> | --all-surveys] [--quiet]\n\n",
        "Triages outputs/<survey>/oob_log.csv — the record of values the harmonize\n",
        "engine coerced to NA for falling outside qc.valid_range. Writes\n",
        "audit/reports/<survey>/03-oob.csv.\n\n",
        "Surveys: ", paste(.OOB_SURVEYS, collapse = ", "), "\n",
        "Exit: 0 clean | 1 error row(s) | 2 config error\n", sep = "")
    quit(status = 0)
  }

  quiet <- "--quiet" %in% args
  targets <- if ("--all-surveys" %in% args) {
    .OOB_SURVEYS
  } else {
    i <- match("--survey", args)
    if (is.na(i) || is.na(args[i + 1L])) {
      cat("ERROR: pass --survey <slug> or --all-surveys (see --help)\n")
      quit(status = 2)
    }
    s <- args[i + 1L]
    if (!(s %in% .OOB_SURVEYS)) {
      cat(sprintf("ERROR: unknown survey '%s'. Known: %s\n",
                  s, paste(.OOB_SURVEYS, collapse = ", ")))
      quit(status = 2)
    }
    s
  }

  tot_err <- 0L; tot_warn <- 0L; tot_events <- 0L; tot_deleted <- 0L
  cfg_error <- FALSE

  for (s in targets) {
    res <- run_oob_triage(s)
    if (res$status == "config_error") {
      cat(sprintf("\n=== %s — CONFIG ERROR: %s\n", s, res$message))
      cfg_error <- TRUE
      next
    }
    .print_survey_result(s, res, quiet)
    tot_err <- tot_err + res$n_error
    tot_warn <- tot_warn + res$n_warn
    tot_events <- tot_events + res$n_rows
    if (!is.null(res$rows) && nrow(res$rows) > 0L) {
      tot_deleted <- tot_deleted + sum(res$rows$n_oob, na.rm = TRUE)
    }
  }

  cat(sprintf("\n---\n%d event(s) across %d survey(s): %d error, %d warn — %s value(s) coerced to NA\n",
              tot_events, length(targets), tot_err, tot_warn,
              format(tot_deleted, big.mark = ",")))

  if (cfg_error) quit(status = 2)
  quit(status = if (tot_err > 0L) 1L else 0L)
}

if (sys.nframe() == 0L && !interactive()) .main()
