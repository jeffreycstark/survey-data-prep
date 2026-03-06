# 00_load_data.R
# Paper 10: Democratic Aspiration Gap
# Load harmonized datasets from all four surveys
#
# Variable map: analysis/cross_survey_variable_map.md

library(tidyverse)
library(here)

# ── ABS (6 waves, 16 countries, 110,721 respondents) ────────────────────────
# Per-wave files for time-series analysis
abs_waves <- list(
  w1 = readRDS(here("outputs", "master_w1.rds")),
  w2 = readRDS(here("outputs", "master_w2.rds")),
  w3 = readRDS(here("outputs", "master_w3.rds")),
  w4 = readRDS(here("outputs", "master_w4.rds")),
  w5 = readRDS(here("outputs", "master_w5.rds")),
  w6 = readRDS(here("outputs", "master_w6.rds"))
)

# Combined file
abs <- readRDS(here("data", "processed", "abs_harmonized.rds"))

cat("ABS:", nrow(abs), "rows,", length(unique(abs$country)), "countries,",
    length(unique(abs$wave)), "waves\n")

# ── Afrobarometer (9 rounds, 39 countries, ~53k per round) ──────────────────
afro <- readRDS(here("data", "processed", "afro_harmonized.rds"))

cat("Afro:", nrow(afro), "rows,", length(unique(afro$country)), "countries,",
    length(unique(afro$wave)), "waves\n")

# ── LBS (24 waves 1995-2024, 18 countries, ~20k per wave) ──────────────────
lbs <- readRDS(here("data", "processed", "lbs_harmonized.rds"))

cat("LBS:", nrow(lbs), "rows,", length(unique(lbs$country)), "countries,",
    length(unique(lbs$wave)), "waves\n")

# ── WVS (2 waves, 84 countries, 186,785 respondents) ───────────────────────
wvs <- readRDS(here("data", "processed", "wvs_harmonized.rds"))

cat("WVS:", nrow(wvs), "rows,", length(unique(wvs$country)), "countries,",
    length(unique(wvs$wave)), "waves\n")

# ── Key variable cross-references ───────────────────────────────────────────
# See cross_survey_variable_map.md for full details.
#
# TRUST (all 1-4, higher = more trust, no polarity conflicts):
#   Executive:     trust_president, trust_police, trust_military/trust_armed_forces
#   Intermediary:  trust_parliament, trust_political_parties, trust_courts, trust_election(s)
#
# AUTHORITARIAN ALTERNATIVES:
#   ABS: strongman_rule, expert_rule, military_rule, single_party_rule (1-4, high = more auth)
#   LBS: strongman_mano_dura (0/1, 1 = pro-strongman)
#   Afro: reject_one_party, reject_military_rule, reject_one_man_rule (1-5, high = MORE REJECTION)
#   WVS: dem_strong_leader, dem_experts_rule, dem_army_rule (1-4, high = more auth)
#   !! Afro polarity is REVERSED relative to ABS/WVS/LBS !!
#
# DEMOCRACY PREFERABLE (all 1-3 nominal, directly comparable):
#   ABS:  dem_always_preferable   (1=Dem, 2=Auth, 3=Doesn't matter)
#   Afro: dem_support_preferable  (1=Dem, 2=Auth, 3=Doesn't matter)
#   LBS:  dem_always_preferable   (1=Dem, 2=Auth, 3=Doesn't matter)
#
# ECON EVALUATIONS (all 1-5, higher = better, directly comparable):
#   ABS:  econ_national_now, econ_family_now
#   Afro: econ_national_current, econ_living_conditions
#   LBS:  econ_national_current, econ_personal_current
#
# DEM SATISFACTION (1-4, higher = more satisfied — but WVS uses 1-10):
#   ABS:  democracy_satisfaction
#   Afro: dem_satisfaction
#   LBS:  dem_satisfaction
#   WVS:  dem_satisfaction_political_system (1-10, W7 only)
