#!/usr/bin/env Rscript
# src/scripts/harmonize_democracy_satisfaction.R
# Harmonize democracy satisfaction variables across 6 waves

cat("\n")
cat(paste0("=", strrep("=", 78), "\n"))
cat("DEMOCRACY SATISFACTION HARMONIZATION\n")
cat(paste0("=", strrep("=", 78), "\n\n"))

# ==============================================================================
# LOAD LIBRARIES
# ==============================================================================

library(haven)    # For reading .sav files
library(yaml)     # For reading YAML specs
library(tidyverse) # For data manipulation
library(stringr)  # For string operations

cat("📦 Libraries loaded\n\n")

# ==============================================================================
# LOAD HARMONIZATION SYSTEM
# ==============================================================================

source("src/r/harmonize/harmonize.R")
source("src/r/harmonize/validate_spec.R")
source("src/r/harmonize/report_harmonization.R")
source("src/r/utils/recoding.R")

cat("✅ Harmonization system loaded\n\n")

# ==============================================================================
# LOAD WAVE DATA
# ==============================================================================

cat("📊 Loading wave data...\n")

# Wave 1
cat("  W1: Loading Wave1_20170906.sav... ")
w1 <- read_sav("data/raw/wave1/Wave1_20170906.sav")
cat(sprintf("✓ (%s rows, %s cols)\n", nrow(w1), ncol(w1)))

# Wave 2
cat("  W2: Loading Wave2_20250609.sav... ")
w2 <- read_sav("data/raw/wave2/Wave2_20250609.sav")
cat(sprintf("✓ (%s rows, %s cols)\n", nrow(w2), ncol(w2)))

# Wave 3
cat("  W3: Loading ABS3 merge20250609.sav... ")
w3 <- read_sav("data/raw/wave3/ABS3 merge20250609.sav")
cat(sprintf("✓ (%s rows, %s cols)\n", nrow(w3), ncol(w3)))

# Wave 4
cat("  W4: Loading W4_v15_merged20250609_release.sav... ")
w4 <- read_sav("data/raw/wave4/W4_v15_merged20250609_release.sav")
cat(sprintf("✓ (%s rows, %s cols)\n", nrow(w4), ncol(w4)))

# Wave 5
cat("  W5: Loading 20230505_W5_merge_15.sav... ")
w5 <- read_sav("data/raw/wave5/20230505_W5_merge_15.sav")
cat(sprintf("✓ (%s rows, %s cols)\n", nrow(w5), ncol(w5)))

# Wave 6
cat("  W6: Loading w6_all_countries_merged.rds... ")
w6 <- readRDS("data/processed/w6_all_countries_merged.rds")
cat(sprintf("✓ (%s rows, %s cols)\n\n", nrow(w6), ncol(w6)))

# Create waves list
waves <- list(w1 = w1, w2 = w2, w3 = w3, w4 = w4, w5 = w5, w6 = w6)

# ==============================================================================
# LOAD YAML SPECIFICATION
# ==============================================================================

cat("📋 Loading YAML specification...\n")
spec <- read_yaml("src/config/harmonize/democracy_satisfaction.yml")
cat("✅ YAML specification loaded\n\n")

# ==============================================================================
# VALIDATE SPECIFICATION
# ==============================================================================

cat("🔍 Validating specification...\n")
validation_result <- tryCatch({
  validate_harmonize_spec(spec)
  cat("✅ Specification validation passed\n\n")
  TRUE
}, error = function(e) {
  cat(sprintf("❌ Validation failed: %s\n\n", e$message))
  FALSE
})

if (!validation_result) {
  cat("⚠️  Specification has errors. Please review src/config/harmonize/democracy_satisfaction.yml\n")
  quit(status = 1)
}

# ==============================================================================
# RUN HARMONIZATION
# ==============================================================================

cat("🚀 Running harmonization...\n")
cat("   Processing variables: ")
cat(paste(names(spec$variables), collapse = ", "))
cat("\n\n")

harmonized <- tryCatch({
  harmonize_all(spec, waves = waves, silent = FALSE)
}, error = function(e) {
  cat(sprintf("❌ Harmonization failed: %s\n", e$message))
  NULL
})

if (is.null(harmonized)) {
  cat("\n❌ Harmonization failed. Check errors above.\n")
  quit(status = 1)
}

cat("\n✅ Harmonization complete!\n\n")

# ==============================================================================
# GENERATE REPORTS
# ==============================================================================

cat(paste0("=", strrep("=", 78), "\n"))
cat("HARMONIZATION REPORTS\n")
cat(paste0("=", strrep("=", 78), "\n\n"))

# Report for each variable
for (var_id in names(harmonized)) {
  cat(sprintf("\n### Variable: %s ###\n", var_id))

  var_spec <- spec$variables[[var_id]]
  report <- report_harmonization(harmonized[[var_id]], var_spec = var_spec)
  print(report)

  cat("\n")
}

# ==============================================================================
# SAVE RESULTS
# ==============================================================================

cat(paste0("\n", strrep("=", 78), "\n"))
cat("SAVING RESULTS\n")
cat(paste0(strrep("=", 78), "\n\n"))

# Save harmonized data
output_file <- "data/processed/democracy_satisfaction_harmonized.rds"
saveRDS(harmonized, output_file)
cat(sprintf("✅ Saved: %s\n", output_file))

# Save summary
summary_file <- "outputs/democracy_satisfaction_harmonization_summary.txt"
dir.create(dirname(summary_file), showWarnings = FALSE, recursive = TRUE)

sink(summary_file)
cat("DEMOCRACY SATISFACTION HARMONIZATION SUMMARY\n")
cat(paste0("=", strrep("=", 78), "\n\n"))
cat(sprintf("Date: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat(sprintf("Spec file: src/config/harmonize/democracy_satisfaction.yml\n\n"))

cat("VARIABLES HARMONIZED:\n")
for (var_id in names(harmonized)) {
  cat(sprintf("\n  %s\n", var_id))
  cat(sprintf("    Q1: democracy satisfaction (q098 → q90)\n"))
  cat(sprintf("    Q2: government satisfaction (q104 → q96)\n"))
  cat(sprintf("    Q3: household income satisfaction (se9a → SE14a)\n"))
}

cat("\n\nWAVE DATA SUMMARY:\n")
for (wave_name in names(waves)) {
  df <- waves[[wave_name]]
  cat(sprintf("  %s: %s rows, %s columns\n", wave_name, nrow(df), ncol(df)))
}

cat("\n\nHARMONIZATION RESULTS:\n")
for (var_id in names(harmonized)) {
  var_data <- harmonized[[var_id]]
  cat(sprintf("\n  %s:\n", var_id))
  for (wave_name in names(var_data)) {
    vec <- var_data[[wave_name]]
    n_valid <- sum(!is.na(vec))
    n_missing <- sum(is.na(vec))
    mean_val <- mean(vec, na.rm = TRUE)
    cat(sprintf("    %s: n=%s, valid=%s, missing=%s, mean=%.2f\n",
                wave_name, length(vec), n_valid, n_missing, mean_val))
  }
}

sink()
cat(sprintf("✅ Saved: %s\n", summary_file))

# ==============================================================================
# COMPLETION MESSAGE
# ==============================================================================

cat(paste0("\n", strrep("=", 78), "\n"))
cat("✅ HARMONIZATION COMPLETE!\n")
cat(paste0(strrep("=", 78), "\n\n"))

cat("Results saved to:\n")
cat(sprintf("  • Data: %s\n", output_file))
cat(sprintf("  • Summary: %s\n", summary_file))

cat("\nNext steps:\n")
cat("  1. Review the summary report\n")
cat("  2. Check harmonization results for any warnings\n")
cat("  3. Use harmonized data in analysis\n\n")
