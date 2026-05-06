# IPUS Unification Survey: Load raw wave files
#
# Returns a named list: list(w2007 = df, w2008 = df, ..., w2024 = df)
#
# Source files:
#   data/ipus/raw/{YYYY}/ipus_{YYYY}.sav   (one .sav per year, 2007-2024)
#
# IPUS = SNU Institute for Peace and Unification Studies (서울대 통일평화연구원).
# Annual since 2007; n=1,200 each year (n=1,213 in 2008, 1,203 in 2009, 1,201 in 2011).
# Total: 21,617 respondents across 18 waves.
#
# ENCODING NOTES:
#   Some years' .sav files have Korean variable labels written in CP949
#   (Korean Windows codepage) but no encoding marker, so haven::read_sav
#   defaults to UTF-8 and produces mojibake. We pass encoding="CP949"
#   explicitly for those years.
#
#   - CP949 years: 2008, 2009, 2013, 2014, 2015, 2016
#   - UTF-8 years: 2007, 2010, 2011, 2012, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024
#
# WAVE NAMING:
#   wave key is "w{year}" matching KGSS/KINU convention. Calendar year
#   integer is added to the per-wave dataframe as `year` since IPUS files
#   do not embed it.

library(here)
library(haven)

IPUS_YEARS <- 2007:2024

# Years whose .sav files need CP949 encoding for Korean labels
IPUS_CP949_YEARS <- c(2008, 2009, 2013, 2014, 2015, 2016)

load_ipus_waves <- function() {

  cat("\n── Loading IPUS raw waves ──\n")

  waves <- list()
  for (yr in IPUS_YEARS) {
    f <- here("data", "ipus", "raw", as.character(yr), sprintf("ipus_%d.sav", yr))
    if (!file.exists(f)) stop("File not found: ", f)

    enc <- if (yr %in% IPUS_CP949_YEARS) "CP949" else NULL
    df  <- if (is.null(enc)) read_sav(f) else read_sav(f, encoding = enc)

    df$year <- as.integer(yr)
    waves[[paste0("w", yr)]] <- df

    cat(sprintf("  w%d: %s rows, %d cols%s\n",
                yr, format(nrow(df), big.mark = ","), ncol(df),
                if (!is.null(enc)) sprintf(" [encoding=%s]", enc) else ""))
  }

  waves
}

# When run directly, print a summary
if (!interactive() && identical(environment(), globalenv())) {
  waves <- load_ipus_waves()
  cat("\nLoaded waves:", paste(names(waves), collapse = ", "), "\n")
  cat(sprintf("Total: %s respondents across %d years\n",
              format(sum(sapply(waves, nrow)), big.mark = ","),
              length(waves)))
}
