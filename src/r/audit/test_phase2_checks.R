#!/usr/bin/env Rscript
# src/r/audit/test_phase2_checks.R
#
# Phase 2 tests: strict-reversal symmetrization + anchor-coverage meta-check.
#
# Run:  Rscript src/r/audit/test_phase2_checks.R
# Exit: 0 if all pass, 1 otherwise.

suppressPackageStartupMessages({ library(here); library(yaml) })
source(here::here("src", "r", "audit", "04_strict_reversal.R"))
source(here::here("src", "r", "audit", "04_anchor_coverage.R"))

.pass <- 0L; .fail <- 0L
ok <- function(cond, msg) {
  if (isTRUE(cond)) { .pass <<- .pass + 1L; cat(sprintf("  PASS  %s\n", msg)) }
  else              { .fail <<- .fail + 1L; cat(sprintf("  FAIL  %s\n", msg)) }
}

cat("=== 2a: strict-reversal registry partition ===\n")
rev <- load_reverser_set()
idn <- load_identity_set()
ok("safe_reverse_4pt" %in% rev, "safe_reverse_4pt in reverser set")
ok("safe_4pt_none"   %in% idn, "safe_4pt_none in identity set")
ok(!("safe_4pt_none" %in% rev), "safe_4pt_none NOT in reverser set")
ok(!("safe_reverse_4pt" %in% idn), "safe_reverse_4pt NOT in identity set")
ok(length(intersect(rev, idn)) == 0, "reverser and identity sets disjoint")
# Scale-changing fn must be in NEITHER (not pure same-scale).
ok(!("recode_5pt_to_4pt" %in% c(rev, idn)),
   "scale-changing recode_5pt_to_4pt excluded from both strict sets")

cat("\n=== 2a: compute emits direction/expected_sign columns (ABS integration) ===\n")
sr <- compute_strict_reversal("abs")
ok(all(c("direction", "expected_sign") %in% names(sr)),
   "strict-reversal output has direction + expected_sign columns")
ok(any(sr$direction == "identity"),
   "identity arm active (>=1 identity row on ABS)")
ok(any(sr$direction == "reverse"),
   "reverse arm still active (>=1 reverse row on ABS)")
ok(all(sr$expected_sign[sr$direction == "identity"] == 1L),
   "identity rows expect +1")
ok(all(sr$expected_sign[sr$direction == "reverse"] == -1L),
   "reverse rows expect -1")

cat("\n=== 2b: anchor-coverage classification (synthetic) ===\n")
# Synthetic spec file with one covered, one exempt-by-concept, one uncovered.
tmp_spec <- tempfile(fileext = ".yml")
writeLines(c(
  "schema_version: 1",
  "variables:",
  "  - id: system_prefer",      # covered: anchor of system_support.yml
  "    concept: political_attitudes",
  "    type: ordinal",
  "    source: {w3: q83}",
  "  - id: fake_age",            # exempt: concept demographics
  "    concept: demographics",
  "    type: continuous",
  "    source: {w3: q1}",
  "  - id: fake_uncovered_attitude",  # uncovered: ordinal, no anchor, no exempt
  "    concept: zzz_made_up_concept",
  "    type: ordinal",
  "    source: {w3: q999}",
  "  - id: fake_party",          # skip: nominal
  "    concept: zzz_made_up_concept",
  "    type: nominal",
  "    source: {w3: q998}"
), tmp_spec)

cov <- compute_anchor_coverage("abs", spec_files = tmp_spec)
st <- function(v) cov$status[cov$variable == v]
ok(identical(st("system_prefer"), "covered"), "anchor var -> covered")
ok(identical(st("fake_age"), "exempt"), "demographics concept -> exempt")
ok(identical(st("fake_uncovered_attitude"), "uncovered"), "ordinal w/o anchor -> uncovered")
ok(identical(st("fake_party"), "skip"), "nominal -> skip (not direction-bearing)")

cat("\n=== 2b: coverage index reads new anchor files + honors surveys gate ===\n")
idx <- build_anchor_coverage_index()
ok("system_deserves_support" %in% idx$variable,
   "system_deserves_support now in anchor coverage index (system_support.yml)")
ok("dem_free_speech" %in% idx$variable,
   "dem_free_speech now in anchor coverage index (democracy_supply.yml)")

cat(sprintf("\n=== %d passed, %d failed ===\n", .pass, .fail))
if (.fail > 0L) quit(status = 1L) else quit(status = 0L)
