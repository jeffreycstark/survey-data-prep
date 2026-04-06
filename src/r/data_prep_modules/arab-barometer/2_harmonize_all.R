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

run_arab_barometer_harmonization <- function(output_format = "wide", silent = FALSE) {
  run_survey_harmonization("arab-barometer", load_arab_barometer_waves, output_format, silent)
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
  specs <- list_survey_specs("arab-barometer")
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
