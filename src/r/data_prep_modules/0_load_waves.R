# Load all survey waves and strip haven labels
# Creates clean dataframes ready for harmonization

library(dplyr)
library(haven)
library(here)

#' Load all survey waves
#'
#' Loads RDS files with haven labels (for validation during harmonization)
#' @return List of 6 dataframes (w1-w6) with haven labels intact
#' @examples
#' waves <- load_waves()
#'
#' @export
load_waves <- function() {

  wave_names <- c("w1", "w2", "w3", "w4", "w5", "w6")
  waves <- list()

  for (wave in wave_names) {
    path <- here::here("data", "processed", sprintf("%s.rds", wave))

    cat(sprintf("Loading %s from %s\n", wave, basename(path)))
    df <- readRDS(path)
    waves[[wave]] <- df
  }

  cat(sprintf("\n✅ Loaded %d waves\n", length(waves)))
  return(waves)
}


#' Strip haven labels from dataframe
#'
#' Removes all haven_labelled class attributes
#' @param df Dataframe with haven labels
#' @return Dataframe with plain numeric/character columns
#'
#' @export
strip_haven_labels <- function(df) {
  df %>%
    mutate(across(everything(), ~ {
      if (inherits(., "haven_labelled")) {
        as.numeric(.)
      } else {
        .
      }
    })) %>%
    {
      # Remove all attributes except dim and names
      for (i in seq_along(.)) {
        attributes(.[[i]]) <- NULL
      }
      .
    }
}


#' Extract variable from specific wave
#'
#' Gets a named variable from a wave dataframe
#' @param waves List of dataframes
#' @param wave Wave name (w1, w2, etc.)
#' @param var Variable name
#' @return Numeric vector, or NA vector if variable doesn't exist
#'
#' @export
extract_var <- function(waves, wave, var) {
  df <- waves[[wave]]

  if (is.null(df)) {
    warning(sprintf("Wave %s not found in waves list", wave))
    return(numeric(0))
  }

  if (!var %in% names(df)) {
    warning(sprintf("Variable %s not found in %s", var, wave))
    return(rep(NA_real_, nrow(df)))
  }

  as.numeric(df[[var]])
}
