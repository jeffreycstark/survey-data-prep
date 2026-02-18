# Afrobarometer: Create final combined dataset
#
# This script:
# 1. Loads per-wave master files from outputs/afro/
# 2. Adds country identifier (COUNTRY) from raw .sav
# 3. Saves as afro_harmonized.rds and .parquet

library(here)
library(dplyr)
library(haven)
library(arrow)

cat("\n")
cat(strrep("=", 70), "\n")
cat("CREATING FINAL DATASET: afro_harmonized\n")
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# LOAD MASTER WAVE FILES
# ==============================================================================

output_dir <- here("outputs", "afro")
wave_files <- sort(list.files(output_dir, pattern = "^master_w9\\.rds$", full.names = TRUE))

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
# ADD COUNTRY IDENTIFIER FROM RAW DATA
# ==============================================================================

cat("\nAdding country identifiers from raw .sav file...\n")

# Afrobarometer R9 country codes (COUNTRY variable) → ISO alpha-3
afro_country_to_iso3 <- c(
  "2" = "AGO", "3" = "BEN", "4" = "BWA", "5" = "BFA", "6" = "CPV",
  "7" = "CMR", "8" = "COG", "9" = "CIV", "10" = "SWZ", "11" = "ETH",
  "12" = "GAB", "13" = "GMB", "14" = "GHA", "15" = "GIN", "16" = "KEN",
  "17" = "LSO", "18" = "LBR", "19" = "MDG", "20" = "MWI", "21" = "MLI",
  "22" = "MRT", "23" = "MUS", "24" = "MAR", "25" = "MOZ", "26" = "NAM",
  "27" = "NER", "28" = "NGA", "29" = "STP", "30" = "SEN", "31" = "SYC",
  "32" = "SLE", "33" = "ZAF", "34" = "SDN", "35" = "TZA", "36" = "TGO",
  "37" = "TUN", "38" = "UGA", "39" = "ZMB", "40" = "ZWE"
)

raw_path <- here("data", "afro", "raw", "wave9",
                 "R9.Merge_39ctry.20Nov23.final_.release_Updated.4Jun25-3.sav")

raw <- haven::read_sav(raw_path, col_select = "COUNTRY")
country_codes <- as.character(as.integer(raw$COUNTRY))

# Map to ISO alpha-3
country <- afro_country_to_iso3[country_codes]

if (length(country) != nrow(wave_list[["w9"]])) {
  warning(sprintf("Row count mismatch for w9: master=%d, raw=%d",
                  nrow(wave_list[["w9"]]), length(country)))
} else {
  wave_list[["w9"]]$country <- country
  n_countries <- length(unique(na.omit(country)))
  cat(sprintf("  w9: %d countries\n", n_countries))
}

# ==============================================================================
# ADD YEAR VARIABLE
# ==============================================================================

# Afrobarometer R9 fieldwork was 2021-2023; use 2022 as representative year
wave_list[["w9"]]$year <- 2022L

# ==============================================================================
# COMBINE (single wave, but keep pattern consistent)
# ==============================================================================

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

# Remove row_id (internal tracking, not useful for analysis)
afro_harmonized <- afro_combined %>%
  select(-row_id)

# Zap any remaining haven labels
afro_harmonized <- afro_harmonized %>%
  mutate(across(where(~ inherits(.x, "haven_labelled")), ~ as.numeric(haven::zap_labels(.x))))

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("DATASET SUMMARY\n")
cat(strrep("=", 70), "\n\n")

# Wave summary
cat("Respondents per wave:\n")
wave_summary <- afro_harmonized %>%
  group_by(wave, year) %>%
  summarise(n = n(), countries = n_distinct(country, na.rm = TRUE), .groups = "drop")
print(as.data.frame(wave_summary))

cat(sprintf("\nTotal: %s respondents across %d wave(s)\n",
            format(nrow(afro_harmonized), big.mark = ","),
            n_distinct(afro_harmonized$wave)))

# Variable list
var_names <- setdiff(names(afro_harmonized), c("wave", "year", "country"))
cat(sprintf("\n%d harmonized variables:\n", length(var_names)))
cat(paste("  ", var_names, collapse = "\n"), "\n")

# ==============================================================================
# SAVE
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("SAVING\n")
cat(strrep("=", 70), "\n\n")

# Ensure output directory exists
dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)

# RDS
rds_path <- here("data", "processed", "afro_harmonized.rds")
saveRDS(afro_harmonized, rds_path)
cat(sprintf("  RDS:     %s\n", rds_path))

# Parquet
parquet_path <- here("data", "processed", "afro_harmonized.parquet")
arrow::write_parquet(afro_harmonized, parquet_path)
cat(sprintf("  Parquet: %s\n", parquet_path))

# Also save to outputs for convenience
saveRDS(afro_harmonized, here("outputs", "afro", "afro_harmonized.rds"))

cat(sprintf("\n✅ afro_harmonized saved: %s rows, %d columns\n",
            format(nrow(afro_harmonized), big.mark = ","),
            ncol(afro_harmonized)))
cat(strrep("=", 70), "\n\n")
