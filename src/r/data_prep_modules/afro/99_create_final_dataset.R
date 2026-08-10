# Afrobarometer: Create final combined dataset
#
# This script:
# 1. Loads per-wave master files from outputs/afro/
# 2. Adds country identifier from raw .sav value labels
# 3. Adds year variable (midpoint of fieldwork)
# 4. Row-binds waves into a single dataset
# 5. Saves as afro_harmonized.rds and .parquet

library(here)
library(dplyr)
library(haven)
library(arrow)

source(here::here("src", "r", "utils", "provenance.R"))
source(here::here("src", "r", "utils", "keys.R"))
source(here::here("src", "r", "utils", "education.R"))
source(here::here("src", "r", "utils", "spec_discovery.R"))

cat("\n")
cat(strrep("=", 70), "\n")
cat("CREATING FINAL DATASET: afro_harmonized\n")
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# LOAD MASTER WAVE FILES
# ==============================================================================

output_dir <- here("outputs", "afro")
wave_files <- sort(list.files(output_dir, pattern = "^master_w[0-9]+\\.rds$", full.names = TRUE))

if (length(wave_files) == 0) {
  stop("No master files found in outputs/afro/. Run 2_harmonize_all.R first.")
}

cat("Loading master wave files...\n")
wave_list <- list()

for (f in wave_files) {
  wave_name <- gsub("master_|\\.rds", "", basename(f))
  cat(sprintf("  %s: %s ... ", wave_name, basename(f)))
  df <- readRDS(f)
  cat(sprintf("%s rows, %d cols\n", format(nrow(df), big.mark = ","), ncol(df)))
  wave_list[[wave_name]] <- df
}

# ==============================================================================
# COUNTRY NAME → ISO3 LOOKUP
# ==============================================================================

# Comprehensive mapping of Afrobarometer country names to ISO alpha-3 codes
# Handles variations in spelling across rounds
country_name_to_iso3 <- c(
  "Algeria" = "DZA",
  "Angola" = "AGO",
  "Benin" = "BEN",
  "Botswana" = "BWA",
  "Burkina Faso" = "BFA",
  "Burundi" = "BDI",
  "Cabo Verde" = "CPV",
  "Cape Verde" = "CPV",
  "Cameroon" = "CMR",
  "Congo" = "COG",
  "Congo-Brazzaville" = "COG",
  "Cote d'Ivoire" = "CIV",
  "Cote dIvoire" = "CIV",
  "Egypt" = "EGY",
  "eSwatini" = "SWZ",
  "Eswatini" = "SWZ",
  "Ethiopia" = "ETH",
  "Gabon" = "GAB",
  "Gambia" = "GMB",
  "Ghana" = "GHA",
  "Guinea" = "GIN",
  "Kenya" = "KEN",
  "Lesotho" = "LSO",
  "Liberia" = "LBR",
  "Madagascar" = "MDG",
  "Malawi" = "MWI",
  "Mali" = "MLI",
  "Mauritania" = "MRT",
  "Mauritius" = "MUS",
  "Morocco" = "MAR",
  "Mozambique" = "MOZ",
  "Namibia" = "NAM",
  "Niger" = "NER",
  "Nigeria" = "NGA",
  "Senegal" = "SEN",
  "Seychelles" = "SYC",
  "Sierra Leone" = "SLE",
  "South Africa" = "ZAF",
  "Sudan" = "SDN",
  "Swaziland" = "SWZ",
  "Tanzania" = "TZA",
  "Togo" = "TGO",
  "Tunisia" = "TUN",
  "Uganda" = "UGA",
  "Zambia" = "ZMB",
  "Zimbabwe" = "ZWE"
)

# ==============================================================================
# RAW DATA PATHS (for country extraction)
# ==============================================================================

raw_paths <- list(
  w1  = here("data", "afro", "raw", "round1",  "merged_r1_data.sav"),
  w2  = here("data", "afro", "raw", "round2",  "merged_r2_data.sav"),
  w3  = here("data", "afro", "raw", "round3",  "merged_r3_data.sav"),
  w4  = here("data", "afro", "raw", "round4",  "merged_r4_data.sav"),
  w5  = here("data", "afro", "raw", "round5",  "merged_r5_data.sav"),
  w6  = here("data", "afro", "raw", "round6",  "merged_r6_data.sav"),
  w7  = here("data", "afro", "raw", "round7",  "merged_r7_data.sav"),
  w8  = here("data", "afro", "raw", "round8",  "merged_r8_data.sav"),
  w9  = here("data", "afro", "raw", "round9",
             "R9.Merge_39ctry.20Nov23.final_.release_Updated.4Jun25-3.sav"),
  w10 = here("data", "afro", "raw", "round10", "merged_r10_data.sav")
)

# Representative years for each round (midpoint of fieldwork).
# w10 fieldwork year is a placeholder; update when the round's
# technical report confirms the timeline.
round_years <- c(
  w1 = 1999L, w2 = 2002L, w3 = 2005L, w4 = 2008L,
  w5 = 2012L, w6 = 2015L, w7 = 2017L, w8 = 2019L, w9 = 2022L,
  w10 = 2025L
)

# ==============================================================================
# ADD COUNTRY IDENTIFIER FROM RAW DATA
# ==============================================================================

cat("\nAdding country identifiers from raw .sav files...\n")

for (wave_name in names(wave_list)) {
  raw_path <- raw_paths[[wave_name]]

  # R10 special case: per-country .sav files (no merged release yet).
  # The 0_load_waves.R stacker tags rows with country_iso3 from filename
  # prefixes; replicate the same logic here to build the iso3 vector in
  # the same row order.
  if (wave_name == "w10" && (is.null(raw_path) || !file.exists(raw_path))) {
    r10_dir <- here("data", "afro", "raw", "round10")
    country_files <- list.files(r10_dir, pattern = "^[A-Z]{3}_R10.*\\.sav$",
                                full.names = TRUE)
    if (length(country_files) == 0L) {
      warning("R10: no per-country files found either; setting country=NA")
      wave_list[[wave_name]]$country <- NA_character_
      next
    }
    cat(sprintf("  R10: assembling country from %d per-country files...\n",
                length(country_files)))
    iso3 <- unlist(lapply(country_files, function(f) {
      iso_prefix <- substr(basename(f), 1L, 3L)
      n <- nrow(haven::read_sav(f, encoding = "latin1"))
      rep(iso_prefix, n)
    }))
    if (length(iso3) != nrow(wave_list[[wave_name]])) {
      warning(sprintf("Row count mismatch for w10: master=%d, stacked=%d",
                      nrow(wave_list[[wave_name]]), length(iso3)))
    }
    wave_list[[wave_name]]$country <- iso3
    next
  }

  if (is.null(raw_path) || !file.exists(raw_path)) {
    warning(sprintf("No raw file for %s", wave_name))
    wave_list[[wave_name]]$country <- NA_character_
    next
  }

  # Find country variable (case-insensitive)
  raw <- haven::read_sav(raw_path, encoding = "latin1")
  cvar <- grep("^country$", names(raw), ignore.case = TRUE, value = TRUE)

  if (length(cvar) == 0) {
    warning(sprintf("No COUNTRY variable found for %s", wave_name))
    wave_list[[wave_name]]$country <- NA_character_
    next
  }

  cvar <- cvar[1]

  # Use haven labels to get country names, then map to ISO3
  country_factor <- haven::as_factor(raw[[cvar]])
  country_names <- as.character(country_factor)

  # Clean up encoding artifacts
  country_names <- gsub("\u00e2\u0080\u0099", "'", country_names)  # smart apostrophe
  country_names <- gsub("\u00c3\u00b4", "o", country_names)  # o-circumflex
  country_names <- gsub("\u00c3\u00a3", "a", country_names)  # a-tilde
  country_names <- gsub("\u00c3\u00ad", "i", country_names)  # i-acute
  country_names <- trimws(country_names)

  # Map to ISO3
  iso3 <- country_name_to_iso3[country_names]

  # Handle Sao Tome (encoding issues)
  iso3[grepl("Tom", country_names, ignore.case = TRUE)] <- "STP"
  # Handle Cote d'Ivoire encoding variants
  iso3[grepl("Ivoire|voire", country_names, ignore.case = TRUE)] <- "CIV"

  if (length(iso3) != nrow(wave_list[[wave_name]])) {
    warning(sprintf("Row count mismatch for %s: master=%d, raw=%d",
                    wave_name, nrow(wave_list[[wave_name]]), length(iso3)))
  } else {
    wave_list[[wave_name]]$country <- iso3
    n_countries <- length(unique(na.omit(iso3)))
    n_unmapped <- sum(is.na(iso3) & !is.na(country_names) & country_names != "")
    cat(sprintf("  %s: %d countries", wave_name, n_countries))
    if (n_unmapped > 0) cat(sprintf(" (%d unmapped)", n_unmapped))
    cat("\n")
  }
}

# ==============================================================================
# ADD YEAR VARIABLE
# ==============================================================================

for (wave_name in names(wave_list)) {
  wave_list[[wave_name]]$year <- round_years[[wave_name]]
}

# ==============================================================================
# COMBINE WAVES
# ==============================================================================

# Coerce int_date to consistent type (Date in w9, NA/double in w1-w8)
for (wn in names(wave_list)) {
  if ("int_date" %in% names(wave_list[[wn]])) {
    if (!inherits(wave_list[[wn]]$int_date, "Date")) {
      wave_list[[wn]]$int_date <- as.Date(NA)
    }
  }
}

cat("\nCombining waves...\n")
afro_combined <- bind_rows(wave_list)

# Convert wave column from character ("w9") to numeric (9)
afro_combined <- afro_combined %>%
  mutate(wave = as.integer(gsub("w", "", wave)))

cat(sprintf("  Combined: %s rows, %d columns\n",
            format(nrow(afro_combined), big.mark = ","),
            ncol(afro_combined)))

# ==============================================================================
# CLEAN UP
# ==============================================================================

afro_harmonized <- afro_combined

# Zap any remaining haven labels
afro_harmonized <- afro_harmonized %>%
  mutate(across(where(~ inherits(.x, "haven_labelled")), ~ as.numeric(haven::zap_labels(.x))))

# Rescale education to 0-1 (Afro raw: 0-3)
# NOTE: education_level_01 is a min-max rescale of Afro's OWN 0-3 ladder. It is
# NOT comparable with other surveys' education_level_01 (different denominators).
# For cross-survey work use education_5cat_01. See src/r/utils/education.R.
if ("education_level" %in% names(afro_harmonized)) {
  afro_harmonized <- afro_harmonized %>%
    mutate(education_level_01 = education_level / 3)
}

# Shared 5-category education. Mapping lives in src/r/utils/education.R, which
# prefers the 0-9 education_detailed ladder and falls back to the condensed
# education_level for R1 (which has no detailed item, and so can never resolve
# category 5).
if ("education_detailed" %in% names(afro_harmonized)) {
  afro_harmonized <- afro_harmonized %>%
    mutate(
      education_5cat    = edu5_from_afro(education_detailed, education_level),
      education_5cat_01 = edu5_to_01(education_5cat)
    )
} else if ("education_level" %in% names(afro_harmonized)) {
  afro_harmonized <- afro_harmonized %>%
    mutate(
      education_5cat    = edu5_from_afro(NA_real_, education_level),
      education_5cat_01 = edu5_to_01(education_5cat)
    )
}

# ==============================================================================
# DERIVED INDICES (Tambe & Monyake 2023 extension, added 2026-07-03)
# ==============================================================================

# Perceived-corruption additive index: sum of the six 0-3 battery items
# (0-18, higher = more perceived corruption). COMPLETE CASES ONLY — T&M
# describe an additive index without an imputation rule, so a respondent
# missing any sub-item gets NA (judgment call, logged in corruption.yml).
corr_items <- c("corr_perc_president", "corr_perc_mp", "corr_perc_officials",
                "corr_perc_councilors", "corr_perc_police", "corr_perc_judges")
if (all(corr_items %in% names(afro_harmonized))) {
  m <- as.matrix(afro_harmonized[, corr_items])
  afro_harmonized$corruption_perc <-
    ifelse(rowSums(is.na(m)) == 0, rowSums(m), NA_real_)
}

# Lived Poverty Index: respondent MEAN of the five 0-4 items (Mattes/
# Afrobarometer LPI convention), complete cases only (T&M unspecified;
# logged in lived_poverty.yml). poverty_ctry = UNWEIGHTED country x round
# mean of lived_poverty — the level-2 predictor in the T&M design.
lpi_items <- c("lpi_food", "lpi_water", "lpi_medicine", "lpi_fuel", "lpi_income")
if (all(lpi_items %in% names(afro_harmonized))) {
  m <- as.matrix(afro_harmonized[, lpi_items])
  afro_harmonized$lived_poverty <-
    ifelse(rowSums(is.na(m)) == 0, rowMeans(m), NA_real_)
  afro_harmonized <- afro_harmonized %>%
    group_by(country, wave) %>%
    mutate(poverty_ctry = mean(lived_poverty, na.rm = TRUE)) %>%
    ungroup() %>%
    mutate(poverty_ctry = ifelse(is.nan(poverty_ctry), NA_real_, poverty_ctry))
}

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("DATASET SUMMARY\n")
cat(strrep("=", 70), "\n\n")

cat("Respondents per wave:\n")
wave_summary <- afro_harmonized %>%
  group_by(wave, year) %>%
  summarise(n = n(), countries = n_distinct(country, na.rm = TRUE), .groups = "drop")
print(as.data.frame(wave_summary))

cat(sprintf("\nTotal: %s respondents across %d wave(s)\n",
            format(nrow(afro_harmonized), big.mark = ","),
            n_distinct(afro_harmonized$wave)))

var_names <- setdiff(names(afro_harmonized), c("wave", "year", "country"))
cat(sprintf("\n%d harmonized variables:\n", length(var_names)))
cat(paste("  ", var_names, collapse = "\n"), "\n")

# ==============================================================================
# SAVE
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("SAVING\n")
cat(strrep("=", 70), "\n\n")

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)

rds_path <- here("data", "processed", "afro_harmonized.rds")
assert_row_uid(afro_harmonized, "afro")

saveRDS(afro_harmonized, rds_path)
cat(sprintf("  RDS:     %s\n", rds_path))

parquet_path <- here("data", "processed", "afro_harmonized.parquet")
arrow::write_parquet(afro_harmonized, parquet_path)
cat(sprintf("  Parquet: %s\n", parquet_path))

saveRDS(afro_harmonized, here("outputs", "afro", "afro_harmonized.rds"))

cat(sprintf("\nafro_harmonized saved: %s rows, %d columns\n",
            format(nrow(afro_harmonized), big.mark = ","),
            ncol(afro_harmonized)))
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# VALUE-LABEL LOOKUP EXPORT (paper 22, §7)
# ==============================================================================
# The harmonize engine zaps haven_labelled at harmonize time, so the final
# dataset keeps numeric codes only. For the nominal party / ethnic / occupation
# variables those codes are meaningless without the country×round value labels,
# so export a lookup rebuilt from the RAW .sav attr(,"labels"). Paper-bank joins
# afro_value_labels.csv on (variable, wave, country, code) to recover party
# names / ethnic groups / occupations and identify the ruling party.

cat("\nBuilding value-label lookup (afro_value_labels.csv)...\n")

label_var_map <- list(
  vote_intent_party = c(w3 = "q99", w5 = "Q99",     w6 = "Q99",  w8 = "Q99"),
  party_close_which = c(w3 = "q86", w5 = "Q89B",    w6 = "Q90B", w8 = "Q91B"),
  ethnic_group      = c(w3 = "q79", w5 = "Q84",     w6 = "Q87",  w8 = "Q81"),
  occupation        = c(           w5 = "Q96_ARB", w6 = "Q96A", w8 = "Q95C")
)

# Reuse the same country-name → ISO3 logic as the country-identifier section.
raw_to_iso3 <- function(raw, ccol) {
  cn <- as.character(haven::as_factor(raw[[ccol]]))
  cn <- gsub("â", "'", cn)
  cn <- gsub("Ã´", "o", cn)
  cn <- gsub("Ã£", "a", cn)
  cn <- gsub("Ã­", "i", cn)
  cn <- trimws(cn)
  iso <- country_name_to_iso3[cn]
  iso[grepl("Tom", cn, ignore.case = TRUE)] <- "STP"
  iso[grepl("Ivoire|voire", cn, ignore.case = TRUE)] <- "CIV"
  unname(iso)
}

vl_rows <- list()
for (varname in names(label_var_map)) {
  wmap <- label_var_map[[varname]]
  for (wn in names(wmap)) {
    raw_col <- wmap[[wn]]
    path <- raw_paths[[wn]]
    if (is.null(path) || !file.exists(path)) next
    hdr <- haven::read_sav(path, n_max = 0)
    real_col <- names(hdr)[match(tolower(raw_col), tolower(names(hdr)))]
    ccol <- grep("^country$", names(hdr), ignore.case = TRUE, value = TRUE)[1]
    if (is.na(real_col) || is.na(ccol)) {
      warning(sprintf("value-labels: %s/%s — column '%s' or COUNTRY missing",
                      varname, wn, raw_col))
      next
    }
    raw <- haven::read_sav(path, col_select = dplyr::all_of(c(real_col, ccol)))
    x <- raw[[real_col]]
    labs <- attr(x, "labels")
    lab_map <- if (!is.null(labs)) {
      setNames(names(labs), as.character(as.numeric(labs)))
    } else character(0)
    codes <- suppressWarnings(as.numeric(haven::zap_labels(x)))
    iso3  <- raw_to_iso3(raw, ccol)
    keep  <- !is.na(codes) & !is.na(iso3)
    df <- unique(data.frame(country = iso3[keep], code = codes[keep],
                            stringsAsFactors = FALSE))
    df$label    <- unname(lab_map[as.character(df$code)])
    df$variable <- varname
    df$wave     <- as.integer(sub("w", "", wn))
    vl_rows[[paste(varname, wn)]] <- df[, c("variable", "wave", "country", "code", "label")]
  }
}

afro_value_labels <- do.call(rbind, vl_rows)
afro_value_labels <- afro_value_labels[order(afro_value_labels$variable,
                                             afro_value_labels$wave,
                                             afro_value_labels$country,
                                             afro_value_labels$code), ]
value_labels_path <- here("data", "processed", "afro_value_labels.csv")
if (requireNamespace("readr", quietly = TRUE)) {
  readr::write_csv(afro_value_labels, value_labels_path)
} else {
  utils::write.csv(afro_value_labels, value_labels_path, row.names = FALSE)
}
cat(sprintf("  Value labels: %s rows across %d variables → %s\n",
            format(nrow(afro_value_labels), big.mark = ","),
            length(unique(afro_value_labels$variable)),
            basename(value_labels_path)))

# ==============================================================================
# RUN MANIFEST (audit ticket C2)
# ==============================================================================
# raw_paths is the per-round .sav map already defined above; reuse it as the
# manifest's input list (one .sav per round). Round 9 has the long filename;
# the rest follow merged_r{N}_data.sav.
#
# R10 special case: when merged_r10_data.sav doesn't exist yet, the actual
# inputs are the 29 per-country .sav files. Substitute them so the manifest
# records what's really being hashed (instead of a placeholder path that
# doesn't exist).
manifest_inputs <- unlist(lapply(names(raw_paths), function(wn) {
  p <- raw_paths[[wn]]
  if (wn == "w10" && !file.exists(p)) {
    r10_files <- list.files(here("data", "afro", "raw", "round10"),
                            pattern = "^[A-Z]{3}_R10.*\\.sav$", full.names = TRUE)
    if (length(r10_files) > 0) return(r10_files)
  }
  p
}), use.names = FALSE)
manifest_outputs <- c(
  rds_path,
  parquet_path,
  here("outputs", "afro", "afro_harmonized.rds"),
  value_labels_path
)

write_manifest(
  survey      = "afro",
  inputs      = manifest_inputs,
  specs       = list_survey_specs("afro"),
  outputs     = manifest_outputs,
  output_path = here("outputs", "afro", "manifest.json")
)

cat("Manifest written: ", here("outputs", "afro", "manifest.json"), "\n", sep = "")

# ==============================================================================
# OUTPUT INVARIANTS (audit ticket E2)
# ==============================================================================
source(here("src", "r", "data_prep_modules", "2.5_validate_harmonization.R"))
results <- tryCatch(
  run_validation(survey = "afro", save_report = TRUE, verbose = FALSE),
  error = function(e) { message("validation step failed: ", e$message); NULL }
)
if (!is.null(results)) {
  cat(sprintf(
    "Invariants: ok=%d warn=%d error=%d skip=%d (total=%d)\n",
    results$counts$ok, results$counts$warn,
    results$counts$error, results$counts$skip,
    nrow(results$summary)
  ))
}

# ==============================================================================
# LAYER-4 DIRECTION GATE (harmonization auditor Phase 5)
# ==============================================================================
# Deterministic direction checks on the freshly built output: label
# reconciliation (hard), battery coherence + anchor coverage (soft).
# REPORT-ONLY by default: prints findings, never stops this script. Set
# HARMONIZE_AUDIT_GATE=block to make label-reconciliation errors fail the
# pipeline (flip once the label-recon backlog is cleared).
source(here::here("src", "r", "audit", "99_post_harmonize_gate.R"))
run_post_harmonize_gate("afro", quiet_checks = TRUE)
