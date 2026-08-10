# IPUS: Harmonize all variables from YAML specs
#
# Sources the shared harmonization engine, then processes
# all IPUS YAML specs from src/config/ipus/harmonize/

library(here)
library(yaml)
library(dplyr)

source(here::here("src/r/data_prep_modules/2_harmonize_all.R"))
source(here::here("src/r/data_prep_modules/ipus/0_load_waves.R"))

run_ipus_harmonization <- function(output_format = "wide", silent = FALSE) {
  run_survey_harmonization("ipus", load_ipus_waves, output_format, silent)
}

if (sys.nframe() == 0) {
  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("IPUS HARMONIZATION PIPELINE\n")
  cat(strrep("=", 70), "\n\n")

  waves <- load_ipus_waves()

  specs <- list_survey_specs("ipus")
  cat(sprintf("\nFound %d YAML specs: %s\n\n",
              length(specs),
              paste(basename(specs), collapse = ", ")))

  if (length(specs) == 0) {
    cat("No YAML specs in src/config/ipus/harmonize/. Add specs and rerun.\n")
    quit(save = "no")
  }

  # E1: always-on out-of-range logging
  oob_log_path <- here::here("outputs", "ipus", "oob_log.csv")
  dir.create(dirname(oob_log_path), showWarnings = FALSE, recursive = TRUE)

  results <- harmonize_all_specs(waves, specs = specs,
                                 oob_log_path = oob_log_path)
  harmonized_wide <- stack_harmonized_wide(results, waves, survey = "ipus")

  cat("\n", strrep("=", 70), "\n", sep = "")
  cat("SAVING MASTER FILES\n")
  cat(strrep("=", 70), "\n\n")

  output_dir <- here::here("outputs", "ipus")
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  for (wave_name in names(harmonized_wide)) {
    df <- harmonized_wide[[wave_name]]
    output_file <- file.path(output_dir, paste0("master_", wave_name, ".rds"))
    saveRDS(df, output_file)
    cat(sprintf("  Saved %s: %s rows, %d harmonized variables\n",
                basename(output_file),
                format(nrow(df), big.mark = ","),
                ncol(df) - 2))
  }

  cat("\n✅ IPUS harmonization complete\n")
}
