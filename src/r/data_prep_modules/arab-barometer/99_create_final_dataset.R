# Arab Barometer: Create final combined dataset
#
# This script:
# 1. Loads per-wave master files from outputs/arab-barometer/
# 2. Adds country identifier (ISO3 from raw value labels)
# 3. Adds year variable (midpoint of fieldwork)
# 4. Row-binds waves into a single dataset
# 5. Saves as arab_barometer_harmonized.rds and .parquet

library(here)
library(dplyr)
library(haven)
library(arrow)

source(here::here("src", "r", "utils", "provenance.R"))
source(here::here("src", "r", "utils", "spec_discovery.R"))

cat("\n")
cat(strrep("=", 70), "\n")
cat("CREATING FINAL DATASET: arab_barometer_harmonized\n")
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# LOAD MASTER WAVE FILES
# ==============================================================================

output_dir <- here("outputs", "arab-barometer")
wave_files <- sort(list.files(output_dir, pattern = "^master_w[0-9]+\\.rds$", full.names = TRUE))

if (length(wave_files) == 0) {
  stop("No master files found in outputs/arab-barometer/. Run 2_harmonize_all.R first.")
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

# Arab Barometer country names to ISO alpha-3
country_name_to_iso3 <- c(
  "Algeria"     = "DZA",
  "Bahrain"     = "BHR",
  "Egypt"       = "EGY",
  "Iraq"        = "IRQ",
  "Jordan"      = "JOR",
  "Kuwait"      = "KWT",
  "Lebanon"     = "LBN",
  "Libya"       = "LBY",
  "Mauritania"  = "MRT",
  "Morocco"     = "MAR",
  "Palestine"   = "PSE",
  "Qatar"       = "QAT",
  "Saudi Arabia" = "SAU",
  "Sudan"       = "SDN",
  "Syria"       = "SYR",
  "Tunisia"     = "TUN",
  "Yemen"       = "YEM"
)

# ==============================================================================
# RAW DATA PATHS (for country extraction)
# ==============================================================================

# These will need updating once the actual filenames are known
# W1 excluded (no Tunisia), W6 deprioritized (COVID split questionnaire)
raw_dirs <- list(
  w2 = here("data", "arab-barometer", "raw", "wave2"),
  w3 = here("data", "arab-barometer", "raw", "wave3"),
  w4 = here("data", "arab-barometer", "raw", "wave4"),
  w5 = here("data", "arab-barometer", "raw", "wave5"),
  w7 = here("data", "arab-barometer", "raw", "wave7"),
  w8 = here("data", "arab-barometer", "raw", "wave8")
)

# Representative years for each wave (midpoint of fieldwork)
wave_years <- c(
  w2 = 2011L, w3 = 2013L, w4 = 2016L, w5 = 2019L,
  w7 = 2022L, w8 = 2024L
)

# ==============================================================================
# ADD COUNTRY IDENTIFIER FROM RAW DATA
# ==============================================================================

cat("\nAdding country identifiers from raw .sav files...\n")

for (wave_name in names(wave_list)) {
  raw_dir <- raw_dirs[[wave_name]]

  if (is.null(raw_dir) || !dir.exists(raw_dir)) {
    warning(sprintf("No raw directory for %s", wave_name))
    wave_list[[wave_name]]$country <- NA_character_
    next
  }

  # Find .sav file
  sav_files <- list.files(raw_dir, pattern = "\\.sav$", full.names = TRUE,
                          ignore.case = TRUE)
  if (length(sav_files) == 0) {
    warning(sprintf("No .sav file for %s", wave_name))
    wave_list[[wave_name]]$country <- NA_character_
    next
  }

  raw <- haven::read_sav(sav_files[which.max(file.size(sav_files))],
                         encoding = "latin1")

  # Country variable name varies across waves
  # Common names: COUNTRY, country, Q1001, Q1, QCOUNTRY
  cvar_candidates <- c("COUNTRY", "country", "Country", "Q1001", "Q1", "QCOUNTRY")
  cvar <- intersect(cvar_candidates, names(raw))

  if (length(cvar) == 0) {
    # Fallback: search for any variable with "country" in the name
    cvar <- grep("country", names(raw), ignore.case = TRUE, value = TRUE)
  }

  if (length(cvar) == 0) {
    warning(sprintf("No COUNTRY variable found for %s", wave_name))
    wave_list[[wave_name]]$country <- NA_character_
    next
  }

  cvar <- cvar[1]

  # Use haven labels to get country names, then map to ISO3
  country_factor <- haven::as_factor(raw[[cvar]])
  country_names <- as.character(country_factor)
  country_names <- trimws(country_names)

  # Strip numbered prefixes like "21. Tunisia" → "Tunisia" (W2 format)
  country_names <- gsub("^[0-9]+\\.\\s*", "", country_names)

  # Map to ISO3
  iso3 <- country_name_to_iso3[country_names]

  # Handle any unmapped names
  unmapped <- unique(country_names[is.na(iso3) & !is.na(country_names) & country_names != ""])
  if (length(unmapped) > 0) {
    warning(sprintf("Unmapped country names in %s: %s",
                    wave_name, paste(unmapped, collapse = ", ")))
  }

  if (length(iso3) == nrow(wave_list[[wave_name]])) {
    wave_list[[wave_name]]$country <- iso3
    n_countries <- length(unique(na.omit(iso3)))
    cat(sprintf("  %s: %d countries\n", wave_name, n_countries))
  } else {
    warning(sprintf("Row count mismatch for %s", wave_name))
    wave_list[[wave_name]]$country <- NA_character_
  }
}

# ==============================================================================
# ADD YEAR VARIABLE
# ==============================================================================

for (wave_name in names(wave_list)) {
  wave_list[[wave_name]]$year <- wave_years[[wave_name]]
}

# ==============================================================================
# FILL int_year FOR W2/W4/W5 FROM FIELDWORK CROSSWALK
# ==============================================================================
# W2, W4, W5 raw AB files contain no interview-date column. Populate int_year
# (and int_month where known from AB methodology reports) using a country ×
# wave crosswalk. W3/W7/W8 retain their date-derived int_year.
#
# Sources: Arab Barometer methodology reports (abvvi methodology pdf,
# waveV methodology pdf, waveIV methodology pdf, aboutarabbarometer.org).
# Where a wave straddled a calendar boundary, the year listed below is the
# one during which the majority of interviews took place.

ab_fieldwork_year <- function(wave, country_iso3) {
  # Returns integer fieldwork year, or NA if unknown
  cross <- list(
    w2 = c(ALG = 2011L, EGY = 2011L, IRQ = 2011L, JOR = 2010L, LBN = 2010L,
           PSE = 2010L, SAU = 2011L, SDN = 2011L, TUN = 2011L, YEM = 2011L,
           DZA = 2011L),
    w4 = c(ALG = 2016L, DZA = 2016L, EGY = 2016L, IRQ = 2016L, JOR = 2016L,
           KWT = 2016L, LBN = 2016L, MAR = 2016L, PSE = 2016L, TUN = 2016L),
    w5 = c(ALG = 2019L, DZA = 2019L, EGY = 2019L, IRQ = 2018L, JOR = 2018L,
           KWT = 2019L, LBN = 2018L, LBY = 2019L, MAR = 2018L, PSE = 2018L,
           QAT = 2018L, SDN = 2018L, TUN = 2018L, YEM = 2019L)
  )
  if (!wave %in% names(cross)) return(NA_integer_)
  table <- cross[[wave]]
  out <- unname(table[country_iso3])
  # Fallback to wave default if country not in crosswalk
  default <- switch(wave, w2 = 2011L, w4 = 2016L, w5 = 2018L, NA_integer_)
  ifelse(is.na(out), default, out)
}

for (wave_name in c("w2", "w4", "w5")) {
  if (!wave_name %in% names(wave_list)) next
  df <- wave_list[[wave_name]]
  df$int_year <- ab_fieldwork_year(wave_name, df$country)
  wave_list[[wave_name]] <- df
  cat(sprintf("  %s int_year filled from crosswalk (%d non-NA / %d)\n",
              wave_name, sum(!is.na(df$int_year)), nrow(df)))
}

# ==============================================================================
# COERCE int_date TO CONSISTENT TYPE BEFORE BINDING
# ==============================================================================
# int_date is Date in waves with dates, NA/double in waves without.
# Coerce all to Date so bind_rows doesn't choke on mixed types.
for (wn in names(wave_list)) {
  if ("int_date" %in% names(wave_list[[wn]])) {
    if (!inherits(wave_list[[wn]]$int_date, "Date")) {
      wave_list[[wn]]$int_date <- as.Date(NA)
    }
  }
}

# ==============================================================================
# COMBINE WAVES
# ==============================================================================

cat("\nCombining waves...\n")
ab_combined <- bind_rows(wave_list)

cat(sprintf("  Combined: %s rows, %d columns\n",
            format(nrow(ab_combined), big.mark = ","),
            ncol(ab_combined)))

# ==============================================================================
# CLEAN UP
# ==============================================================================

ab_harmonized <- ab_combined %>%
  select(-row_id)

# Zap any remaining haven labels
ab_harmonized <- ab_harmonized %>%
  mutate(across(where(~ inherits(.x, "haven_labelled")), ~ as.numeric(haven::zap_labels(.x))))

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("DATASET SUMMARY\n")
cat(strrep("=", 70), "\n\n")

cat("Respondents per wave:\n")
wave_summary <- ab_harmonized %>%
  group_by(wave, year) %>%
  summarise(n = n(), countries = n_distinct(country, na.rm = TRUE), .groups = "drop")
print(as.data.frame(wave_summary))

cat(sprintf("\nTotal: %s respondents across %d wave(s)\n",
            format(nrow(ab_harmonized), big.mark = ","),
            n_distinct(ab_harmonized$wave)))

cat(sprintf("\nTunisia respondents: %s\n",
            format(sum(ab_harmonized$country == "TUN", na.rm = TRUE), big.mark = ",")))

var_names <- setdiff(names(ab_harmonized), c("wave", "year", "country"))
cat(sprintf("\n%d harmonized variables:\n", length(var_names)))
cat(paste("  ", var_names, collapse = "\n"), "\n")

# ==============================================================================
# SAVE
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("SAVING\n")
cat(strrep("=", 70), "\n\n")

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)

rds_path <- here("data", "processed", "arab_barometer_harmonized.rds")
saveRDS(ab_harmonized, rds_path)
cat(sprintf("  RDS:     %s\n", rds_path))

parquet_path <- here("data", "processed", "arab_barometer_harmonized.parquet")
arrow::write_parquet(ab_harmonized, parquet_path)
cat(sprintf("  Parquet: %s\n", parquet_path))

cat(sprintf("\narab_barometer_harmonized saved: %s rows, %d columns\n",
            format(nrow(ab_harmonized), big.mark = ","),
            ncol(ab_harmonized)))
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# RUN MANIFEST (audit ticket C2)
# ==============================================================================
# Inputs: one .sav per included wave dir (largest .sav wins, matching the
# loader's policy). raw_dirs was defined above for country extraction.
.ab_pick_sav <- function(d) {
  if (is.null(d) || !dir.exists(d)) return(NA_character_)
  files <- list.files(d, pattern = "\\.sav$", full.names = TRUE,
                      ignore.case = TRUE)
  if (length(files) == 0) return(NA_character_)
  files[which.max(file.size(files))]
}
manifest_inputs <- vapply(raw_dirs, .ab_pick_sav, character(1))
manifest_inputs <- unname(manifest_inputs[!is.na(manifest_inputs)])

manifest_outputs <- c(rds_path, parquet_path)

write_manifest(
  survey      = "arab-barometer",
  inputs      = manifest_inputs,
  specs       = list_survey_specs("arab-barometer"),
  outputs     = manifest_outputs,
  output_path = here("outputs", "arab-barometer", "manifest.json")
)

cat("Manifest written: ",
    here("outputs", "arab-barometer", "manifest.json"), "\n", sep = "")
