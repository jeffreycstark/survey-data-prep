# WVS: Create final combined dataset
#
# This script:
# 1. Loads per-wave master files from outputs/wvs/
# 2. Adds country identifier (B_COUNTRY_ALPHA) from raw parquet
# 3. Row-binds waves into a single dataset
# 4. Saves as wvs_harmonized.rds and .parquet

library(here)
library(dplyr)
library(arrow)

cat("\n")
cat(strrep("=", 70), "\n")
cat("CREATING FINAL DATASET: wvs_harmonized\n")
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# LOAD MASTER WAVE FILES
# ==============================================================================

output_dir <- here("outputs", "wvs")
wave_files <- sort(list.files(output_dir, pattern = "^master_w[67]\\.rds$", full.names = TRUE))

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

cat("\nAdding country identifiers from raw parquet...\n")

raw_paths <- list(
  w6 = here("data", "wvs", "raw", "wave6", "wvs_wave6.parquet"),
  w7 = here("data", "wvs", "raw", "wave7", "wvs_wave7.parquet")
)

for (wave_name in names(wave_list)) {
  raw <- arrow::read_parquet(raw_paths[[wave_name]], col_select = "B_COUNTRY_ALPHA")
  country <- raw$B_COUNTRY_ALPHA

  if (length(country) != nrow(wave_list[[wave_name]])) {
    warning(sprintf("Row count mismatch for %s: master=%d, raw=%d",
                    wave_name, nrow(wave_list[[wave_name]]), length(country)))
  } else {
    wave_list[[wave_name]]$country <- country
    n_countries <- length(unique(country))
    cat(sprintf("  %s: %d countries\n", wave_name, n_countries))
  }
}

# ==============================================================================
# COMBINE WAVES
# ==============================================================================

cat("\nCombining waves...\n")
wvs_combined <- bind_rows(wave_list)

# Convert wave column from character ("w6"/"w7") to numeric (6/7)
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
  summarise(n = n(), countries = n_distinct(country), .groups = "drop")
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

cat(sprintf("\n✅ wvs_harmonized saved: %s rows, %d columns\n",
            format(nrow(wvs_harmonized), big.mark = ","),
            ncol(wvs_harmonized)))
cat(strrep("=", 70), "\n\n")
