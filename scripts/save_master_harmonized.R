#!/usr/bin/env Rscript
#' Save Master Harmonized Datasets
#'
#' Runs harmonization on all YAML specs and saves master datasets per wave

library(here)
library(yaml)
library(dplyr)

cat("\n=== HARMONIZATION AND MASTER DATASET GENERATION ===\n\n")

# Load functions
source(here("src/r/harmonize/_load_harmonize.R"))
source(here("src/r/utils/_load_functions.R"))
source(here("src/r/data_prep_modules/0_load_waves.R"))

# Load waves
waves <- load_waves()

# List all YAML specs (excluding MODEL_VARIABLE)
config_dir <- here("src/config/harmonize_validated")
spec_files <- list.files(config_dir, pattern = "\\.yml$", full.names = TRUE)
spec_files <- spec_files[!grepl("MODEL_VARIABLE", spec_files)]

cat("Found", length(spec_files), "YAML specifications\n\n")

# Build master datasets by wave
master <- list(w1 = list(), w2 = list(), w3 = list(), w4 = list(), w5 = list(), w6 = list())

var_count <- 0
failed_vars <- character()

for (spec_path in spec_files) {
  spec_name <- tools::file_path_sans_ext(basename(spec_path))
  cat("Processing:", spec_name, "...")

  tryCatch({
    spec <- yaml::read_yaml(spec_path)
    missing_conventions <- spec$missing_conventions
    spec_vars <- 0

    for (var_spec in spec$variables) {
      var_id <- var_spec$id

      tryCatch({
        harmonized <- harmonize_variable(
          var_spec = var_spec,
          waves = waves,
          missing_conventions = missing_conventions
        )

        # Add to each wave
        for (wave_name in names(harmonized)) {
          master[[wave_name]][[var_id]] <- harmonized[[wave_name]]
        }
        spec_vars <- spec_vars + 1
        var_count <- var_count + 1

      }, error = function(e) {
        cat("   ERROR in", var_id, ":", e$message, "\n")
        failed_vars <<- c(failed_vars, var_id)
      })
    }
    cat(" ", spec_vars, "vars\n")

  }, error = function(e) {
    cat(" ERROR:", e$message, "\n")
  })
}

cat("\n=== SAVING MASTER DATASETS ===\n\n")

# Convert to data frames and save
output_dir <- here("outputs")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

for (wave_name in names(master)) {
  wave_data <- master[[wave_name]]
  if (length(wave_data) > 0) {
    # Get base row count
    n_rows <- nrow(waves[[wave_name]])

    # Build data frame
    wave_df <- data.frame(
      wave = rep(wave_name, n_rows),
      row_id = seq_len(n_rows)
    )

    for (var_id in names(wave_data)) {
      vals <- wave_data[[var_id]]
      if (length(vals) == n_rows) {
        wave_df[[var_id]] <- vals
      }
    }

    # Save
    output_file <- file.path(output_dir, paste0("master_", wave_name, ".rds"))
    saveRDS(wave_df, output_file)
    cat("Saved master_", wave_name, ".rds: ",
        format(nrow(wave_df), big.mark = ","), " rows, ",
        ncol(wave_df) - 2, " variables\n", sep = "")
  }
}

# Summary
cat("\n", paste(rep("=", 60), collapse = ""), "\n", sep = "")
cat("HARMONIZATION COMPLETE\n")
cat(paste(rep("=", 60), collapse = ""), "\n\n", sep = "")

cat("Summary:\n")
cat("  Specs processed:", length(spec_files), "\n")
cat("  Variables harmonized:", var_count, "\n")
if (length(failed_vars) > 0) {
  cat("  Variables failed:", length(failed_vars), "\n")
  cat("  Failed:", paste(head(failed_vars, 10), collapse = ", "),
      ifelse(length(failed_vars) > 10, "...", ""), "\n")
}
cat("\nOutput files saved to: outputs/\n")
cat(paste(rep("=", 60), collapse = ""), "\n\n", sep = "")
