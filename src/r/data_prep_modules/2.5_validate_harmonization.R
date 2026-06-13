# 2.5_validate_harmonization.R
# Post-hoc validation of harmonization quality (audit Layer 3)
#
# Compares harmonized output against raw wave data to ensure:
# 1. Coverage: No values silently dropped
# 2. Transformation: Reversals/scale conversions applied correctly
# 3. Range: All values within expected bounds
# 4. Crosstab: Each raw value maps to exactly one harmonized value
#
# Survey-parametric (E2): pass `survey =` to validate any of the surveys with
# a per-survey 0_load_waves.R + harmonized .rds. Wave-key handling adapts to
# each survey's convention (w<N>, y<year>, w<year>, w<year>a/b, …).
#
# Usage:
#   source("src/r/data_prep_modules/2.5_validate_harmonization.R")
#   results <- run_validation(survey = "abs", save_report = TRUE)
#   results <- run_validation(survey = "kgss", verbose = FALSE)

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
source(here::here("src/r/utils/spec_discovery.R"))
source(here::here("src/r/data_prep_modules/_yaml_utils.R"))
source(here::here("src/r/harmonize/_load_harmonize.R"))
source(here::here("src/r/utils/recoding.R"))

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Extract missing codes from spec (per-variable aware)
get_missing_codes <- function(spec, var_spec = NULL) {
  codes <- c()
  has_explicit_declaration <- FALSE

  extract_codes <- function(convention) {
    if (is.null(convention)) return(numeric(0))
    if (is.list(convention) && !is.null(convention$codes)) {
      return(as.numeric(convention$codes))
    }
    as.numeric(convention)
  }

  # Variable-specific missing codes take precedence. Track whether the
  # variable explicitly declared its convention — an empty convention
  # (codes: []) is a valid intentional declaration and must not silently
  # fall back to treat_as_na.
  if (!is.null(var_spec) && !is.null(var_spec$missing)) {
    if (!is.null(var_spec$missing$codes)) {
      codes <- c(codes, as.numeric(var_spec$missing$codes))
      has_explicit_declaration <- TRUE
    }
    if (!is.null(var_spec$missing$use_convention)) {
      key <- var_spec$missing$use_convention
      codes <- c(codes, extract_codes(spec$missing_conventions[[key]]))
      has_explicit_declaration <- TRUE
    }
  }

  # Fallback to default convention only when the variable did NOT explicitly
  # declare its missing-code handling.
  if (!has_explicit_declaration &&
      !is.null(spec$missing_conventions$treat_as_na)) {
    codes <- c(codes, extract_codes(spec$missing_conventions$treat_as_na))
  }

  unique(codes)
}


# ==============================================================================
# SURVEY-PARAMETRIC LOADERS
# ==============================================================================

# Map survey -> (loader script path, loader function name).
# ABS is the legacy case: it lives in the parent data_prep_modules/ dir and
# its loader function is named load_waves(). All other surveys live in their
# own subdirectory and follow the load_<survey>_waves() convention.
.SURVEY_LOADERS <- list(
  abs              = list(script = "src/r/data_prep_modules/0_load_waves.R",
                          fn     = "load_waves"),
  wvs              = list(script = "src/r/data_prep_modules/wvs/0_load_waves.R",
                          fn     = "load_wvs_waves"),
  lbs              = list(script = "src/r/data_prep_modules/lbs/0_load_waves.R",
                          fn     = "load_lbs_waves"),
  afro             = list(script = "src/r/data_prep_modules/afro/0_load_waves.R",
                          fn     = "load_afro_waves"),
  `arab-barometer` = list(script = "src/r/data_prep_modules/arab-barometer/0_load_waves.R",
                          fn     = "load_arab_barometer_waves"),
  kamos            = list(script = "src/r/data_prep_modules/kamos/0_load_waves.R",
                          fn     = "load_kamos_waves"),
  kgss             = list(script = "src/r/data_prep_modules/kgss/0_load_waves.R",
                          fn     = "load_kgss_waves"),
  `kipa-corruption` = list(script = "src/r/data_prep_modules/kipa-corruption/0_load_waves.R",
                          fn     = "load_kipa_corruption_waves"),
  kinu             = list(script = "src/r/data_prep_modules/kinu/0_load_waves.R",
                          fn     = "load_kinu_waves"),
  ipus             = list(script = "src/r/data_prep_modules/ipus/0_load_waves.R",
                          fn     = "load_ipus_waves"),
  gcb              = list(script = "src/r/data_prep_modules/gcb/0_load_waves.R",
                          fn     = "load_gcb_waves")
)

# Map survey -> harmonized .rds filename. Most use {survey}_harmonized.rds, but
# `arab-barometer` and `kipa-corruption` use underscores in the filename.
.SURVEY_HARMONIZED <- list(
  abs              = "abs_harmonized.rds",
  wvs              = "wvs_harmonized.rds",
  lbs              = "lbs_harmonized.rds",
  afro             = "afro_harmonized.rds",
  `arab-barometer` = "arab_barometer_harmonized.rds",
  kamos            = "kamos_harmonized.rds",
  kgss             = "kgss_harmonized.rds",
  `kipa-corruption` = "kipa_corruption_harmonized.rds",
  kinu             = "kinu_harmonized.rds",
  ipus             = "ipus_harmonized.rds",
  gcb              = "gcb_harmonized.rds"
)


#' Load raw wave data for a given survey
#'
#' Sources the survey's `0_load_waves.R` and calls its loader function. The
#' loader returns a named list of wave dataframes (e.g. list(w1=..., w6=...)
#' for ABS, list(y1995=..., y2024=...) for LBS).
load_raw_waves <- function(survey = "abs") {
  loader <- .SURVEY_LOADERS[[survey]]
  if (is.null(loader)) {
    stop(sprintf("load_raw_waves(): no loader registered for survey '%s'. ",
                 survey),
         "Add an entry to .SURVEY_LOADERS in 2.5_validate_harmonization.R.",
         call. = FALSE)
  }

  script_path <- here::here(loader$script)
  if (!file.exists(script_path)) {
    stop(sprintf("load_raw_waves(): loader script not found: %s", script_path),
         call. = FALSE)
  }

  cat(sprintf("Loading raw wave data for '%s' via %s::%s() ...\n",
              survey, basename(loader$script), loader$fn))

  # Source the loader into the calling environment so library() calls run
  source(script_path)

  if (!exists(loader$fn, mode = "function")) {
    stop(sprintf(
      "load_raw_waves(): function '%s' not defined after sourcing %s",
      loader$fn, loader$script
    ), call. = FALSE)
  }

  fn <- get(loader$fn, mode = "function")
  fn()
}


#' Load harmonized dataset for a given survey
#'
#' Resolves to `data/processed/{survey}_harmonized.rds` (with the
#' arab-barometer / kipa-corruption underscore special-cases). Errors loudly
#' if the file is missing — this means the harmonization pipeline has not
#' been run yet for that survey.
load_harmonized_data <- function(survey = "abs") {
  fname <- .SURVEY_HARMONIZED[[survey]]
  if (is.null(fname)) {
    stop(sprintf("load_harmonized_data(): no harmonized filename registered for survey '%s'", survey),
         call. = FALSE)
  }

  path <- here::here("data", "processed", fname)

  if (!file.exists(path)) {
    stop(sprintf(
      "Harmonized output not found at %s — run the %s harmonization pipeline first.",
      path, survey
    ), call. = FALSE)
  }

  cat(sprintf("Loading harmonized dataset: %s\n", path))
  data <- readRDS(path)
  cat(sprintf("  Loaded: %d rows, %d cols\n", nrow(data), ncol(data)))

  if ("wave" %in% names(data)) {
    cat(sprintf("  Waves: %s\n", paste(unique(data$wave), collapse = ", ")))
  } else {
    warning("Harmonized dataset has no `wave` column — per-wave validation will skip", call. = FALSE)
  }

  data
}


#' Convert a wave-list key (e.g. "w1", "y1995", "w2019a") to the matching
#' value in the harmonized data's `wave` column.
#'
#' Rules:
#'   - If the harmonized wave column is character, return wave_name as-is when
#'     it appears literally in the column (covers Arab Barometer's "w2");
#'     otherwise strip the leading alpha prefix (covers KINU's "2019a").
#'   - If the harmonized wave column is numeric, extract the digits via regex
#'     and coerce to integer. This handles ABS ("w1" -> 1), KGSS ("w2003" ->
#'     2003), LBS ("y1995" -> 1995) uniformly.
#'   - Errors informatively for unrecognised conventions.
.wave_key_to_id <- function(wave_name, harmonized_wave_col) {
  if (is.numeric(harmonized_wave_col)) {
    digits <- regmatches(wave_name, regexpr("[0-9]+", wave_name))
    if (length(digits) == 0L || !nzchar(digits)) {
      stop(sprintf(
        "Cannot derive numeric wave id from wave key '%s' (harmonized wave column is numeric)",
        wave_name
      ), call. = FALSE)
    }
    return(as.integer(digits))
  }

  # Character wave column: prefer literal match (Arab Barometer "w2") over
  # alpha-strip ("w2014" -> "2014" for KINU).
  uniq <- unique(as.character(harmonized_wave_col))
  if (wave_name %in% uniq) return(wave_name)

  stripped <- sub("^[A-Za-z]+", "", wave_name)
  if (stripped %in% uniq) return(stripped)

  stop(sprintf(
    "Cannot match wave key '%s' to any value in harmonized wave column [%s]",
    wave_name, paste(head(uniq, 10), collapse = ", ")
  ), call. = FALSE)
}


# ==============================================================================
# MAIN VALIDATION FUNCTION
# ==============================================================================

#' Run full validation pipeline
#'
#' @param survey Survey name (must be a key in .SURVEY_LOADERS). Defaults to
#'   "abs" for backward compatibility with pre-E2 callers.
#' @param specs Optional: specific spec files to validate (default: all for
#'   the survey).
#' @param waves Optional: specific wave keys to validate (default: all keys
#'   returned by the survey's loader).
#' @param harmonized Optional: pre-loaded harmonized data frame (skips disk
#'   read). Useful for tests.
#' @param save_report Save markdown + CSV reports to outputs/<survey>/ and
#'   audit/reports/<survey>/.
#' @param verbose Print progress messages.
#' @return List of validation results.
run_validation <- function(survey = "abs",
                           specs = NULL,
                           waves = NULL,
                           harmonized = NULL,
                           save_report = TRUE,
                           verbose = TRUE) {

  if (verbose) {
    cat(sprintf("\n=== run_validation(survey = '%s') ===\n", survey))
  }

  # Load data
  raw_waves <- load_raw_waves(survey)
  if (is.null(harmonized)) {
    harmonized <- load_harmonized_data(survey)
  }

  # Get YAML specs
  if (is.null(specs)) {
    spec_files <- list_survey_specs(survey)
  } else {
    spec_files <- specs
  }

  if (verbose) {
    cat(sprintf("\nValidating %d YAML specs...\n", length(spec_files)))
  }

  # Determine waves to validate
  wave_names <- if (is.null(waves)) names(raw_waves) else waves

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

        # Skip if harmonized has no wave column
        if (!"wave" %in% names(harmonized)) next

        # Resolve wave key (e.g. "w1" -> 1, "y1995" -> 1995, "w2" -> "w2")
        wave_id <- tryCatch(
          .wave_key_to_id(wave_name, harmonized$wave),
          error = function(e) {
            cat(sprintf("\n    ! wave-id resolution failed: %s\n", e$message))
            NULL
          }
        )
        if (is.null(wave_id)) next

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

        status_str <- sprintf("%d ok", n_ok)
        if (n_warn > 0) status_str <- paste0(status_str, sprintf(", %d warn", n_warn))
        if (n_error > 0) status_str <- paste0(status_str, sprintf(", %d error", n_error))
        if (n_skip > 0) status_str <- paste0(status_str, sprintf(", %d skip", n_skip))

        cat(status_str, "\n")
      } else if (verbose) {
        cat("(no waves matched)\n")
      }
    }
  }

  # Generate summary
  summary_df <- generate_validation_summary(all_results)
  status_counts <- table(summary_df$status)
  na_to_zero <- function(x) { if (is.null(x) || is.na(x)) 0L else as.integer(x) }
  n_ok    <- na_to_zero(status_counts["ok"])
  n_warn  <- na_to_zero(status_counts["warn"])
  n_error <- na_to_zero(status_counts["error"])
  n_skip  <- na_to_zero(status_counts["skip"])

  if (verbose) {
    cat("\n", strrep("=", 60), "\n", sep = "")
    cat(sprintf("VALIDATION SUMMARY (%s)\n", survey))
    cat(strrep("=", 60), "\n", sep = "")
    cat(sprintf("Total checks: %d\n", nrow(summary_df)))
    cat(sprintf("  ok:    %d\n", n_ok))
    cat(sprintf("  warn:  %d\n", n_warn))
    cat(sprintf("  error: %d\n", n_error))
    cat(sprintf("  skip:  %d\n", n_skip))
  }

  # Save reports
  if (save_report) {
    md_dir <- here::here("outputs", survey)
    dir.create(md_dir, showWarnings = FALSE, recursive = TRUE)
    md_path <- file.path(md_dir, "03-invariants.md")
    generate_validation_report(all_results, md_path)

    csv_dir <- here::here("audit", "reports", survey)
    dir.create(csv_dir, showWarnings = FALSE, recursive = TRUE)
    csv_path <- file.path(csv_dir, "03-invariants.csv")
    write_invariants_csv(all_results, csv_path)
    cat(sprintf("Structured CSV: %s\n", csv_path))
  }

  invisible(list(
    results = all_results,
    summary = summary_df,
    counts  = list(ok = n_ok, warn = n_warn, error = n_error, skip = n_skip)
  ))
}


#' Write per-(variable × wave × check) structured CSV.
#'
#' Schema: var_id, wave, check, status, value, threshold, message.
#' One row per check (coverage / transformation / range / crosstab) per
#' (variable × wave) pair. The `value` and `threshold` columns are best-effort
#' string renderings of the most informative numeric for each check; consumers
#' should treat them as diagnostic metadata, not as primary keys.
write_invariants_csv <- function(results, output_path) {

  fmt <- function(x) {
    if (is.null(x)) return(NA_character_)
    if (is.numeric(x)) {
      if (length(x) == 1) return(formatC(x, digits = 4, format = "g"))
      return(paste(formatC(x, digits = 4, format = "g"), collapse = ","))
    }
    as.character(x)[1]
  }

  rows <- purrr::map_dfr(results, function(r) {
    if (is.null(r$checks) || length(r$checks) == 0) {
      return(tibble::tibble(
        var_id    = r$var_id %||% NA_character_,
        wave      = r$wave %||% NA_character_,
        check     = "overall",
        status    = r$status %||% NA_character_,
        value     = NA_character_,
        threshold = NA_character_,
        message   = r$message %||% NA_character_
      ))
    }

    purrr::imap_dfr(r$checks, function(chk, name) {
      # Pick the most informative numeric per check type.
      val <- switch(name,
        coverage           = fmt(chk$pct_loss),
        completeness       = fmt(chk$n_valid),
        transformation     = fmt(chk$pearson),
        range              = fmt(chk$out_of_range),
        crosstab           = fmt(chk$n_raw_values),
        type_stability     = fmt(chk$observed_storage),
        level_preservation = fmt(chk$observed_levels),
        NA_character_
      )
      thr <- switch(name,
        range              = if (!is.null(chk$valid_range)) fmt(chk$valid_range) else NA_character_,
        type_stability     = fmt(chk$declared_type),
        level_preservation = fmt(chk$declared_range),
        NA_character_
      )

      tibble::tibble(
        var_id    = r$var_id %||% NA_character_,
        wave      = as.character(r$wave) %||% NA_character_,
        check     = name,
        status    = chk$status %||% NA_character_,
        value     = val,
        threshold = thr,
        message   = chk$message %||% NA_character_
      )
    })
  })

  utils::write.csv(rows, output_path, row.names = FALSE, na = "")
  invisible(rows)
}


#' Quick validation for specific variables
#'
#' @param var_ids Character vector of variable IDs to validate
#' @param survey Survey name (default "abs" for backward compat)
#' @param waves Character vector of wave keys to check (default: all)
#' @return Validation results for specified variables
validate_variables <- function(var_ids, survey = "abs", waves = NULL) {

  raw_waves <- load_raw_waves(survey)
  harmonized <- load_harmonized_data(survey)

  spec_files <- list_survey_specs(survey)

  results <- list()
  result_idx <- 1

  wave_names <- if (is.null(waves)) names(raw_waves) else waves

  for (spec_file in spec_files) {
    spec <- yaml::read_yaml(spec_file)

    for (var_spec in spec$variables) {
      if (!var_spec$id %in% var_ids) next
      missing_codes <- get_missing_codes(spec, var_spec)

      cat(sprintf("\n=== %s ===\n", var_spec$id))

      for (wave_name in wave_names) {
        if (is.null(var_spec$source[[wave_name]])) next
        if (!wave_name %in% names(raw_waves)) next
        if (!"wave" %in% names(harmonized)) next

        wave_id <- tryCatch(
          .wave_key_to_id(wave_name, harmonized$wave),
          error = function(e) NULL
        )
        if (is.null(wave_id)) next

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
          tag <- switch(check$status,
            ok    = "[ok]   ",
            warn  = "[warn] ",
            error = "[err]  ",
            skip  = "[skip] ",
            "[?]    "
          )
          cat(sprintf("  %s %s: %s\n", tag, check_name, check$message))
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

  args <- commandArgs(trailingOnly = TRUE)
  survey <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "abs"

  cat("\n", strrep("=", 60), "\n", sep = "")
  cat(sprintf("  HARMONIZATION VALIDATION PIPELINE: %s\n", survey))
  cat(strrep("=", 60), "\n", sep = "")
  cat("  Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
  cat(strrep("=", 60), "\n\n", sep = "")

  start_time <- Sys.time()

  results <- run_validation(survey = survey, save_report = TRUE, verbose = TRUE)

  elapsed <- round(difftime(Sys.time(), start_time, units = "secs"), 1)

  cat("\n", strrep("=", 60), "\n", sep = "")
  cat("  VALIDATION COMPLETE\n")
  cat(strrep("=", 60), "\n", sep = "")
  cat("  Elapsed:", elapsed, "seconds\n")
  cat(sprintf("  Report:  outputs/%s/03-invariants.md\n", survey))
  cat(sprintf("  CSV:     audit/reports/%s/03-invariants.csv\n", survey))
  cat("  Finished:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
  cat(strrep("=", 60), "\n\n", sep = "")
}
