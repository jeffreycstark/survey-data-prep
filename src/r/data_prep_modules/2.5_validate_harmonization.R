# 2.5_validate_harmonization.R
# Post-hoc validation of harmonization quality
#
# Compares harmonized output against raw wave data to ensure:
# 1. Coverage: No values silently dropped
# 2. Transformation: Reversals/scale conversions applied correctly
# 3. Range: All values within expected bounds
# 4. Crosstab: Each raw value maps to exactly one harmonized value
#
# Usage:
#   source("src/r/data_prep_modules/2.5_validate_harmonization.R")
#   # Or run directly: Rscript src/r/data_prep_modules/2.5_validate_harmonization.R

library(here)
library(yaml)
library(dplyr)
library(purrr)
library(haven)

# ==============================================================================
# SETUP
# ==============================================================================

here::i_am("src/r/data_prep_modules/2.5_validate_harmonization.R")

# Load validation functions
source(here::here("src/r/utils/validation.R"))
source(here::here("src/r/data_prep_modules/_yaml_utils.R"))
source(here::here("src/r/harmonize/_load_harmonize.R"))
source(here::here("src/r/utils/recoding.R"))

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Extract missing codes from spec (per-variable aware)
get_missing_codes <- function(spec, var_spec = NULL) {
  codes <- c()

  extract_codes <- function(convention) {
    if (is.null(convention)) return(numeric(0))
    if (is.list(convention) && !is.null(convention$codes)) {
      return(as.numeric(convention$codes))
    }
    as.numeric(convention)
  }

  # Variable-specific missing codes take precedence
  if (!is.null(var_spec) && !is.null(var_spec$missing)) {
    if (!is.null(var_spec$missing$codes)) {
      codes <- c(codes, as.numeric(var_spec$missing$codes))
    }
    if (!is.null(var_spec$missing$use_convention)) {
      key <- var_spec$missing$use_convention
      codes <- c(codes, extract_codes(spec$missing_conventions[[key]]))
    }
  }

  # Fallback to default convention
  if (length(codes) == 0 && !is.null(spec$missing_conventions$treat_as_na)) {
    codes <- c(codes, extract_codes(spec$missing_conventions$treat_as_na))
  }

  unique(codes)
}


#' Load raw wave data (from processed RDS files with haven labels)
#'
#' Uses the existing load_waves() function which loads from data/processed/{w1-w6}.rds
#' These contain the source variables with haven labels intact.
load_raw_waves <- function() {
  cat("Loading raw wave data (from processed RDS files)...\n")

  # Use the existing load_waves function
  source(here::here("src/r/data_prep_modules/0_load_waves.R"))
  waves <- load_waves()

  waves
}


#' Load harmonized dataset
load_harmonized_data <- function() {
  cat("Loading harmonized dataset...\n")

  path <- here::here("data/processed/abs_econdev_authpref.rds")

  if (!file.exists(path)) {
    # Try alternate location
    path <- here::here("outputs/abs_econdev_authpref.rds")
  }

  if (!file.exists(path)) {
    stop("Harmonized dataset not found. Run harmonization first.")
  }

  data <- readRDS(path)
  cat(sprintf("  Loaded: %d rows, %d cols\n", nrow(data), ncol(data)))
  cat(sprintf("  Waves: %s\n", paste(unique(data$wave), collapse = ", ")))

  data
}


# ==============================================================================
# MAIN VALIDATION FUNCTION
# ==============================================================================

#' Run full validation pipeline
#'
#' @param specs Optional: specific spec files to validate (default: all)
#' @param waves Optional: specific waves to validate (default: all)
#' @param save_report Save markdown report to outputs/
#' @param verbose Print progress messages
#' @return List of validation results
run_validation <- function(specs = NULL, waves = NULL,
                           save_report = TRUE, verbose = TRUE) {

  # Load data
  raw_waves <- load_raw_waves()
  harmonized <- load_harmonized_data()

  # Get YAML specs
  if (is.null(specs)) {
    spec_files <- list_yaml_specs()
  } else {
    spec_files <- specs
  }

  if (verbose) {
    cat(sprintf("\nValidating %d YAML specs...\n", length(spec_files)))
  }

  # Determine waves to validate
  wave_names <- if (is.null(waves)) names(raw_waves) else waves
  harmonized_wave_is_numeric <- "wave" %in% names(harmonized) && is.numeric(harmonized$wave)

  # Collect all results
  all_results <- list()
  result_idx <- 1

  # Process each spec
  for (spec_file in spec_files) {
    spec_name <- tools::file_path_sans_ext(basename(spec_file))

    if (verbose) {
      cat(sprintf("\n=== %s ===\n", spec_name))
    }

    # Load spec
    spec <- tryCatch(
      yaml::read_yaml(spec_file),
      error = function(e) {
        cat(sprintf("  ERROR: Failed to load %s: %s\n", spec_file, e$message))
        return(NULL)
      }
    )

    if (is.null(spec)) next

    # Process each variable in spec
    for (var_spec in spec$variables) {
      var_id <- var_spec$id
      missing_codes <- get_missing_codes(spec, var_spec)

      if (verbose) {
        cat(sprintf("  %s: ", var_id))
      }

      # Validate across waves
      wave_statuses <- c()

      for (wave_name in wave_names) {

        # Skip if wave not in raw data
        if (!wave_name %in% names(raw_waves)) next

        # Skip if variable not expected in this wave
        if (is.null(var_spec$source[[wave_name]])) next

        # Get harmonized data for this wave
        wave_id <- if (harmonized_wave_is_numeric) {
          as.integer(sub("^w", "", wave_name))
        } else {
          wave_name
        }

        harmonized_wave <- harmonized %>%
          dplyr::filter(wave == wave_id)

        # Run validation
        result <- validate_variable_wave(
          raw_data = raw_waves[[wave_name]],
          harmonized_data = harmonized_wave,
          var_spec = var_spec,
          wave_name = wave_name,
          missing_codes = missing_codes
        )

        # Store result
        all_results[[result_idx]] <- result
        result_idx <- result_idx + 1

        wave_statuses <- c(wave_statuses, result$status)
      }

      # Print summary for this variable
      if (verbose && length(wave_statuses) > 0) {
        n_ok <- sum(wave_statuses == "ok")
        n_warn <- sum(wave_statuses == "warn")
        n_error <- sum(wave_statuses == "error")
        n_skip <- sum(wave_statuses == "skip")

        status_str <- sprintf("%d✅", n_ok)
        if (n_warn > 0) status_str <- paste0(status_str, sprintf(" %d⚠️", n_warn))
        if (n_error > 0) status_str <- paste0(status_str, sprintf(" %d❌", n_error))
        if (n_skip > 0) status_str <- paste0(status_str, sprintf(" %d⏭️", n_skip))

        cat(status_str, "\n")
      }
    }
  }

  # Generate summary
  if (verbose) {
    cat("\n")
    cat("=" , rep("=", 50), "\n", sep = "")
    cat("VALIDATION SUMMARY\n")
    cat("=" , rep("=", 50), "\n", sep = "")

    summary_df <- generate_validation_summary(all_results)
    status_counts <- table(summary_df$status)

    cat(sprintf("Total checks: %d\n", nrow(summary_df)))
    cat(sprintf("  ✅ OK: %d\n", status_counts["ok"] %||% 0))
    cat(sprintf("  ⚠️ Warnings: %d\n", status_counts["warn"] %||% 0))
    cat(sprintf("  ❌ Errors: %d\n", status_counts["error"] %||% 0))
    cat(sprintf("  ⏭️ Skipped: %d\n", status_counts["skip"] %||% 0))
  }

  # Save report
  if (save_report) {
    report_path <- here::here("outputs/harmonization_validation_report.md")
    generate_validation_report(all_results, report_path)
  }

  invisible(all_results)
}


#' Quick validation for specific variables
#'
#' @param var_ids Character vector of variable IDs to validate
#' @param waves Character vector of waves to check (default: all)
#' @return Validation results for specified variables
validate_variables <- function(var_ids, waves = NULL) {

  # Load data
  raw_waves <- load_raw_waves()
  harmonized <- load_harmonized_data()

  # Find specs containing these variables
  spec_files <- list_yaml_specs()

  results <- list()
  result_idx <- 1

  wave_names <- if (is.null(waves)) names(raw_waves) else waves
  harmonized_wave_is_numeric <- "wave" %in% names(harmonized) && is.numeric(harmonized$wave)

  for (spec_file in spec_files) {
    spec <- yaml::read_yaml(spec_file)
    missing_codes <- get_missing_codes(spec)

    for (var_spec in spec$variables) {
      if (!var_spec$id %in% var_ids) next

      cat(sprintf("\n=== %s ===\n", var_spec$id))

      for (wave_name in wave_names) {
        if (is.null(var_spec$source[[wave_name]])) next
        if (!wave_name %in% names(raw_waves)) next

        wave_id <- if (harmonized_wave_is_numeric) {
          as.integer(sub("^w", "", wave_name))
        } else {
          wave_name
        }

        harmonized_wave <- harmonized %>% dplyr::filter(wave == wave_id)

        result <- validate_variable_wave(
          raw_data = raw_waves[[wave_name]],
          harmonized_data = harmonized_wave,
          var_spec = var_spec,
          wave_name = wave_name,
          missing_codes = missing_codes
        )

        # Print detailed results
        cat(sprintf("\n%s:\n", wave_name))
        cat(sprintf("  Overall: %s\n", toupper(result$status)))

        for (check_name in names(result$checks)) {
          check <- result$checks[[check_name]]
          icon <- dplyr::case_when(
            check$status == "ok" ~ "✅",
            check$status == "warn" ~ "⚠️",
            check$status == "error" ~ "❌",
            TRUE ~ "?"
          )
          cat(sprintf("  %s %s: %s\n", icon, check_name, check$message))
        }

        results[[result_idx]] <- result
        result_idx <- result_idx + 1
      }
    }
  }

  invisible(results)
}


# ==============================================================================
# RUN IF EXECUTED DIRECTLY
# ==============================================================================

if (sys.nframe() == 0) {
  cat("\n")
  cat("=" , rep("=", 60), "\n", sep = "")
  cat("  HARMONIZATION VALIDATION PIPELINE\n")
  cat("=" , rep("=", 60), "\n", sep = "")
  cat("  Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
  cat("=" , rep("=", 60), "\n\n", sep = "")

  start_time <- Sys.time()

  # Run full validation
  results <- run_validation(save_report = TRUE, verbose = TRUE)

  elapsed <- round(difftime(Sys.time(), start_time, units = "secs"), 1)

  cat("\n")
  cat("=" , rep("=", 60), "\n", sep = "")
  cat("  VALIDATION COMPLETE\n")
  cat("=" , rep("=", 60), "\n", sep = "")
  cat("  Elapsed:", elapsed, "seconds\n")
  cat("  Report: outputs/harmonization_validation_report.md\n")
  cat("  Finished:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
  cat("=" , rep("=", 60), "\n\n", sep = "")
}
