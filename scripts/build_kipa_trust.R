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
                education = NULL, weight = NULL),
  "2013" = list(gen_trust = "q28", ideology = "q22", pol_sat = "q4",
                dem_sat = NULL, efficacy = NULL, income_hh = NULL,
                sex = "d1", age = "d2", region = "ara",
                education = NULL, weight = NULL),
  "2014" = list(gen_trust = "q28", ideology = "q22", pol_sat = "q4",
                dem_sat = NULL, efficacy = NULL, income_hh = NULL,
                sex = "d1", age = "d2", region = "ara",
                education = NULL, weight = NULL),
  "2015" = list(gen_trust = "q30", ideology = "q24", pol_sat = "q6",
                dem_sat = NULL, efficacy = NULL, income_hh = NULL,
                sex = "d1", age = "d2", region = "ara",
                education = NULL, weight = NULL),
  "2016" = list(gen_trust = "q31", ideology = "q25", pol_sat = "q6",
                dem_sat = NULL, efficacy = NULL, income_hh = NULL,
                sex = "d1", age = "d2", region = "ara",
                education = NULL, weight = NULL),
  "2017" = list(gen_trust = "q30", ideology = "q24", pol_sat = "q6",
                dem_sat = NULL, efficacy = NULL, income_hh = NULL,
                sex = "d1", age = "d2", region = "ara",
                education = NULL, weight = NULL),
  "2018" = list(gen_trust = "q33", ideology = "q27", pol_sat = "q6",
                dem_sat = "q8", efficacy = "q21_1", income_hh = "d12_2",
                sex = "d1", age = "d2", region = "ara",
                education = "d5_1_1", weight = "wt2"),
  "2019" = list(gen_trust = "q33", ideology = "q27", pol_sat = "q6",
                dem_sat = "q8", efficacy = "q21_1", income_hh = "d12_2",
                sex = "d1", age = "d2", region = "ara",
                education = "d5_1_1", weight = "wt2"),
  "2020" = list(gen_trust = "q31", ideology = "q25", pol_sat = "q6",
                dem_sat = "q8", efficacy = "q19_1", income_hh = "d12_2",
                sex = "d1", age = "d2", region = "ara",
                education = "d5_1_1", weight = "wt2"),
  "2021" = list(gen_trust = "q33", ideology = "q26", pol_sat = "q6",
                dem_sat = "q8", efficacy = "q20_1", income_hh = "d12_2",
                sex = "d1", age = "d2", region = "ara",
                education = "d5_1_1", weight = "wt2"),
  "2022" = list(gen_trust = "q33", ideology = "q26", pol_sat = "q6",
                dem_sat = "q8", efficacy = "q20_1", income_hh = "d12_2",
                sex = "d1", age = "d2", region = "ara",
                education = "d5_1_1", weight = "wt2"),
  "2023" = list(gen_trust = "q28", ideology = "q21", pol_sat = "q6",
                dem_sat = NULL, efficacy = "q17_1", income_hh = "d11_2",
                sex = "d1", age = "d2", region = "ara",
                education = "d5_1_1", weight = "wt2"),
  "2024" = list(gen_trust = "q28", ideology = "q21", pol_sat = "q6",
                dem_sat = NULL, efficacy = "q17_1", income_hh = "d11_2",
                sex = "d1", age = "d2", region = "ara",
                education = "d5_1_1", weight = "wt2")
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
      ideology          = ideology,
      pol_satisfaction   = pol_sat,
      pol_efficacy      = efficacy,
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
for (v in c(core_inst, "trust_financial", "trust_public_enterprises",
            core_hon[1:4],  # honesty for top institutions
            "trust_generalized", "dem_satisfaction", "ideology",
            "pol_satisfaction", "pol_efficacy")) {
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
