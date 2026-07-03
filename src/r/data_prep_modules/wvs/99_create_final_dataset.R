# WVS: Create final combined dataset
#
# This script:
# 1. Loads per-wave master files from outputs/wvs/
# 2. Adds country identifier (ISO alpha-3) from raw data
#    - W1: COUNTRY_ISO from .sav (ISO alpha-3 directly)
#    - W2, W3, W5: V2 from .sav (ISO 3166 numeric → countrycode conversion)
#    - W4: B_COUNTRY_ALPHA from .sav (ISO alpha-3 directly)
#    - W6-W7: B_COUNTRY_ALPHA from parquet (existing)
# 3. Row-binds waves into a single dataset
# 4. Saves as wvs_harmonized.rds and .parquet

library(here)
library(dplyr)
library(arrow)
library(haven)
library(countrycode)

source(here::here("src", "r", "utils", "provenance.R"))
source(here::here("src", "r", "utils", "spec_discovery.R"))

cat("\n")
cat(strrep("=", 70), "\n")
cat("CREATING FINAL DATASET: wvs_harmonized\n")
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# LOAD MASTER WAVE FILES
# ==============================================================================

output_dir <- here("outputs", "wvs")
wave_files <- sort(list.files(output_dir, pattern = "^master_w[1-7]\\.rds$", full.names = TRUE))

if (length(wave_files) == 0) {
  stop("No master files found in outputs/wvs/. Run 2_harmonize_all.R first.")
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
# ADD COUNTRY IDENTIFIER FROM RAW DATA
# ==============================================================================

cat("\nAdding country identifiers...\n")

# Define country source per wave
country_sources <- list(
  w1 = list(file = here("data", "wvs", "raw", "wave1", "WV1_Data_spss_v20200208.sav"),
            type = "sav", col = "COUNTRY_ISO", format = "iso3c"),
  w2 = list(file = here("data", "wvs", "raw", "wave2", "WV2_Data_Spss_v20180912.sav"),
            type = "sav", col = "V2", format = "iso3n"),
  w3 = list(file = here("data", "wvs", "raw", "wave3", "WV3_Data_Spss_v20180912.sav"),
            type = "sav", col = "V2", format = "iso3n"),
  w4 = list(file = here("data", "wvs", "raw", "wave4", "WV4_Data_spss_v20201117.sav"),
            type = "sav", col = "B_COUNTRY_ALPHA", format = "iso3c"),
  w5 = list(file = here("data", "wvs", "raw", "wave5", "WV5_Data_Spss_v20180912.sav"),
            type = "sav", col = "V2", format = "iso3n"),
  w6 = list(file = here("data", "wvs", "raw", "wave6", "wvs_wave6.parquet"),
            type = "parquet", col = "B_COUNTRY_ALPHA", format = "iso3c"),
  w7 = list(file = here("data", "wvs", "raw", "wave7", "wvs_wave7.parquet"),
            type = "parquet", col = "B_COUNTRY_ALPHA", format = "iso3c")
)

for (wave_name in names(wave_list)) {
  src <- country_sources[[wave_name]]

  # Read country column from raw data
  if (src$type == "parquet") {
    raw <- arrow::read_parquet(src$file, col_select = src$col)
    country_raw <- raw[[src$col]]
  } else {
    raw <- haven::read_sav(src$file, col_select = src$col, encoding = "latin1")
    if (src$format == "iso3c") {
      # Alpha columns: extract character values from haven_labelled
      country_raw <- as.character(haven::as_factor(raw[[src$col]]))
    } else {
      # Numeric columns: extract numeric codes
      country_raw <- as.numeric(haven::zap_labels(raw[[src$col]]))
    }
  }

  # Convert to ISO alpha-3 if needed
  if (src$format == "iso3n") {
    country <- countrycode::countrycode(country_raw, origin = "iso3n",
                                        destination = "iso3c", warn = FALSE)
  } else {
    country <- country_raw
  }

  if (length(country) != nrow(wave_list[[wave_name]])) {
    warning(sprintf("Row count mismatch for %s: master=%d, raw=%d",
                    wave_name, nrow(wave_list[[wave_name]]), length(country)))
  } else {
    wave_list[[wave_name]]$country <- country
    n_countries <- length(unique(na.omit(country)))
    cat(sprintf("  %s: %d countries\n", wave_name, n_countries))
  }
}

# ==============================================================================
# COMBINE WAVES
# ==============================================================================

cat("\nCombining waves...\n")
wvs_combined <- bind_rows(wave_list)

# Convert wave column from character ("w1"/"w2"/...) to numeric (1/2/...)
wvs_combined <- wvs_combined %>%
  mutate(wave = as.integer(gsub("w", "", wave)))

cat(sprintf("  Combined: %s rows, %d columns\n",
            format(nrow(wvs_combined), big.mark = ","),
            ncol(wvs_combined)))

# ==============================================================================
# CLEAN UP
# ==============================================================================

# Remove row_id (internal tracking, not useful for analysis)
wvs_harmonized <- wvs_combined %>%
  select(-row_id)

# Zap any remaining haven labels
wvs_harmonized <- wvs_harmonized %>%
  mutate(across(where(~ inherits(.x, "haven_labelled")), ~ as.numeric(haven::zap_labels(.x))))

# Rescale education to 0-1 (WVS raw: 1-3)
if ("education_level" %in% names(wvs_harmonized)) {
  wvs_harmonized <- wvs_harmonized %>%
    mutate(education_level_01 = (education_level - 1) / 2)
}

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("DATASET SUMMARY\n")
cat(strrep("=", 70), "\n\n")

# Wave summary
cat("Respondents per wave:\n")
wave_summary <- wvs_harmonized %>%
  group_by(wave) %>%
  summarise(n = n(), countries = n_distinct(country, na.rm = TRUE), .groups = "drop")
print(as.data.frame(wave_summary))

cat(sprintf("\nTotal: %s respondents across %d waves\n",
            format(nrow(wvs_harmonized), big.mark = ","),
            n_distinct(wvs_harmonized$wave)))

# Variable list
var_names <- setdiff(names(wvs_harmonized), c("wave", "country"))
cat(sprintf("\n%d harmonized variables:\n", length(var_names)))
cat(paste("  ", var_names, collapse = "\n"), "\n")

# ==============================================================================
# SAVE
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("SAVING\n")
cat(strrep("=", 70), "\n\n")

# RDS
rds_path <- here("data", "processed", "wvs_harmonized.rds")
saveRDS(wvs_harmonized, rds_path)
cat(sprintf("  RDS:     %s\n", rds_path))

# Parquet
parquet_path <- here("data", "processed", "wvs_harmonized.parquet")
arrow::write_parquet(wvs_harmonized, parquet_path)
cat(sprintf("  Parquet: %s\n", parquet_path))

# Also save to outputs for convenience
saveRDS(wvs_harmonized, here("outputs", "wvs", "wvs_harmonized.rds"))

cat(sprintf("\nwvs_harmonized saved: %s rows, %d columns\n",
            format(nrow(wvs_harmonized), big.mark = ","),
            ncol(wvs_harmonized)))
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# RUN MANIFEST (audit ticket C2)
# ==============================================================================
manifest_inputs <- unname(unlist(lapply(country_sources, `[[`, "file")))

manifest_outputs <- c(
  rds_path,
  parquet_path,
  here("outputs", "wvs", "wvs_harmonized.rds")
)

write_manifest(
  survey      = "wvs",
  inputs      = manifest_inputs,
  specs       = list_survey_specs("wvs"),
  outputs     = manifest_outputs,
  output_path = here("outputs", "wvs", "manifest.json")
)

cat("Manifest written: ", here("outputs", "wvs", "manifest.json"), "\n", sep = "")

# ==============================================================================
# OUTPUT INVARIANTS (audit ticket E2)
# ==============================================================================
# Non-blocking post-hoc validator. Writes outputs/wvs/03-invariants.md and
# audit/reports/wvs/03-invariants.csv.
source(here("src", "r", "data_prep_modules", "2.5_validate_harmonization.R"))
results <- tryCatch(
  run_validation(survey = "wvs", save_report = TRUE, verbose = FALSE),
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
run_post_harmonize_gate("wvs", quiet_checks = TRUE)
