# KAMOS: Load raw wave files
#
# Returns a named list: list(w1 = df, w2 = df, w3 = df, w4 = df)
#
# Source files (all from data/kamos/raw/all_waves/):
#   KAMOS_1-1_2016.02.16-2016.05.16_data.sav  (n=2000, Feb–May 2016)
#   KAMOS_2-1_2017.05.16-2017.07.10_data.sav  (n=2000, May–Jul 2017)
#   KAMOS_3-1_2018.04.23-2018.06.22_data.sav  (n=2010, Apr–Jun 2018)
#   KAMOS_4-1_2019.04.20-2019.06.20_data.sav  (n=1500, Apr–Jun 2019)
#
# W2 and W3 have trust, economy, and political items with PARTIAL demographics:
#   - age: de2 is categorical (1-5 age bracket), not raw age (no continuous age)
#   - gender: de1 (1=male, 2=female) — available in both waves
#   - education, income, marital status available with different var names in W3
#   - no birth year, no region

library(here)
library(haven)

load_kamos_waves <- function() {

  cat("\n── Loading KAMOS raw waves ──\n")

  raw_dir <- here("data", "kamos", "raw", "all_waves")
  w1_path <- file.path(raw_dir, "KAMOS_1-1_2016.02.16-2016.05.16_data.sav")
  w2_path <- file.path(raw_dir, "KAMOS_2-1_2017.05.16-2017.07.10_data.sav")
  w3_path <- file.path(raw_dir, "KAMOS_3-1_2018.04.23-2018.06.22_data.sav")
  w4_path <- file.path(raw_dir, "KAMOS_4-1_2019.04.20-2019.06.20_data.sav")

  for (p in c(w1_path, w2_path, w3_path, w4_path)) {
    if (!file.exists(p)) stop("File not found: ", p)
  }

  w1 <- read_sav(w1_path)
  cat(sprintf("  w1: %s rows, %d cols\n", format(nrow(w1), big.mark = ","), ncol(w1)))

  w2 <- read_sav(w2_path)
  cat(sprintf("  w2: %s rows, %d cols\n", format(nrow(w2), big.mark = ","), ncol(w2)))

  w3 <- read_sav(w3_path)
  cat(sprintf("  w3: %s rows, %d cols\n", format(nrow(w3), big.mark = ","), ncol(w3)))

  w4 <- read_sav(w4_path)
  cat(sprintf("  w4: %s rows, %d cols\n", format(nrow(w4), big.mark = ","), ncol(w4)))

  list(w1 = w1, w2 = w2, w3 = w3, w4 = w4)
}

# When run directly, print a quick summary
if (!interactive() && identical(environment(), globalenv())) {
  waves <- load_kamos_waves()
  cat("\nLoaded waves:", paste(names(waves), collapse = ", "), "\n")
}
