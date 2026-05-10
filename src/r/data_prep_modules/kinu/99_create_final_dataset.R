# KINU: Create final combined dataset
#
# Loads per-wave master files from outputs/kinu/, adds
# country / year / fieldwork_month identifiers, and saves
# kinu_harmonized.rds / .parquet.
#
# WAVE STRUCTURE (string keys, year integer in `year` column):
#   w2014, w2015, w2016, w2017, w2018,
#   w2019a, w2019b, w2020a, w2020b, w2021a, w2021b,
#   w2022, w2023
#
# 2019, 2020, 2021 each have two fieldwork rounds (a/b). The `year` column
# collapses sub-waves to calendar year; `fieldwork_month` distinguishes them.
#
# WEIGHT: TBD — confirm raw weight column name from codebook before harmonization.

library(here)
library(dplyr)
library(arrow)

source(here("src", "r", "data_prep_modules", "kinu", "0_load_waves.R"))
source(here::here("src", "r", "utils", "provenance.R"))
source(here::here("src", "r", "utils", "spec_discovery.R"))

cat("\n")
cat(strrep("=", 70), "\n")
cat("CREATING FINAL DATASET: kinu_harmonized\n")
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# LOAD MASTER WAVE FILES
# ==============================================================================

output_dir <- here("outputs", "kinu")
wave_files <- sort(list.files(output_dir,
                               pattern = "^master_w20[0-9]{2}[ab]?\\.rds$",
                               full.names = TRUE))

if (length(wave_files) == 0) {
  stop("No master files found in outputs/kinu/. Run 2_harmonize_all.R first.")
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
# ADD COUNTRY, YEAR, FIELDWORK MONTH
# ==============================================================================

cat("\nAdding country/year/fieldwork_month identifiers...\n")

for (wave_name in names(wave_list)) {
  yr  <- KINU_WAVE_TO_YEAR[wave_name]
  mon <- KINU_WAVE_TO_MONTH[wave_name]
  wave_list[[wave_name]]$country         <- "KOR"
  wave_list[[wave_name]]$year            <- as.integer(yr)
  wave_list[[wave_name]]$fieldwork_month <- as.integer(mon)
  cat(sprintf("  %s → country=KOR, year=%d, fieldwork_month=%s\n",
              wave_name, yr, ifelse(is.na(mon), "NA", as.character(mon))))
}

# ==============================================================================
# COMBINE WAVES
# ==============================================================================

cat("\nCombining waves...\n")
kinu_combined <- bind_rows(wave_list)

# Keep `wave` as character (preserves a/b suffix); year is the numeric companion.
kinu_combined <- kinu_combined %>%
  mutate(wave = sub("^w", "", wave))

cat(sprintf("  Combined: %s rows, %d columns\n",
            format(nrow(kinu_combined), big.mark = ","),
            ncol(kinu_combined)))

# ==============================================================================
# CLEAN UP
# ==============================================================================

kinu_harmonized <- kinu_combined
if ("row_id" %in% names(kinu_harmonized)) {
  kinu_harmonized <- kinu_harmonized %>% select(-row_id)
}

# Zap any remaining haven labels
kinu_harmonized <- kinu_harmonized %>%
  mutate(across(where(~ inherits(.x, "haven_labelled")),
                ~ as.numeric(haven::zap_labels(.x))))

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("DATASET SUMMARY\n")
cat(strrep("=", 70), "\n\n")

wave_summary <- kinu_harmonized %>%
  group_by(wave, year, fieldwork_month) %>%
  summarise(n = n(), .groups = "drop")
print(as.data.frame(wave_summary))

cat(sprintf("\nTotal: %s respondents, %d wave entries (%d distinct calendar years)\n",
            format(nrow(kinu_harmonized), big.mark = ","),
            n_distinct(kinu_harmonized$wave),
            n_distinct(kinu_harmonized$year)))

var_names <- setdiff(names(kinu_harmonized),
                     c("wave", "year", "fieldwork_month", "country", "weight"))
cat(sprintf("\n%d harmonized variables:\n", length(var_names)))
cat(paste0("  ", var_names, collapse = "\n"), "\n")

# ==============================================================================
# SAVE
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("SAVING\n")
cat(strrep("=", 70), "\n\n")

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)

rds_path     <- here("data", "processed", "kinu_harmonized.rds")
parquet_path <- here("data", "processed", "kinu_harmonized.parquet")

saveRDS(kinu_harmonized, rds_path)
cat(sprintf("  RDS:     %s\n", rds_path))

arrow::write_parquet(kinu_harmonized, parquet_path)
cat(sprintf("  Parquet: %s\n", parquet_path))

saveRDS(kinu_harmonized, here("outputs", "kinu", "kinu_harmonized.rds"))

cat(sprintf("\n✅ kinu_harmonized saved: %s rows, %d columns\n",
            format(nrow(kinu_harmonized), big.mark = ","),
            ncol(kinu_harmonized)))
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# RUN MANIFEST (audit ticket C2)
# ==============================================================================
# KINU reads a single cumulative .sav and splits it by year-code.
manifest_inputs  <- c(here("data", "kinu", "raw", "kinu_2014-2023_en.sav"))
manifest_outputs <- c(
  rds_path,
  parquet_path,
  here("outputs", "kinu", "kinu_harmonized.rds")
)

write_manifest(
  survey      = "kinu",
  inputs      = manifest_inputs,
  specs       = list_survey_specs("kinu"),
  outputs     = manifest_outputs,
  output_path = here("outputs", "kinu", "manifest.json")
)

cat("Manifest written: ", here("outputs", "kinu", "manifest.json"), "\n", sep = "")
