# CFPS: Harmonize all variables from YAML specs
#
# Sources the shared harmonization engine, then processes
# all CFPS YAML specs from src/config/cfps/harmonize/

library(here)
library(yaml)
library(dplyr)

# Load shared pipeline functions (harmonize engine + recoding functions)
source(here::here("src/r/data_prep_modules/2_harmonize_all.R"))

# Load CFPS wave loader
source(here::here("src/r/data_prep_modules/cfps/0_load_waves.R"))

run_cfps_harmonization <- function(output_format = "wide", silent = FALSE) {
  run_survey_harmonization("cfps", load_cfps_waves, output_format, silent)
}

# ==============================================================================
# RUN IF EXECUTED DIRECTLY
# ==============================================================================

if (sys.nframe() == 0) {
  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("CFPS HARMONIZATION PIPELINE\n")
  cat(strrep("=", 70), "\n\n")

  waves <- load_cfps_waves()

  specs <- list_survey_specs("cfps")
  cat(sprintf("\nFound %d YAML specs: %s\n\n",
              length(specs),
              paste(basename(specs), collapse = ", ")))

  # E1: always-on out-of-range logging
  oob_log_path <- here::here("outputs", "cfps", "oob_log.csv")
  dir.create(dirname(oob_log_path), showWarnings = FALSE, recursive = TRUE)

  results <- harmonize_all_specs(waves, specs = specs,
                                 oob_log_path = oob_log_path)

  harmonized_wide <- stack_harmonized_wide(results, waves, survey = "cfps")

  cat("\n", strrep("=", 70), "\n", sep = "")
  cat("SAVING MASTER FILES\n")
  cat(strrep("=", 70), "\n\n")

  output_dir <- here::here("outputs", "cfps")
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  for (wave_name in names(harmonized_wide)) {
    df <- harmonized_wide[[wave_name]]
    output_file <- file.path(output_dir, paste0("master_", wave_name, ".rds"))
    saveRDS(df, output_file)
    n_vars <- ncol(df) - 2
    cat(sprintf("  Saved %s: %s rows, %d harmonized variables\n",
                basename(output_file),
                format(nrow(df), big.mark = ","),
                n_vars))
  }

  cat("\n✅ CFPS harmonization complete\n")
}
