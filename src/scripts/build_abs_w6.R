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

# Value labels captured per country BEFORE stripping, so they can be restored
# after the bind. See .restore_value_labels() below for why.
.w6_label_sets <- new.env(parent = emptyenv())
.w6_var_labels <- new.env(parent = emptyenv())

# Read each file, attach country column, drop haven labels for safe stacking.
read_one <- function(path, country_name) {
  df <- haven::read_sav(path)
  # Capture the value labels first — stripping them was losing metadata that
  # exists in every country file (see .restore_value_labels()).
  .w6_label_sets[[country_name]] <- lapply(df, function(x) attr(x, "labels"))
  # ...and the question text. attr() PARTIAL-MATCHES, so once a column carries
  # `labels` but no `label`, attr(x, "label") silently returns the value-label
  # vector instead of NULL — which recycles into duplicate rows in any
  # data.frame() built from it. Restoring the real `label` removes that trap.
  .w6_var_labels[[country_name]] <- lapply(df, function(x) attr(x, "label", exact = TRUE))
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

#' Restore the question text (`label`) onto the stacked frame.
#'
#' Unlike value labels, where a cross-country disagreement can mean a code means
#' DIFFERENT THINGS and must never be merged, question-text variance is
#' translation and typo noise ("how serious is it in your view?" vs "how serious
#' it is in your view?"). The modal text is therefore used, and the number of
#' columns with variants is reported so the noise stays visible.
#'
#' This exists as much for hygiene as for metadata: without a real `label`,
#' attr(x, "label") partial-matches `labels` and returns a vector.
.restore_var_labels <- function(df, label_sets) {
  restored <- 0L; variant <- 0L; none <- 0L
  for (col in names(df)) {
    txt <- unlist(Filter(function(z) !is.null(z) && nzchar(z),
                         lapply(label_sets, function(cl) cl[[col]])))
    if (!length(txt)) { none <- none + 1L; next }
    tab <- sort(table(txt), decreasing = TRUE)
    attr(df[[col]], "label") <- names(tab)[1]
    restored <- restored + 1L
    if (length(tab) > 1L) variant <- variant + 1L
  }
  cat(sprintf("Question text restored: %d columns | %d had country variants (modal used) | %d had none\n",
              restored, variant, none))
  df
}

#' Restore value labels onto the stacked frame.
#'
#' Stripping labels before bind_rows is necessary — countries genuinely differ
#' in their label sets and bind_rows fails on the resulting type mismatches —
#' but discarding them permanently left W6 unverifiable. `data/processed/w6.rds`
#' retained value labels on 0 of 488 columns, which is why label reconciliation
#' reported `too_few_labels` for 192 W6 rows (193 variables) and why the
#' `govt_responds_people` w6 direction had to be confirmed by correlation rather
#' than read off the metadata that was sitting in all twelve source files.
#'
#' A label set is restored ONLY when every country that has one agrees on it,
#' code for code. Where countries disagree the column is left unlabelled and the
#' conflict is reported — a disagreement is a real finding in its own right (cf.
#' the W6 Thailand `REGION` 803/804 swap documented in CLAUDE.md), not something
#' to paper over by picking one country's labels.
#'
#' Only the `labels` ATTRIBUTE is attached, never the `haven_labelled` class:
#' values and storage types stay byte-identical, so no downstream consumer
#' changes behaviour, while `attr(x, "labels")` — all the audit reads — works.
.restore_value_labels <- function(df, label_sets) {
  canon <- function(l) {
    if (is.null(l) || !length(l)) return(NA_character_)
    o <- order(unname(l))
    paste(sprintf("%s=%s", unname(l)[o], names(l)[o]), collapse = "")
  }
  restored <- 0L; conflicts <- character(0); unlabelled <- 0L
  for (col in names(df)) {
    sets <- Filter(Negate(is.null), lapply(label_sets, function(cl) cl[[col]]))
    if (!length(sets)) { unlabelled <- unlabelled + 1L; next }
    sigs <- unique(vapply(sets, canon, character(1)))
    if (length(sigs) > 1L) { conflicts <- c(conflicts, col); next }
    attr(df[[col]], "labels") <- sets[[1]]
    restored <- restored + 1L
  }
  cat(sprintf("\nValue labels restored: %d columns | conflicting across countries: %d | never labelled: %d\n",
              restored, length(conflicts), unlabelled))
  if (length(conflicts)) {
    cat("  columns whose countries disagree (left unlabelled, worth a look):\n    ",
        paste(utils::head(conflicts, 25), collapse = ", "),
        if (length(conflicts) > 25) sprintf(" ... +%d more", length(conflicts) - 25) else "", "\n")
  }
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

# Restore the value labels stripped in read_one() — attribute only, so values
# and types are unchanged.
w6 <- .restore_value_labels(w6, as.list(.w6_label_sets))
w6 <- .restore_var_labels(w6, as.list(.w6_var_labels))

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
