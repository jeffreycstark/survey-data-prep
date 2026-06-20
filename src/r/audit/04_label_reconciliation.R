#!/usr/bin/env Rscript
# src/r/audit/04_label_reconciliation.R
#
# Layer 4 — Label-reconciliation check (audit ticket D5; the "wrong-fn" detector).
#
# Catches the failure mode that the strict-reversal check (04_strict_reversal.R)
# and the transformation invariant (validation.R) are blind to: a variable whose
# recoding function RAN CLEANLY but was the WRONG function, so the stored data
# points the OPPOSITE direction from its own documented scale.labels.
#
# This is exactly how two ABS bugs shipped (system_deserves_support and the
# dem_* democracy-supply battery, both 2026-06-20): raw value labels put the
# positive pole at code 1 ("Strongly agree"), the spec's scale.labels declared
# the positive pole at code 4 ("Strongly agree"), and the chosen fn was a
# non-reversing safe_4pt_none — so the harmonized output stored every respondent
# backwards relative to its labels. It passed range/type/completeness/reversal-
# fidelity because safe_4pt_none did its (identity) job perfectly.
#
# Mechanism (deterministic, no correlations, no external construct):
#   1. RAW direction  : classify the raw .sav value labels into poles and find
#                       which END (low/high code) holds the positive pole.
#   2. REALIZED output: apply the declared fn's direction (reverses? from the
#                       recoding registry) to that end. A monotone non-reversing
#                       fn preserves the end; a reversing fn flips it.
#   3. DECLARED output: classify the spec's scale.labels and find which end the
#                       positive pole is declared to sit at.
#   4. COMPARE        : realized end must equal declared end. Mismatch => ERROR.
#
# Ground truth for the RAW side is the .sav value labels — NOT the verbatim
# question dictionary, whose response_scale records the INTENDED (post-harmonize)
# direction and would have endorsed the bug.
#
# Division of labor (state explicitly):
#   strict-reversal      = "did the fn run cleanly?"   (mechanical fidelity)
#   label-reconciliation = "was choosing that fn correct?" (direction correctness)
# Together they close the loop for every monotone, label-bearing variable.
#
# Public API:
#   classify_pole(label_text, lexicon)        -- pure pole classifier
#   find_pole_end(labels_named, lexicon)      -- "low" | "high" | NA + detail
#   reconcile_one(...)                         -- one (var, wave) row (testable)
#   compute_label_reconciliation(survey, ...)  -- tibble for a survey
#   run_label_reconciliation(survey, ...)      -- write CSV + summary
#
# CLI:
#   Rscript src/r/audit/04_label_reconciliation.R --survey abs
#   Rscript src/r/audit/04_label_reconciliation.R --all-surveys
#
# Status meanings:
#   ok    — realized output direction matches declared scale.labels
#   error — realized output direction CONTRADICTS declared labels (bug)
#   skip  — cannot anchor (no raw labels / no declared labels / ambiguous /
#           non-reversible fn / nominal / unknown fn). Always carries a reason.
#
# Exit code 0 if no errors; 1 if any error rows present.
#
# v1 (Phase 1): ABS, English lexicon, method ∈ {identity, r_function}. Korean
# lexicon, verbatim-CSV fallback for the declared side, and method=recode are
# Phase 4 (see skip reasons `label_locale_unsupported`, `no_declared_labels`,
# `recode_not_yet_checked`).
#
# See audit/01-audit-framework.md §Layer 4 and the plan at
#   ~/.claude/plans/so-how-do-i-glowing-meteor.md

suppressPackageStartupMessages({
  library(yaml)
  library(here)
  library(haven)
  library(dplyr)
  library(tibble)
})

`%||%` <- function(a, b) if (!is.null(a)) a else b

# Reuse the engine-mirroring resolver (.resolve_wave_rule) from the strict-
# reversal script so the two Layer-4 checks resolve wave rules identically.
if (!exists(".resolve_wave_rule", mode = "function")) {
  source(here::here("src", "r", "audit", "04_strict_reversal.R"))
}


# ===========================================================================
# Polarity lexicon (English, Phase 1). Each family lists positive-pole and
# negative-pole regex patterns. Word boundaries keep "disagree" out of
# "\\bagree\\b". Patterns match the EXTREMES and the bare poles; that is
# sufficient to establish which end of a monotone scale is positive.
# ===========================================================================
default_polarity_lexicon <- function() {
  list(
    agree     = list(pos = c("\\bagree\\b"),
                     neg = c("\\bdisagree\\b")),
    satisfied = list(pos = c("\\bsatisfied\\b", "\\bsatisfaction\\b"),
                     neg = c("\\bdissatisfied\\b", "not.*satisfied")),
    trust     = list(pos = c("great deal", "\\ba lot\\b", "quite a lot",
                             "trust.*completely", "\\bfully trust"),
                     neg = c("not at all", "none at all", "no trust",
                             "do not trust", "don'?t trust", "not very much")),
    amount    = list(pos = c("a great deal", "\\ba lot\\b", "very much",
                             "\\bgood deal\\b"),
                     neg = c("not at all", "\\bnone\\b", "very little",
                             "\\bnot much\\b")),
    quality   = list(pos = c("very good", "\\bgood\\b", "much better",
                             "\\bbetter\\b"),
                     neg = c("very bad", "\\bbad\\b", "much worse",
                             "\\bworse\\b")),
    proud     = list(pos = c("\\bproud\\b"),
                     neg = c("\\bashamed\\b", "not.*proud")),
    frequency = list(pos = c("\\balways\\b", "\\boften\\b", "frequently"),
                     neg = c("\\bnever\\b", "\\brarely\\b", "\\bseldom\\b"))
  )
}

# Labels that denote missing / non-substantive responses; excluded from polarity.
.MISSING_LABEL_PATTERNS <- c(
  "missing", "don'?t know", "do not know", "can'?t choose", "cannot choose",
  "decline", "refus", "no answer", "not applicable", "\\bn/?a\\b",
  "don'?t understand", "do not understand", "not asked", "no response",
  "haven'?t thought", "not sure"
)

.norm_label <- function(s) {
  s <- tolower(as.character(s))
  s <- gsub("[[:punct:]]", " ", s)
  s <- gsub("\\s+", " ", s)
  trimws(s)
}

.match_any <- function(s, patterns) {
  any(vapply(patterns, function(p) grepl(p, s, perl = TRUE), logical(1)))
}

# Classify a single label string -> "pos" | "neg" | "missing" | "unknown".
classify_pole <- function(label_text, lexicon = default_polarity_lexicon()) {
  s <- .norm_label(label_text)
  if (!nzchar(s)) return("unknown")
  if (.match_any(s, .MISSING_LABEL_PATTERNS)) return("missing")
  hit_pos <- FALSE; hit_neg <- FALSE
  for (fam in lexicon) {
    if (.match_any(s, fam$neg)) hit_neg <- TRUE
    if (.match_any(s, fam$pos)) hit_pos <- TRUE
  }
  if (hit_pos && !hit_neg) return("pos")
  if (hit_neg && !hit_pos) return("neg")
  "unknown"  # both (contradiction) or neither
}

# Given a named-numeric vector (names = label text, values = numeric codes),
# determine which END of the scale holds the positive pole.
# Returns list(end = "low"|"high"|NA, pos_codes, neg_codes, reason).
find_pole_end <- function(labels_named, lexicon = default_polarity_lexicon()) {
  if (is.null(labels_named) || length(labels_named) < 2) {
    return(list(end = NA_character_, pos_codes = numeric(0),
                neg_codes = numeric(0), reason = "too_few_labels"))
  }
  texts <- names(labels_named)
  codes <- suppressWarnings(as.numeric(labels_named))
  pos_codes <- numeric(0); neg_codes <- numeric(0)
  for (i in seq_along(codes)) {
    if (is.na(codes[i])) next
    p <- classify_pole(texts[i], lexicon)
    if (p == "pos") pos_codes <- c(pos_codes, codes[i])
    if (p == "neg") neg_codes <- c(neg_codes, codes[i])
  }
  if (length(pos_codes) == 0 || length(neg_codes) == 0) {
    return(list(end = NA_character_, pos_codes = pos_codes,
                neg_codes = neg_codes, reason = "no_classifiable_poles"))
  }
  if (max(pos_codes) < min(neg_codes)) {
    return(list(end = "low", pos_codes = pos_codes,
                neg_codes = neg_codes, reason = "ok"))
  }
  if (min(pos_codes) > max(neg_codes)) {
    return(list(end = "high", pos_codes = pos_codes,
                neg_codes = neg_codes, reason = "ok"))
  }
  list(end = NA_character_, pos_codes = pos_codes,
       neg_codes = neg_codes, reason = "poles_overlap")
}

.flip_end <- function(e) if (identical(e, "low")) "high" else if (identical(e, "high")) "low" else NA_character_

# Convert a spec scale.labels list (code-string -> text) to the same
# named-numeric form as haven value labels (names = text, values = codes).
.spec_labels_to_named <- function(spec_labels) {
  if (is.null(spec_labels) || length(spec_labels) == 0) return(NULL)
  codes <- suppressWarnings(as.numeric(names(spec_labels)))
  texts <- as.character(unlist(spec_labels, use.names = FALSE))
  keep <- !is.na(codes) & nzchar(texts)
  if (!any(keep)) return(NULL)
  setNames(codes[keep], texts[keep])
}


# ===========================================================================
# Registry index: full per-fn rows (reverses / scales / flags). Parallel to
# load_reverser_set() in 04_strict_reversal.R but returns the whole row.
# ===========================================================================
.lr_registry_cache <- new.env(parent = emptyenv())

load_registry_index <- function(
  registry_path = here::here("src", "r", "utils", "recoding_registry.yml")
) {
  if (!is.null(.lr_registry_cache$idx)) return(.lr_registry_cache$idx)
  if (!file.exists(registry_path)) {
    stop(sprintf("recoding registry not found at %s", registry_path), call. = FALSE)
  }
  reg <- yaml::read_yaml(registry_path)
  idx <- list()
  for (e in reg) {
    if (is.null(e$fn)) next
    idx[[e$fn]] <- list(
      fn = e$fn,
      reverses = isTRUE(e$reverses),
      monotonic = isTRUE(e$monotonic),
      requires_data = isTRUE(e$requires_data),
      input_scale = e$input_scale,
      output_scale = e$output_scale
    )
  }
  .lr_registry_cache$idx <- idx
  idx
}


# ===========================================================================
# Per-survey raw VALUE-LABEL loader. Returns, for a (wave, source_var), a
# named-numeric vector (names = label text, values = codes) from the .sav.
# ABS: the cached data/processed/w<N>.rds retains haven value labels.
# ===========================================================================
.label_cache <- new.env(parent = emptyenv())

.SURVEY_LABEL_LOADER <- list(
  abs = function(wave_key) {
    if (!grepl("^w[0-9]+$", wave_key)) return(NULL)
    n <- sub("^w", "", wave_key)
    p <- here::here("data", "processed", paste0("w", n, ".rds"))
    if (!file.exists(p)) return(NULL)
    ck <- paste0("abs::", wave_key)
    if (is.null(.label_cache[[ck]])) .label_cache[[ck]] <- readRDS(p)
    .label_cache[[ck]]
  }
)

# Extract the value-label vector for one source variable from a loaded wave df.
.get_value_labels <- function(wave_df, src) {
  if (is.null(wave_df) || is.null(src) || !src %in% names(wave_df)) return(NULL)
  lab <- attr(wave_df[[src]], "labels")
  if (is.null(lab) || length(lab) == 0) return(NULL)
  # haven stores names = label text, values = codes — exactly our convention.
  lab
}


# ===========================================================================
# Reconcile ONE (variable, wave). raw_labels / spec_labels are parameters so
# this is unit-testable with synthetic inputs (no .sav read).
# ===========================================================================
reconcile_one <- function(survey, var_id, wave_key, source_var, fn_name,
                          fn_entry, raw_labels, spec_labels,
                          var_type = NULL,
                          lexicon = default_polarity_lexicon()) {
  mk <- function(status, reason, message,
                 raw_end = NA_character_, realized_end = NA_character_,
                 declared_end = NA_character_, reverses = NA) {
    tibble(
      survey = survey, variable = var_id, wave = wave_key,
      source_var = source_var %||% NA_character_, fn = fn_name %||% NA_character_,
      reverses = reverses, raw_pos_end = raw_end,
      realized_pos_end = realized_end, declared_pos_end = declared_end,
      declared_source = "scale_labels",
      label_locale = "en", status = status, reason = reason, message = message
    )
  }

  if (identical(var_type, "nominal")) {
    return(mk("skip", "nominal_no_polarity", "nominal variable — no pole"))
  }
  # Resolve fn direction.
  if (is.null(fn_entry)) {
    return(mk("skip", "unknown_fn",
              sprintf("fn '%s' not in recoding registry", fn_name %||% "NULL")))
  }
  if (isTRUE(fn_entry$requires_data)) {
    return(mk("skip", "conditional_fn",
              sprintf("fn '%s' is data-conditional; delegated to anchor check", fn_name),
              reverses = fn_entry$reverses))
  }
  if (!isTRUE(fn_entry$monotonic)) {
    return(mk("skip", "non_monotonic_fn",
              sprintf("fn '%s' not monotone; cannot map ends", fn_name),
              reverses = fn_entry$reverses))
  }

  # RAW side (ground truth).
  raw <- find_pole_end(raw_labels, lexicon)
  if (is.na(raw$end)) {
    return(mk("skip", paste0("unanchorable_raw:", raw$reason),
              sprintf("raw labels not pole-anchorable (%s)", raw$reason),
              reverses = fn_entry$reverses))
  }
  # DECLARED side.
  spec_named <- .spec_labels_to_named(spec_labels)
  if (is.null(spec_named)) {
    return(mk("skip", "no_declared_labels",
              "no scale.labels (verbatim fallback is Phase 4)",
              raw_end = raw$end, reverses = fn_entry$reverses))
  }
  decl <- find_pole_end(spec_named, lexicon)
  if (is.na(decl$end)) {
    return(mk("skip", paste0("no_declared_direction:", decl$reason),
              sprintf("scale.labels not pole-anchorable (%s)", decl$reason),
              raw_end = raw$end, reverses = fn_entry$reverses))
  }

  realized_end <- if (isTRUE(fn_entry$reverses)) .flip_end(raw$end) else raw$end

  if (identical(realized_end, decl$end)) {
    mk("ok", "ok_match",
       sprintf("direction consistent (raw pos=%s, fn %s, declared pos=%s)",
               raw$end, if (isTRUE(fn_entry$reverses)) "reverses" else "keeps",
               decl$end),
       raw_end = raw$end, realized_end = realized_end,
       declared_end = decl$end, reverses = fn_entry$reverses)
  } else {
    mk("error", "opposite_labels",
       sprintf(paste0("STORED OPPOSITE ITS LABELS: raw positive pole at %s end, ",
                      "fn %s -> output positive pole at %s end, but scale.labels ",
                      "declare positive pole at %s end"),
               raw$end, if (isTRUE(fn_entry$reverses)) "reverses" else "keeps",
               realized_end, decl$end),
       raw_end = raw$end, realized_end = realized_end,
       declared_end = decl$end, reverses = fn_entry$reverses)
  }
}


# ===========================================================================
# Survey driver.
# ===========================================================================
compute_label_reconciliation <- function(survey, spec_files = NULL,
                                         registry_index = NULL,
                                         lexicon = default_polarity_lexicon()) {
  if (is.null(registry_index)) registry_index <- load_registry_index()

  label_loader <- .SURVEY_LABEL_LOADER[[survey]]
  if (is.null(label_loader)) {
    return(tibble(
      survey = survey, variable = NA_character_, wave = NA_character_,
      source_var = NA_character_, fn = NA_character_, reverses = NA,
      raw_pos_end = NA_character_, realized_pos_end = NA_character_,
      declared_pos_end = NA_character_, declared_source = NA_character_,
      label_locale = NA_character_, status = "skip",
      reason = "no_label_loader",
      message = sprintf("no value-label loader for survey '%s' (Phase 1 = ABS)", survey)
    ))
  }

  if (is.null(spec_files)) {
    if (!exists("list_survey_specs", mode = "function")) {
      source(here::here("src", "r", "utils", "spec_discovery.R"))
    }
    spec_files <- list_survey_specs(survey)
  }

  rows <- list()
  for (spec_path in spec_files) {
    spec <- yaml::read_yaml(spec_path)
    for (v in spec$variables %||% list()) {
      wave_keys <- names(v$source %||% list())
      for (wave_key in wave_keys) {
        src <- v$source[[wave_key]]
        if (is.null(src)) next  # explicit null -> skipped wave

        rule <- .resolve_wave_rule(v, wave_key)
        method <- rule$method %||% "identity"

        # Resolve fn_entry by method.
        if (identical(method, "identity")) {
          fn_name <- "identity"
          fn_entry <- list(fn = "identity", reverses = FALSE, monotonic = TRUE,
                           requires_data = FALSE)
        } else if (identical(method, "r_function")) {
          fn_name <- rule$fn %||% ""
          fn_entry <- registry_index[[fn_name]]  # may be NULL -> unknown_fn
        } else if (identical(method, "recode")) {
          rows[[length(rows) + 1]] <- reconcile_one(
            survey, v$id, wave_key, src, "recode", NULL, NULL, NULL,
            var_type = v$type)
          rows[[length(rows)]]$reason <- "recode_not_yet_checked"
          rows[[length(rows)]]$message <- "method=recode (Phase 4 extension)"
          next
        } else {
          rows[[length(rows) + 1]] <- reconcile_one(
            survey, v$id, wave_key, src, method, NULL, NULL, NULL,
            var_type = v$type)
          rows[[length(rows)]]$reason <- "derived_not_reconcilable"
          rows[[length(rows)]]$message <- sprintf("method=%s not reconcilable", method)
          next
        }

        wave_df <- label_loader(wave_key)
        raw_labels <- .get_value_labels(wave_df, src)

        rows[[length(rows) + 1]] <- reconcile_one(
          survey = survey, var_id = v$id, wave_key = wave_key, source_var = src,
          fn_name = fn_name, fn_entry = fn_entry,
          raw_labels = raw_labels, spec_labels = v$scale$labels,
          var_type = v$type, lexicon = lexicon
        )
      }
    }
  }

  if (length(rows) == 0) {
    return(tibble(
      survey = character(0), variable = character(0), wave = character(0),
      source_var = character(0), fn = character(0), reverses = logical(0),
      raw_pos_end = character(0), realized_pos_end = character(0),
      declared_pos_end = character(0), declared_source = character(0),
      label_locale = character(0), status = character(0),
      reason = character(0), message = character(0)
    ))
  }
  bind_rows(rows)
}


# ===========================================================================
# Run + write CSV + summary.
# ===========================================================================
run_label_reconciliation <- function(survey, output_dir = NULL) {
  if (is.null(output_dir)) output_dir <- here::here("audit", "reports", survey)
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  results <- compute_label_reconciliation(survey)
  csv_path <- file.path(output_dir, "04-label-reconciliation.csv")
  write.csv(results, csv_path, row.names = FALSE)

  status_levels <- c("ok", "error", "skip")
  counts <- if (nrow(results) > 0) {
    as.list(table(factor(results$status, levels = status_levels)))
  } else setNames(as.list(rep(0L, 3)), status_levels)

  cat(sprintf("\n[label reconciliation] survey=%s\n", survey))
  cat(sprintf("  total checks: %d (ok=%d, error=%d, skip=%d)\n",
              nrow(results), counts$ok %||% 0, counts$error %||% 0, counts$skip %||% 0))
  cat(sprintf("  CSV: %s\n", csv_path))

  if ((counts$skip %||% 0) > 0) {
    sk <- results[results$status == "skip", , drop = FALSE]
    by_reason <- sort(table(sub(":.*$", "", sk$reason)), decreasing = TRUE)
    cat("  skip reasons: ",
        paste(sprintf("%s=%d", names(by_reason), as.integer(by_reason)), collapse = ", "),
        "\n", sep = "")
  }

  errs <- results[results$status == "error", , drop = FALSE]
  if (nrow(errs) > 0) {
    cat(sprintf("\n  *** %d ERROR row(s) — stored opposite documented labels:\n", nrow(errs)))
    print(as.data.frame(errs[, c("variable", "wave", "fn", "raw_pos_end",
                                 "realized_pos_end", "declared_pos_end")]),
          row.names = FALSE)
    cat("\n  -> Each error: the harmonized variable points opposite its own\n")
    cat("     scale.labels. Fix the fn (reverse <-> non-reverse) or the labels.\n\n")
  }
  invisible(results)
}

run_all_surveys <- function() {
  supported <- names(.SURVEY_LABEL_LOADER)
  all_results <- list()
  for (survey in supported) all_results[[survey]] <- run_label_reconciliation(survey)
  bind_rows(all_results)
}


# ===========================================================================
# CLI.
# ===========================================================================
.parse_cli_args <- function(argv) {
  out <- list(survey = NULL, all_surveys = FALSE, output_dir = NULL)
  i <- 1
  while (i <= length(argv)) {
    a <- argv[i]
    if (a == "--survey")      { out$survey      <- argv[i + 1]; i <- i + 2; next }
    if (a == "--all-surveys") { out$all_surveys <- TRUE;        i <- i + 1; next }
    if (a == "--output-dir")  { out$output_dir  <- argv[i + 1]; i <- i + 2; next }
    if (a %in% c("-h", "--help")) {
      cat("Usage: Rscript src/r/audit/04_label_reconciliation.R\n",
          "         (--survey <name> | --all-surveys) [--output-dir <path>]\n",
          "\nReconcile raw .sav value-label polarity (transformed by the\n",
          "declared fn) against the spec's scale.labels. error = stored\n",
          "opposite its labels. Exit 0 if no errors, 1 otherwise.\n", sep = "")
      quit(status = 0)
    }
    stop(sprintf("unknown argument: %s", a), call. = FALSE)
  }
  if (is.null(out$survey) && !out$all_surveys) {
    stop("usage: --survey <name> OR --all-surveys (see --help)", call. = FALSE)
  }
  out
}

if (sys.nframe() == 0L) {
  argv <- commandArgs(trailingOnly = TRUE)
  if (length(argv) > 0) {
    args <- .parse_cli_args(argv)
    results <- if (args$all_surveys) run_all_surveys() else
      run_label_reconciliation(args$survey, output_dir = args$output_dir)
    n_err <- sum(results$status == "error", na.rm = TRUE)
    if (n_err > 0) quit(status = 1) else quit(status = 0)
  }
}
