# KINU: Harmonize all variables from YAML specs
#
# Sources the shared harmonization engine, then processes
# all KINU YAML specs from src/config/kinu/harmonize/

library(here)
library(yaml)
library(dplyr)

# Load shared pipeline functions (harmonize engine + recoding functions)
source(here::here("src/r/data_prep_modules/2_harmonize_all.R"))

# Load KINU wave loader
source(here::here("src/r/data_prep_modules/kinu/0_load_waves.R"))

run_kinu_harmonization <- function(output_format = "wide", silent = FALSE) {
  run_survey_harmonization("kinu", load_kinu_waves, output_format, silent)
}

# ==============================================================================
# RUN IF EXECUTED DIRECTLY
# ==============================================================================

if (sys.nframe() == 0) {
  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("KINU HARMONIZATION PIPELINE\n")
  cat(strrep("=", 70), "\n\n")

  waves <- load_kinu_waves()

  specs <- list_survey_specs("kinu")
  cat(sprintf("\nFound %d YAML specs: %s\n\n",
              length(specs),
              paste(basename(specs), collapse = ", ")))

  if (length(specs) == 0) {
    cat("No YAML specs in src/config/kinu/harmonize/. Add specs and rerun.\n")
    quit(save = "no")
  }

  results <- harmonize_all_specs(waves, specs = specs)

  harmonized_wide <- stack_harmonized_wide(results, waves)

  cat("\n", strrep("=", 70), "\n", sep = "")
  cat("SAVING MASTER FILES\n")
  cat(strrep("=", 70), "\n\n")

  output_dir <- here::here("outputs", "kinu")
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

  cat("\n✅ KINU harmonization complete\n")
}
