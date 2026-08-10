# LBS: Harmonize all variables from YAML specs
#
# Sources the shared harmonization engine, then processes
# all LBS YAML specs from src/config/lbs/harmonize/

library(here)
library(yaml)
library(dplyr)

# Load shared pipeline functions (also loads harmonize engine + recoding functions)
source(here::here("src/r/data_prep_modules/2_harmonize_all.R"))

# Load LBS wave loader
source(here::here("src/r/data_prep_modules/lbs/0_load_waves.R"))

run_lbs_harmonization <- function(output_format = "wide", silent = FALSE) {
  run_survey_harmonization("lbs", load_lbs_waves, output_format, silent)
}

# ==============================================================================
# RUN IF EXECUTED DIRECTLY
# ==============================================================================

if (sys.nframe() == 0) {
  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("LBS HARMONIZATION PIPELINE\n")
  cat(strrep("=", 70), "\n\n")

  # Load waves
  waves <- load_lbs_waves()

  # Get specs
  specs <- list_survey_specs("lbs")
  cat(sprintf("\nFound %d YAML specs: %s\n\n",
              length(specs),
              paste(basename(specs), collapse = ", ")))

  # E1: always-on out-of-range logging
  oob_log_path <- here::here("outputs", "lbs", "oob_log.csv")
  dir.create(dirname(oob_log_path), showWarnings = FALSE, recursive = TRUE)

  # Run harmonization
  results <- harmonize_all_specs(waves, specs = specs,
                                 oob_log_path = oob_log_path)

  # Stack into wide format
  harmonized_wide <- stack_harmonized_wide(results, waves, survey = "lbs")

  # Save per-wave master files
  cat("\n", strrep("=", 70), "\n", sep = "")
  cat("SAVING MASTER FILES\n")
  cat(strrep("=", 70), "\n\n")

  output_dir <- here::here("outputs", "lbs")
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  for (wave_name in names(harmonized_wide)) {
    df <- harmonized_wide[[wave_name]]
    output_file <- file.path(output_dir, paste0("master_", wave_name, ".rds"))
    saveRDS(df, output_file)
    n_vars <- ncol(df) - 2  # subtract wave + row_uid
    cat(sprintf("  Saved %s: %s rows, %d harmonized variables\n",
                basename(output_file),
                format(nrow(df), big.mark = ","),
                n_vars))
  }

  cat("\n✅ LBS harmonization complete\n")
}
