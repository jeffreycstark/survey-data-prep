# 2_harmonize_all.R
# Mass harmonization phase - process all YAML specs
#
# Reads all YAML configurations from src/config/abs/harmonize_validated/
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
harmonize_spec <- function(spec_path, waves, silent = FALSE, oob_log = NULL) {

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
        missing_conventions = missing_conventions,
        oob_log = oob_log
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
harmonize_all_specs <- function(waves, specs = NULL, silent = FALSE,
                                oob_log_path = NULL) {

  if (is.null(specs)) {
    specs <- list_yaml_specs()
  }

  if (!silent) {
    cat(sprintf("Found %d YAML specs to process\n", length(specs)))
    cat("Specs:", paste(basename(specs), collapse = ", "), "\n")
  }

  oob_log <- if (!is.null(oob_log_path)) {
    e <- new.env(parent = emptyenv())
    e$records <- list()
    e
  } else NULL

  results <- list()

  for (spec_path in specs) {
    spec_name <- tools::file_path_sans_ext(basename(spec_path))

    result <- harmonize_spec(spec_path, waves, silent = silent, oob_log = oob_log)

    if (!is.null(result)) {
      results[[spec_name]] <- result
    }
  }

  if (!is.null(oob_log_path)) {
    if (length(oob_log$records) > 0) {
      oob_df <- do.call(rbind, oob_log$records)
      write.csv(oob_df, oob_log_path, row.names = FALSE)
      if (!silent) {
        cat(sprintf("\n⚠  Out-of-range log: %d events written to %s\n",
                    nrow(oob_df), oob_log_path))
      }
    } else {
      # Write empty log so QA script can distinguish "ran and clean" from "never ran"
      write.csv(data.frame(variable=character(), wave=character(),
                            n_oob=integer(), obs_min=numeric(), obs_max=numeric(),
                            valid_min=numeric(), valid_max=numeric()),
                oob_log_path, row.names = FALSE)
      if (!silent) cat(sprintf("\n✅ Out-of-range log: no events (written to %s)\n", oob_log_path))
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
# GENERIC SURVEY HELPERS (used by per-survey 2_harmonize_all.R files)
# ==============================================================================

#' List YAML spec files for any survey
#'
#' @param survey Survey directory name under src/config/ (e.g. "afro", "wvs")
#' @return Character vector of YAML file paths (excludes template/doc files)
list_survey_specs <- function(survey) {
  config_dir <- here::here("src", "config", survey, "harmonize")
  files <- list.files(config_dir, pattern = "\\.yml$", full.names = TRUE)
  exclude_patterns <- c("MODEL_VARIABLE", "TEMPLATE", "README")
  files[!grepl(paste(exclude_patterns, collapse = "|"), files, ignore.case = TRUE)]
}

#' Generic harmonization pipeline for any survey
#'
#' @param survey Survey directory name (used to locate YAML specs)
#' @param load_fn Zero-argument function that returns the named list of wave data frames
#' @param output_format "wide" (list of wave dfs) or "long" (single stacked df)
#' @param silent Suppress messages
#' @return Harmonized data
run_survey_harmonization <- function(survey, load_fn,
                                     output_format = "wide", silent = FALSE) {
  waves <- load_fn()
  specs <- list_survey_specs(survey)
  results <- harmonize_all_specs(waves, specs = specs, silent = silent)
  if (output_format == "wide") {
    stack_harmonized_wide(results, waves)
  } else {
    stack_harmonized(results, waves)
  }
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

  # ---------------------------------------------------------------------------
  # Post-hoc country exclusions
  # For variables where within-wave question wording was substituted per country,
  # set affected country × wave cells to NA to prevent cross-national pollution.
  # ---------------------------------------------------------------------------

  # gate_contact_influential W2: question substituted for Indonesia (9), Taiwan (7),
  # Hong Kong (2). Those respondents were asked about "Mass media" (IN) or
  # "Acquaintances in the government" (TW/HK) — not traditional/community leaders.
  if ("gate_contact_influential" %in% names(harmonized_wide[["w2"]])) {
    harmonized_wide[["w2"]] <- harmonized_wide[["w2"]] |>
      dplyr::mutate(gate_contact_influential = dplyr::if_else(
        country %in% c(2, 7, 9), NA_real_, gate_contact_influential
      ))
    cat("  [post-hoc] gate_contact_influential W2: set NA for HK/TW/IN (country substitution)\n")
  }

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
