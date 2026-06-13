# Global Corruption Barometer (GCB): Load raw edition files
#
# Returns a named list keyed by REGIONAL EDITION (the GCB "wave"):
#   list(asia2020 = df, ...)
#
# Unlike the multi-year surveys, GCB's unit of release is a regional edition.
# Transparency International publishes one microdata file per region per round
# (Asia 2020 = Edition 10). Each file is a multi-country cross-section: country
# is a per-respondent column (TCOUNTRY), not a separate file. This mirrors ABS
# (country column + per-wave files), with the "wave" being the region-edition.
#
# Source files (one .sav per edition):
#   data/gcb/raw/asia2020/GCB_Edition10_Asia_2020.sav
#     n=19,416 | 17 countries | fieldwork spanning 2019-2020
#
# Adding a second region (the consistency test): drop its .sav under
#   data/gcb/raw/<edition_key>/  and add one row to GCB_EDITIONS below. Then
# extend each YAML spec's `source:` block with the new edition's raw variable
# names — which is exactly where cross-edition naming differences surface, and
# where the source-coverage reconciler / completeness check will flag any gaps.
#
# NOTE: GCB column names carry survey-firm suffixes (…FIN = final/cleaned,
# …FINB = a dichotomized variant). Whether a second region reuses these exact
# names is unknown until its file lands — hence the per-edition source mapping.

library(here)
library(haven)

# edition key → relative .sav path (under data/gcb/raw/)
GCB_EDITIONS <- c(
  asia2020 = "asia2020/GCB_Edition10_Asia_2020.sav"
)

# edition key → human-readable metadata (carried into the final dataset)
GCB_EDITION_REGION <- c(asia2020 = "Asia")
GCB_EDITION_YEAR   <- c(asia2020 = 2020L)

load_gcb_waves <- function() {

  cat("\n── Loading GCB editions ──\n")

  waves <- list()
  for (key in names(GCB_EDITIONS)) {
    sav_path <- here("data", "gcb", "raw", GCB_EDITIONS[[key]])
    if (!file.exists(sav_path)) {
      stop("File not found: ", sav_path,
           "\n  (declared for edition '", key, "' in GCB_EDITIONS)")
    }
    cat(sprintf("  Reading %s: %s\n", key, basename(sav_path)))
    df <- read_sav(sav_path)
    cat(sprintf("    %s rows, %d cols\n",
                format(nrow(df), big.mark = ","), ncol(df)))
    waves[[key]] <- df
  }

  waves
}

# When run directly, print a quick summary
if (!interactive() && identical(environment(), globalenv())) {
  waves <- load_gcb_waves()
  cat("\nLoaded editions:", paste(names(waves), collapse = ", "), "\n")
  cat(sprintf("Total: %s respondents across %d edition(s)\n",
              format(sum(sapply(waves, nrow)), big.mark = ","),
              length(waves)))
}
