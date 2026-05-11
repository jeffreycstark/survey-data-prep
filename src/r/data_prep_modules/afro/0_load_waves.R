# Afrobarometer: Load wave data from .sav files
# Creates wave list ready for harmonization
#
# Waves: w1-w10 = Rounds 1-10
# Each directory is data/afro/raw/round<N>/. w10 file may not be present
# yet — it will auto-load when the .sav arrives (the loader silently
# skips missing files).

library(haven)
library(here)

#' Load Afrobarometer wave data
#'
#' Loads Rounds 1-10 from the merged .sav files. Skips any round whose
#' .sav file is not yet on disk (round10 data may not have arrived).
#'
#' @return List of dataframes (w1 through w10, minus any not on disk)
#' @export
load_afro_waves <- function() {

  wave_info <- list(
    w1  = here::here("data", "afro", "raw", "round1",  "merged_r1_data.sav"),
    w2  = here::here("data", "afro", "raw", "round2",  "merged_r2_data.sav"),
    w3  = here::here("data", "afro", "raw", "round3",  "merged_r3_data.sav"),
    w4  = here::here("data", "afro", "raw", "round4",  "merged_r4_data.sav"),
    w5  = here::here("data", "afro", "raw", "round5",  "merged_r5_data.sav"),
    w6  = here::here("data", "afro", "raw", "round6",  "merged_r6_data.sav"),
    w7  = here::here("data", "afro", "raw", "round7",  "merged_r7_data.sav"),
    w8  = here::here("data", "afro", "raw", "round8",  "merged_r8_data.sav"),
    w9  = here::here("data", "afro", "raw", "round9",
                     "R9.Merge_39ctry.20Nov23.final_.release_Updated.4Jun25-3.sav"),
    # round10 placeholder — update the filename when the .sav is published.
    # If multiple plausible names are possible, list `list.files()` here and
    # auto-pick. For now this static path will silently skip until the file
    # lands at this exact path.
    w10 = here::here("data", "afro", "raw", "round10", "merged_r10_data.sav")
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
