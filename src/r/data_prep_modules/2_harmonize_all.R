# 2_harmonize_all.R
# Mass harmonization phase - process all YAML specs
#
# Reads all YAML configurations from src/config/harmonize_validated/
# Applies harmonize_variable() to each variable
# Returns harmonized data organized by concept

library(here)
library(yaml)
library(dplyr)

# Load harmonization engine
source(here::here("src/r/harmonize/_load_harmonize.R"))
source(here::here("src/r/utils/_load_functions.R"))
source(here::here("src/r/data_prep_modules/_yaml_utils.R"))

# ==============================================================================
# MAIN FUNCTIONS
# ==============================================================================

#' Harmonize all variables from a single YAML spec
#'
#' @param spec_path Path to YAML spec file
#' @param waves List of wave dataframes
#' @param silent Suppress messages
#' @return List with harmonized variables and metadata
harmonize_spec <- function(spec_path, waves, silent = FALSE) {

  spec_name <- tools::file_path_sans_ext(basename(spec_path))

  if (!silent) {
    cat(sprintf("\n=== Processing: %s ===\n", spec_name))
  }

  # Load and validate spec
  spec <- yaml::read_yaml(spec_path)

  tryCatch({
    validate_harmonize_spec(spec)
  }, error = function(e) {
    warning(sprintf("Validation failed for %s: %s", spec_name, e$message))
    return(NULL)
  })

  # Get missing conventions
  missing_conventions <- spec$missing_conventions

  # Process each variable
  results <- list()

  for (var_spec in spec$variables) {
    var_id <- var_spec$id

    if (!silent) {
      cat(sprintf("  - %s\n", var_id))
    }

    tryCatch({
      harmonized <- harmonize_variable(
        var_spec = var_spec,
        waves = waves,
        missing_conventions = missing_conventions
      )

      results[[var_id]] <- harmonized

    }, error = function(e) {
      warning(sprintf("Failed to harmonize %s: %s", var_id, e$message))
    })
  }

  list(
    spec_name = spec_name,
    concept = spec$variables[[1]]$concept %||% spec_name,
    variables = results,
    n_variables = length(results)
  )
}


#' Run mass harmonization on all YAML specs
#'
#' @param waves List of wave dataframes (from load_waves())
#' @param specs Optional: specific spec files to process (default: all)
#' @param silent Suppress messages
#' @return List of harmonization results by spec
harmonize_all_specs <- function(waves, specs = NULL, silent = FALSE) {

  if (is.null(specs)) {
    specs <- list_yaml_specs()
  }

  if (!silent) {
    cat(sprintf("Found %d YAML specs to process\n", length(specs)))
    cat("Specs:", paste(basename(specs), collapse = ", "), "\n")
  }

  results <- list()

  for (spec_path in specs) {
    spec_name <- tools::file_path_sans_ext(basename(spec_path))

    result <- harmonize_spec(spec_path, waves, silent = silent)

    if (!is.null(result)) {
      results[[spec_name]] <- result
    }
  }

  if (!silent) {
    cat("\n=== Summary ===\n")
    total_vars <- sum(sapply(results, function(x) x$n_variables))
    cat(sprintf("Processed %d specs, %d total variables\n",
                length(results), total_vars))
  }

  results
}


#' Stack harmonized results into a long dataframe
#'
#' @param harmonized_results Output from harmonize_all_specs()
#' @param waves List of wave dataframes (for row counts)
#' @return Long dataframe with wave, variable columns
stack_harmonized <- function(harmonized_results, waves) {
  all_rows <- list()

  for (spec_name in names(harmonized_results)) {
    spec_result <- harmonized_results[[spec_name]]

    for (var_id in names(spec_result$variables)) {
      var_data <- spec_result$variables[[var_id]]

      for (wave_name in names(var_data)) {
        values <- var_data[[wave_name]]

        if (length(values) > 0) {
          all_rows[[paste(spec_name, var_id, wave_name, sep = "_")]] <- tibble(
            wave = wave_name,
            concept = spec_result$concept,
            variable = var_id,
            row_id = seq_along(values),
            value = values
          )
        }
      }
    }
  }

  bind_rows(all_rows)
}


#' Stack harmonized results into wide format (one row per observation)
#'
#' @param harmonized_results Output from harmonize_all_specs()
#' @param waves List of wave dataframes
#' @return List of dataframes, one per wave, with all harmonized variables as columns
stack_harmonized_wide <- function(harmonized_results, waves) {

  wave_names <- names(waves)
  output <- list()

  for (wave_name in wave_names) {
    n_rows <- nrow(waves[[wave_name]])

    # Start with wave identifier
    wave_df <- tibble(
      wave = rep(wave_name, n_rows),
      row_id = seq_len(n_rows)
    )

    # Add each harmonized variable
    for (spec_name in names(harmonized_results)) {
      spec_result <- harmonized_results[[spec_name]]

      for (var_id in names(spec_result$variables)) {
        var_data <- spec_result$variables[[var_id]]

        if (wave_name %in% names(var_data)) {
          values <- var_data[[wave_name]]

          if (length(values) == n_rows) {
            wave_df[[var_id]] <- values
          } else if (length(values) > 0) {
            warning(sprintf(
              "Length mismatch for %s in %s: expected %d, got %d",
              var_id, wave_name, n_rows, length(values)
            ))
          }
        }
      }
    }

    output[[wave_name]] <- wave_df
  }

  output
}


# ==============================================================================
# CONVENIENCE WRAPPER
# ==============================================================================

#' Full harmonization pipeline
#'
#' Load waves, harmonize all specs, return wide format
#'
#' @param output_format "wide" (list of wave dfs) or "long" (single stacked df)
#' @return Harmonized data
run_harmonization <- function(output_format = "wide") {

  # Load waves
  source(here::here("src/r/data_prep_modules/0_load_waves.R"))
  waves <- load_waves()

  # Harmonize all specs
  results <- harmonize_all_specs(waves)

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
  cat("Running mass harmonization...\n\n")

  # Load waves
  source(here::here("src/r/data_prep_modules/0_load_waves.R"))
  waves <- load_waves()

  # Run harmonization
  results <- harmonize_all_specs(waves)

  # Stack into wide format
  harmonized_wide <- stack_harmonized_wide(results, waves)

  # Save master files
  cat("\n=== Saving master files ===\n")
  output_dir <- here::here("outputs")
  for (wave_name in names(harmonized_wide)) {
    df <- harmonized_wide[[wave_name]]
    output_file <- file.path(output_dir, paste0("master_", wave_name, ".rds"))
    saveRDS(df, output_file)
    cat(sprintf("  Saved %s: %d rows, %d variables\n",
                basename(output_file), nrow(df), ncol(df) - 2))  # -2 for wave, row_id
  }
}
