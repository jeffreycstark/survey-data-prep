# GCB: Harmonize all variables from YAML specs
#
# Sources the shared harmonization engine, then processes all GCB YAML specs
# from src/config/gcb/harmonize/. One master_<edition>.rds per regional edition.

library(here)
library(yaml)
library(dplyr)

source(here::here("src/r/data_prep_modules/2_harmonize_all.R"))   # shared engine
source(here::here("src/r/data_prep_modules/gcb/0_load_waves.R"))  # edition loader

run_gcb_harmonization <- function(output_format = "wide", silent = FALSE) {
  run_survey_harmonization("gcb", load_gcb_waves, output_format, silent)
}

# ==============================================================================
# RUN IF EXECUTED DIRECTLY
# ==============================================================================

if (sys.nframe() == 0) {
  cat("\n", strrep("=", 70), "\n", sep = "")
  cat("GCB HARMONIZATION PIPELINE\n")
  cat(strrep("=", 70), "\n\n")

  waves <- load_gcb_waves()

  specs <- list_survey_specs("gcb")
  cat(sprintf("\nFound %d YAML specs: %s\n\n",
              length(specs), paste(basename(specs), collapse = ", ")))
  if (length(specs) == 0) {
    cat("No YAML specs in src/config/gcb/harmonize/. Add specs and rerun.\n")
    quit(save = "no")
  }

  oob_log_path <- here::here("outputs", "gcb", "oob_log.csv")
  dir.create(dirname(oob_log_path), showWarnings = FALSE, recursive = TRUE)

  results <- harmonize_all_specs(waves, specs = specs, oob_log_path = oob_log_path)
  harmonized_wide <- stack_harmonized_wide(results, waves)

  cat("\n", strrep("=", 70), "\n", sep = "")
  cat("SAVING MASTER FILES\n")
  cat(strrep("=", 70), "\n\n")

  output_dir <- here::here("outputs", "gcb")
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  for (wave_name in names(harmonized_wide)) {
    df <- harmonized_wide[[wave_name]]
    output_file <- file.path(output_dir, paste0("master_", wave_name, ".rds"))
    saveRDS(df, output_file)
    cat(sprintf("  Saved %s: %s rows, %d harmonized variables\n",
                basename(output_file), format(nrow(df), big.mark = ","),
                ncol(df) - 2))  # -2 for wave, row_id
  }

  cat("\n✅ GCB harmonization complete\n")
}
