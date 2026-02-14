# LBS: Create final combined dataset
#
# This script:
# 1. Loads per-wave master files from outputs/lbs/
# 2. Adds country identifier (IDENPA) from raw .sav
# 3. Row-binds waves into a single dataset
# 4. Saves as lbs_harmonized.rds and .parquet

library(here)
library(dplyr)
library(haven)
library(arrow)

cat("\n")
cat(strrep("=", 70), "\n")
cat("CREATING FINAL DATASET: lbs_harmonized\n")
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# LOAD MASTER WAVE FILES
# ==============================================================================

output_dir <- here("outputs", "lbs")
wave_files <- sort(list.files(output_dir, pattern = "^master_w[1-5]\\.rds$", full.names = TRUE))

if (length(wave_files) == 0) {
  stop("No master files found in outputs/lbs/. Run 2_harmonize_all.R first.")
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

cat("\nAdding country identifiers from raw .sav files...\n")

# LBS country codes (IDENPA) are ISO 3166-1 numeric codes
# Map to ISO alpha-3 for consistency with WVS
idenpa_to_iso3 <- c(
  "32" = "ARG", "68" = "BOL", "76" = "BRA", "152" = "CHL",
  "170" = "COL", "188" = "CRI", "214" = "DOM", "218" = "ECU",
  "222" = "SLV", "320" = "GTM", "340" = "HND", "484" = "MEX",
  "558" = "NIC", "591" = "PAN", "600" = "PRY", "604" = "PER",
  "724" = "ESP", "858" = "URY", "862" = "VEN"
)

raw_paths <- list(
  w1 = here("data", "lbs", "raw", "2015", "Latinobarometro_2015_Eng.sav"),
  w2 = here("data", "lbs", "raw", "2016", "Latinobarometro2016Eng_v20170205.sav"),
  w3 = here("data", "lbs", "raw", "2018", "Latinobarometro_2018_Eng_Spss_v20190303.sav"),
  w4 = here("data", "lbs", "raw", "2020", "Latinobarometro_2020_Eng_Spss_v1_0.sav"),
  w5 = here("data", "lbs", "raw", "2023", "Latinobarometro_2023_Eng_Spss_v1_0.sav")
)

for (wave_name in names(wave_list)) {
  raw <- haven::read_sav(raw_paths[[wave_name]], col_select = "IDENPA")
  country_codes <- as.character(as.integer(raw$IDENPA))

  # Map to ISO alpha-3
  country <- idenpa_to_iso3[country_codes]

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
# ADD YEAR VARIABLE
# ==============================================================================

wave_years <- c(w1 = 2015L, w2 = 2016L, w3 = 2018L, w4 = 2020L, w5 = 2023L)

for (wave_name in names(wave_list)) {
  wave_list[[wave_name]]$year <- wave_years[[wave_name]]
}

# ==============================================================================
# COMBINE WAVES
# ==============================================================================

cat("\nCombining waves...\n")
lbs_combined <- bind_rows(wave_list)

# Convert wave column from character ("w1"/"w2"/...) to numeric (1/2/...)
lbs_combined <- lbs_combined %>%
  mutate(wave = as.integer(gsub("w", "", wave)))

cat(sprintf("  Combined: %s rows, %d columns\n",
            format(nrow(lbs_combined), big.mark = ","),
            ncol(lbs_combined)))

# ==============================================================================
# CLEAN UP
# ==============================================================================

# Remove row_id (internal tracking, not useful for analysis)
lbs_harmonized <- lbs_combined %>%
  select(-row_id)

# Zap any remaining haven labels
lbs_harmonized <- lbs_harmonized %>%
  mutate(across(where(~ inherits(.x, "haven_labelled")), ~ as.numeric(haven::zap_labels(.x))))

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("DATASET SUMMARY\n")
cat(strrep("=", 70), "\n\n")

# Wave summary
cat("Respondents per wave:\n")
wave_summary <- lbs_harmonized %>%
  group_by(wave, year) %>%
  summarise(n = n(), countries = n_distinct(country, na.rm = TRUE), .groups = "drop")
print(as.data.frame(wave_summary))

cat(sprintf("\nTotal: %s respondents across %d waves\n",
            format(nrow(lbs_harmonized), big.mark = ","),
            n_distinct(lbs_harmonized$wave)))

# Variable list
var_names <- setdiff(names(lbs_harmonized), c("wave", "year", "country"))
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
rds_path <- here("data", "processed", "lbs_harmonized.rds")
saveRDS(lbs_harmonized, rds_path)
cat(sprintf("  RDS:     %s\n", rds_path))

# Parquet
parquet_path <- here("data", "processed", "lbs_harmonized.parquet")
arrow::write_parquet(lbs_harmonized, parquet_path)
cat(sprintf("  Parquet: %s\n", parquet_path))

# Also save to outputs for convenience
saveRDS(lbs_harmonized, here("outputs", "lbs", "lbs_harmonized.rds"))

cat(sprintf("\n✅ lbs_harmonized saved: %s rows, %d columns\n",
            format(nrow(lbs_harmonized), big.mark = ","),
            ncol(lbs_harmonized)))
cat(strrep("=", 70), "\n\n")
