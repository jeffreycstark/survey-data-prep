# src/r/data_prep_modules/cfps/0_load_waves.R
# CFPS (China Family Panel Studies): load raw individual-level wave files
# -> named list(y2010, y2012, ... y2020)
#
# STATUS: SCAFFOLD. No CFPS data is present in this repo yet — access requires a
# data-use application to ISSS Peking University (https://cfpsdata.pku.edu.cn).
# Run 00_probe_variables.R first once the files land; nothing downstream of this
# file has verified source-variable names yet.
#
# WHY FILES ARE DISCOVERED, NOT HARDCODED
# CFPS release filenames carry a release-version stamp that changes between
# distributions (e.g. cfps2010adult_202008.dta vs a later re-release), and the
# individual-level file is named "adult" in the early waves and "person" in the
# later ones. Hardcoding either would break on a different download than the one
# this was written against. So: glob by wave year, report what was found, and
# make the caller confirm. Loud and inspectable beats silently loading the wrong
# file.

library(here); library(haven); library(dplyr); library(purrr)

# Wave years CFPS has released. 2010 is the baseline.
CFPS_WAVES <- c(2010, 2012, 2014, 2016, 2018, 2020)

# Individual-respondent file, by convention across releases. CFPS also ships
# family / child / community files per wave — those are NOT what this loads.
# The regex accepts both the early "adult" and later "person" naming.
CFPS_INDIV_PATTERN <- "(adult|person)"

#' Locate the individual-level CFPS file for one wave.
#'
#' Returns a single path, or NULL with a warning if zero / ambiguous matches.
find_cfps_wave_file <- function(year, raw_dir = here("data", "cfps", "raw")) {
  if (!dir.exists(raw_dir)) {
    stop("CFPS raw directory does not exist: ", raw_dir,
         "\n  CFPS has not been downloaded yet. See docs/surveys/cfps.md.")
  }

  pat <- sprintf("^cfps.*%d.*%s.*\\.dta$", year, CFPS_INDIV_PATTERN)
  hits <- list.files(raw_dir, pattern = pat, ignore.case = TRUE, full.names = TRUE)

  if (length(hits) == 0) {
    warning(sprintf("CFPS %d: no individual-level .dta matched /%s/ in %s",
                    year, pat, raw_dir))
    return(NULL)
  }
  if (length(hits) > 1) {
    warning(sprintf(
      "CFPS %d: %d files matched — resolve the ambiguity before trusting this load:\n%s",
      year, length(hits), paste0("    ", basename(hits), collapse = "\n")))
    return(NULL)
  }
  hits
}

#' Load all available CFPS individual-level waves.
#'
#' @param waves Integer vector of wave years to attempt.
#' @param strict If TRUE, error when any requested wave is missing. Default
#'   FALSE so a partial download is still usable for probing.
load_cfps_waves <- function(waves = CFPS_WAVES, strict = FALSE) {
  cat("\n── Loading CFPS raw waves ──\n")

  out <- list()
  for (yr in waves) {
    f <- find_cfps_wave_file(yr)
    if (is.null(f)) {
      msg <- sprintf("  y%d: NOT FOUND — skipped", yr)
      if (strict) stop(msg) else cat(msg, "\n")
      next
    }
    # encoding: Stata 14+ .dta is UTF-8 natively. Older releases may need an
    # explicit encoding (GB18030) — read_dta() will raise if it cannot decode,
    # which is the signal to add encoding = "GB18030" here.
    df <- haven::read_dta(f)
    cat(sprintf("  y%d: %s rows, %d cols  [%s]\n",
                yr, format(nrow(df), big.mark = ","), ncol(df), basename(f)))
    out[[sprintf("y%d", yr)]] <- df
  }

  if (length(out) == 0) {
    stop("No CFPS waves loaded. Has the data been downloaded to data/cfps/raw/?")
  }
  cat(sprintf("\nLoaded %d wave(s): %s\n", length(out), paste(names(out), collapse = ", ")))
  out
}

if (!interactive() && identical(environment(), globalenv())) {
  w <- load_cfps_waves()
  cat("\nLoaded:", paste(names(w), collapse = ", "), "\n")
}
