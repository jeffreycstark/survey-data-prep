#!/usr/bin/env Rscript
# src/r/audit/99_post_harmonize_gate.R
#
# Layer-4 direction gate for the harmonization pipeline (Phase 5 of the
# harmonization auditor, 2026-07-03).
#
# Runs the three deterministic direction checks against a survey's freshly
# built harmonized output, immediately after 99_create_final_dataset.R:
#
#   1. label reconciliation (04_label_reconciliation.R) — HARD signal.
#      error = a variable is stored opposite its own documented labels
#      (the system_deserves_support / econ_family_income_fair_6pt class).
#   2. battery coherence   (04_battery_coherence.R)     — soft hints.
#   3. anchor coverage     (04_anchor_coverage.R)       — soft coverage metric.
#
# A label-reconciliation error that coincides with a battery-coherence
# negative-correlation hint on the same variable is flagged HIGH-CONFIDENCE.
#
# ENFORCEMENT — report-only by default. The gate always completes and never
# raises in report-only mode (each check runs under its own tryCatch, so a
# crashed check cannot break a pipeline run). Set the environment variable
#   HARMONIZE_AUDIT_GATE=block
# (or call run_post_harmonize_gate(survey, blocking = TRUE)) to make
# label-reconciliation errors stop the pipeline. Per the auditor plan the
# flip to blocking happens only after the known ABS backlog
# (project_abs_label_recon_backlog) is cleared — until then every run prints
# the error count loudly but exits clean.
#
# Public API:
#   run_post_harmonize_gate(survey, blocking = <env>, quiet_checks = TRUE)
#
# CLI:
#   Rscript src/r/audit/99_post_harmonize_gate.R --survey abs
#   Rscript src/r/audit/99_post_harmonize_gate.R --survey abs --block
#
# Exit (CLI): report-only -> always 0; --block -> 1 if any label-recon error.

suppressPackageStartupMessages({
  library(here)
})

# The three check modules (each is CLI-guarded, so sourcing is side-effect
# free). label_reconciliation sources 04_strict_reversal.R for the shared
# wave-rule resolver; battery_coherence sources 04_anchor_diagnostic.R for
# the harmonized loader + correlation helper.
source(here::here("src", "r", "audit", "04_label_reconciliation.R"))
source(here::here("src", "r", "audit", "04_battery_coherence.R"))
source(here::here("src", "r", "audit", "04_anchor_coverage.R"))

`%||%` <- function(a, b) if (!is.null(a)) a else b

.gate_check <- function(label, fun) {
  res <- tryCatch(fun(), error = function(e) {
    cat(sprintf("  [gate] %s CRASHED: %s\n", label, conditionMessage(e)))
    NULL
  })
  res
}

run_post_harmonize_gate <- function(
  survey,
  blocking = identical(Sys.getenv("HARMONIZE_AUDIT_GATE"), "block"),
  quiet_checks = FALSE
) {
  cat(sprintf("\n==== Layer-4 direction gate: %s [%s] ====\n",
              survey, if (blocking) "BLOCKING" else "report-only"))

  run_quiet <- function(fun) {
    if (!quiet_checks) return(fun())
    out <- utils::capture.output(res <- fun())
    res
  }

  lr <- .gate_check("label reconciliation", function()
    run_quiet(function() run_label_reconciliation(survey)))
  bc <- .gate_check("battery coherence", function()
    run_quiet(function() run_battery_coherence(survey)))
  ac <- .gate_check("anchor coverage", function()
    run_quiet(function() run_anchor_coverage(survey)))

  n_err  <- if (is.null(lr)) NA_integer_ else sum(lr$status == "error")
  n_hint <- if (is.null(bc)) NA_integer_ else sum(bc$status == "hint")
  n_unc  <- if (is.null(ac)) NA_integer_ else sum(ac$status == "uncovered")

  # High-confidence overlap: label-recon error AND neg-corr battery hint.
  high_conf <- character(0)
  if (!is.null(lr) && !is.null(bc)) {
    err_vars <- unique(lr$variable[lr$status == "error"])
    hint_vars <- unique(bc$variable[bc$status == "hint" &
                                    !is.na(bc$neg_corr) & bc$neg_corr])
    high_conf <- intersect(err_vars, hint_vars)
  }

  cat(sprintf("\n[gate] %s: label-recon errors=%s | battery hints=%s | uncovered=%s\n",
              survey,
              ifelse(is.na(n_err), "check-crashed", n_err),
              ifelse(is.na(n_hint), "check-crashed", n_hint),
              ifelse(is.na(n_unc), "check-crashed", n_unc)))
  if (length(high_conf) > 0) {
    cat(sprintf("[gate] HIGH-CONFIDENCE direction bugs (error + neg-corr hint): %s\n",
                paste(high_conf, collapse = ", ")))
  }
  if (!is.na(n_err) && n_err > 0) {
    err_vars <- unique(lr$variable[lr$status == "error"])
    cat(sprintf("[gate] variables stored opposite their labels: %s\n",
                paste(err_vars, collapse = ", ")))
    cat(sprintf("[gate] details: audit/reports/%s/04-label-reconciliation.csv\n",
                survey))
    if (blocking) {
      stop(sprintf(
        "[gate] BLOCKING: %d label-reconciliation error(s) in '%s' — fix the fn/labels or unset HARMONIZE_AUDIT_GATE",
        n_err, survey), call. = FALSE)
    } else {
      cat("[gate] report-only: not failing the pipeline (set HARMONIZE_AUDIT_GATE=block to enforce)\n")
    }
  } else if (!is.na(n_err)) {
    cat(sprintf("[gate] clean: no label-reconciliation errors for '%s'\n", survey))
  }

  invisible(list(
    survey = survey, blocking = blocking,
    n_errors = n_err, n_hints = n_hint, n_uncovered = n_unc,
    high_confidence = high_conf,
    label_recon = lr, battery = bc, coverage = ac
  ))
}


# ---------------------------------------------------------------------------
# CLI.
# ---------------------------------------------------------------------------
.parse_cli_args <- function(argv) {
  out <- list(survey = NULL, block = FALSE)
  i <- 1
  while (i <= length(argv)) {
    a <- argv[i]
    if (a == "--survey") { out$survey <- argv[i + 1]; i <- i + 2; next }
    if (a == "--block")  { out$block  <- TRUE;        i <- i + 1; next }
    if (a %in% c("-h", "--help")) {
      cat("Usage: Rscript src/r/audit/99_post_harmonize_gate.R --survey <name> [--block]\n",
          "\nRuns label reconciliation (hard), battery coherence + anchor\n",
          "coverage (soft) on the survey's harmonized output. Report-only by\n",
          "default (exit 0); with --block (or HARMONIZE_AUDIT_GATE=block),\n",
          "label-reconciliation errors exit 1.\n", sep = "")
      quit(status = 0)
    }
    stop(sprintf("unknown argument: %s", a), call. = FALSE)
  }
  if (is.null(out$survey)) stop("usage: --survey <name> [--block]", call. = FALSE)
  out
}

if (sys.nframe() == 0L) {
  argv <- commandArgs(trailingOnly = TRUE)
  if (length(argv) > 0) {
    args <- .parse_cli_args(argv)
    res <- tryCatch(
      run_post_harmonize_gate(args$survey,
                              blocking = args$block ||
                                identical(Sys.getenv("HARMONIZE_AUDIT_GATE"), "block")),
      error = function(e) { cat(conditionMessage(e), "\n"); NULL }
    )
    blocking <- args$block || identical(Sys.getenv("HARMONIZE_AUDIT_GATE"), "block")
    # Blocking mode fails CLOSED: a crashed label-recon check (n_errors NA)
    # means "could not verify", which is not the same as "verified clean".
    failed <- is.null(res) || is.na(res$n_errors) || res$n_errors > 0
    quit(status = if (blocking && failed) 1L else 0L)
  }
}
