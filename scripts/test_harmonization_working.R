#!/usr/bin/env Rscript
#' Working Harmonization Test with Data Conversion
#' 
#' Tests harmonization with proper haven_labelled conversion

library(yaml)
library(dplyr)
library(here)
library(haven)

cat("\n=== SETUP ===\n")

source(here("src/r/harmonize/_load_harmonize.R"))
source(here("src/r/utils/_load_functions.R"))

# Convert haven_labelled to numeric
convert_haven_to_numeric <- function(df) {
  for (col in names(df)) {
    if (inherits(df[[col]], 'haven_labelled')) {
      df[[col]] <- as.numeric(df[[col]])
    }
  }
  return(df)
}

cat("Loading and converting data waves...\n")
waves <- list(
  w1 = convert_haven_to_numeric(readRDS(here("data/processed/w1.rds"))),
  w2 = convert_haven_to_numeric(readRDS(here("data/processed/w2.rds"))),
  w3 = convert_haven_to_numeric(readRDS(here("data/processed/w3.rds"))),
  w4 = convert_haven_to_numeric(readRDS(here("data/processed/w4.rds"))),
  w5 = convert_haven_to_numeric(readRDS(here("data/processed/w5.rds"))),
  w6 = convert_haven_to_numeric(readRDS(here("data/processed/w6.rds")))
)

cat("✓ Loaded and converted 6 waves of data\n")
cat("  Sizes: w1=", nrow(waves$w1), ", w2=", nrow(waves$w2), ", w3=", nrow(waves$w3),
    ", w4=", nrow(waves$w4), ", w5=", nrow(waves$w5), ", w6=", nrow(waves$w6), "\n", sep="")

# ============================================================================
# LOAD SPECS AND HARMONIZE
# ============================================================================

cat("\n=== HARMONIZATION TESTING ===\n")

spec_files <- c(
  "authoritarianism_democracy_scale",
  "community_leader_contact",
  "democracy_satisfaction",
  "economy",
  "government_leader_accountability",
  "hierarchical_obedience",
  "institutional_trust",
  "local_government_corruption",
  "national_government_corruption",
  "strong_leader_preference",
  "upright_leader_discretion"
)

results_summary <- list()
output_dir <- here("outputs")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

for (spec_file in spec_files) {
  start_time <- Sys.time()
  
  cat("\nProcessing:", spec_file, "\n")
  
  tryCatch({
    # Load spec
    spec_path <- here("src/config/harmonize", paste0(spec_file, ".yml"))
    spec <- read_yaml(spec_path)
    
    # Harmonize
    harmonized <- harmonize_all(spec, waves)
    
    duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    
    # Check results
    num_vars <- length(harmonized)
    if (num_vars == 0) {
      cat("  ⚠ Warning: Empty harmonization result\n")
      status <- "EMPTY"
    } else {
      # Count total rows across all variables
      total_rows <- 0
      for (var_name in names(harmonized)) {
        for (wave_name in names(harmonized[[var_name]])) {
          rows <- length(harmonized[[var_name]][[wave_name]])
          total_rows <- total_rows + rows
        }
      }
      cat("  ✓ Harmonized", num_vars, "variables with", total_rows, "total values\n")
      
      # Save results
      output_file <- file.path(output_dir, paste0(spec_file, "_harmonized_working.rds"))
      saveRDS(harmonized, output_file)
      cat("  ✓ Saved to:", basename(output_file), "\n")
      
      status <- "SUCCESS"
    }
    
    results_summary[[spec_file]] <- list(
      status = status,
      num_variables = num_vars,
      duration = duration
    )
    
  }, error = function(e) {
    cat("  ✗ Error:", e$message, "\n")
    results_summary[[spec_file]] <<- list(
      status = "ERROR",
      error = e$message,
      duration = as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    )
  })
}

# ============================================================================
# SUMMARY
# ============================================================================

cat("\n=== SUMMARY ===\n")

successful <- sum(sapply(results_summary, function(x) x$status == "SUCCESS"))
empty <- sum(sapply(results_summary, function(x) x$status == "EMPTY"))
errors <- sum(sapply(results_summary, function(x) x$status == "ERROR"))

cat("Total concepts:      ", length(results_summary), "\n")
cat("Successful:          ", successful, "\n")
cat("Empty results:       ", empty, "\n")
cat("Errors:              ", errors, "\n")
cat("Total execution:     ", round(sum(sapply(results_summary, function(x) x$duration)), 2), " sec\n")

# ============================================================================
# DATA CHECK
# ============================================================================

cat("\n=== DATA VERIFICATION ===\n")

# Load one harmonized dataset and verify
test_file <- file.path(output_dir, "economy_harmonized_working.rds")
if (file.exists(test_file)) {
  test_data <- readRDS(test_file)
  cat("\nSample: economy harmonization\n")
  cat("  Variables:", length(test_data), "\n")
  
  for (var_id in names(test_data)) {
    cat("  -", var_id, "\n")
    for (wave_name in names(test_data[[var_id]])) {
      vals <- test_data[[var_id]][[wave_name]]
      cat("    ", wave_name, ": n=", length(vals), 
          ", mean=", round(mean(vals, na.rm=T), 2),
          ", min=", min(vals, na.rm=T),
          ", max=", max(vals, na.rm=T), "\n", sep="")
    }
  }
}

cat("\n", paste(rep("=", 70), collapse=""), "\n", sep="")
