# WVS: Load wave data from parquet files
# Creates wave list ready for harmonization

library(arrow)
library(here)

#' Load WVS wave data
#'
#' Loads waves 6 and 7 from parquet files.
#' Returns a named list compatible with the harmonization engine.
#'
#' @return List of 2 dataframes (w6, w7)
#' @export
load_wvs_waves <- function() {

  wave_info <- list(
    w6 = here::here("data", "wvs", "raw", "wave6", "wvs_wave6.parquet"),
    w7 = here::here("data", "wvs", "raw", "wave7", "wvs_wave7.parquet")
  )

  waves <- list()

  for (wave_name in names(wave_info)) {
    path <- wave_info[[wave_name]]
    cat(sprintf("Loading %s from %s ... ", wave_name, basename(path)))
    df <- arrow::read_parquet(path)
    waves[[wave_name]] <- df
    cat(sprintf("%s rows, %s cols\n", format(nrow(df), big.mark = ","), ncol(df)))
  }

  cat(sprintf("\n✅ Loaded %d WVS waves\n", length(waves)))
  waves
}
