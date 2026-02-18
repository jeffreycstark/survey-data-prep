# Afrobarometer: Load wave data from .sav file
# Creates wave list ready for harmonization
#
# Waves: w9 = Round 9 (2021-2023)

library(haven)
library(here)

#' Load Afrobarometer wave data
#'
#' Loads Round 9 from the merged .sav file.
#' Returns a named list compatible with the harmonization engine.
#'
#' @return List of 1 dataframe (w9)
#' @export
load_afro_waves <- function() {

  wave_info <- list(
    w9 = here::here("data", "afro", "raw", "wave9",
                    "R9.Merge_39ctry.20Nov23.final_.release_Updated.4Jun25-3.sav")
  )

  waves <- list()

  for (wave_name in names(wave_info)) {
    path <- wave_info[[wave_name]]
    cat(sprintf("Loading %s from %s ... ", wave_name, basename(path)))
    df <- haven::read_sav(path)
    waves[[wave_name]] <- df
    cat(sprintf("%s rows, %s cols\n", format(nrow(df), big.mark = ","), ncol(df)))
  }

  cat(sprintf("\n✅ Loaded %d Afrobarometer wave(s)\n", length(waves)))
  waves
}
