# src/r/utils/spec_discovery.R
# Canonical spec-discovery utility (audit ticket A3 / CC1)
#
# Single source of truth for "where does this survey's harmonization
# YAML spec directory live, and what production specs are in it?"
#
# Every survey uses `harmonize/`. ABS used to be the exception, reading a
# curated `harmonize_validated/`; the two were merged 2026-08-07 so the layout
# is uniform. Draft specs live in `<survey>/_drafts/` and are never loaded.

library(here)

#' Find the canonical harmonization spec directory for a survey
#'
#' @param survey Character: survey directory name under `src/config/`
#'   (e.g. "abs", "kgss", "ipus", "wvs"). Always resolves to
#'   `src/config/<survey>/harmonize/`.
#'
#' @return Absolute path (character) to the spec directory.
#'   Errors informatively if the directory does not exist.
#'
#' @export
find_survey_spec_dir <- function(survey) {

  if (missing(survey) || is.null(survey) || !nzchar(survey)) {
    stop("find_survey_spec_dir(): `survey` must be a non-empty string", call. = FALSE)
  }

  subdir <- "harmonize"
  spec_dir <- here::here("src", "config", survey, subdir)

  if (!dir.exists(spec_dir)) {
    # Try to give a helpful message that distinguishes "no such survey"
    # from "survey exists but spec dir is missing".
    survey_root <- here::here("src", "config", survey)
    if (!dir.exists(survey_root)) {
      stop(sprintf(
        "find_survey_spec_dir(): no config directory for survey '%s' (looked for %s)",
        survey, survey_root
      ), call. = FALSE)
    }
    stop(sprintf(
      "find_survey_spec_dir(): survey '%s' exists at %s but spec subdir '%s' is missing",
      survey, survey_root, subdir
    ), call. = FALSE)
  }

  spec_dir
}


#' List production YAML spec files for a survey
#'
#' Returns absolute paths to `.yml` files in the survey's canonical spec
#' directory, excluding template/documentation files (case-insensitive
#' match on `MODEL_VARIABLE`, `TEMPLATE`, `README`).
#'
#' @param survey Character: survey directory name under `src/config/`.
#'
#' @return Character vector of absolute paths.
#'
#' @export
list_survey_specs <- function(survey) {
  spec_dir <- find_survey_spec_dir(survey)

  files <- list.files(
    spec_dir,
    pattern = "\\.yml$",
    full.names = TRUE
  )

  exclude_patterns <- c("MODEL_VARIABLE", "TEMPLATE", "README")
  excl_re <- paste(exclude_patterns, collapse = "|")
  files <- files[!grepl(excl_re, basename(files), ignore.case = TRUE)]

  # `list.files(full.names = TRUE)` already returns paths anchored at
  # `spec_dir`, which is absolute (here::here resolves to absolute).
  # Normalize defensively in case CWD-relative roots ever sneak in.
  normalizePath(files, winslash = "/", mustWork = FALSE)
}
