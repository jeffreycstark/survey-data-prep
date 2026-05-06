# KINU Unification Survey: Load raw wave file
#
# Returns a named list: list(w2014 = df, w2015 = df, ..., w2023 = df)
#
# Source file:
#   data/kinu/raw/kinu_2014-2023_en.sav  (n=13,030, 13 waves 2014-2023)
#
# The cumulative .sav has a single `year` column with integer codes 1-13
# whose haven value labels indicate calendar year + fieldwork month.
# 2019, 2020, and 2021 each have TWO fieldwork rounds, so we keep them
# as distinct sub-waves (a/b suffix), matching the codebook's convention.
#
# Year integer → wave key mapping:
#   1  → w2014    (single round, ~Apr)
#   2  → w2015    (single round)
#   3  → w2016    (single round)
#   4  → w2017    (single round)
#   5  → w2018    (single round, Apr)
#   6  → w2019a   (Apr 2019)
#   7  → w2019b   (Sep 2019)
#   8  → w2020a   (Jun 2020)
#   9  → w2020b   (Nov 2020)
#   10 → w2021a   (Apr 2021)
#   11 → w2021b   (Oct 2021)
#   12 → w2022    (single round, Apr)
#   13 → w2023    (single round, Apr)
#
# NOTE: 2024 wave exists in codebook but is NOT in the dataset file we hold.

library(here)
library(haven)

KINU_YEAR_TO_WAVE <- c(
  "1"  = "w2014",
  "2"  = "w2015",
  "3"  = "w2016",
  "4"  = "w2017",
  "5"  = "w2018",
  "6"  = "w2019a",
  "7"  = "w2019b",
  "8"  = "w2020a",
  "9"  = "w2020b",
  "10" = "w2021a",
  "11" = "w2021b",
  "12" = "w2022",
  "13" = "w2023"
)

# Map wave key → calendar year integer (subwave-collapsing)
KINU_WAVE_TO_YEAR <- setNames(
  c(2014, 2015, 2016, 2017, 2018,
    2019, 2019, 2020, 2020, 2021, 2021,
    2022, 2023),
  c("w2014","w2015","w2016","w2017","w2018",
    "w2019a","w2019b","w2020a","w2020b","w2021a","w2021b",
    "w2022","w2023")
)

# Map wave key → fieldwork month (NA if unknown)
KINU_WAVE_TO_MONTH <- setNames(
  c(NA, NA, NA, NA, 4,
    4, 9, 6, 11, 4, 10,
    4, 4),
  c("w2014","w2015","w2016","w2017","w2018",
    "w2019a","w2019b","w2020a","w2020b","w2021a","w2021b",
    "w2022","w2023")
)

load_kinu_waves <- function() {

  cat("\n── Loading KINU raw waves ──\n")

  sav_path <- here("data", "kinu", "raw", "kinu_2014-2023_en.sav")
  if (!file.exists(sav_path)) stop("File not found: ", sav_path)

  cat(sprintf("  Reading: %s\n", basename(sav_path)))
  raw <- read_sav(sav_path)
  cat(sprintf("  Full file: %s rows, %d cols\n",
              format(nrow(raw), big.mark = ","), ncol(raw)))

  # Coerce year (haven_labelled) to integer for splitting
  raw$year_int <- as.integer(raw$year)
  yrs_found <- sort(unique(raw$year_int))
  cat(sprintf("  Year codes found: %s\n", paste(yrs_found, collapse = ", ")))

  unknown <- setdiff(as.character(yrs_found), names(KINU_YEAR_TO_WAVE))
  if (length(unknown) > 0) {
    stop("Unknown KINU year codes (no wave-key mapping): ",
         paste(unknown, collapse = ", "))
  }

  waves <- split(raw, raw$year_int)
  names(waves) <- KINU_YEAR_TO_WAVE[as.character(yrs_found)]

  for (wn in names(waves)) {
    cat(sprintf("  %s: %s rows\n", wn,
                format(nrow(waves[[wn]]), big.mark = ",")))
  }

  waves
}

# When run directly, print a quick summary
if (!interactive() && identical(environment(), globalenv())) {
  waves <- load_kinu_waves()
  cat("\nLoaded waves:", paste(names(waves), collapse = ", "), "\n")
  cat(sprintf("Total: %s respondents across %d wave files\n",
              format(sum(sapply(waves, nrow)), big.mark = ","),
              length(waves)))
}
