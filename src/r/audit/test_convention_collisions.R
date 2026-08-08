#!/usr/bin/env Rscript
# src/r/audit/test_convention_collisions.R
#
# Fault-injection tests for the convention-collision check.
# Run:  Rscript src/r/audit/test_convention_collisions.R
# Exit: 0 if all pass, 1 otherwise.
#
# Strategy: build synthetic spec files in a temp survey config dir, point the
# scanner at them via a shimmed list_survey_specs(), and assert on the rows
# it returns. Exercises both live spec formats, valid_range_by_wave, wave
# rules that leave identity, inline missing$codes, exemption matching
# (full and codes-subset), and the parse-failure path.

suppressPackageStartupMessages({ library(here); library(yaml) })
source(here::here("src", "r", "audit", "check_convention_collisions.R"))

.pass <- 0L; .fail <- 0L
ok <- function(cond, msg) {
  if (isTRUE(cond)) { .pass <<- .pass + 1L; cat(sprintf("  PASS  %s\n", msg)) }
  else              { .fail <<- .fail + 1L; cat(sprintf("  FAIL  %s\n", msg)) }
}

tmp <- file.path(tempdir(), "cc_test_specs")
dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
write_spec <- function(name, text) {
  path <- file.path(tmp, paste0(name, ".yml"))
  writeLines(text, path, useBytes = TRUE)
  invisible(path)
}
# Shim discovery so scan_survey_collisions() reads the temp dir.
list_survey_specs <- function(survey) {
  list.files(tmp, pattern = "\\.yml$", full.names = TRUE)
}

reset <- function() unlink(list.files(tmp, full.names = TRUE))

cat("=== T1: identity-wave collision -> error row with the right codes ===\n")
reset()
write_spec("toy", '
missing_conventions:
  treat_as_na:
    codes: [7, 8, 9, 97, 98, 99]
variables:
  - id: rating_10pt
    source: {w1: q1, w2: q2}
    harmonize:
      default: {method: identity}
    missing: {use_convention: treat_as_na}
    qc:
      valid_range: [1, 10]
')
res <- scan_survey_collisions("toy")
ok(nrow(res$rows) == 1L, "one collision row")
ok(res$rows$variable[1] == "rating_10pt", "flags the right variable")
ok(res$rows$codes[1] == "7;8;9", "flags exactly the in-range codes")
ok(res$rows$status[1] == "error", "unexempted -> error")
ok(grepl("w1", res$rows$waves[1]) && grepl("w2", res$rows$waves[1]),
   "both identity waves recorded")

cat("=== T2: r_function wave is NOT flagged (out of scope) ===\n")
reset()
write_spec("toy", '
missing_conventions:
  treat_as_na:
    codes: [7, 8, 9]
variables:
  - id: recoded_var
    source: {w1: q1}
    harmonize:
      default: {method: r_function, fn: safe_6pt_to_4pt}
    missing: {use_convention: treat_as_na}
    qc:
      valid_range: [1, 4]
')
res <- scan_survey_collisions("toy")
ok(nrow(res$rows) == 0L, "non-identity waves produce no rows")

cat("=== T3: per-wave exception leaves only identity waves flagged ===\n")
reset()
write_spec("toy", '
missing_conventions:
  treat_as_na:
    codes: [9]
variables:
  - id: mixed_var
    source: {w1: q1, w2: q2}
    harmonize:
      default: {method: identity}
      exceptions:
        w2: {method: r_function, fn: some_fn}
    missing: {use_convention: treat_as_na}
    qc:
      valid_range: [0, 10]
')
res <- scan_survey_collisions("toy")
ok(nrow(res$rows) == 1L && res$rows$waves[1] == "w1",
   "exception wave excluded, identity wave kept")

cat("=== T4: valid_range_by_wave respected per wave ===\n")
reset()
write_spec("toy", '
missing_conventions:
  treat_as_na:
    codes: [9]
variables:
  - id: shifting_scale
    source: {w1: q1, w2: q2}
    harmonize:
      default: {method: identity}
    missing: {use_convention: treat_as_na}
    qc:
      valid_range: [1, 4]
      valid_range_by_wave:
        w2: [0, 10]
')
res <- scan_survey_collisions("toy")
ok(nrow(res$rows) == 1L && res$rows$waves[1] == "w2",
   "9 collides only where the by-wave range contains it")

cat("=== T5: named-list variable format + inline missing codes union ===\n")
reset()
write_spec("toy", '
missing_conventions:
  treat_as_na:
    codes: [99]
variables:
  ladder:
    source: {w1: q1}
    harmonize:
      default: {method: identity}
    missing:
      use_convention: treat_as_na
      codes: [5]
    qc:
      valid_range: [1, 10]
')
res <- scan_survey_collisions("toy")
ok(nrow(res$rows) == 1L, "named-list format parsed")
ok(res$rows$variable[1] == "ladder", "id taken from the list name")
ok(res$rows$codes[1] == "5", "inline missing$codes join the effective set")

cat("=== T6: exemptions — full and codes-subset matching ===\n")
reset()
write_spec("toy", '
missing_conventions:
  treat_as_na:
    codes: [97, 98, 99]
variables:
  - id: age
    source: {w1: q1}
    harmonize:
      default: {method: identity}
    missing: {use_convention: treat_as_na}
    qc:
      valid_range: [17, 99]
  - id: other_var
    source: {w1: q2}
    harmonize:
      default: {method: identity}
    missing: {use_convention: treat_as_na}
    qc:
      valid_range: [1, 99]
')
exempt_full   <- list(list(survey = "toy", variable = "age",
                           reason = "top-code ambiguity"))
exempt_subset <- list(list(survey = "toy", variable = "age",
                           codes = list(97), reason = "only 97"))
res <- scan_survey_collisions("toy", exemptions = exempt_full)
age_row <- res$rows[res$rows$variable == "age", ]
oth_row <- res$rows[res$rows$variable == "other_var", ]
ok(age_row$status == "exempt" && age_row$reason == "top-code ambiguity",
   "matching exemption downgrades to exempt and carries the reason")
ok(oth_row$status == "error", "non-matching variable stays error")
res <- scan_survey_collisions("toy", exemptions = exempt_subset)
ok(res$rows[res$rows$variable == "age", "status"] == "error",
   "codes-subset exemption does NOT cover a wider collision set")

cat("=== T7: skip_range_check honored; clean spec yields no rows ===\n")
reset()
write_spec("toy", '
missing_conventions:
  treat_as_na:
    codes: [98, 99]
variables:
  - id: skipped
    source: {w1: q1}
    harmonize:
      default: {method: identity}
    missing: {use_convention: treat_as_na}
    qc:
      valid_range: [1, 99]
      skip_range_check: true
  - id: clean_10pt
    source: {w1: q2}
    harmonize:
      default: {method: identity}
    missing: {use_convention: treat_as_na}
    qc:
      valid_range: [0, 10]
')
res <- scan_survey_collisions("toy")
ok(nrow(res$rows) == 0L, "skip_range_check + out-of-range codes -> clean")

cat("=== T8: unparseable spec is REPORTED, not silently skipped ===\n")
reset()
write_spec("broken", 'missing_conventions:\n  treat_as_na: [9\nvariables: "not: [valid')
res <- scan_survey_collisions("toy")
ok(length(res$parse_failures) == 1L, "parse failure surfaces in the result")
ok(grepl("broken", res$parse_failures[1]), "failure names the spec")

cat(sprintf("\n%d passed, %d failed\n", .pass, .fail))
quit(status = if (.fail > 0L) 1L else 0L)
