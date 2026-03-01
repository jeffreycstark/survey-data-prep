# KGSS: Harmonize all variables from YAML specs
#
# Sources the shared harmonization engine, then processes
# all KGSS YAML specs from src/config/kgss/harmonize/

library(here)
library(yaml)
library(dplyr)

# Load shared pipeline functions (harmonize engine + recoding functions)
source(here::here("src/r/data_prep_modules/2_harmonize_all.R"))

# Load KGSS wave loader
source(here::here("src/r/data_prep_modules/kgss/0_load_waves.R"))

# ==============================================================================
# KGSS-SPECIFIC FUNCTIONS
# ==============================================================================

#' List KGSS YAML spec files
list_kgss_specs <- function() {
  config_dir <- here::here("src", "config", "kgss", "harmonize")
  files <- list.files(config_dir, pattern = "\\.yml$", full.names = TRUE)
  exclude_patterns <- c("MODEL_VARIABLE", "TEMPLATE", "README")
  files[!grepl(paste(exclude_patterns, collapse = "|"), files, ignore.case = TRUE)]
}

#' Run KGSS harmonization pipeline
#'
#' @param output_format "wide" (list of wave dfs) or "long" (single stacked df)
#' @param silent Suppress messages
#' @return Harmonized data
run_kgss_harmonization <- function(output_format = "wide", silent = FALSE) {
  waves <- load_kgss_waves()
  specs <- list_kgss_specs()
  results <- harmonize_all_specs(waves, specs = specs, silent = silent)
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
  cat("KGSS HARMONIZATION PIPELINE\n")
  cat(strrep("=", 70), "\n\n")

  waves <- load_kgss_waves()

  specs <- list_kgss_specs()
  cat(sprintf("\nFound %d YAML specs: %s\n\n",
              length(specs),
              paste(basename(specs), collapse = ", ")))

  results <- harmonize_all_specs(waves, specs = specs)

  harmonized_wide <- stack_harmonized_wide(results, waves)

  cat("\n", strrep("=", 70), "\n", sep = "")
  cat("SAVING MASTER FILES\n")
  cat(strrep("=", 70), "\n\n")

  output_dir <- here::here("outputs", "kgss")
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

  cat("\n✅ KGSS harmonization complete\n")
}
