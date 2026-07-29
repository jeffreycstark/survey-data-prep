#!/usr/bin/env Rscript
# src/r/audit/07_module_coverage.R
#
# Layer 7 — Module-coverage meta-check.
#
# Every other audit layer answers "is this survey's data right?". This one
# answers the prior question the system never asked: "is this module being
# audited AT ALL?"
#
# THE GAP THIS CLOSES
# -------------------
# The audit system enumerates its targets from two hardcoded vectors —
# run_all.R's .SUPPORTED_SURVEYS and 06_check_freshness.R's .FRESHNESS_SURVEYS —
# synchronised only by a comment reading "kept in sync with run_all.R". Nothing
# compared either vector against the modules actually present in
# src/r/data_prep_modules/. A module added after those vectors were written got
# ZERO coverage, silently.
#
# That is worse than a missing check. 06_check_freshness.R is the documented
# pre-flight ("run this before consuming data", docs/QA.md §6d), so it returned
# a clean bill of health while never having looked at the module — a FALSE
# ALL-CLEAR, the most dangerous QA failure mode there is.
#
# Found 2026-07-29: 4 of 15 modules unregistered — marpor, unga, unsc (added
# 2026-07-28) and vdem, invisible since it was scaffolded — shipping 8 live
# artifacts to data/processed/ between them.
#
# WHAT IT CHECKS
# --------------
#   1. LIST DRIFT (hard). .SUPPORTED_SURVEYS and .FRESHNESS_SURVEYS must be
#      identical. Today they are; nothing enforced it, and a one-sided edit
#      would silently drop a survey from the freshness pre-flight only.
#   2. MODULE REGISTRATION (hard). Every module directory must be registered or
#      exempted in src/config/_audit/module_coverage_exemptions.yml.
#   3. RESIDUAL COVERAGE (soft). An exempted module still has to satisfy its
#      declared `still_required` checks. Reported, not fatal, so the gap stays
#      visible instead of being closed by assertion.
#
# Pure metadata — no data load, so it is fast and safe to run anywhere.
#
# Usage:
#   Rscript src/r/audit/07_module_coverage.R           # report
#   Rscript src/r/audit/07_module_coverage.R --strict  # non-zero exit on soft findings
#
# Exit codes: 0 ok (soft findings allowed unless --strict) | 1 hard finding | 2 config error

suppressPackageStartupMessages({
  library(yaml)
})

MODULE_DIR      <- "src/r/data_prep_modules"
EXEMPTIONS_PATH <- "src/config/_audit/module_coverage_exemptions.yml"
RUN_ALL_PATH    <- "src/r/audit/run_all.R"
FRESHNESS_PATH  <- "src/r/audit/06_check_freshness.R"

# Directories under MODULE_DIR that are not pipeline modules.
NON_MODULE_DIRS <- c("extractors")

#' Extract a character vector literal (e.g. `.SUPPORTED_SURVEYS <- c(...)`)
#' from an R source file without evaluating it.
extract_vector <- function(path, symbol) {
  if (!file.exists(path)) return(NULL)
  x <- readLines(path, warn = FALSE)
  i <- grep(paste0("^\\s*", symbol, "\\s*<-\\s*c\\("), x)[1]
  if (is.na(i)) return(NULL)
  j <- i - 1 + grep("^\\s*\\)", x[i:length(x)])[1]
  if (is.na(j)) return(NULL)
  blob <- paste(x[i:j], collapse = " ")
  vals <- regmatches(blob, gregexpr('"[^"]+"', blob))[[1]]
  sort(gsub('"', "", vals))
}

list_modules <- function(root = MODULE_DIR) {
  if (!dir.exists(root)) return(character(0))
  sort(setdiff(basename(list.dirs(root, recursive = FALSE)), NON_MODULE_DIRS))
}

#' Run the module-coverage check.
#'
#' Returns a list with `hard`, `soft` (character vectors of findings) and the
#' resolved inputs, so tests can fault-inject without re-reading the repo.
check_module_coverage <- function(module_dir      = MODULE_DIR,
                                  exemptions_path = EXEMPTIONS_PATH,
                                  run_all_path    = RUN_ALL_PATH,
                                  freshness_path  = FRESHNESS_PATH,
                                  modules         = NULL) {

  hard <- character(0)
  soft <- character(0)

  registered <- extract_vector(run_all_path, "\\.SUPPORTED_SURVEYS")
  freshness  <- extract_vector(freshness_path, "\\.FRESHNESS_SURVEYS")

  if (is.null(registered))
    return(list(hard = "could not parse .SUPPORTED_SURVEYS from run_all.R",
                soft = soft, config_error = TRUE))
  if (is.null(freshness))
    return(list(hard = "could not parse .FRESHNESS_SURVEYS from 06_check_freshness.R",
                soft = soft, config_error = TRUE))

  # ── 1. list drift (hard) ──────────────────────────────────────────────────
  # The invariant is SUBSET, not equality: .SUPPORTED_SURVEYS ⊆ .FRESHNESS_SURVEYS.
  #
  # Equality was the original rule and it was wrong. Freshness legitimately
  # covers more than the survey checks do — staleness is the one failure every
  # generated artifact is exposed to, including the non-survey macro panels that
  # have no YAML specs and so cannot be label-reconciled or gated. Those belong
  # in the freshness list and NOT in .SUPPORTED_SURVEYS, which would make
  # run_all attempt survey checks that cannot apply.
  #
  # The dangerous direction is the asymmetric one: a survey that IS audited but
  # is absent from the pre-flight looks covered while its data can silently rot.
  missing_fresh <- setdiff(registered, freshness)
  if (length(missing_fresh)) {
    hard <- c(hard, sprintf(
      paste0("survey(s) in .SUPPORTED_SURVEYS but MISSING from .FRESHNESS_SURVEYS: %s.",
             " They are audited but never staleness-checked — the pre-flight skips",
             " them while every other layer reports them as covered."),
      paste(missing_fresh, collapse = ", ")))
  }

  # Freshness-only entries are legitimate ONLY if registered as exempt modules.
  # An unexplained extra is a typo or a stale entry, and would make --all report
  # SKIP for a survey nobody owns.
  freshness_only <- setdiff(freshness, registered)

  # ── 2. module registration (hard) ─────────────────────────────────────────
  if (is.null(modules)) modules <- list_modules(module_dir)

  ex <- list(exempt_modules = list())
  if (file.exists(exemptions_path)) ex <- yaml::read_yaml(exemptions_path)
  exempt <- vapply(ex$exempt_modules %||% list(),
                   function(e) as.character(e$module), character(1))

  unexplained <- setdiff(freshness_only, exempt)
  if (length(unexplained)) {
    hard <- c(hard, sprintf(
      paste0("entr(y/ies) in .FRESHNESS_SURVEYS with no run_all registration and no",
             " exemption: %s. Either a typo or a stale entry — --all would report",
             " SKIP for something nobody owns."),
      paste(unexplained, collapse = ", ")))
  }

  unregistered <- setdiff(modules, c(registered, exempt))
  if (length(unregistered)) {
    hard <- c(hard, sprintf(
      paste0("%d module(s) have NO audit coverage and no exemption: %s.",
             " Register in run_all.R's .SUPPORTED_SURVEYS (and the freshness list),",
             " or exempt in %s with a reason."),
      length(unregistered), paste(unregistered, collapse = ", "), exemptions_path))
  }

  # An exemption for a module that no longer exists is stale config.
  stale <- setdiff(exempt, modules)
  if (length(stale)) {
    soft <- c(soft, sprintf("exemption listed for module(s) not on disk: %s — stale config",
                            paste(stale, collapse = ", ")))
  }

  # ── 3. residual coverage of exempted modules (soft) ───────────────────────
  for (e in ex$exempt_modules %||% list()) {
    m <- as.character(e$module)
    if (!m %in% modules) next
    if (is.null(e$reason) || !nzchar(trimws(as.character(e$reason)))) {
      hard <- c(hard, sprintf("module '%s' is exempted without a reason", m))
    }
    for (req in as.character(e$still_required %||% character(0))) {
      if (identical(req, "freshness") && !m %in% freshness) {
        soft <- c(soft, sprintf(
          paste0("module '%s' declares freshness still_required but is absent from",
                 " .FRESHNESS_SURVEYS — its artifacts are NOT staleness-checked"), m))
      }
    }
  }

  list(hard = hard, soft = soft, registered = registered,
       modules = modules, exempt = exempt, config_error = FALSE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# ── CLI ─────────────────────────────────────────────────────────────────────
# sys.nframe() == 0L is the house guard (cf. 04_bin_width_parity.R): true only
# when run directly via Rscript, false when source()d. The
# `!interactive() && identical(environment(), globalenv())` form does NOT hold
# that property — it fires on source() too, so the CLI would quit() out of the
# test harness before a single test ran.
if (sys.nframe() == 0L) {
  strict <- "--strict" %in% commandArgs(TRUE)
  r <- check_module_coverage()

  cat("\n── Layer 7: module coverage ──\n")
  if (isTRUE(r$config_error)) {
    cat("  CONFIG ERROR:", r$hard[1], "\n")
    quit(status = 2)
  }

  cat(sprintf("  modules on disk : %d (%s)\n", length(r$modules),
              paste(r$modules, collapse = ", ")))
  cat(sprintf("  registered      : %d | exempted: %d\n",
              length(r$registered), length(r$exempt)))

  if (length(r$hard)) {
    cat("\n  ERROR:\n"); for (h in r$hard) cat("   -", h, "\n")
  }
  if (length(r$soft)) {
    cat("\n  WARN:\n"); for (s in r$soft) cat("   -", s, "\n")
  }
  if (!length(r$hard) && !length(r$soft)) cat("  ✅ every module is registered or exempted\n")

  if (length(r$hard)) quit(status = 1)
  if (strict && length(r$soft)) quit(status = 1)
  quit(status = 0)
}
