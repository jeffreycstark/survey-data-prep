# 99_create_final_dataset.R
# Final step: Combine harmonized waves and create abs_econdev_authpref.rds
#
# This script:
# 1. Loads the master harmonized datasets from outputs/
# 2. Row-binds all waves into a single dataset
# 3. Applies known data corrections
# 4. Zaps haven labels for clean R usage
# 5. Saves as abs_econdev_authpref.rds

library(here)
library(dplyr)
library(haven)

source(here::here("src", "r", "utils", "provenance.R"))
source(here::here("src", "r", "utils", "spec_discovery.R"))

cat("\n=== CREATING FINAL DATASET: abs_harmonized.rds ===\n\n")

# Load all master wave files
output_dir <- here("outputs")
wave_files <- sort(list.files(output_dir, pattern = "^master_w[1-6]\\.rds$", full.names = TRUE))

cat("Loading master wave files...\n")
wave_list <- lapply(wave_files, function(f) {
  wave_name <- gsub("master_|\\.rds", "", basename(f))
  wave_num <- as.integer(gsub("w", "", wave_name))
  cat("  Loading", basename(f), "...")
  df <- readRDS(f)
  # Add wave column
  df$wave <- wave_num
  cat(format(nrow(df), big.mark = ","), "rows\n")
  df
})

# Combine all waves
cat("\nCombining waves...\n")
abs_combined <- bind_rows(wave_list)
cat("  Combined dataset:", format(nrow(abs_combined), big.mark = ","), "rows,",
    ncol(abs_combined), "columns\n")

cat("\nApplying known data corrections...\n")
cat("  None (all corrections handled during harmonization)\n")

# Zap haven labels (convert labelled vectors to regular R vectors)
cat("\nZapping haven labels...\n")
abs_econdev_authpref <- abs_combined %>%
  mutate(across(where(haven::is.labelled), haven::zap_labels))

# Also zap any remaining label attributes
abs_econdev_authpref <- abs_econdev_authpref %>%
  mutate(across(everything(), ~{
    attr(.x, "label") <- NULL
    attr(.x, "format.spss") <- NULL
    attr(.x, "display_width") <- NULL
    .x
  }))

cat("  Labels zapped successfully\n")

# Add ISO 3166 alpha-3 country codes
abs_econdev_authpref <- abs_econdev_authpref %>%
  mutate(country_iso = case_when(
    country ==  1 ~ "JPN",
    country ==  2 ~ "HKG",
    country ==  3 ~ "KOR",
    country ==  4 ~ "CHN",
    country ==  5 ~ "MNG",
    country ==  6 ~ "PHL",
    country ==  7 ~ "TWN",
    country ==  8 ~ "THA",
    country ==  9 ~ "IDN",
    country == 10 ~ "SGP",
    country == 11 ~ "VNM",
    country == 12 ~ "KHM",
    country == 13 ~ "MYS",
    country == 14 ~ "MMR",
    country == 15 ~ "AUS",
    country == 18 ~ "IND",
    TRUE ~ NA_character_
  ))
cat("  Added country_iso (ISO 3166 alpha-3)\n")

# Rescale education to 0-1 (ABS raw: 1-10)
if ("education_level" %in% names(abs_econdev_authpref)) {
  abs_econdev_authpref <- abs_econdev_authpref %>%
    mutate(education_level_01 = (education_level - 1) / 9)
}

# 5-category education (ABS 1-10 → 1-5)
# 1=No formal(1), 2=Primary(2-3), 3=Secondary(4-7), 4=Post-sec/some uni(8), 5=Uni+postgrad(9-10)
if ("education_level" %in% names(abs_econdev_authpref)) {
  abs_econdev_authpref <- abs_econdev_authpref %>%
    mutate(education_5cat = case_when(
      education_level == 1             ~ 1L,
      education_level %in% 2:3        ~ 2L,
      education_level %in% 4:7        ~ 3L,
      education_level == 8            ~ 4L,
      education_level %in% 9:10       ~ 5L,
      TRUE                            ~ NA_integer_
    ))
}

# Summary by wave
cat("\n=== WAVE SUMMARY ===\n")
wave_summary <- abs_econdev_authpref %>%
  group_by(wave) %>%
  summarise(n = n(), .groups = "drop")
print(wave_summary)

# Save final dataset
output_file <- here("data", "processed", "abs_harmonized.rds")
saveRDS(abs_econdev_authpref, output_file)

cat("\n=== FINAL DATASET SAVED ===\n")
cat("File:", output_file, "\n")
cat("Rows:", format(nrow(abs_econdev_authpref), big.mark = ","), "\n")
cat("Columns:", ncol(abs_econdev_authpref), "\n")
cat("Waves:", paste(unique(abs_econdev_authpref$wave), collapse = ", "), "\n")

# List variables
cat("\nVariables:\n")
var_names <- setdiff(names(abs_econdev_authpref), c("wave", "row_id"))
cat(paste(" ", var_names, collapse = "\n"), "\n")

cat("\n", paste(rep("=", 60), collapse = ""), "\n", sep = "")
cat("DONE: abs_harmonized.rds ready for analysis\n")
cat(paste(rep("=", 60), collapse = ""), "\n\n", sep = "")

# ==============================================================================
# RUN MANIFEST (audit ticket C2)
# ==============================================================================
# Records sha256 of every input wave RDS, every YAML spec consumed, and the
# harmonized output, plus engine-file hashes and git state. Re-running with
# no upstream changes produces identical hashes; only run_id/timestamp drift.

manifest_inputs  <- here("data", "processed",
                         sprintf("w%d.rds", 1:6))
manifest_outputs <- c(output_file)

write_manifest(
  survey      = "abs",
  inputs      = manifest_inputs,
  specs       = list_survey_specs("abs"),
  outputs     = manifest_outputs,
  output_path = here("outputs", "abs", "manifest.json")
)

cat("Manifest written: ", here("outputs", "abs", "manifest.json"), "\n", sep = "")

# ==============================================================================
# OUTPUT INVARIANTS (audit ticket E2)
# ==============================================================================
# Run the post-hoc validator on the freshly-built harmonized output. Produces
# outputs/abs/03-invariants.md (human-readable) and audit/reports/abs/
# 03-invariants.csv (one row per variable × wave × check). Non-blocking — the
# pipeline completes whatever the validator finds; investigate the report.
source(here("src", "r", "data_prep_modules", "2.5_validate_harmonization.R"))
results <- tryCatch(
  run_validation(survey = "abs", save_report = TRUE, verbose = FALSE),
  error = function(e) {
    message("validation step failed: ", e$message)
    NULL
  }
)
if (!is.null(results)) {
  cat(sprintf(
    "Invariants: ok=%d warn=%d error=%d skip=%d (total=%d)\n",
    results$counts$ok, results$counts$warn,
    results$counts$error, results$counts$skip,
    nrow(results$summary)
  ))
}
