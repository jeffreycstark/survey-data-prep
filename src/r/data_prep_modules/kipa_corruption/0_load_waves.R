# KIPA Survey on Corruption in Public Office (공직부패의 실태에 관한 설문조사)
# Load raw wave files into a year-keyed list.
#
# Source files live in data/kipa_corruption/raw/unzipped/<handle>/ with the
# following year mapping (determined from KOSSDA handles):
#
#   Cumulative (2004-2007):  13081 / kor_data_cum0009.sav  (n=2000; year col = 1..4)
#   Individual annual files: one per year 2008-2023 (n=1000 each)
#
# The cumulative file contains 4 pooled years with a `year` column valued 1..4.
# We split it into four wave-keyed data frames so the harmonization engine
# can treat each calendar year uniformly.
#
# NOTE on encoding: 2009-2021 .sav files use EUC-KR for labels; 2008/2022/2023
# use UTF-8. haven::read_sav reads variable names as ASCII in all cases, so
# the harmonization pipeline works regardless. Labels may appear as mojibake
# when printed; that does not affect numeric processing.

library(here)
library(haven)

# Map handle directory -> year label for wave names (w{year}).
# Keyed values: the file pattern in that directory.
.kipa_corruption_handle_year <- list(
  "13081" = "cum",       # Cumulative 2004-2007 (split below)
  "13988" = "2008",
  "15387" = "2009",
  "15386" = "2010",
  "15356" = "2011",
  "15788" = "2012",
  "23278" = "2013",
  "23277" = "2014",
  "23276" = "2015",
  "23275" = "2016",
  "23266" = "2017",
  "24741" = "2018",
  "24742" = "2019",
  "24743" = "2020",
  "25785" = "2021",
  "26248" = "2022",
  "30856" = "2023"
)

load_kipa_corruption_waves <- function() {

  cat("\n── Loading KIPA Corruption raw waves ──\n")

  base_dir <- here("data", "kipa_corruption", "raw", "unzipped")
  if (!dir.exists(base_dir)) {
    stop("Unzipped directory not found: ", base_dir)
  }

  waves <- list()

  for (handle in names(.kipa_corruption_handle_year)) {
    yr <- .kipa_corruption_handle_year[[handle]]
    hdir <- file.path(base_dir, handle)
    if (!dir.exists(hdir)) {
      message(sprintf("  [skip] handle %s: directory missing", handle))
      next
    }

    sav_files <- list.files(hdir, pattern = "\\.sav$|\\.SAV$", full.names = TRUE)
    # Prefer Korean-label file over English when both exist (Korean is source of truth)
    kor <- sav_files[!grepl("^eng_", basename(sav_files), ignore.case = FALSE)]
    sav <- if (length(kor)) kor[1] else sav_files[1]

    if (!length(sav)) {
      message(sprintf("  [skip] handle %s: no .sav file", handle))
      next
    }

    d <- suppressWarnings(read_sav(sav))

    if (yr == "cum") {
      # Cumulative file: split by the `year` column (values 1..4 → 2004..2007)
      if (!"year" %in% names(d)) {
        stop("Cumulative file missing `year` column: ", sav)
      }
      year_codes <- as.integer(zap_labels(d$year))
      code_to_year <- c("1" = "2004", "2" = "2005", "3" = "2006", "4" = "2007")
      for (code in names(code_to_year)) {
        wyear <- code_to_year[[code]]
        wname <- paste0("w", wyear)
        sub <- d[year_codes == as.integer(code), , drop = FALSE]
        waves[[wname]] <- sub
        cat(sprintf("  [cum] w%s: %s rows\n", wyear,
                    format(nrow(sub), big.mark = ",")))
      }
    } else {
      wname <- paste0("w", yr)
      waves[[wname]] <- d
      cat(sprintf("  [ann] %s: %s rows  (%s)\n", wname,
                  format(nrow(d), big.mark = ","), basename(sav)))
    }
  }

  # Sort waves chronologically
  waves <- waves[order(names(waves))]

  cat(sprintf("\n  Total: %d waves, %s respondents\n",
              length(waves),
              format(sum(sapply(waves, nrow)), big.mark = ",")))

  waves
}

# When run directly, print a summary
if (!interactive() && identical(environment(), globalenv())) {
  waves <- load_kipa_corruption_waves()
  cat("\nLoaded waves:", paste(names(waves), collapse = ", "), "\n")
}
