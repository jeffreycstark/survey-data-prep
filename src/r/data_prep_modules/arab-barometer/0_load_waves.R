# Arab Barometer: Load wave data from .sav files
# Creates wave list ready for harmonization
#
# Waves: w2-w5, w7-w8 (W1 excluded: no Tunisia; W6 deprioritized: COVID phone split)
# W2 = 2010-2011, W3 = 2012-2014, W4 = 2016, W5 = 2018-2019,
# W7 = 2021-2022, W8 = 2023-2024
#
# W1 (2006-2009): 7 countries, no Tunisia — skipped
# W6 (2020-2021): 3-part COVID phone survey with split questionnaire design,
#   only 41 of 188 vars shared across parts. Deprioritized for now.
#
# Data source: https://www.arabbarometer.org/survey-data/data-downloads/
# Free registration required.
#
# Expected file layout:
#   data/arab-barometer/raw/wave2/<filename>.sav
#   ...
#   data/arab-barometer/raw/wave8/<filename>.sav
#
# File names vary by wave -- the loader finds the first .sav in each directory.

library(haven)
library(here)

#' Load Arab Barometer wave data
#'
#' Scans each wave directory for the .sav file and loads it.
#' Returns a named list compatible with the harmonization engine.
#'
#' @return List of dataframes (w2 through w8)
#' @export
load_arab_barometer_waves <- function() {

  # W1 excluded (no Tunisia), W6 deprioritized (COVID split questionnaire)
  wave_dirs <- list(
    w2 = here::here("data", "arab-barometer", "raw", "wave2"),
    w3 = here::here("data", "arab-barometer", "raw", "wave3"),
    w4 = here::here("data", "arab-barometer", "raw", "wave4"),
    w5 = here::here("data", "arab-barometer", "raw", "wave5"),
    w7 = here::here("data", "arab-barometer", "raw", "wave7"),
    w8 = here::here("data", "arab-barometer", "raw", "wave8")
  )

  waves <- list()

  for (wave_name in names(wave_dirs)) {
    wave_dir <- wave_dirs[[wave_name]]

    if (!dir.exists(wave_dir)) {
      cat(sprintf("Skipping %s (directory not found: %s)\n", wave_name, wave_dir))
      next
    }

    # Find .sav files in the directory
    sav_files <- list.files(wave_dir, pattern = "\\.sav$", full.names = TRUE,
                            ignore.case = TRUE)

    if (length(sav_files) == 0) {
      cat(sprintf("Skipping %s (no .sav file in %s)\n", wave_name, basename(wave_dir)))
      next
    }

    # Use the first (or largest) .sav file
    sav_file <- sav_files[which.max(file.size(sav_files))]

    cat(sprintf("Loading %s from %s ... ", wave_name, basename(sav_file)))
    df <- haven::read_sav(sav_file, encoding = "latin1")
    waves[[wave_name]] <- df
    cat(sprintf("%s rows, %s cols\n", format(nrow(df), big.mark = ","), ncol(df)))
  }

  cat(sprintf("\nLoaded %d Arab Barometer wave(s)\n", length(waves)))
  waves
}
