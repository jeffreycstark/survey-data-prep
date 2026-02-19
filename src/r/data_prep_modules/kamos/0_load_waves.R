# KAMOS: Load raw wave files
#
# Returns a named list: list(w1 = df, w4 = df)
#
# Source files:
#   data/kamos/raw/wave1/KAMOS 1-1 data e.sav   (n=2000, 2016)
#   data/kamos/raw/wave4/KAMOS 4-1 (E).sav       (n=1500, 2019)
#
# NOTE: No wave 2 or wave 3 data is available in this repository.
# Waves are named w1 and w4 to match the original KAMOS numbering.

library(here)
library(haven)

load_kamos_waves <- function() {

  cat("\n── Loading KAMOS raw waves ──\n")

  w1_path <- here("data", "kamos", "raw", "wave1", "KAMOS 1-1 data e.sav")
  w4_path <- here("data", "kamos", "raw", "wave4", "KAMOS 4-1 (E).sav")

  for (p in c(w1_path, w4_path)) {
    if (!file.exists(p)) stop("File not found: ", p)
  }

  w1 <- read_sav(w1_path)
  cat(sprintf("  w1: %s rows, %d cols\n", format(nrow(w1), big.mark = ","), ncol(w1)))

  w4 <- read_sav(w4_path)
  cat(sprintf("  w4: %s rows, %d cols\n", format(nrow(w4), big.mark = ","), ncol(w4)))

  list(w1 = w1, w4 = w4)
}

# When run directly, print a quick summary
if (!interactive() && identical(environment(), globalenv())) {
  waves <- load_kamos_waves()
  cat("\nLoaded waves:", paste(names(waves), collapse = ", "), "\n")
}
