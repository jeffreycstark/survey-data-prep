# LBS: Load wave data from .sav files
# Creates wave list ready for harmonization
#
# Waves: w1=2015, w2=2016, w3=2018, w4=2020, w5=2023

library(haven)
library(here)

#' Load LBS wave data
#'
#' Loads 5 waves from English .sav files.
#' Returns a named list compatible with the harmonization engine.
#'
#' @return List of 5 dataframes (w1 through w5)
#' @export
load_lbs_waves <- function() {

  wave_info <- list(
    w1 = here::here("data", "lbs", "raw", "2015", "Latinobarometro_2015_Eng.sav"),
    w2 = here::here("data", "lbs", "raw", "2016", "Latinobarometro2016Eng_v20170205.sav"),
    w3 = here::here("data", "lbs", "raw", "2018", "Latinobarometro_2018_Eng_Spss_v20190303.sav"),
    w4 = here::here("data", "lbs", "raw", "2020", "Latinobarometro_2020_Eng_Spss_v1_0.sav"),
    w5 = here::here("data", "lbs", "raw", "2023", "Latinobarometro_2023_Eng_Spss_v1_0.sav")
  )

  waves <- list()

  for (wave_name in names(wave_info)) {
    path <- wave_info[[wave_name]]
    cat(sprintf("Loading %s from %s ... ", wave_name, basename(path)))
    df <- haven::read_sav(path)
    waves[[wave_name]] <- df
    cat(sprintf("%s rows, %s cols\n", format(nrow(df), big.mark = ","), ncol(df)))
  }

  cat(sprintf("\n✅ Loaded %d LBS waves\n", length(waves)))
  waves
}
