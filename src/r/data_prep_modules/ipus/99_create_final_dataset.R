# IPUS: Create final combined dataset
#
# Loads per-wave master files from outputs/ipus/, adds country/year
# identifiers, and saves ipus_harmonized.rds / .parquet.
#
# WAVE STRUCTURE: 18 annual waves 2007-2024.
# WEIGHT: TBD per-wave (varies; some years have wt2/weight columns, others none).

library(here)
library(dplyr)
library(arrow)

source(here::here("src", "r", "data_prep_modules", "ipus", "0_load_waves.R"))
source(here::here("src", "r", "utils", "provenance.R"))
source(here::here("src", "r", "utils", "spec_discovery.R"))

cat("\n")
cat(strrep("=", 70), "\n")
cat("CREATING FINAL DATASET: ipus_harmonized\n")
cat(strrep("=", 70), "\n\n")

output_dir <- here("outputs", "ipus")
wave_files <- sort(list.files(output_dir,
                               pattern = "^master_w20[0-9]{2}\\.rds$",
                               full.names = TRUE))

if (length(wave_files) == 0) {
  stop("No master files found in outputs/ipus/. Run 2_harmonize_all.R first.")
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

cat("\nAdding country/year identifiers...\n")
for (wave_name in names(wave_list)) {
  yr <- as.integer(gsub("w", "", wave_name))
  wave_list[[wave_name]]$country <- "KOR"
  wave_list[[wave_name]]$year    <- yr
  cat(sprintf("  %s -> country=KOR, year=%d\n", wave_name, yr))
}

cat("\nCombining waves...\n")
ipus_combined <- bind_rows(wave_list)

# wave column: integer year, matching KGSS convention
ipus_combined <- ipus_combined %>% mutate(wave = as.integer(gsub("w", "", wave)))

cat(sprintf("  Combined: %s rows, %d columns\n",
            format(nrow(ipus_combined), big.mark = ","), ncol(ipus_combined)))

ipus_harmonized <- ipus_combined
if ("row_id" %in% names(ipus_harmonized)) {
  ipus_harmonized <- ipus_harmonized %>% select(-row_id)
}

ipus_harmonized <- ipus_harmonized %>%
  mutate(across(where(~ inherits(.x, "haven_labelled")),
                ~ as.numeric(haven::zap_labels(.x))))

cat("\n", strrep("=", 70), "\n", sep = "")
cat("DATASET SUMMARY\n")
cat(strrep("=", 70), "\n\n")

wave_summary <- ipus_harmonized %>% group_by(wave, year) %>%
  summarise(n = n(), .groups = "drop")
print(as.data.frame(wave_summary))

cat(sprintf("\nTotal: %s respondents, %d survey years\n",
            format(nrow(ipus_harmonized), big.mark = ","),
            n_distinct(ipus_harmonized$wave)))

var_names <- setdiff(names(ipus_harmonized), c("wave", "year", "country", "weight"))
cat(sprintf("\n%d harmonized variables:\n", length(var_names)))
cat(paste0("  ", var_names, collapse = "\n"), "\n")

cat("\n", strrep("=", 70), "\n", sep = "")
cat("SAVING\n")
cat(strrep("=", 70), "\n\n")

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)
rds_path     <- here("data", "processed", "ipus_harmonized.rds")
parquet_path <- here("data", "processed", "ipus_harmonized.parquet")

saveRDS(ipus_harmonized, rds_path)
cat(sprintf("  RDS:     %s\n", rds_path))
arrow::write_parquet(ipus_harmonized, parquet_path)
cat(sprintf("  Parquet: %s\n", parquet_path))
saveRDS(ipus_harmonized, here("outputs", "ipus", "ipus_harmonized.rds"))

cat(sprintf("\n✅ ipus_harmonized saved: %s rows, %d columns\n",
            format(nrow(ipus_harmonized), big.mark = ","), ncol(ipus_harmonized)))
cat(strrep("=", 70), "\n\n")

# ==============================================================================
# RUN MANIFEST (audit ticket C2)
# ==============================================================================
# IPUS_YEARS is sourced from 0_load_waves.R; one .sav per year.
manifest_inputs <- vapply(IPUS_YEARS, function(yr) {
  here("data", "ipus", "raw", as.character(yr),
       sprintf("ipus_%d.sav", yr))
}, character(1))

manifest_outputs <- c(
  rds_path,
  parquet_path,
  here("outputs", "ipus", "ipus_harmonized.rds")
)

write_manifest(
  survey      = "ipus",
  inputs      = manifest_inputs,
  specs       = list_survey_specs("ipus"),
  outputs     = manifest_outputs,
  output_path = here("outputs", "ipus", "manifest.json")
)

cat("Manifest written: ", here("outputs", "ipus", "manifest.json"), "\n", sep = "")

# ==============================================================================
# OUTPUT INVARIANTS (audit ticket E2)
# ==============================================================================
source(here("src", "r", "data_prep_modules", "2.5_validate_harmonization.R"))
results <- tryCatch(
  run_validation(survey = "ipus", save_report = TRUE, verbose = FALSE),
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
