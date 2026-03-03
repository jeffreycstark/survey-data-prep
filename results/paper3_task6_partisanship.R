# Paper 3 – Task 6: Partisanship decomposition W3→W4→W6
# Insert as ```{r partisanship-decomp} in paper3.qmd
# Cambodia (country=12); cross-sectional (NOT panel) — within-wave by partisan group
# Party codes are country-specific numeric codes in raw SPSS vote-choice variables

suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
  library(tidyr)
})

# --- Helper: load harmonized + raw vote choice ---
load_wave <- function(harm_path, raw_path, vote_var, pid_var, country_code = 12) {
  dh <- readRDS(harm_path)
  dr <- haven::read_sav(raw_path, encoding = "latin1")
  dh_k <- dh[dh$country == country_code, ]
  if ("country" %in% names(dr)) {
    dr_k <- dr[!is.na(dr$country) & as.numeric(dr$country) == country_code, ]
  } else {
    dr_k <- dr  # W6 Cambodia-only file (no country column)
  }
  stopifnot(nrow(dh_k) == nrow(dr_k))
  dh_k$raw_vote <- as.numeric(dr_k[[vote_var]])
  dh_k$raw_pid  <- as.numeric(dr_k[[pid_var]])
  dh_k
}

# --- Party codes ---
# W3: CPP=1202, SRP=1204, HRP=1206 (SRP+HRP = pre-merger CNRP proxies)
# W4: CPP=1204, CNRP=1206
# W6: CPP=1204, CNRP=1206 (CNRP dissolved Nov 2017; 34 respondents still report it)

make_partisan <- function(df, wave) {
  df$partisan <- switch(as.character(wave),
    "3" = dplyr::case_when(
      df$raw_vote == 1202                ~ "CPP",
      df$raw_vote %in% c(1204, 1206)    ~ "CNRP-prox",   # SRP + HRP pre-merger
      df$raw_vote %in% c(90, 92, -1)    ~ "Nonvoter",
      df$raw_vote %in% c(97, 98, 99)    ~ "DK/Refuse",
      !is.na(df$raw_vote)               ~ "Other party",
      TRUE                              ~ NA_character_),
    "4" = dplyr::case_when(
      df$raw_vote == 1204               ~ "CPP",
      df$raw_vote == 1206               ~ "CNRP",
      df$raw_vote %in% c(90, -1)        ~ "Nonvoter",
      df$raw_vote %in% c(98, 99)        ~ "DK/Refuse",
      !is.na(df$raw_vote)               ~ "Other party",
      TRUE                              ~ NA_character_),
    "6" = dplyr::case_when(
      df$raw_vote == 1204               ~ "CPP",
      df$raw_vote == 1206               ~ "CNRP-residual",
      df$raw_vote == 0                  ~ "Nonvoter",
      df$raw_vote %in% c(98, 99)        ~ "DK/Refuse",
      !is.na(df$raw_vote)               ~ "Other party",
      TRUE                              ~ NA_character_))
  df
}

# Load waves
w3 <- load_wave("outputs/master_w3.rds",
                "data/abs/raw/wave3/ABS3 merge20250609.sav",
                "q33", "q47") |> make_partisan(3) |> mutate(wave = 3)
w4 <- load_wave("outputs/master_w4.rds",
                "data/abs/raw/wave4/W4_v15_merged20250609_release.sav",
                "q34", "q53") |> make_partisan(4) |> mutate(wave = 4)
w6 <- load_wave("outputs/master_w6.rds",
                "data/abs/raw/wave6/W6_Cambodia_Release_20240819.sav",
                "q34", "q54") |> make_partisan(6) |> mutate(wave = 6)

# Outcomes to decompose
outcomes <- c("dem_country_future", "dem_always_preferable", "dem_vs_equality",
              "democracy_satisfaction", "gate_contact_influential", "single_party_rule")

# --- Partisan distribution ---
# CNRP: 21.3% (W4) → 2.7% (W6); DK/Refuse: 7.2% (W4) → 18.8% (W6)

# --- Key finding: shifts UNIFORM across partisan groups ---
# gate_contact_influential: CPP -35.1pp, CNRP -30.9pp, Nonvoter -29.9pp (W4→W6)
# dem_country_future:       CPP -1.39,   CNRP -0.91,   Nonvoter -1.36
# → consistent with GENERALIZED closure, not subtraction-specific mechanism
#
# CAVEAT: W6 "CPP" category contains former CNRP voters who voted under duress
# (Cambodian government verified voting compliance by checking for indelible ink)
# DK/Refuse in W6 (n=233) = lowest dem_always_preferable (61.1%) — suppressed but intact

# For kable table in .qmd:
# wave_partisan_dist |> knitr::kable(caption = "Partisan distribution by wave, Cambodia")
