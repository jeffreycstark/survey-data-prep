#' Tests for validate_completeness() and its wiring into validate_variable_wave()
#'
#' Run with:
#'   Rscript src/r/utils/test_validation_completeness.R
#'
#' Three unit blocks for the pure function plus one integration block that
#' reproduces the silent-pass gap this check was built to close: a raw source
#' column that is present in a wave but entirely missing (e.g. ABS W1/W2 Korea
#' interview-date variables). validate_coverage() rates that cell "ok" (0%
#' loss because raw_valid == 0); validate_completeness() must flag it "warn".

suppressPackageStartupMessages({
  library(here)
})

here::i_am("src/r/utils/test_validation_completeness.R")
source(here::here("src", "r", "utils", "validation.R"))
source(here::here("src", "r", "harmonize", "harmonize.R"))  # resolve_wave_rule()

fails <- 0L
ok <- function(cond, label) {
  if (isTRUE(cond)) {
    cat(sprintf("  PASS: %s\n", label))
  } else {
    cat(sprintf("  FAIL: %s\n", label))
    fails <<- fails + 1L
  }
}

cat("=== unit 1: non-empty vector -> ok ===\n")
r1 <- validate_completeness(c(1, 2, NA, 4))
ok(r1$status == "ok",        "status is ok")
ok(r1$n_valid == 3,          "counts 3 non-missing")
ok(r1$check == "completeness", "check name is completeness")

cat("=== unit 2: all-NA vector -> warn ===\n")
r2 <- validate_completeness(c(NA, NA, NA))
ok(r2$status == "warn",      "all-NA flags warn")
ok(r2$n_valid == 0,          "n_valid is 0")
ok(grepl("entirely missing", r2$message), "message names the failure")

cat("=== unit 3: all-NA + allow_empty -> skip ===\n")
r3 <- validate_completeness(c(NA, NA, NA), allow_empty = TRUE)
ok(r3$status == "skip",      "allow_empty downgrades to skip")

cat("=== integration: silent-pass gap through validate_variable_wave ===\n")
# Source column present in the wave but 100% NA -> the exact ABS W1/W2 shape.
raw <- data.frame(idate = rep(NA_real_, 50))
# Identity harmonization of an all-NA source yields an all-NA harmonized column.
harm <- data.frame(interview_month = rep(NA_real_, 50))
spec <- list(
  id     = "interview_month",
  type   = "ordinal",
  source = list(w1 = "idate"),
  harmonize = list(w1 = list(method = "identity")),
  scale  = list(min = 1, max = 12),
  qc     = list(skip_range_check = TRUE)
)

res <- validate_variable_wave(raw, harm, spec, wave_name = "w1")
ok(res$checks$coverage$status == "ok",
   "coverage still rates the empty cell ok (the silent gap)")
ok(res$checks$completeness$status == "warn",
   "completeness flags the empty cell")
ok(res$status == "warn",
   "overall status is warn (gap now surfaced)")

# Control: a populated source must not trip the new check.
raw2  <- data.frame(idate = sample(1:12, 50, replace = TRUE))
harm2 <- data.frame(interview_month = raw2$idate)
res2  <- validate_variable_wave(raw2, harm2, spec, wave_name = "w1")
ok(res2$checks$completeness$status == "ok",
   "populated source passes completeness")

cat(sprintf("\n%s (%d failure%s)\n",
            if (fails == 0L) "ALL TESTS PASSED" else "TESTS FAILED",
            fails, if (fails == 1L) "" else "s"))
if (fails > 0L) quit(status = 1L)
