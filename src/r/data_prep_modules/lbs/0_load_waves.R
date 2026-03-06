# LBS: Load wave data from .sav files
# Creates wave list ready for harmonization
#
# 24 waves: 1995, 1996, 1997, 1998, 2000, 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2013, 2015, 2016, 2017, 2018, 2020, 2023, 2024

library(haven)
library(here)

#' Find English .sav file for a given year
#'
#' @param year Integer year
#' @return Path to English .sav file
find_lbs_eng_sav <- function(year) {
  dir_path <- here::here("data", "lbs", "raw", as.character(year))
  files <- list.files(dir_path, pattern = "\\.sav$", full.names = TRUE, ignore.case = TRUE)
  eng_files <- files[grepl("eng", files, ignore.case = TRUE)]
  if (length(eng_files) == 0) stop(sprintf("No English .sav file found for %d in %s", year, dir_path))
  eng_files[1]  # take first match
}

#' Load all LBS wave data
#'
#' Loads all available waves from English .sav files.
#' Returns a named list with keys y1995, y1996, ..., y2024.
#'
#' @return Named list of dataframes
#' @export
load_lbs_waves <- function() {

  years <- c(1995, 1996, 1997, 1998, 2000, 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2013, 2015, 2016, 2017, 2018, 2020, 2023, 2024)
  waves <- list()

  for (yr in years) {
    wave_key <- paste0("y", yr)
    path <- find_lbs_eng_sav(yr)
    cat(sprintf("Loading %s from %s ... ", wave_key, basename(path)))
    df <- haven::read_sav(path, encoding = "latin1")
    waves[[wave_key]] <- df
    cat(sprintf("%s rows, %s cols\n", format(nrow(df), big.mark = ","), ncol(df)))
  }

  cat(sprintf("\nLoaded %d LBS waves\n", length(waves)))
  waves
}

