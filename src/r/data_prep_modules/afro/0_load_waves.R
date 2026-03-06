# Afrobarometer: Load wave data from .sav files
# Creates wave list ready for harmonization
#
# Waves: w1-w9 = Rounds 1-9

library(haven)
library(here)

#' Load Afrobarometer wave data
#'
#' Loads Rounds 1-9 from the merged .sav files.
#' Returns a named list compatible with the harmonization engine.
#'
#' @return List of dataframes (w1 through w9)
#' @export
load_afro_waves <- function() {

  wave_info <- list(
    w1 = here::here("data", "afro", "raw", "round1", "merged_r1_data.sav"),
    w2 = here::here("data", "afro", "raw", "round2", "merged_r2_data.sav"),
    w3 = here::here("data", "afro", "raw", "round3", "merged_r3_data.sav"),
    w4 = here::here("data", "afro", "raw", "round4", "merged_r4_data.sav"),
    w5 = here::here("data", "afro", "raw", "round5", "merged_r5_data.sav"),
    w6 = here::here("data", "afro", "raw", "round6", "merged_r6_data.sav"),
    w7 = here::here("data", "afro", "raw", "round7", "merged_r7_data.sav"),
    w8 = here::here("data", "afro", "raw", "round8", "merged_r8_data.sav"),
    w9 = here::here("data", "afro", "raw", "wave9",
                    "R9.Merge_39ctry.20Nov23.final_.release_Updated.4Jun25-3.sav")
  )

  waves <- list()

  for (wave_name in names(wave_info)) {
    path <- wave_info[[wave_name]]
    if (!file.exists(path)) {
      cat(sprintf("Skipping %s (file not found: %s)\n", wave_name, basename(path)))
      next
    }
    cat(sprintf("Loading %s from %s ... ", wave_name, basename(path)))
    df <- haven::read_sav(path, encoding = "latin1")
    waves[[wave_name]] <- df
    cat(sprintf("%s rows, %s cols\n", format(nrow(df), big.mark = ","), ncol(df)))
  }

  cat(sprintf("\nLoaded %d Afrobarometer wave(s)\n", length(waves)))
  waves
}
