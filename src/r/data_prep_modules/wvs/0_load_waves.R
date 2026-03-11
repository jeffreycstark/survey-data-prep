# WVS: Load wave data
# W1-W5: SPSS .sav files via haven
# W6-W7: Apache Parquet files via arrow
# Creates wave list ready for harmonization

library(arrow)
library(haven)
library(here)

#' Load WVS wave data
#'
#' Loads waves 1-7: W1-W5 from SPSS .sav, W6-W7 from parquet.
#' Returns a named list compatible with the harmonization engine.
#'
#' @return List of 7 dataframes (w1, w2, w3, w4, w5, w6, w7)
#' @export
load_wvs_waves <- function() {

  # W1-W5: SPSS .sav files
  sav_waves <- list(
    w1 = here("data", "wvs", "raw", "wave1", "WV1_Data_spss_v20200208.sav"),
    w2 = here("data", "wvs", "raw", "wave2", "WV2_Data_Spss_v20180912.sav"),
    w3 = here("data", "wvs", "raw", "wave3", "WV3_Data_Spss_v20180912.sav"),
    w4 = here("data", "wvs", "raw", "wave4", "WV4_Data_spss_v20201117.sav"),
    w5 = here("data", "wvs", "raw", "wave5", "WV5_Data_Spss_v20180912.sav")
  )

  # W6-W7: Parquet files
  parquet_waves <- list(
    w6 = here("data", "wvs", "raw", "wave6", "wvs_wave6.parquet"),
    w7 = here("data", "wvs", "raw", "wave7", "wvs_wave7.parquet")
  )

  waves <- list()

  # Load .sav waves
  for (wave_name in names(sav_waves)) {
    path <- sav_waves[[wave_name]]
    cat(sprintf("Loading %s from %s ... ", wave_name, basename(path)))
    df <- haven::read_sav(path, encoding = "latin1")
    waves[[wave_name]] <- df
    cat(sprintf("%s rows, %s cols\n",
                format(nrow(df), big.mark = ","), ncol(df)))
  }

  # Load parquet waves
  for (wave_name in names(parquet_waves)) {
    path <- parquet_waves[[wave_name]]
    cat(sprintf("Loading %s from %s ... ", wave_name, basename(path)))
    df <- arrow::read_parquet(path)
    waves[[wave_name]] <- df
    cat(sprintf("%s rows, %s cols\n",
                format(nrow(df), big.mark = ","), ncol(df)))
  }

  cat(sprintf("\nLoaded %d WVS waves\n", length(waves)))
  waves
}
