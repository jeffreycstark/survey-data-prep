#!/usr/bin/env Rscript
# src/scripts/harmonize_all_validated.R
# Harmonize all 27 validated YAML specifications across 6 waves
# Generated: 2025-01-11

cat("\n")
cat(paste0(strrep("=", 80), "\n"))
cat("FULL HARMONIZATION: ALL 27 VALIDATED YAML SPECIFICATIONS\n")
cat(paste0(strrep("=", 80), "\n\n"))

# ==============================================================================
# LOAD LIBRARIES
# ==============================================================================

library(haven)     # For reading .sav files
library(yaml)      # For reading YAML specs
library(dplyr)     # For data manipulation
library(tidyr)     # For data reshaping
library(stringr)   # For string operations

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
# HELPER FUNCTION: CONVERT YAML ARRAY TO NAMED LIST
# ==============================================================================

#' Convert YAML variables array to named list
#'
#' Our YAML v2 format uses an array of variables, but harmonize_all()
#' expects a named list keyed by variable id. This function converts.
#'
#' @param spec Parsed YAML spec with variables as array
#' @return Modified spec with variables as named list
convert_variables_to_named <- function(spec) {
  if (is.null(spec$variables)) return(spec)

  # Check if already named (has names attribute)
  if (!is.null(names(spec$variables)) && !all(names(spec$variables) == "")) {
    return(spec)
  }

  # Convert array to named list
  named_vars <- list()
  for (var in spec$variables) {
    if (!is.null(var$id)) {
      named_vars[[var$id]] <- var
    }
  }

  spec$variables <- named_vars
  spec
}

# ==============================================================================
# LOAD WAVE DATA
# ==============================================================================

cat("📊 Loading wave data from processed RDS files...\n")

waves <- list()

# Wave 1
cat("  W1: Loading data/processed/w1.rds... ")
waves$w1 <- readRDS("data/processed/w1.rds")
cat(sprintf("✓ (%s rows, %s cols)\n", nrow(waves$w1), ncol(waves$w1)))

# Wave 2
cat("  W2: Loading data/processed/w2.rds... ")
waves$w2 <- readRDS("data/processed/w2.rds")
cat(sprintf("✓ (%s rows, %s cols)\n", nrow(waves$w2), ncol(waves$w2)))

# Wave 3
cat("  W3: Loading data/processed/w3.rds... ")
waves$w3 <- readRDS("data/processed/w3.rds")
cat(sprintf("✓ (%s rows, %s cols)\n", nrow(waves$w3), ncol(waves$w3)))

# Wave 4
cat("  W4: Loading data/processed/w4.rds... ")
waves$w4 <- readRDS("data/processed/w4.rds")
cat(sprintf("✓ (%s rows, %s cols)\n", nrow(waves$w4), ncol(waves$w4)))

# Wave 5
cat("  W5: Loading data/processed/w5.rds... ")
waves$w5 <- readRDS("data/processed/w5.rds")
cat(sprintf("✓ (%s rows, %s cols)\n", nrow(waves$w5), ncol(waves$w5)))

# Wave 6
cat("  W6: Loading data/processed/w6.rds... ")
waves$w6 <- readRDS("data/processed/w6.rds")
cat(sprintf("✓ (%s rows, %s cols)\n\n", nrow(waves$w6), ncol(waves$w6)))

# ==============================================================================
# LOAD ALL YAML SPECIFICATIONS
# ==============================================================================

cat("📋 Loading YAML specifications from harmonize_validated/...\n")

yaml_dir <- "src/config/harmonize_validated"
yaml_files <- list.files(yaml_dir, pattern = "\\.yml$", full.names = TRUE)

cat(sprintf("   Found %d YAML files\n\n", length(yaml_files)))

# ==============================================================================
# RUN HARMONIZATION FOR EACH SPEC
# ==============================================================================

cat(paste0(strrep("=", 80), "\n"))
cat("RUNNING HARMONIZATION\n")
cat(paste0(strrep("=", 80), "\n\n"))

# Store all harmonized results by wave
all_harmonized <- list(
  w1 = list(),
  w2 = list(),
  w3 = list(),
  w4 = list(),
  w5 = list(),
  w6 = list()
)

# Summary statistics
summary_stats <- list()
total_vars <- 0
total_errors <- 0

for (yml_path in yaml_files) {

  spec_name <- tools::file_path_sans_ext(basename(yml_path))

  cat(sprintf("━━━ %s ━━━\n", toupper(spec_name)))

  # Load and convert spec
  spec <- tryCatch({
    raw_spec <- read_yaml(yml_path)
    convert_variables_to_named(raw_spec)
  }, error = function(e) {
    cat(sprintf("   ❌ Failed to load: %s\n", e$message))
    NULL
  })

  if (is.null(spec)) {
    total_errors <- total_errors + 1
    next
  }

  n_vars <- length(spec$variables)
  cat(sprintf("   Variables: %d\n", n_vars))

  # Run harmonization
  harmonized <- tryCatch({
    harmonize_all(spec, waves = waves, silent = TRUE)
  }, error = function(e) {
    cat(sprintf("   ❌ Harmonization error: %s\n", e$message))
    NULL
  })

  if (is.null(harmonized)) {
    total_errors <- total_errors + 1
    cat(sprintf("   ⚠️  Skipping %s due to errors\n\n", spec_name))
    next
  }

  # Add to wave results
  success_count <- 0
  for (var_id in names(harmonized)) {
    var_result <- harmonized[[var_id]]

    for (wave_name in names(var_result)) {
      vec <- var_result[[wave_name]]

      # Skip if all NA (variable not in this wave)
      if (!all(is.na(vec))) {
        all_harmonized[[wave_name]][[var_id]] <- vec
        success_count <- success_count + 1
      }
    }
  }

  total_vars <- total_vars + n_vars

  summary_stats[[spec_name]] <- list(
    n_vars = n_vars,
    success = success_count
  )

  cat(sprintf("   ✅ Harmonized: %d variable-wave combinations\n\n", success_count))
}

cat(paste0(strrep("=", 80), "\n"))
cat("HARMONIZATION COMPLETE\n")
cat(paste0(strrep("=", 80), "\n\n"))

cat(sprintf("Total YAML specs processed: %d\n", length(yaml_files)))
cat(sprintf("Total variables defined: %d\n", total_vars))
cat(sprintf("Errors encountered: %d\n", total_errors))

# ==============================================================================
# BUILD MASTER DATASETS
# ==============================================================================

cat(paste0("\n", strrep("=", 80), "\n"))
cat("BUILDING MASTER DATASETS\n")
cat(paste0(strrep("=", 80), "\n\n"))

for (wave_name in names(all_harmonized)) {

  wave_vars <- all_harmonized[[wave_name]]
  n_vars <- length(wave_vars)

  if (n_vars == 0) {
    cat(sprintf("%s: No harmonized variables\n", toupper(wave_name)))
    next
  }

  # Get original wave data for ID columns
  original <- waves[[wave_name]]
  n_rows <- nrow(original)

  # Start with ID columns
  master <- data.frame(row.names = 1:n_rows)

  # Add country and idnumber if they exist
  id_cols <- c("country", "COUNTRY", "Country", "idnumber", "IDnumber", "id")
  for (col in id_cols) {
    if (col %in% names(original)) {
      master[[col]] <- original[[col]]
    }
  }

  # Add harmonized variables
  for (var_id in names(wave_vars)) {
    vec <- wave_vars[[var_id]]

    # Ensure vector length matches
    if (length(vec) == n_rows) {
      master[[var_id]] <- vec
    } else {
      cat(sprintf("   ⚠️  %s (%s): Length mismatch (%d vs %d)\n",
                  var_id, wave_name, length(vec), n_rows))
    }
  }

  # Save master dataset
  output_file <- sprintf("outputs/master_%s.rds", wave_name)
  saveRDS(master, output_file)

  cat(sprintf("%s: %d variables → %s\n",
              toupper(wave_name), ncol(master) - length(id_cols), output_file))
}

# ==============================================================================
# GENERATE SUMMARY REPORT
# ==============================================================================

cat(paste0("\n", strrep("=", 80), "\n"))
cat("SUMMARY REPORT\n")
cat(paste0(strrep("=", 80), "\n\n"))

# Variables per wave
cat("HARMONIZED VARIABLES PER WAVE:\n")
for (wave_name in names(all_harmonized)) {
  n <- length(all_harmonized[[wave_name]])
  cat(sprintf("  %s: %d variables\n", toupper(wave_name), n))
}

# Variables per concept
cat("\nVARIABLES PER CONCEPT:\n")
for (spec_name in names(summary_stats)) {
  stats <- summary_stats[[spec_name]]
  cat(sprintf("  %-30s: %3d variables\n", spec_name, stats$n_vars))
}

# Save summary
summary_file <- "outputs/HARMONIZATION_RUN_SUMMARY.md"
sink(summary_file)

cat("# Harmonization Run Summary\n\n")
cat(sprintf("**Date:** %s\n\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat(sprintf("**YAML Specs:** %d\n", length(yaml_files)))
cat(sprintf("**Total Variables:** %d\n\n", total_vars))

cat("## Variables per Wave\n\n")
cat("| Wave | Variables |\n")
cat("|------|----------|\n")
for (wave_name in names(all_harmonized)) {
  n <- length(all_harmonized[[wave_name]])
  cat(sprintf("| %s | %d |\n", toupper(wave_name), n))
}

cat("\n## Variables per Concept\n\n")
cat("| Concept | Variables |\n")
cat("|---------|----------|\n")
for (spec_name in names(summary_stats)) {
  stats <- summary_stats[[spec_name]]
  cat(sprintf("| %s | %d |\n", spec_name, stats$n_vars))
}

cat("\n## Output Files\n\n")
for (wave_name in names(all_harmonized)) {
  n <- length(all_harmonized[[wave_name]])
  if (n > 0) {
    cat(sprintf("- `outputs/master_%s.rds` - %d harmonized variables\n", wave_name, n))
  }
}

sink()

cat(sprintf("\n✅ Summary saved to: %s\n", summary_file))

# ==============================================================================
# COMPLETION
# ==============================================================================

cat(paste0("\n", strrep("=", 80), "\n"))
cat("✅ HARMONIZATION PIPELINE COMPLETE!\n")
cat(paste0(strrep("=", 80), "\n\n"))

cat("Output files:\n")
for (wave_name in names(all_harmonized)) {
  if (length(all_harmonized[[wave_name]]) > 0) {
    cat(sprintf("  • outputs/master_%s.rds\n", wave_name))
  }
}
cat(sprintf("  • %s\n\n", summary_file))
