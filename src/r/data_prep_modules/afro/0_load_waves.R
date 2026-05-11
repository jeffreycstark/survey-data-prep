# Afrobarometer: Load wave data from .sav files
# Creates wave list ready for harmonization
#
# Waves: w1-w10 = Rounds 1-10
# Each directory is data/afro/raw/round<N>/.
# R1-R9 each ship as one merged .sav. R10 currently ships as 29 per-country
# .sav files (no merged release yet — same pattern ABS W6 went through).
# The loader stacks the per-country files on the fly; once AB publishes a
# merged R10 .sav, drop it at data/afro/raw/round10/merged_r10_data.sav
# and the loader will prefer that single file.

library(haven)
library(here)
library(dplyr)

# Internal: stack the 29 (or however many) R10 per-country files into a
# single data frame. Mirrors src/scripts/build_abs_w6.R's approach:
# zap haven_labelled to avoid bind_rows type conflicts across countries;
# resolve column-name collisions; tag each row with `country_iso3` from
# the 3-letter filename prefix.
.load_afro_r10_country_files <- function() {
  r10_dir <- here::here("data", "afro", "raw", "round10")
  if (!dir.exists(r10_dir)) return(NULL)
  files <- list.files(r10_dir, pattern = "^[A-Z]{3}_R10.*\\.sav$", full.names = TRUE)
  if (length(files) == 0L) return(NULL)
  cat(sprintf("Loading R10 from %d country .sav files in %s ...\n",
              length(files), basename(r10_dir)))

  read_one <- function(path) {
    iso3 <- substr(basename(path), 1L, 3L)
    df <- haven::read_sav(path, encoding = "latin1")
    # Strip haven_labelled so bind_rows doesn't choke on per-country
    # label-set differences for the same variable name. Preserve storage type.
    df[] <- lapply(df, function(x) {
      if (inherits(x, "haven_labelled")) {
        if (typeof(x) == "character") as.character(x) else as.numeric(x)
      } else x
    })
    # Lowercase column names for consistency with the merged R1-R9 convention.
    names(df) <- tolower(names(df))
    df$country_iso3 <- iso3
    df
  }

  dfs <- lapply(files, read_one)

  # Coerce per-column type mismatches to character (safest common denominator),
  # matching the ABS W6 builder logic.
  all_cols <- unique(unlist(lapply(dfs, names)))
  for (col in all_cols) {
    types <- vapply(dfs, function(df) if (col %in% names(df)) typeof(df[[col]]) else NA_character_,
                    character(1))
    types <- types[!is.na(types)]
    if (length(unique(types)) > 1L) {
      for (i in seq_along(dfs)) {
        if (col %in% names(dfs[[i]])) dfs[[i]][[col]] <- as.character(dfs[[i]][[col]])
      }
    }
  }

  stacked <- bind_rows(dfs)
  cat(sprintf("  R10 stacked: %s rows across %d countries\n",
              format(nrow(stacked), big.mark = ","), length(files)))
  stacked
}

#' Load Afrobarometer wave data
#'
#' Loads Rounds 1-10. For R10, prefers a merged .sav if present at
#' data/afro/raw/round10/merged_r10_data.sav (auto-detected when AB
#' publishes one); otherwise stacks the per-country .sav files on the fly.
#' Skips any wave whose data is not yet on disk.
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
    w10 = here::here("data", "afro", "raw", "round10", "merged_r10_data.sav")
  )

  waves <- list()

  for (wave_name in names(wave_info)) {
    path <- wave_info[[wave_name]]

    # R10 fallback: if no merged file, stack the per-country files.
    if (wave_name == "w10" && !file.exists(path)) {
      stacked <- .load_afro_r10_country_files()
      if (!is.null(stacked)) {
        waves[[wave_name]] <- stacked
      } else {
        cat(sprintf("Skipping %s (no merged file and no per-country files)\n", wave_name))
      }
      next
    }

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
