# Joint EVS/WVS 2017-2022 (ZA7505 / WVSA joint release v5.0.0) — loader.
#
# SOURCE: data/wvs/raw/evs_wvs_joint/EVS_WVS_Joint_Spss_v5_0.sav
#   (internal version stamp 5-0-0 (2024-06-24); 156,658 respondents,
#   92 country-surveys, fieldwork years 2017-2023; `uniqid` fully unique.)
#
# ONE wave, keyed `joint2017_2022`. This is a CROSS-SECTION pooling two
# instruments — the `study` variable (1=EVS, 2=WVS) marks which; keep it in
# every model touching items with any study-specific fielding.
#
# LOADER-LEVEL DERIVATION: income arrives study-split (X047_WVS7 for WVS
# cases, X047E_EVS5 for EVS cases — both 1-10 income steps/deciles, verified
# 2026-08-10). They are coalesced here into `x047_joint` so the spec can map
# one source column; negatives (missing) in one column never overwrite a
# valid value in the other because each respondent has at most one of them.

library(here)
library(haven)

.EVS_WVS_JOINT_FILE <- file.path(
  "data", "wvs", "raw", "evs_wvs_joint", "EVS_WVS_Joint_Spss_v5_0.sav")

load_evs_wvs_joint_waves <- function() {

  cat("\n── Loading Joint EVS/WVS 2017-2022 ──\n")
  path <- here(.EVS_WVS_JOINT_FILE)
  if (!file.exists(path)) stop("Joint EVS/WVS file not found: ", path)

  d <- read_sav(path)

  # Coalesce the study-split income scales (see header).
  w <- as.numeric(d$X047_WVS7)
  e <- as.numeric(d$X047E_EVS5)
  w[w < 0] <- NA_real_
  e[e < 0] <- NA_real_
  d$x047_joint <- dplyr::coalesce(w, e)

  cat(sprintf("  joint2017_2022: %s rows, %d cols (income coalesced: %s valid)\n",
              format(nrow(d), big.mark = ","), ncol(d),
              format(sum(!is.na(d$x047_joint)), big.mark = ",")))

  list(joint2017_2022 = d)
}
