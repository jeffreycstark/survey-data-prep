# src/r/data_prep_modules/klosa/0_load_waves.R
# KLoSA: load raw main wave files W1-W9 -> named list(w1..w9)
library(here); library(haven)

load_klosa_waves <- function() {
  cat("\n── Loading KLoSA raw waves ──\n")
  waves <- list()
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
