# Arab Barometer: Harmonize all variables from YAML specs
#
# Sources the shared harmonization engine, then processes
# all Arab Barometer YAML specs from src/config/arab-barometer/harmonize/

library(here)
library(yaml)
library(dplyr)

# Load shared pipeline functions (also loads harmonize engine + recoding functions)
source(here::here("src/r/data_prep_modules/2_harmonize_all.R"))

# Load Arab Barometer wave loader
source(here::here("src/r/data_prep_modules/arab-barometer/0_load_waves.R"))

# ==============================================================================
# ARAB BAROMETER-SPECIFIC FUNCTIONS
# ==============================================================================

#' List Arab Barometer YAML spec files
#'
#' @return Character vector of YAML file paths
list_arab_barometer_specs <- function() {
  config_dir <- here::here("src", "config", "arab-barometer", "harmonize")
  files <- list.files(config_dir, pattern = "\\.yml$", full.names = TRUE)

  # Exclude template/doc files
  exclude_patterns <- c("MODEL_VARIABLE", "TEMPLATE", "README")
  files <- files[!grepl(paste(exclude_patterns, collapse = "|"), files, ignore.case = TRUE)]

  files
}


#' Run Arab Barometer harmonization pipeline
#'
#' Loads waves, harmonizes all specs, returns wide format.
#'
#' @param output_format "wide" (list of wave dfs) or "long" (single stacked df)
#' @param silent Suppress messages
#' @return Harmonized data
run_arab_barometer_harmonization <- function(output_format = "wide", silent = FALSE) {

  # Load waves
  waves <- load_arab_barometer_waves()

  # Get spec files
  specs <- list_arab_barometer_specs()

  # Harmonize all specs (uses shared harmonize_spec from ABS module)
  results <- harmonize_all_specs(waves, specs = specs, silent = silent)

  # Format output
  if (output_format == "wide") {
    stack_harmonized_wide(results, waves)
  } else {
    stack_harmonized(results, waves)
  }
}

# ==============================================================================
# RUN IF EXECUTED DIRECTLY
# ==============================================================================

if (sys.nframe() == 0) {
  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("ARAB BAROMETER HARMONIZATION PIPELINE\n")
  cat(strrep("=", 70), "\n\n")

  # Load waves
  waves <- load_arab_barometer_waves()

  # Get specs
  specs <- list_arab_barometer_specs()
  cat(sprintf("\nFound %d YAML specs: %s\n\n",
              length(specs),
              paste(basename(specs), collapse = ", ")))

  # Run harmonization
  results <- harmonize_all_specs(waves, specs = specs)

  # Stack into wide format
  harmonized_wide <- stack_harmonized_wide(results, waves)

  # Save per-wave master files
  cat("\n", strrep("=", 70), "\n", sep = "")
  cat("SAVING MASTER FILES\n")
  cat(strrep("=", 70), "\n\n")

  output_dir <- here::here("outputs", "arab-barometer")
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  for (wave_name in names(harmonized_wide)) {
    df <- harmonized_wide[[wave_name]]
    output_file <- file.path(output_dir, paste0("master_", wave_name, ".rds"))
    saveRDS(df, output_file)
    n_vars <- ncol(df) - 2  # subtract wave + row_id
    cat(sprintf("  Saved %s: %s rows, %d harmonized variables\n",
                basename(output_file),
                format(nrow(df), big.mark = ","),
                n_vars))
  }

  cat("\nArab Barometer harmonization complete\n")
}
