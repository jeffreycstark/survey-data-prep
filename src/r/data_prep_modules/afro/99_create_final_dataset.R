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
  w1 = here("data", "afro", "raw", "round1", "merged_r1_data.sav"),
  w2 = here("data", "afro", "raw", "round2", "merged_r2_data.sav"),
  w3 = here("data", "afro", "raw", "round3", "merged_r3_data.sav"),
  w4 = here("data", "afro", "raw", "round4", "merged_r4_data.sav"),
  w5 = here("data", "afro", "raw", "round5", "merged_r5_data.sav"),
  w6 = here("data", "afro", "raw", "round6", "merged_r6_data.sav"),
  w7 = here("data", "afro", "raw", "round7", "merged_r7_data.sav"),
  w8 = here("data", "afro", "raw", "round8", "merged_r8_data.sav"),
  w9 = here("data", "afro", "raw", "wave9",
            "R9.Merge_39ctry.20Nov23.final_.release_Updated.4Jun25-3.sav")
)

# Representative years for each round (midpoint of fieldwork)
round_years <- c(
  w1 = 1999L, w2 = 2002L, w3 = 2005L, w4 = 2008L,
  w5 = 2012L, w6 = 2015L, w7 = 2017L, w8 = 2019L, w9 = 2022L
)

# ==============================================================================
# ADD COUNTRY IDENTIFIER FROM RAW DATA
# ==============================================================================

cat("\nAdding country identifiers from raw .sav files...\n")

for (wave_name in names(wave_list)) {
  raw_path <- raw_paths[[wave_name]]

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
