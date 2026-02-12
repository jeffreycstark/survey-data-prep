#!/usr/bin/env Rscript
#
# Build script for R data processing pipeline
# Runs all data processing steps in sequence
#

# Setup -------------------------------------------------------------------

# Set working directory to project root
if (interactive()) {
  setwd(here::here())
} else {
  # When run as script, get directory from command line
  initial.options <- commandArgs(trailingOnly = FALSE)
  file.arg.name <- "--file="
  script.name <- sub(file.arg.name, "", 
                     initial.options[grep(file.arg.name, initial.options)])
  script.dir <- dirname(normalizePath(script.name))
  setwd(file.path(script.dir, ".."))
}

message("="  %>% rep(60) %>% paste(collapse = ""))
message("R Data Processing Pipeline")
message("Working directory: ", getwd())
message("=" %>% rep(60) %>% paste(collapse = ""))

# Load required packages
suppressPackageStartupMessages({
  library(tidyverse)
  library(here)
})

# Helper Functions --------------------------------------------------------

run_step <- function(script_path, description) {
  message("\n", "=" %>% rep(60) %>% paste(collapse = ""))
  message("Running: ", description)
  message("Script: ", script_path)
  message("=" %>% rep(60) %>% paste(collapse = ""))
  
  if (!file.exists(script_path)) {
    message("⚠ Skipping - script not found: ", script_path)
    return(invisible(NULL))
  }
  
  tryCatch({
    source(script_path)
    message("✓ ", description, " completed successfully")
  }, error = function(e) {
    message("✗ Error in ", description)
    message("Error: ", e$message)
    quit(status = 1)
  })
}

# Processing Steps --------------------------------------------------------

# Define processing pipeline
steps <- tribble(
  ~script, ~description,
  # "src/r/ingest/load_raw_data.R", "Load raw data",
  # "src/r/validation/validate_data.R", "Validate data",
  # "src/r/models/fit_models.R", "Fit statistical models",
)

# Run each step
if (nrow(steps) > 0) {
  walk2(steps$script, steps$description, run_step)
} else {
  message("\n⚠ No processing steps defined yet")
  message("Add steps to the 'steps' tibble in scripts/build.R")
}

# Completion --------------------------------------------------------------

message("\n", "=" %>% rep(60) %>% paste(collapse = ""))
message("Build pipeline completed successfully!")
message("=" %>% rep(60) %>% paste(collapse = ""))
