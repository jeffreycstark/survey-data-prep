#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# KIPA Social Cohesion Survey (사회통합실태조사) — Trust & Honesty Harmonization
#
# Loads 14 annual SPSS files (2011-2024), harmonizes:
#   - trust_* : 기관별 신뢰 정도 (institutional trust/confidence)
#   - honesty_* : 기관별 청렴도 (institutional integrity/honesty)
# These are conceptually distinct dimensions exported as separate columns.
# Uses label-based matching (question number prefixes shift across years).
#
# Key design decisions:
#   - 2012 excluded: different survey design, no institutional trust battery
#   - 2011: 5-point trust scale (rescaled to 4-point); no honesty battery
#   - 2013-2024: both trust and honesty batteries present (4-point scale)
#   - Institution suffix ordering shifts across years → matched by label
#
# Exports:
#   data/processed/kipa_trust_harmonized.rds
#   data/processed/kipa_trust_harmonized.parquet
#   data/kipa/kipa_annual_trust_means.csv
# ─────────────────────────────────────────────────────────────────────────────

library(haven)
library(arrow)

cat("\n══ KIPA Social Cohesion Survey — Trust Harmonization ══\n\n")

# ── Label-to-harmonized-name mapping ─────────────────────────────────────────
# Map Korean label keywords to harmonized variable names.
# Order matters: first match wins. These patterns match across all years.

inst_label_map <- list(
  list(pattern = "중앙정부",          name = "trust_central_govt"),
  list(pattern = "국회",              name = "trust_national_assembly"),
  list(pattern = "법원|대법원",       name = "trust_courts"),
  list(pattern = "검찰",              name = "trust_prosecution"),
  list(pattern = "경찰",              name = "trust_police"),
  list(pattern = "지방자치",          name = "trust_local_govt"),
  list(pattern = "공기업",            name = "trust_public_enterprises"),
  list(pattern = "군대|군$",          name = "trust_military"),
  list(pattern = "노동조합",          name = "trust_labor_unions"),
  list(pattern = "시민단체",          name = "trust_civic_orgs"),
  list(pattern = "TV방송|TV|방송사",  name = "trust_tv"),
  list(pattern = "신문사|신문$",      name = "trust_newspapers"),
  list(pattern = "교육기관|교육계",   name = "trust_education"),
  list(pattern = "의료기관|의료계",   name = "trust_medical"),
  list(pattern = "대기업",            name = "trust_large_corps"),
  list(pattern = "종교기관|종교계|종교단체", name = "trust_religious"),
  list(pattern = "금융기관|금융$",    name = "trust_financial"),
  # 2011-only institutions
  list(pattern = "기업$",             name = "trust_corporations"),
  list(pattern = "언론$",             name = "trust_media"),
  list(pattern = "정당",              name = "trust_political_parties"),
  list(pattern = "청와대",            name = "trust_blue_house")
)

# ── Honesty/integrity label map (기관별 청렴도) ────────────────────────────────
# Same institution set as trust, matched via 청렴도 labels.
# Available 2013-2024 (not 2011, not 2012).

honesty_label_map <- list(
  list(pattern = "중앙정부",          name = "honesty_central_govt"),
  list(pattern = "국회",              name = "honesty_national_assembly"),
  list(pattern = "법원|대법원",       name = "honesty_courts"),
  list(pattern = "검찰",              name = "honesty_prosecution"),
  list(pattern = "경찰",              name = "honesty_police"),
  list(pattern = "지방자치",          name = "honesty_local_govt"),
  list(pattern = "공기업",            name = "honesty_public_enterprises"),
  list(pattern = "군대|군$",          name = "honesty_military"),
  list(pattern = "노동조합",          name = "honesty_labor_unions"),
  list(pattern = "시민단체",          name = "honesty_civic_orgs"),
  list(pattern = "TV방송|TV|방송사",  name = "honesty_tv"),
  list(pattern = "신문사|신문$",      name = "honesty_newspapers"),
  list(pattern = "교육기관|교육계",   name = "honesty_education"),
  list(pattern = "의료기관|의료계",   name = "honesty_medical"),
  list(pattern = "대기업",            name = "honesty_large_corps"),
  list(pattern = "종교기관|종교계|종교단체", name = "honesty_religious"),
  list(pattern = "금융기관|금융$",    name = "honesty_financial")
)

all_honesty_names <- unique(sapply(honesty_label_map, `[[`, "name"))

social_label_map <- list(
  list(pattern = "가족",              name = "trust_family"),
  list(pattern = "이웃",              name = "trust_neighbors"),
  list(pattern = "지인|알고.*사람",   name = "trust_acquaintances"),
  list(pattern = "낯선.*사람",        name = "trust_strangers"),
  list(pattern = "외국인",            name = "trust_foreigners")
)

# All possible harmonized trust variable names (for consistent output columns)
all_inst_names <- unique(sapply(inst_label_map, `[[`, "name"))
all_social_names <- unique(sapply(social_label_map, `[[`, "name"))

# ── Per-year crosswalk for non-trust variables ───────────────────────────────
# These are found by label search but crosswalk helps confirm
bonus_crosswalk <- list(
  "2011" = list(gen_trust = "T12_1", ideology = NULL, pol_sat = NULL,
                dem_sat = NULL, efficacy = NULL, income_hh = NULL,
                sex = "sex", age = "age", region = "region_1",
                education = NULL, weight = NULL,
                # Economic evaluations (not available in 2011)
                econ_nat_sat = NULL, econ_nat_prosp = NULL,
                econ_pers_stab = NULL, econ_pers_prosp = NULL,
                mobility_self = NULL, mobility_child = NULL,
                # Political/democratic prospects (not available in 2011)
                pol_prosp = NULL, dem_prosp = NULL,
                # Vote participation (not available in 2011)
                vote_pres = NULL, vote_assembly = NULL,
                vote_local = NULL, vote_importance = NULL,
                # Social engagement (not available in 2011)
                national_pride = NULL, belong_province = NULL,
                belong_city = NULL, belong_town = NULL,
                grp_party = NULL, grp_labor = NULL, grp_religion = NULL,
                grp_hobby = NULL, grp_civic = NULL, grp_community = NULL,
                grp_alumni = NULL, grp_volunteer = NULL, grp_social_econ = NULL,
                pol_interest = NULL),
  "2013" = list(gen_trust = "q28", ideology = "q22", pol_sat = "q4",
                dem_sat = NULL, efficacy = NULL, income_hh = NULL,
                sex = "d1", age = "d2", region = "ara",
                education = NULL, weight = NULL,
                econ_nat_sat = "q6", econ_nat_prosp = "q7",
                econ_pers_stab = "q42", econ_pers_prosp = NULL,
                mobility_self = "q3_3", mobility_child = "q3_4",
                pol_prosp = "q5", dem_prosp = NULL,
                vote_pres = "q19", vote_assembly = "q20",
                vote_local = NULL, vote_importance = "q16_1",
                national_pride = "q3_1", belong_province = "q3_2",
                belong_city = NULL, belong_town = NULL,
                grp_party = "q15_1", grp_labor = "q15_2", grp_religion = "q15_3",
                grp_hobby = "q15_4", grp_civic = "q15_5", grp_community = "q15_6",
                grp_alumni = "q15_7", grp_volunteer = NULL, grp_social_econ = NULL,
                pol_interest = NULL),
  "2014" = list(gen_trust = "q28", ideology = "q22", pol_sat = "q4",
                dem_sat = NULL, efficacy = NULL, income_hh = NULL,
                sex = "d1", age = "d2", region = "ara",
                education = NULL, weight = NULL,
                econ_nat_sat = "q6", econ_nat_prosp = NULL,
                econ_pers_stab = "q44", econ_pers_prosp = NULL,
                mobility_self = "q3_3", mobility_child = "q3_4",
                pol_prosp = NULL, dem_prosp = NULL,
                vote_pres = "q19", vote_assembly = NULL,
                vote_local = "q20", vote_importance = "q16_1",
                national_pride = "q3_1", belong_province = "q3_2",
                belong_city = NULL, belong_town = NULL,
                grp_party = "q15_1", grp_labor = "q15_2", grp_religion = "q15_3",
                grp_hobby = "q15_4", grp_civic = "q15_5", grp_community = "q15_6",
                grp_alumni = "q15_7", grp_volunteer = NULL, grp_social_econ = NULL,
                pol_interest = NULL),
  "2015" = list(gen_trust = "q30", ideology = "q24", pol_sat = "q6",
                dem_sat = NULL, efficacy = NULL, income_hh = NULL,
                sex = "d1", age = "d2", region = "ara",
                education = NULL, weight = NULL,
                econ_nat_sat = "q8", econ_nat_prosp = "q9",
                econ_pers_stab = "q47", econ_pers_prosp = NULL,
                mobility_self = "q5_3", mobility_child = "q5_4",
                pol_prosp = "q7", dem_prosp = NULL,
                vote_pres = "q21", vote_assembly = NULL,
                vote_local = "q22", vote_importance = "q18_1",
                national_pride = "q5_1", belong_province = "q5_2",
                belong_city = "q5_2_1", belong_town = "q5_2_2",
                grp_party = "q17_1", grp_labor = "q17_2", grp_religion = "q17_3",
                grp_hobby = "q17_4", grp_civic = "q17_5", grp_community = "q17_6",
                grp_alumni = "q17_7", grp_volunteer = "q17_8", grp_social_econ = "q17_9",
                pol_interest = NULL),
  "2016" = list(gen_trust = "q31", ideology = "q25", pol_sat = "q6",
                dem_sat = NULL, efficacy = NULL, income_hh = NULL,
                sex = "d1", age = "d2", region = "ara",
                education = NULL, weight = NULL,
                econ_nat_sat = "q8", econ_nat_prosp = "q9",
                econ_pers_stab = "q49", econ_pers_prosp = NULL,
                mobility_self = "q5_3", mobility_child = "q5_4",
                pol_prosp = "q7", dem_prosp = NULL,
                vote_pres = "q21", vote_assembly = "q23",
                vote_local = "q22", vote_importance = "q18_1",
                national_pride = "q5_1", belong_province = "q5_2",
                belong_city = "q5_2_1", belong_town = "q5_2_2",
                grp_party = "q17_1", grp_labor = "q17_2", grp_religion = "q17_3",
                grp_hobby = "q17_4", grp_civic = "q17_5", grp_community = "q17_6",
                grp_alumni = "q17_7", grp_volunteer = "q17_8", grp_social_econ = "q17_9",
                pol_interest = NULL),
  "2017" = list(gen_trust = "q30", ideology = "q24", pol_sat = "q6",
                dem_sat = NULL, efficacy = NULL, income_hh = NULL,
                sex = "d1", age = "d2", region = "ara",
                education = NULL, weight = NULL,
                econ_nat_sat = "q8", econ_nat_prosp = "q9",
                econ_pers_stab = "q48", econ_pers_prosp = NULL,
                mobility_self = "q5_3", mobility_child = "q5_4",
                pol_prosp = "q7", dem_prosp = NULL,
                vote_pres = "q21", vote_assembly = "q22",
                vote_local = NULL, vote_importance = "q18_1",
                national_pride = "q5_1", belong_province = "q5_2",
                belong_city = "q5_2_1", belong_town = "q5_2_2",
                grp_party = "q17_1", grp_labor = "q17_2", grp_religion = "q17_3",
                grp_hobby = "q17_4", grp_civic = "q17_5", grp_community = "q17_6",
                grp_alumni = "q17_7", grp_volunteer = "q17_8", grp_social_econ = "q17_9",
                pol_interest = NULL),
  "2018" = list(gen_trust = "q33", ideology = "q27", pol_sat = "q6",
                dem_sat = "q8", efficacy = "q21_1", income_hh = "d12_2",
                sex = "d1", age = "d2", region = "ara",
                education = "d5_1_1", weight = "wt2",
                econ_nat_sat = "q10", econ_nat_prosp = "q11",
                econ_pers_stab = "q51", econ_pers_prosp = "q52",
                mobility_self = "q5_3", mobility_child = "q5_4",
                pol_prosp = "q7", dem_prosp = "q9",
                vote_pres = "q24", vote_assembly = "q25",
                vote_local = "q23", vote_importance = "q20_1",
                national_pride = "q5_1", belong_province = "q5_2",
                belong_city = "q5_2_1", belong_town = "q5_2_2",
                grp_party = "q19_1", grp_labor = "q19_2", grp_religion = "q19_3",
                grp_hobby = "q19_4", grp_civic = "q19_5", grp_community = "q19_6",
                grp_alumni = "q19_7", grp_volunteer = "q19_8", grp_social_econ = "q19_9",
                pol_interest = NULL),
  "2019" = list(gen_trust = "q33", ideology = "q27", pol_sat = "q6",
                dem_sat = "q8", efficacy = "q21_1", income_hh = "d12_2",
                sex = "d1", age = "d2", region = "ara",
                education = "d5_1_1", weight = "wt2",
                econ_nat_sat = "q10", econ_nat_prosp = "q11",
                econ_pers_stab = "q52", econ_pers_prosp = "q53",
                mobility_self = "q5_3", mobility_child = "q5_4",
                pol_prosp = "q7", dem_prosp = "q9",
                vote_pres = "q24", vote_assembly = "q25",
                vote_local = "q23", vote_importance = "q20_1",
                national_pride = "q5_1", belong_province = "q5_2",
                belong_city = "q5_2_1", belong_town = "q5_2_2",
                grp_party = "q19_1", grp_labor = "q19_2", grp_religion = "q19_3",
                grp_hobby = "q19_4", grp_civic = "q19_5", grp_community = "q19_6",
                grp_alumni = "q19_7", grp_volunteer = "q19_8", grp_social_econ = "q19_9",
                pol_interest = NULL),
  "2020" = list(gen_trust = "q31", ideology = "q25", pol_sat = "q6",
                dem_sat = "q8", efficacy = "q19_1", income_hh = "d12_2",
                sex = "d1", age = "d2", region = "ara",
                education = "d5_1_1", weight = "wt2",
                econ_nat_sat = "q10", econ_nat_prosp = "q11",
                econ_pers_stab = "q51", econ_pers_prosp = "q52",
                mobility_self = "q5_3", mobility_child = "q5_4",
                pol_prosp = "q7", dem_prosp = "q9",
                vote_pres = "q23", vote_assembly = "q21",
                vote_local = "q22", vote_importance = "q18_1",
                national_pride = "q5_1", belong_province = "q5_2",
                belong_city = "q5_2_1", belong_town = "q5_2_2",
                grp_party = "q17_1", grp_labor = "q17_2", grp_religion = "q17_3",
                grp_hobby = "q17_4", grp_civic = "q17_5", grp_community = "q17_6",
                grp_alumni = "q17_7", grp_volunteer = "q17_8", grp_social_econ = "q17_9",
                pol_interest = NULL),
  "2021" = list(gen_trust = "q33", ideology = "q26", pol_sat = "q6",
                dem_sat = "q8", efficacy = "q20_1", income_hh = "d12_2",
                sex = "d1", age = "d2", region = "ara",
                education = "d5_1_1", weight = "wt2",
                econ_nat_sat = "q10", econ_nat_prosp = "q11",
                econ_pers_stab = "q54", econ_pers_prosp = "q55",
                mobility_self = "q5_3", mobility_child = "q5_4",
                pol_prosp = "q7", dem_prosp = "q9",
                vote_pres = "q24", vote_assembly = "q22",
                vote_local = "q23", vote_importance = "q18_1",
                national_pride = "q5_1", belong_province = "q5_2",
                belong_city = "q5_2_1", belong_town = "q5_2_2",
                grp_party = "q17_1", grp_labor = "q17_2", grp_religion = "q17_3",
                grp_hobby = "q17_4", grp_civic = "q17_5", grp_community = "q17_6",
                grp_alumni = "q17_7", grp_volunteer = "q17_8", grp_social_econ = "q17_9",
                pol_interest = "q19"),
  "2022" = list(gen_trust = "q33", ideology = "q26", pol_sat = "q6",
                dem_sat = "q8", efficacy = "q20_1", income_hh = "d12_2",
                sex = "d1", age = "d2", region = "ara",
                education = "d5_1_1", weight = "wt2",
                econ_nat_sat = "q10", econ_nat_prosp = "q11",
                econ_pers_stab = "q55", econ_pers_prosp = "q56",
                mobility_self = "q5_3", mobility_child = "q5_4",
                pol_prosp = "q7", dem_prosp = "q9",
                vote_pres = "q23", vote_assembly = "q24",
                vote_local = "q22", vote_importance = "q18_1",
                national_pride = "q5_1", belong_province = "q5_2",
                belong_city = "q5_2_1", belong_town = "q5_2_2",
                grp_party = "q17_1", grp_labor = "q17_2", grp_religion = "q17_3",
                grp_hobby = "q17_4", grp_civic = "q17_5", grp_community = "q17_6",
                grp_alumni = "q17_7", grp_volunteer = "q17_8", grp_social_econ = "q17_9",
                pol_interest = "q19"),
  "2023" = list(gen_trust = "q28", ideology = "q21", pol_sat = "q6",
                dem_sat = NULL, efficacy = "q17_1", income_hh = "d11_2",
                sex = "d1", age = "d2", region = "ara",
                education = "d5_1_1", weight = "wt2",
                econ_nat_sat = "q8", econ_nat_prosp = "q9",
                econ_pers_stab = "q51", econ_pers_prosp = "q52",
                mobility_self = "q5_3", mobility_child = "q5_4",
                pol_prosp = "q7", dem_prosp = NULL,
                vote_pres = "q19_2", vote_assembly = "q19_3",
                vote_local = "q19_1", vote_importance = "q15_1",
                national_pride = "q5_1", belong_province = "q5_2",
                belong_city = "q5_2_1", belong_town = "q5_2_2",
                grp_party = "q14_1", grp_labor = "q14_2", grp_religion = "q14_3",
                grp_hobby = "q14_4", grp_civic = "q14_5", grp_community = "q14_6",
                grp_alumni = "q14_7", grp_volunteer = "q14_8", grp_social_econ = "q14_9",
                pol_interest = "q16"),
  "2024" = list(gen_trust = "q28", ideology = "q21", pol_sat = "q6",
                dem_sat = NULL, efficacy = "q17_1", income_hh = "d11_2",
                sex = "d1", age = "d2", region = "ara",
                education = "d5_1_1", weight = "wt2",
                econ_nat_sat = "q8", econ_nat_prosp = "q9",
                econ_pers_stab = "q52", econ_pers_prosp = "q53",
                mobility_self = "q5_3", mobility_child = "q5_4",
                pol_prosp = "q7", dem_prosp = NULL,
                vote_pres = "q19_3", vote_assembly = "q19_1",
                vote_local = "q19_2", vote_importance = "q15_1",
                national_pride = "q5_1", belong_province = "q5_2",
                belong_city = "q5_2_1", belong_town = "q5_2_2",
                grp_party = "q14_1", grp_labor = "q14_2", grp_religion = "q14_3",
                grp_hobby = "q14_4", grp_civic = "q14_5", grp_community = "q14_6",
                grp_alumni = "q14_7", grp_volunteer = "q14_8", grp_social_econ = "q14_9",
                pol_interest = "q16")
)

# ── Helpers ──────────────────────────────────────────────────────────────────

strip_haven <- function(x) as.numeric(x)

safe_extract <- function(df, varname) {
  if (!is.null(varname) && varname %in% names(df)) {
    strip_haven(df[[varname]])
  } else {
    rep(NA_real_, nrow(df))
  }
}

# Match variables by label content within a battery
# battery_keyword: Korean keyword to identify the battery (e.g., "신뢰" or "청렴")
match_battery_vars <- function(raw, label_map, battery_keyword) {
  labs <- sapply(raw, function(x) {
    l <- attr(x, "label")
    if (is.null(l)) "" else l
  })

  # Find all vars whose label contains the battery keyword
  battery_idx <- grep(battery_keyword, labs)
  result <- list()

  for (mapping in label_map) {
    matched <- FALSE
    for (i in battery_idx) {
      if (grepl(mapping$pattern, labs[i])) {
        result[[mapping$name]] <- strip_haven(raw[[i]])
        matched <- TRUE
        break
      }
    }
    if (!matched) {
      result[[mapping$name]] <- NULL
    }
  }
  result
}

# Backward-compatible wrapper
match_trust_vars <- function(raw, label_map) {
  match_battery_vars(raw, label_map, "신뢰")
}

# Rescale 5-point to 4-point: (x - 1) * 3/4 + 1
rescale_5_to_4 <- function(x) {
  round((x - 1) * 3 / 4 + 1, 2)
}

# ── Process each year ────────────────────────────────────────────────────────

# Skip 2012 (no institutional trust battery)
years_to_process <- c(2011, 2013:2024)
all_years <- list()

for (yr in years_to_process) {
  yr_char <- as.character(yr)
  fpath <- sprintf("data/kipa/raw/kipa_%d.sav", yr)

  if (!file.exists(fpath)) {
    cat(sprintf("  SKIPPING %d (file not found)\n", yr))
    next
  }

  cat(sprintf("  Loading %d ... ", yr))
  raw <- read_sav(fpath)
  cat(sprintf("%s rows, %d cols\n", format(nrow(raw), big.mark = ","), ncol(raw)))
  n <- nrow(raw)

  cw <- bonus_crosswalk[[yr_char]]

  # ── Institutional trust (label-matched) ──
  inst_matched <- match_trust_vars(raw, inst_label_map)

  # Build institutional trust columns
  inst_df <- data.frame(row.names = seq_len(n))
  for (vname in all_inst_names) {
    vals <- inst_matched[[vname]]
    if (!is.null(vals)) {
      # 2011 uses 5-point scale: rescale
      if (yr == 2011) {
        vals <- rescale_5_to_4(vals)
      }
      # Treat 8/9 as NA (모름/무응답, used in 2013-2014)
      vals[vals >= 8] <- NA
      inst_df[[vname]] <- vals
    } else {
      inst_df[[vname]] <- rep(NA_real_, n)
    }
  }

  matched_inst <- sum(sapply(inst_matched, function(x) !is.null(x)))
  cat(sprintf("    Institutional trust: %d/%d items matched\n",
              matched_inst, length(inst_label_map)))

  # ── Institutional honesty/integrity (label-matched via 청렴도) ──
  hon_df <- data.frame(row.names = seq_len(n))
  if (yr != 2011) {
    # 2011 has no honesty battery
    hon_matched <- match_battery_vars(raw, honesty_label_map, "청렴도")
    for (vname in all_honesty_names) {
      vals <- hon_matched[[vname]]
      if (!is.null(vals)) {
        vals[vals >= 8] <- NA
        hon_df[[vname]] <- vals
      } else {
        hon_df[[vname]] <- rep(NA_real_, n)
      }
    }
    matched_hon <- sum(sapply(hon_matched, function(x) !is.null(x)))
    cat(sprintf("    Institutional honesty: %d/%d items matched\n",
                matched_hon, length(honesty_label_map)))
  } else {
    for (vname in all_honesty_names) hon_df[[vname]] <- rep(NA_real_, n)
    cat("    Institutional honesty: 0 (not available in 2011)\n")
  }

  # ── Social trust (label-matched) ──
  soc_matched <- match_trust_vars(raw, social_label_map)
  soc_df <- data.frame(row.names = seq_len(n))
  for (vname in all_social_names) {
    vals <- soc_matched[[vname]]
    if (!is.null(vals)) {
      if (yr == 2011) vals <- rescale_5_to_4(vals)
      vals[vals >= 8] <- NA
      soc_df[[vname]] <- vals
    } else {
      soc_df[[vname]] <- rep(NA_real_, n)
    }
  }

  # ── Bonus variables ──
  gen_trust <- safe_extract(raw, cw$gen_trust)
  ideology  <- safe_extract(raw, cw$ideology)
  pol_sat   <- safe_extract(raw, cw$pol_sat)
  efficacy  <- safe_extract(raw, cw$efficacy)

  # Democracy satisfaction: crosswalk then label fallback
  dem_sat_var <- cw$dem_sat
  if (is.null(dem_sat_var)) {
    labs <- sapply(raw, function(x) {
      l <- attr(x, "label"); if (is.null(l)) "" else l
    })
    dem_idx <- grep("민주주의.*만족", labs)
    if (length(dem_idx) > 0) {
      dem_sat_var <- names(raw)[dem_idx[1]]
      cat(sprintf("    [label search] dem_satisfaction → %s\n", dem_sat_var))
    }
  }
  dem_sat <- safe_extract(raw, dem_sat_var)

  # ── Economic evaluations (0-10 scale, higher=better) ──
  econ_nat_sat    <- safe_extract(raw, cw$econ_nat_sat)
  econ_nat_prosp  <- safe_extract(raw, cw$econ_nat_prosp)
  econ_pers_stab  <- safe_extract(raw, cw$econ_pers_stab)
  econ_pers_prosp <- safe_extract(raw, cw$econ_pers_prosp)

  # Clean 0-10 economic vars: 98/99 → NA
  for (nm in c("econ_nat_sat", "econ_nat_prosp", "econ_pers_stab", "econ_pers_prosp")) {
    vals <- get(nm)
    vals[vals >= 98] <- NA
    assign(nm, vals)
  }

  # Social mobility (1-4 scale, higher=more possible); 9=DK/NR
  mobility_self  <- safe_extract(raw, cw$mobility_self)
  mobility_child <- safe_extract(raw, cw$mobility_child)
  mobility_self[mobility_self >= 9]   <- NA
  mobility_child[mobility_child >= 9] <- NA

  # ── Political/democratic prospects (0-10 scale) ──
  pol_prosp <- safe_extract(raw, cw$pol_prosp)
  dem_prosp <- safe_extract(raw, cw$dem_prosp)
  pol_prosp[pol_prosp >= 98] <- NA
  dem_prosp[dem_prosp >= 98] <- NA

  # ── Vote participation (1=voted, 2=did not, 3=ineligible) ──
  vote_pres     <- safe_extract(raw, cw$vote_pres)
  vote_assembly <- safe_extract(raw, cw$vote_assembly)
  vote_local    <- safe_extract(raw, cw$vote_local)

  # Clean vote vars: 8/9 → NA
  for (nm in c("vote_pres", "vote_assembly", "vote_local")) {
    vals <- get(nm)
    vals[vals >= 8] <- NA
    assign(nm, vals)
  }

  # Vote importance (1-7, higher=more important); 9=DK/NR
  vote_importance <- safe_extract(raw, cw$vote_importance)
  vote_importance[vote_importance >= 9] <- NA

  # ── Social engagement: belonging, national pride, social groups, pol interest ──
  national_pride   <- safe_extract(raw, cw$national_pride)
  belong_province  <- safe_extract(raw, cw$belong_province)
  belong_city      <- safe_extract(raw, cw$belong_city)
  belong_town      <- safe_extract(raw, cw$belong_town)
  pol_interest_val <- safe_extract(raw, cw$pol_interest)

  # Clean 1-4 belonging/pride/interest vars: 8/9 → NA
  for (nm in c("national_pride", "belong_province", "belong_city",
               "belong_town", "pol_interest_val")) {
    vals <- get(nm)
    vals[vals >= 8] <- NA
    assign(nm, vals)
  }

  # Social group activity (1-5 scale); 8/9=DK/NR
  grp_names <- c("grp_party", "grp_labor", "grp_religion", "grp_hobby",
                  "grp_civic", "grp_community", "grp_alumni",
                  "grp_volunteer", "grp_social_econ")
  grp_vals <- list()
  for (gn in grp_names) {
    v <- safe_extract(raw, cw[[gn]])
    v[v >= 8] <- NA
    grp_vals[[gn]] <- v
  }

  # ── Demographics ──
  sex       <- safe_extract(raw, cw$sex)
  age_group <- safe_extract(raw, cw$age)
  education <- safe_extract(raw, cw$education)
  income_hh <- safe_extract(raw, cw$income_hh)
  region    <- safe_extract(raw, cw$region)
  weight    <- safe_extract(raw, cw$weight)

  # ── Assemble ──
  yr_df <- cbind(
    data.frame(
      year              = yr,
      country           = "KOR",
      sex               = sex,
      age_group         = age_group,
      education         = education,
      income_hh         = income_hh,
      region            = region,
      weight            = weight,
      trust_generalized = gen_trust,
      dem_satisfaction   = dem_sat,
      dem_prospect      = dem_prosp,
      ideology          = ideology,
      pol_satisfaction   = pol_sat,
      pol_prospect      = pol_prosp,
      pol_efficacy      = efficacy,
      econ_nat_sat      = econ_nat_sat,
      econ_nat_prospect = econ_nat_prosp,
      econ_pers_stability = econ_pers_stab,
      econ_pers_prospect  = econ_pers_prosp,
      mobility_self     = mobility_self,
      mobility_children = mobility_child,
      voted_presidential = vote_pres,
      voted_assembly    = vote_assembly,
      voted_local       = vote_local,
      vote_importance   = vote_importance,
      national_pride    = national_pride,
      belong_province   = belong_province,
      belong_city       = belong_city,
      belong_town       = belong_town,
      grp_party         = grp_vals$grp_party,
      grp_labor         = grp_vals$grp_labor,
      grp_religion      = grp_vals$grp_religion,
      grp_hobby         = grp_vals$grp_hobby,
      grp_civic         = grp_vals$grp_civic,
      grp_community     = grp_vals$grp_community,
      grp_alumni        = grp_vals$grp_alumni,
      grp_volunteer     = grp_vals$grp_volunteer,
      grp_social_econ   = grp_vals$grp_social_econ,
      pol_interest      = pol_interest_val,
      stringsAsFactors  = FALSE
    ),
    inst_df,
    hon_df,
    soc_df
  )

  all_years[[yr_char]] <- yr_df
}

# ── Row-bind all years ───────────────────────────────────────────────────────

cat("\n  Combining all years ... ")
combined <- do.call(rbind, all_years)
rownames(combined) <- NULL
cat(sprintf("%s rows, %d cols\n",
            format(nrow(combined), big.mark = ","), ncol(combined)))

# ── Summary: annual means ────────────────────────────────────────────────────

# Core institutional trust variables (present in most/all years)
core_inst <- c("trust_central_govt", "trust_national_assembly", "trust_courts",
               "trust_prosecution", "trust_police", "trust_local_govt",
               "trust_military", "trust_labor_unions", "trust_civic_orgs",
               "trust_education", "trust_medical", "trust_large_corps",
               "trust_religious")

all_trust <- c(all_inst_names, all_honesty_names, all_social_names, "trust_generalized")

cat("\n── Annual Institutional Trust Means (core items, 4-point scale) ──\n\n")

years <- sort(unique(combined$year))
means_list <- list()

for (yr in years) {
  sub <- combined[combined$year == yr, ]
  row <- data.frame(year = yr, n = nrow(sub))
  for (v in all_trust) {
    row[[v]] <- round(mean(sub[[v]], na.rm = TRUE), 3)
  }
  means_list[[as.character(yr)]] <- row
}

means_df <- do.call(rbind, means_list)
rownames(means_df) <- NULL

# Print core items
print_cols <- c("year", "n", core_inst)
print_cols <- print_cols[print_cols %in% names(means_df)]
print(means_df[, print_cols], row.names = FALSE)

cat("\n── Variable Coverage by Year ──\n\n")
core_hon <- gsub("^trust_", "honesty_", core_inst)
coverage_vars <- c(
  core_inst, "trust_financial", "trust_public_enterprises",
  core_hon[1:4],
  "trust_generalized", "dem_satisfaction", "dem_prospect",
  "ideology", "pol_satisfaction", "pol_prospect", "pol_efficacy",
  "econ_nat_sat", "econ_nat_prospect", "econ_pers_stability", "econ_pers_prospect",
  "mobility_self", "mobility_children",
  "voted_presidential", "voted_assembly", "voted_local", "vote_importance",
  "national_pride", "belong_province", "belong_city", "belong_town",
  "grp_party", "grp_religion", "grp_hobby", "grp_civic", "grp_volunteer",
  "pol_interest"
)
for (v in coverage_vars) {
  if (!v %in% names(combined)) next
  non_na <- tapply(!is.na(combined[[v]]), combined$year, sum)
  pct <- round(100 * non_na / tapply(rep(1, nrow(combined)), combined$year, sum), 0)
  coverage <- paste(sprintf("%d:%d%%", as.integer(names(pct)), pct), collapse = " ")
  cat(sprintf("  %-26s %s\n", v, coverage))
}

# ── Export ───────────────────────────────────────────────────────────────────

cat("\n── Exporting ──\n")

out_rds <- "data/processed/kipa_trust_harmonized.rds"
out_pqt <- "data/processed/kipa_trust_harmonized.parquet"
out_csv <- "data/kipa/kipa_annual_trust_means.csv"

saveRDS(combined, out_rds)
cat(sprintf("  %s (%s bytes)\n", out_rds, format(file.size(out_rds), big.mark = ",")))

write_parquet(combined, out_pqt)
cat(sprintf("  %s (%s bytes)\n", out_pqt, format(file.size(out_pqt), big.mark = ",")))

write.csv(means_df, out_csv, row.names = FALSE)
cat(sprintf("  %s\n", out_csv))

cat(sprintf("\n══ Done: %s respondents, %d years (2011, 2013-2024), %d variables ══\n\n",
            format(nrow(combined), big.mark = ","),
            length(unique(combined$year)),
            ncol(combined)))
