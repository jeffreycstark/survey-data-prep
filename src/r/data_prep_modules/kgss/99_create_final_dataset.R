# KGSS: Create final combined dataset
#
# Loads per-wave master files from outputs/kgss/,
# adds country and year identifiers, and saves
# kgss_harmonized.rds / .parquet.
#
# SURVEY YEARS (wave = calendar year integer):
#   2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010,
#   2011, 2012, 2013, 2014, 2016, 2018, 2021, 2023, 2025
#   (no data for 2015, 2017, 2019, 2020, 2022, 2024)
#
# WEIGHT: FINALWT (range ~0.20–4.59, mean=1); harmonized name: weight

library(here)
library(dplyr)
library(arrow)

source(here::here("src", "r", "utils", "provenance.R"))
source(here::here("src", "r", "utils", "spec_discovery.R"))

cat("\n")
cat(strrep("=", 70), "\n")
cat("CREATING FINAL DATASET: kgss_harmonized\n")
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# LOAD MASTER WAVE FILES
# ==============================================================================

output_dir <- here("outputs", "kgss")
wave_files <- sort(list.files(output_dir,
                               pattern = "^master_w[0-9]{4}\\.rds$",
                               full.names = TRUE))

if (length(wave_files) == 0) {
  stop("No master files found in outputs/kgss/. Run 2_harmonize_all.R first.")
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
# ADD COUNTRY AND YEAR
# ==============================================================================

cat("\nAdding country and year identifiers...\n")

for (wave_name in names(wave_list)) {
  year_val <- as.integer(gsub("w", "", wave_name))
  wave_list[[wave_name]]$country <- "KOR"
  wave_list[[wave_name]]$year    <- year_val
  cat(sprintf("  %s → country=KOR, year=%d\n", wave_name, year_val))
}

# ==============================================================================
# COMBINE WAVES
# ==============================================================================

cat("\nCombining waves...\n")
kgss_combined <- bind_rows(wave_list)

# wave column: calendar year integer (e.g. 2003, not sequential index)
kgss_combined <- kgss_combined %>%
  mutate(wave = as.integer(gsub("w", "", wave)))

cat(sprintf("  Combined: %s rows, %d columns\n",
            format(nrow(kgss_combined), big.mark = ","),
            ncol(kgss_combined)))

# ==============================================================================
# CLEAN UP
# ==============================================================================

kgss_harmonized <- kgss_combined %>%
  select(-row_id)

# Zap any remaining haven labels
kgss_harmonized <- kgss_harmonized %>%
  mutate(across(where(~ inherits(.x, "haven_labelled")),
                ~ as.numeric(haven::zap_labels(.x))))

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("DATASET SUMMARY\n")
cat(strrep("=", 70), "\n\n")

wave_summary <- kgss_harmonized %>%
  group_by(wave, year) %>%
  summarise(n = n(), .groups = "drop")
print(as.data.frame(wave_summary))

cat(sprintf("\nTotal: %s respondents, %d survey years\n",
            format(nrow(kgss_harmonized), big.mark = ","),
            n_distinct(kgss_harmonized$wave)))

var_names <- setdiff(names(kgss_harmonized), c("wave", "year", "country", "weight"))
cat(sprintf("\n%d harmonized variables:\n", length(var_names)))
cat(paste0("  ", var_names, collapse = "\n"), "\n")

# ==============================================================================
# SAVE
# ==============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("SAVING\n")
cat(strrep("=", 70), "\n\n")

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)

rds_path     <- here("data", "processed", "kgss_harmonized.rds")
parquet_path <- here("data", "processed", "kgss_harmonized.parquet")

saveRDS(kgss_harmonized, rds_path)
cat(sprintf("  RDS:     %s\n", rds_path))

arrow::write_parquet(kgss_harmonized, parquet_path)
cat(sprintf("  Parquet: %s\n", parquet_path))

saveRDS(kgss_harmonized, here("outputs", "kgss", "kgss_harmonized.rds"))

cat(sprintf("\n✅ kgss_harmonized saved: %s rows, %d columns\n",
            format(nrow(kgss_harmonized), big.mark = ","),
            ncol(kgss_harmonized)))
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# RUN MANIFEST (audit ticket C2)
# ==============================================================================
# KGSS reads a single cumulative .sav and splits it by YEAR; the manifest
# records the upstream cumulative file as the input.
manifest_inputs  <- c(here("data", "kgss", "raw", "kor_data_CUM0074.sav"))
manifest_outputs <- c(
  rds_path,
  parquet_path,
  here("outputs", "kgss", "kgss_harmonized.rds")
)

write_manifest(
  survey      = "kgss",
  inputs      = manifest_inputs,
  specs       = list_survey_specs("kgss"),
  outputs     = manifest_outputs,
  output_path = here("outputs", "kgss", "manifest.json")
)

cat("Manifest written: ", here("outputs", "kgss", "manifest.json"), "\n", sep = "")

# ==============================================================================
# OUTPUT INVARIANTS (audit ticket E2)
# ==============================================================================
source(here("src", "r", "data_prep_modules", "2.5_validate_harmonization.R"))
results <- tryCatch(
  run_validation(survey = "kgss", save_report = TRUE, verbose = FALSE),
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
run_post_harmonize_gate("kgss", quiet_checks = TRUE)
