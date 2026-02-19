# V-Dem: Load raw dataset
#
# V-Dem (Varieties of Democracy) v15 — country-year panel.
# Unit of observation: country × year (NOT individual respondents).
#
# Source file:
#   data/v-dem/raw/v15/V-Dem-CY-Full+Others-v15.rds
#   (27,913 rows × 4,607 columns; 202 countries; 1789–2024)
#
# Key identifiers:
#   country_name     — full country name
#   country_text_id  — ISO 3-letter alpha code (e.g. "USA", "KOR")
#   country_id       — V-Dem internal numeric ID
#   COWcode          — Correlates of War numeric code
#   year             — calendar year
#
# NOTE: This is a very wide dataset. Downstream scripts should select only
# the columns they need before merging with survey data.

library(here)

load_vdem <- function(version = "v15") {

  path <- here("data", "v-dem", "raw", version,
               paste0("V-Dem-CY-Full+Others-", version, ".rds"))

  if (!file.exists(path)) {
    stop("V-Dem file not found: ", path,
         "\nExpected: data/v-dem/raw/", version, "/")
  }

  cat("\n── Loading V-Dem", version, "──\n")
  d <- readRDS(path)
  cat(sprintf("  %s rows × %d cols | %d countries | %d–%d\n",
              format(nrow(d), big.mark = ","),
              ncol(d),
              length(unique(d$country_name)),
              min(d$year, na.rm = TRUE),
              max(d$year, na.rm = TRUE)))
  d
}

# When run directly, print a quick summary
if (!interactive() && identical(environment(), globalenv())) {
  vdem <- load_vdem()

  cat("\nIdentifier columns:\n")
  id_cols <- c("country_name", "country_text_id", "country_id", "COWcode", "year")
  for (col in id_cols) {
    cat(sprintf("  %-20s %s\n", col,
                if (is.numeric(vdem[[col]])) {
                  sprintf("range %g–%g", min(vdem[[col]], na.rm=TRUE),
                                          max(vdem[[col]], na.rm=TRUE))
                } else {
                  sprintf("e.g. %s", paste(head(unique(vdem[[col]]), 5), collapse=", "))
                }))
  }
}
