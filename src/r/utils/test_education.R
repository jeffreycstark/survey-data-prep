#!/usr/bin/env Rscript
#' Tests for the shared cross-survey education mapping (src/r/utils/education.R)
#'
#' Run with:
#'   Rscript src/r/utils/test_education.R
#'
#' Two things are being guarded:
#'   1. Each survey's native ladder maps onto the shared 5-category scale, and
#'      every substantive raw code lands somewhere (nothing silently NA).
#'   2. The traps that caused real bugs: Afro codes 8/9 must reach category 5;
#'      KGSS code 8 ("other") must become NA and never rank above a PhD.

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
})
source(here::here("src", "r", "utils", "education.R"))

.pass <- 0L; .fail <- 0L
expect <- function(cond, label) {
  if (isTRUE(cond)) { cat(sprintf("  [PASS] %s\n", label)); .pass <<- .pass + 1L }
  else              { cat(sprintf("  [FAIL] %s\n", label)); .fail <<- .fail + 1L }
}

cat("=== ABS 1-10 ===\n")
expect(identical(edu5_from_abs(1:10), c(1L,2L,2L,3L,3L,3L,3L,4L,5L,5L)),
       "1->1  2,3->2  4-7->3  8->4  9,10->5")
expect(all(!is.na(edu5_from_abs(1:10))), "every ABS level maps somewhere")

cat("\n=== Afrobarometer 0-9 detailed ===\n")
det <- edu5_from_afro(0:9, rep(NA_real_, 10))
expect(identical(det, c(1L,1L,2L,2L,3L,3L,4L,4L,5L,5L)),
       "0,1->1  2,3->2  4,5->3  6,7->4  8,9->5")
expect(det[9] == 5L && det[10] == 5L,
       "codes 8 (University completed) and 9 (Post-graduate) reach category 5")
expect(all(!is.na(det)), "no detailed code is silently dropped")

cat("\n=== Afrobarometer R1 fallback (condensed 0-3, detailed NA) ===\n")
fb <- edu5_from_afro(rep(NA_real_, 4), 0:3)
expect(identical(fb, c(1L,2L,3L,4L)), "0->1 1->2 2->3 3->4 (never 5: cannot see degrees)")
expect(!any(fb == 5L, na.rm = TRUE), "R1 fallback never claims category 5")

cat("\n=== Afro: detailed takes precedence over condensed ===\n")
expect(edu5_from_afro(8, 3) == 5L, "detailed=8 wins over condensed=3 -> 5, not 4")

cat("\n=== Latinobarometro 1-7 ===\n")
expect(identical(edu5_from_lbs(1:7), c(1L,2L,2L,3L,3L,4L,5L)),
       "1->1  2,3->2  4,5->3  6->4  7->5")

cat("\n=== KGSS 0-8 (code 8 = 'other') ===\n")
k <- edu5_from_kgss(0:8)
expect(identical(k[1:8], c(1L,2L,3L,3L,4L,5L,5L,5L)),
       "0->1 1->2 2,3->3 4->4 5,6,7->5")
expect(is.na(k[9]), "code 8 ('other') -> NA, not a level above PhD")
expect(edu5_from_kgss(7) == 5L, "PhD (7) is the top substantive level")
# The trap that broke paper 16: a naive 0-1 rescale of the raw code.
naive <- (0:8 - 0) / 8
expect(naive[9] > naive[8],
       "documents the trap: normalize_01(education) ranks 'other' (8) above PhD (7)")

cat("\n=== WVS harmonized 1-6 ===\n")
expect(identical(edu5_from_wvs(1:6), c(1L,2L,3L,3L,4L,5L)),
       "1->1 2->2 3,4->3 (secondary merged) 5->4 6->5")
expect(all(!is.na(edu5_from_wvs(1:6))), "every WVS level maps somewhere")

cat("\n=== edu5_to_01: comparable across surveys ===\n")
expect(identical(edu5_to_01(1:5), c(0, 0.25, 0.5, 0.75, 1)), "1..5 -> 0,.25,.5,.75,1")
expect(is.na(edu5_to_01(0)) && is.na(edu5_to_01(6)), "out-of-scale -> NA")
expect(is.na(edu5_to_01(NA_integer_)), "NA in -> NA out")
# The point of the column: "secondary" is 0.5 in EVERY survey.
sec <- c(abs  = edu5_to_01(edu5_from_abs(5)),
         afro = edu5_to_01(edu5_from_afro(4, NA)),
         lbs  = edu5_to_01(edu5_from_lbs(4)),
         kgss = edu5_to_01(edu5_from_kgss(3)),
         wvs  = edu5_to_01(edu5_from_wvs(4)))
expect(all(sec == 0.5), "a secondary-educated respondent is 0.5 in all five surveys")

cat("\n=== NA propagation ===\n")
expect(is.na(edu5_from_abs(NA_real_)),  "ABS NA -> NA")
expect(is.na(edu5_from_kgss(NA_real_)), "KGSS NA -> NA")
expect(is.na(edu5_from_wvs(NA_real_)),  "WVS NA -> NA")
expect(is.na(edu5_from_afro(NA_real_, NA_real_)), "Afro NA,NA -> NA")

cat(sprintf("\n%s — %d passed, %d failed\n",
            if (.fail == 0L) "ALL PASS" else "FAILURES", .pass, .fail))
if (.fail > 0L) quit(status = 1)
quit(status = 0)
