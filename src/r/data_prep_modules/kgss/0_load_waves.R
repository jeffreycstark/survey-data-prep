# KGSS: Load raw wave files
#
# Returns a named list: list(w2003 = df, w2004 = df, ..., w2025 = df)
#
# Source file:
#   data/kgss/raw/kor_data_CUM0074.sav  (n=23,282, 2003-2025)
#
# The cumulative .sav is split by YEAR into 17 annual wave dataframes.
# Years available: 2003-2014, 2016, 2018, 2021, 2023, 2025
#   (no 2015, 2017, 2019-2020, 2022, 2024)
#
# NOTE: Wave names use calendar year (w2003, w2004, ..., w2025), not sequential index.
# The final dataset stores wave = calendar year integer.

library(here)
library(haven)

load_kgss_waves <- function() {

  cat("\n── Loading KGSS raw waves ──\n")

  sav_path <- here("data", "kgss", "raw", "kor_data_CUM0074.sav")

  if (!file.exists(sav_path)) stop("File not found: ", sav_path)

  cat(sprintf("  Reading: %s\n", basename(sav_path)))
  raw <- read_sav(sav_path)
  cat(sprintf("  Full file: %s rows, %d cols\n",
              format(nrow(raw), big.mark = ","), ncol(raw)))

  years <- sort(unique(as.integer(raw$YEAR)))
  cat(sprintf("  Years found: %s\n", paste(years, collapse = ", ")))

  waves <- split(raw, raw$YEAR)
  names(waves) <- paste0("w", names(waves))

  for (wn in names(waves)) {
    cat(sprintf("  %s: %s rows\n", wn,
                format(nrow(waves[[wn]]), big.mark = ",")))
  }

  waves
}

# When run directly, print a quick summary
if (!interactive() && identical(environment(), globalenv())) {
  waves <- load_kgss_waves()
  cat("\nLoaded waves:", paste(names(waves), collapse = ", "), "\n")
  cat(sprintf("Total: %s respondents across %d years\n",
              format(sum(sapply(waves, nrow)), big.mark = ","),
              length(waves)))
}
