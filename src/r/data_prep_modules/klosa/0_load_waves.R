# src/r/data_prep_modules/klosa/0_load_waves.R
# KLoSA: load raw main wave files W1-W9 -> named list(w1..w9)
library(here); library(haven)

load_klosa_waves <- function() {
  cat("\n── Loading KLoSA raw waves ──\n")
  waves <- list()
  # NOTE: `w05_new_e.sav` (the W5 refresher cohort, ~920 respondents added by
  # KLoSA in 2014) is deliberately NOT folded in here. This is a documented
  # decision, not an oversight: the cohort is born ~1962-63 and never reaches
  # the age-65 RD cutoff within W1-W9, so excluding it has zero effect on
  # Paper 9's identification. See docs/surveys/klosa.md "Known limitations"
  # for the full rationale (variable-family mismatch, missing participation
  # battery under the standard names) and the fold-in follow-up.
  for (i in 1:9) {
    wv <- sprintf("w%d", i)
    f  <- here("data","klosa","raw", sprintf("w0%d_e.sav", i))
    if (!file.exists(f)) stop("File not found: ", f)
    df <- read_sav(f)
    cat(sprintf("  %s: %s rows, %d cols\n", wv, format(nrow(df), big.mark=","), ncol(df)))
    waves[[wv]] <- df
  }
  waves
}

if (!interactive() && identical(environment(), globalenv())) {
  w <- load_klosa_waves()
  cat("\nLoaded:", paste(names(w), collapse=", "), "\n")
}
