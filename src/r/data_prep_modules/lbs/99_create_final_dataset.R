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

# Load the wave finder function
source(here::here("src/r/data_prep_modules/lbs/0_load_waves.R"))
source(here::here("src", "r", "utils", "provenance.R"))
source(here::here("src", "r", "utils", "spec_discovery.R"))

cat("\n")
cat(strrep("=", 70), "\n")
cat("CREATING FINAL DATASET: lbs_harmonized\n")
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# LOAD MASTER WAVE FILES
# ==============================================================================

output_dir <- here("outputs", "lbs")
wave_files <- sort(list.files(output_dir, pattern = "^master_y[0-9]+\\.rds$", full.names = TRUE))

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
idenpa_to_iso3 <- c(
  "32" = "ARG", "68" = "BOL", "76" = "BRA", "152" = "CHL",
  "170" = "COL", "188" = "CRI", "214" = "DOM", "218" = "ECU",
  "222" = "SLV", "320" = "GTM", "340" = "HND", "484" = "MEX",
  "558" = "NIC", "591" = "PAN", "600" = "PRY", "604" = "PER",
  "724" = "ESP", "858" = "URY", "862" = "VEN"
)

# Country ID variable name differs across waves
# Most waves: IDENPA; some early waves: idenpa or numpais
find_country_var <- function(df) {
  candidates <- c("IDENPA", "idenpa", "Idenpa", "numpais", "NUMPAIS", "pais", "PAIS")
  for (v in candidates) {
    if (v %in% names(df)) return(v)
  }
  # Fallback: case-insensitive search
  idx <- grep("^idenpa$", names(df), ignore.case = TRUE)
  if (length(idx) > 0) return(names(df)[idx[1]])
  return(NULL)
}

for (wave_name in names(wave_list)) {
  yr <- as.integer(gsub("y", "", wave_name))
  raw_path <- find_lbs_eng_sav(yr)

  # Read just the country ID column
  raw <- haven::read_sav(raw_path, encoding = "latin1")
  cvar <- find_country_var(raw)

  if (is.null(cvar)) {
    warning(sprintf("No country ID variable found for %s", wave_name))
    wave_list[[wave_name]]$country <- NA_character_
    next
  }

  country_codes <- as.character(as.integer(raw[[cvar]]))
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

for (wave_name in names(wave_list)) {
  wave_list[[wave_name]]$year <- as.integer(gsub("y", "", wave_name))
}

# ==============================================================================
# COMBINE WAVES
# ==============================================================================

cat("\nCombining waves...\n")
lbs_combined <- bind_rows(wave_list)

# Convert wave column from character ("y1995") to numeric year
lbs_combined <- lbs_combined %>%
  mutate(wave = as.integer(gsub("y", "", wave)))

cat(sprintf("  Combined: %s rows, %d columns\n",
            format(nrow(lbs_combined), big.mark = ","),
            ncol(lbs_combined)))

# ==============================================================================
# CLEAN UP
# ==============================================================================

lbs_harmonized <- lbs_combined %>%
  select(-row_id)

# Zap any remaining haven labels
lbs_harmonized <- lbs_harmonized %>%
  mutate(across(where(~ inherits(.x, "haven_labelled")), ~ as.numeric(haven::zap_labels(.x))))

# Rescale education to 0-1 (LBS raw: 1-7)
if ("education_level" %in% names(lbs_harmonized)) {
  lbs_harmonized <- lbs_harmonized %>%
    mutate(education_level_01 = (education_level - 1) / 6)
}

# 5-category education (LBS REEDUC 1-7 → 1-5)
# 1=No studies(1), 2=Primary(2-3), 3=Secondary(4-5), 4=Incomplete higher(6), 5=Complete higher(7)
if ("education_level" %in% names(lbs_harmonized)) {
  lbs_harmonized <- lbs_harmonized %>%
    mutate(education_5cat = case_when(
      education_level == 1             ~ 1L,
      education_level %in% 2:3        ~ 2L,
      education_level %in% 4:5        ~ 3L,
      education_level == 6            ~ 4L,
      education_level == 7            ~ 5L,
      TRUE                            ~ NA_integer_
    ))
}

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("DATASET SUMMARY\n")
cat(strrep("=", 70), "\n\n")

cat("Respondents per wave:\n")
wave_summary <- lbs_harmonized %>%
  group_by(wave, year) %>%
  summarise(n = n(), countries = n_distinct(country, na.rm = TRUE), .groups = "drop")
print(as.data.frame(wave_summary))

cat(sprintf("\nTotal: %s respondents across %d waves\n",
            format(nrow(lbs_harmonized), big.mark = ","),
            n_distinct(lbs_harmonized$wave)))

var_names <- setdiff(names(lbs_harmonized), c("wave", "year", "country"))
cat(sprintf("\n%d harmonized variables:\n", length(var_names)))
cat(paste("  ", var_names, collapse = "\n"), "\n")

# ==============================================================================
# SAVE
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("SAVING\n")
cat(strrep("=", 70), "\n\n")

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)

rds_path <- here("data", "processed", "lbs_harmonized.rds")
saveRDS(lbs_harmonized, rds_path)
cat(sprintf("  RDS:     %s\n", rds_path))

parquet_path <- here("data", "processed", "lbs_harmonized.parquet")
arrow::write_parquet(lbs_harmonized, parquet_path)
cat(sprintf("  Parquet: %s\n", parquet_path))

saveRDS(lbs_harmonized, here("outputs", "lbs", "lbs_harmonized.rds"))

cat(sprintf("\nlbs_harmonized saved: %s rows, %d columns\n",
            format(nrow(lbs_harmonized), big.mark = ","),
            ncol(lbs_harmonized)))
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# RUN MANIFEST (audit ticket C2)
# ==============================================================================
# Inputs: every English .sav consumed by load_lbs_waves(), one per year. Use
# the same finder the loader uses so the manifest reflects the actual files.
lbs_years <- c(1995, 1996, 1997, 1998, 2000, 2001, 2002, 2003, 2004, 2005,
               2006, 2007, 2008, 2009, 2010, 2011, 2013, 2015, 2016, 2017,
               2018, 2020, 2023, 2024)
manifest_inputs <- vapply(lbs_years, find_lbs_eng_sav, character(1))

manifest_outputs <- c(
  rds_path,
  parquet_path,
  here("outputs", "lbs", "lbs_harmonized.rds")
)

write_manifest(
  survey      = "lbs",
  inputs      = manifest_inputs,
  specs       = list_survey_specs("lbs"),
  outputs     = manifest_outputs,
  output_path = here("outputs", "lbs", "manifest.json")
)

cat("Manifest written: ", here("outputs", "lbs", "manifest.json"), "\n", sep = "")

