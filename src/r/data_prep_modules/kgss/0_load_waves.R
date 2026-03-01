# KGSS: Load raw wave files
#
# Returns a named list: list(w2003 = df, w2004 = df, ..., w2023 = df)
#
# Source file:
#   data/kgss/raw/Eng_data_CUM0062_V3.sav  (n=22,071, 2003-2023)
#
# The cumulative .sav is split by YEAR into 16 annual wave dataframes.
# Years available: 2003-2014, 2016, 2018, 2021, 2023 (no 2015, 2017, 2019-2020, 2022)
#
# NOTE: Wave names use calendar year (w2003, w2004, ..., w2023), not sequential index.
# The final dataset stores wave = calendar year integer.

library(here)
library(haven)

load_kgss_waves <- function() {

  cat("\n── Loading KGSS raw waves ──\n")

  sav_path <- here("data", "kgss", "raw", "Eng_data_CUM0062_V3.sav")

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
