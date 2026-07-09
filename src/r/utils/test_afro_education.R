#!/usr/bin/env Rscript
#' Regression tests for the Afrobarometer education ladder.
#'
#' Run with:
#'   Rscript src/r/utils/test_afro_education.R
#'
#' Guards the 2026-07-09 bug: codes 8 ("University completed") and 9
#' ("Post-graduate") are SUBSTANTIVE on Afrobarometer's 0-9 education ladder,
#' but appeared in both (a) the spec's shared `treat_as_na` convention and
#' (b) `recode_afro_educ_detailed`'s default `missing_codes`. Because
#' `case_when` evaluates its missing branch first, the `c(6,7,8,9) ~ 3` branch
#' was unreachable and every such respondent was silently dropped to NA.
#'
#' The consequence downstream: `education_5cat` (afro/99_create_final_dataset.R)
#' maps `education_detailed %in% 8:9 -> 5`, so category 5 never occurred.

suppressPackageStartupMessages({
  library(here)
  library(yaml)
})

source(here::here("src", "r", "utils", "recoding.R"))

.pass <- 0L; .fail <- 0L
expect <- function(cond, label) {
  if (isTRUE(cond)) { cat(sprintf("  [PASS] %s\n", label)); .pass <<- .pass + 1L }
  else              { cat(sprintf("  [FAIL] %s\n", label)); .fail <<- .fail + 1L }
}

cat("=== recode_afro_educ_detailed: 0-9 ladder -> 0-3 condensed ===\n")
x   <- c(0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
got <- recode_afro_educ_detailed(x)
expect(identical(got, c(0, 0, 1, 1, 2, 2, 3, 3, 3, 3)),
       "0,1->0  2,3->1  4,5->2  6,7,8,9->3")
expect(!is.na(got[9]), "code 8 (University completed) is NOT dropped")
expect(!is.na(got[10]), "code 9 (Post-graduate) is NOT dropped")
expect(got[9] == 3 && got[10] == 3, "8 and 9 both collapse to 3 = Post-secondary")

cat("\n=== genuine missing codes still become NA ===\n")
miss <- recode_afro_educ_detailed(c(-1, 10, 98, 99, 998, 999))
expect(all(is.na(miss)), "-1, 10, 98, 99, 998, 999 -> NA")

cat("\n=== the default missing_codes must never re-list 8 or 9 ===\n")
defaults <- eval(formals(recode_afro_educ_detailed)$missing_codes)
expect(!(8 %in% defaults), "8 absent from default missing_codes")
expect(!(9 %in% defaults), "9 absent from default missing_codes")

cat("\n=== unreachable-branch guard: missing branch must not shadow 8/9 ===\n")
# Simulate the old bug explicitly: if a caller passes 8/9 as missing, the
# c(6,7,8,9) branch is shadowed. We assert the SHAPE of that failure so the
# test documents why the default matters.
shadowed <- recode_afro_educ_detailed(c(8, 9), missing_codes = c(-1, 8, 9))
expect(all(is.na(shadowed)),
       "passing 8/9 as missing_codes reproduces the old NA behaviour (documents the trap)")

cat("\n=== spec wiring: both education vars must avoid `treat_as_na` ===\n")
spec <- yaml::read_yaml(here::here("src", "config", "afro", "harmonize", "demographics.yml"))
conv <- spec$missing_conventions$education_ladder_missing$codes
expect(!is.null(conv), "education_ladder_missing convention exists")
expect(!(8 %in% conv) && !(9 %in% conv), "convention excludes 8 and 9")
expect(8 %in% spec$missing_conventions$treat_as_na$codes,
       "shared treat_as_na still lists 8 (correct for 0-3 items)")

get_var <- function(id) Filter(function(v) identical(v$id, id), spec$variables)[[1]]
ed  <- get_var("education_detailed")
lvl <- get_var("education_level")
expect(identical(ed$missing$use_convention, "education_ladder_missing"),
       "education_detailed uses education_ladder_missing")
expect(identical(lvl$missing$use_convention, "education_ladder_missing"),
       "education_level uses education_ladder_missing")
expect(10 %in% as.numeric(unlist(lvl$missing$codes)),
       "education_level appends 10 (R1 educ Don't-know)")
expect(identical(as.numeric(unlist(lvl$qc$valid_range)), c(0, 3)),
       "education_level valid_range [0,3] catches EDUC_COND's 9 = Don't know")
expect(identical(as.numeric(unlist(ed$qc$valid_range)), c(0, 9)),
       "education_detailed valid_range [0,9] admits 8 and 9")

cat(sprintf("\n%s — %d passed, %d failed\n",
            if (.fail == 0L) "ALL PASS" else "FAILURES", .pass, .fail))
if (.fail > 0L) quit(status = 1)
quit(status = 0)
