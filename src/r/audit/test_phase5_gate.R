#!/usr/bin/env Rscript
# src/r/audit/test_phase5_gate.R
#
# Phase 5 tests: post-harmonize direction gate enforcement semantics.
#
# The gate's contract is the plan's "report-only first" decision:
#   - report-only (default): NEVER fails the pipeline, even with known
#     label-reconciliation errors present (ABS carries the 16-var backlog).
#   - blocking (--block / HARMONIZE_AUDIT_GATE=block): label-recon errors
#     exit 1 — this is the "exit code is non-zero if a safe_4pt_none is
#     reintroduced on an inverse-labeled item" acceptance criterion, since
#     those errors are exactly what Check A flags.
#
# Run:  Rscript src/r/audit/test_phase5_gate.R   (~2-3 min; invokes the gate
#       CLI on gcb + abs)
# Exit: 0 if all pass, 1 otherwise.

suppressPackageStartupMessages({ library(here) })

.pass <- 0L; .fail <- 0L
ok <- function(cond, msg) {
  if (isTRUE(cond)) { .pass <<- .pass + 1L; cat(sprintf("  PASS  %s\n", msg)) }
  else              { .fail <<- .fail + 1L; cat(sprintf("  FAIL  %s\n", msg)) }
}

gate <- here::here("src", "r", "audit", "99_post_harmonize_gate.R")
run_gate <- function(args) {
  out <- suppressWarnings(system2("Rscript", c(gate, args),
                                  stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  list(status = if (is.null(status)) 0L else as.integer(status), stdout = out)
}

cat("=== 5a: report-only never blocks ===\n")
g1 <- run_gate(c("--survey", "gcb"))
ok(g1$status == 0L, "clean survey (gcb), report-only -> exit 0")

g2 <- run_gate(c("--survey", "abs"))
ok(g2$status == 0L,
   "survey with known label-recon errors (abs backlog), report-only -> exit 0")
ok(any(grepl("report-only: not failing the pipeline", g2$stdout)),
   "report-only banner printed when errors present")
ok(any(grepl("HIGH-CONFIDENCE", g2$stdout)),
   "high-confidence overlap (Check A error + Check B neg-corr) surfaced")

cat("\n=== 5b: blocking mode fails on label-recon errors ===\n")
g3 <- run_gate(c("--survey", "abs", "--block"))
ok(g3$status == 1L, "--block with label-recon errors -> exit 1")
ok(any(grepl("BLOCKING", g3$stdout)), "blocking failure message printed")

g4 <- run_gate(c("--survey", "gcb", "--block"))
ok(g4$status == 0L, "--block with clean survey -> exit 0")

cat(sprintf("\n=== %d passed, %d failed ===\n", .pass, .fail))
if (.fail > 0L) quit(status = 1L) else quit(status = 0L)
