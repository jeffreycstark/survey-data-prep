#!/usr/bin/env Rscript
# Build data/processed/w6.rds by stacking all ABS Wave 6 country .sav files.
#
# Why this exists: the original w6.rds was built ad-hoc from interactive R.
# This script reproduces the build deterministically so adding a new country
# release is just: drop the .sav into data/abs/raw/wave6/ and rerun.
#
# Output: data/processed/w6.rds — one row per respondent across all W6
# countries, plus a `country` character column matching the existing
# w6.rds convention (full English country name, e.g. "Korea", "Japan").

suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
  library(here)
  library(stringr)
})

wave6_dir <- here::here("data", "abs", "raw", "wave6")
out_path  <- here::here("data", "processed", "w6.rds")

sav_files <- list.files(wave6_dir, pattern = "^W6_.*\\.sav$", full.names = TRUE)
cat(sprintf("Found %d Wave 6 country .sav files in %s\n",
            length(sav_files), wave6_dir))

# Country names extracted from the filename. ABS releases use a few naming
# patterns; this strips the prefix/suffix and recovers the country word.
country_from_filename <- function(path) {
  base <- tools::file_path_sans_ext(basename(path))
  # Strip leading "W6_" and any leading digit-then-underscore segment
  s <- sub("^W6_", "", base)
  s <- sub("^[0-9]+_", "", s)
  # Drop trailing _Release_<date>, _release_<date>, _EN_<date>
  s <- sub("(_Release_|_release_|_EN_).*$", "", s)
  s
}

countries <- vapply(sav_files, country_from_filename, character(1))
names(countries) <- NULL

cat("Country mapping from filename:\n")
print(setNames(countries, basename(sav_files)))

# Read each file, attach country column, drop haven labels for safe stacking.
read_one <- function(path, country_name) {
  df <- haven::read_sav(path)
  # Strip haven_labelled so bind_rows doesn't choke on type mismatches across
  # country files (different countries can have different label sets for the
  # same variable name). Cast preserving the underlying storage type — numeric
  # for numeric-coded vars, character for the few labelled-character vars.
  df[] <- lapply(df, function(x) {
    if (inherits(x, "haven_labelled")) {
      if (typeof(x) == "character") as.character(x) else as.numeric(x)
    } else x
  })
  df$country <- country_name
  df
}

dfs <- Map(read_one, sav_files, countries)
names(dfs) <- countries

# Lowercase column names — the existing w6.rds convention uses lowercase
# (country, year, month, idnumber, region, level, ...). Each raw .sav also
# has a numeric COUNTRY column that lowercases to "country", colliding with
# our added country-name string. Rename the raw numeric one to country_code
# so both survive.
dfs <- lapply(dfs, function(df) {
  names(df) <- tolower(names(df))
  if ("country" %in% names(df) && "country_code" %in% names(df) == FALSE) {
    # The raw numeric COUNTRY → country_code; our added string country (added
    # last in read_one) overwrote it. Recover by re-adding both clearly.
  }
  df
})

# Resolve the country-name collision: the raw numeric COUNTRY (now lowercase
# "country") appears twice per df because we appended a string country in
# read_one. Drop the numeric duplicate; the string country is the one we
# want, matching existing w6.rds convention.
dfs <- lapply(dfs, function(df) {
  cc <- which(names(df) == "country")
  if (length(cc) >= 2) {
    # Keep the LAST occurrence (the string country we appended) and rename the
    # earlier numeric COUNTRY to country_code.
    str_idx <- cc[length(cc)]
    num_idx <- cc[-length(cc)]
    names(df)[num_idx] <- "country_code"
  }
  df
})

# Resolve type conflicts before bind_rows. For each column appearing in 2+
# country files, if any source has a character type, coerce all to character
# (safest common denominator — preserves leading zeros, mixed encodings, etc.).
all_cols <- unique(unlist(lapply(dfs, names)))
for (col in all_cols) {
  types <- vapply(dfs, function(df) if (col %in% names(df)) typeof(df[[col]]) else NA_character_,
                  character(1))
  types <- types[!is.na(types)]
  if (length(unique(types)) > 1L) {
    # Mixed types — coerce every source to character
    for (cn in names(dfs)) {
      if (col %in% names(dfs[[cn]])) {
        dfs[[cn]][[col]] <- as.character(dfs[[cn]][[col]])
      }
    }
  }
}

# bind_rows fills missing columns with NA — we want the column union.
w6 <- bind_rows(dfs)

# Move country to the front to match existing convention
if ("country" %in% names(w6)) {
  w6 <- w6[, c("country", setdiff(names(w6), "country"))]
}

cat(sprintf("\nStacked Wave 6: %s rows × %d cols\n",
            format(nrow(w6), big.mark = ","), ncol(w6)))
cat("Per-country n:\n")
print(w6 %>% count(country) %>% arrange(country))

dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
saveRDS(w6, out_path)
cat(sprintf("\nWrote %s\n", out_path))
