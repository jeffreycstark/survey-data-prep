# src/r/harmonize/validate_spec.R
# YAML specification validation for harmonization

#' Validate harmonization YAML specification structure
#'
#' Checks that a parsed YAML specification has required fields and
#' correct types. Returns informative errors if validation fails.
#'
#' @param spec List: parsed YAML specification
#' @param var_id Optional: validate specific variable instead of all
#'
#' @return Invisibly returns TRUE if valid; stops with error otherwise
#'
#' @details
#' Top-level required fields:
#' - missing_conventions: named list of missing code vectors
#' - variables: list of variable specifications
#'
#' Per-variable required fields:
#' - id: character, unique identifier
#' - concept: character
#' - description: character
#' - source: named list (at least one wave required)
#' - type: character ("ordinal", "nominal", "continuous")
#' - harmonize: list with "default" method
#'
#' @export
validate_harmonize_spec <- function(spec, var_id = NULL) {

  errors <- list()

  # ---- Check top-level structure ----
  if (is.null(spec$missing_conventions)) {
    errors$missing_conventions <- "Required: missing_conventions"
  }

  if (is.null(spec$variables) || length(spec$variables) == 0) {
    errors$variables <- "Required: variables list (must have ≥1 variable)"
  }

  # ---- Check specific variable(s) ----
  var_ids <- if (!is.null(var_id)) {
    var_id
  } else {
    names(spec$variables) %||% character(0)
  }

  for (vid in var_ids) {

    var_spec <- spec$variables[[vid]]

    if (is.null(var_spec)) {
      errors[[paste0("variables.", vid)]] <- "Variable not found"
      next
    }

    # Required fields
    if (is.null(var_spec$id)) {
      errors[[paste0(vid, ".id")]] <- "Required: id"
    }

    if (is.null(var_spec$concept)) {
      errors[[paste0(vid, ".concept")]] <- "Required: concept"
    }

    if (is.null(var_spec$description)) {
      errors[[paste0(vid, ".description")]] <- "Required: description"
    }

    if (is.null(var_spec$source) || length(var_spec$source) == 0) {
      errors[[paste0(vid, ".source")]] <- "Required: source (named list, ≥1 wave)"
    }

    if (is.null(var_spec$type)) {
      errors[[paste0(vid, ".type")]] <- "Required: type"
    } else if (!var_spec$type %in% c("ordinal", "nominal", "continuous")) {
      errors[[paste0(vid, ".type")]] <- paste(
        "Invalid type. Must be: ordinal, nominal, continuous"
      )
    }

    # Harmonization spec
    if (is.null(var_spec$harmonize)) {
      errors[[paste0(vid, ".harmonize")]] <- "Required: harmonize"
    } else {
      if (is.null(var_spec$harmonize$default)) {
        errors[[paste0(vid, ".harmonize.default")]] <- "Required: default method"
      } else {
        method <- var_spec$harmonize$default$method
        if (!method %in% c("identity", "r_function")) {
          errors[[paste0(vid, ".harmonize.default.method")]] <- paste(
            "Invalid method. Must be: identity, r_function"
          )
        }
      }
    }

    # QC if present
    if (!is.null(var_spec$qc)) {
      if (!is.null(var_spec$qc$valid_range_by_wave)) {
        vr_list <- var_spec$qc$valid_range_by_wave

        for (wave_name in names(vr_list)) {
          vr <- vr_list[[wave_name]]

          if (!is.numeric(vr) || length(vr) != 2) {
            errors[[paste0(vid, ".qc.valid_range.", wave_name)]] <- paste(
              "Invalid range. Must be numeric vector of length 2: [min, max]"
            )
          }
        }
      }
    }
  }

  # ---- Report errors ----
  if (length(errors) > 0) {

    error_msg <- "❌ Specification validation failed:\n\n"

    for (i in seq_along(errors)) {
      error_msg <- paste0(
        error_msg,
        sprintf("  %d. %s: %s\n", i, names(errors)[i], errors[[i]])
      )
    }

    stop(error_msg, call. = FALSE)
  }

  invisible(TRUE)
}

#' Validate variable labels contain expected phrases
#'
#' Checks that source variables in each wave have labels containing
#' the expected phrase from qc$validate. This catches wrong variable mappings.
#'
#' @param spec List: parsed YAML specification
#' @param waves List: named list of wave dataframes (w1, w2, etc.)
#' @param verbose Logical: print results as they're checked
#'
#' @return List with:
#'   - passed: tibble of successful validations
#'   - failed: tibble of failed validations (label doesn't contain phrase)
#'   - missing: tibble of variables that couldn't be checked (no label or var not found)
#'
#' @export
validate_phrases <- function(spec, waves, verbose = TRUE) {

  results <- list(
    passed = list(),
    failed = list(),
    missing = list()
  )

  # Iterate through each variable in spec
  for (var_spec in spec$variables) {

    var_id <- var_spec$id
    validate_rules <- var_spec$qc$validate

    # Skip if no validate rules
    if (is.null(validate_rules)) next

    # Process each validate rule
    for (rule in validate_rules) {

      phrase <- rule$phrase
      rule_waves <- rule$waves

      # Skip if no phrase specified
      if (is.null(phrase)) next

      # Check each wave in this rule
      for (wave_name in rule_waves) {

        # Get source variable name for this wave
        source_var <- var_spec$source[[wave_name]]

        # Skip if source is null (variable not in this wave)
        if (is.null(source_var)) next

        # Check if wave exists
        if (!wave_name %in% names(waves)) {
          results$missing[[length(results$missing) + 1]] <- list(
            var_id = var_id,
            wave = wave_name,
            source_var = source_var,
            phrase = phrase,
            reason = "Wave not loaded"
          )
          next
        }

        wave_data <- waves[[wave_name]]

        # Check if variable exists in wave
        if (!source_var %in% names(wave_data)) {
          results$missing[[length(results$missing) + 1]] <- list(
            var_id = var_id,
            wave = wave_name,
            source_var = source_var,
            phrase = phrase,
            reason = "Variable not found in wave"
          )
          next
        }

        # Get variable label
        var_label <- attr(wave_data[[source_var]], "label")

        if (is.null(var_label) || var_label == "") {
          results$missing[[length(results$missing) + 1]] <- list(
            var_id = var_id,
            wave = wave_name,
            source_var = source_var,
            phrase = phrase,
            reason = "No label found"
          )
          next
        }

        # Check if label contains phrase (case-insensitive regex)
        if (grepl(phrase, var_label, ignore.case = TRUE)) {
          results$passed[[length(results$passed) + 1]] <- list(
            var_id = var_id,
            wave = wave_name,
            source_var = source_var,
            phrase = phrase,
            label = var_label
          )
        } else {
          results$failed[[length(results$failed) + 1]] <- list(
            var_id = var_id,
            wave = wave_name,
            source_var = source_var,
            phrase = phrase,
            label = var_label
          )
        }
      }
    }
  }

  # Convert to tibbles
  results$passed <- if (length(results$passed) > 0) {
    dplyr::bind_rows(results$passed)
  } else {
    dplyr::tibble(var_id = character(), wave = character(),
                  source_var = character(), phrase = character(), label = character())
  }

  results$failed <- if (length(results$failed) > 0) {
    dplyr::bind_rows(results$failed)
  } else {
    dplyr::tibble(var_id = character(), wave = character(),
                  source_var = character(), phrase = character(), label = character())
  }

  results$missing <- if (length(results$missing) > 0) {
    dplyr::bind_rows(results$missing)
  } else {
    dplyr::tibble(var_id = character(), wave = character(),
                  source_var = character(), phrase = character(), reason = character())
  }

  # Print summary if verbose
  if (verbose) {
    n_passed <- nrow(results$passed)
    n_failed <- nrow(results$failed)
    n_missing <- nrow(results$missing)

    cat(sprintf("\n=== Phrase Validation Results ===\n"))
    cat(sprintf("✅ Passed:  %d\n", n_passed))
    cat(sprintf("❌ Failed:  %d\n", n_failed))
    cat(sprintf("⚠️  Missing: %d\n", n_missing))

    if (n_failed > 0) {
      cat("\n❌ FAILED validations (label doesn't contain phrase):\n")
      for (i in seq_len(nrow(results$failed))) {
        row <- results$failed[i, ]
        cat(sprintf("   %s (%s): '%s' not in label\n",
                    row$var_id, row$wave, row$phrase))
        cat(sprintf("      Source: %s\n", row$source_var))
        cat(sprintf("      Label:  %s\n", substr(row$label, 1, 80)))
      }
    }

    if (n_missing > 0 && n_missing <= 20) {
      cat("\n⚠️  Could not validate (missing label or variable):\n")
      for (i in seq_len(nrow(results$missing))) {
        row <- results$missing[i, ]
        cat(sprintf("   %s (%s → %s): %s\n",
                    row$var_id, row$wave, row$source_var, row$reason))
      }
    } else if (n_missing > 20) {
      cat(sprintf("\n⚠️  %d variables could not be validated (use results$missing for details)\n",
                  n_missing))
    }
  }

  results
}


#' Validate all YAML specs against wave data
#'
#' Runs phrase validation for all YAML specs in a directory
#'
#' @param waves List: named list of wave dataframes
#' @param config_dir Path to YAML config directory
#' @param verbose Print progress
#'
#' @return List of validation results by spec name
#'
#' @export
validate_all_specs <- function(waves,
                               config_dir = "src/config/harmonize_validated",
                               verbose = TRUE) {

  yaml_files <- list.files(config_dir, pattern = "\\.yml$", full.names = TRUE)

  # Exclude template/readme files
  exclude <- c("MODEL_VARIABLE", "TEMPLATE", "README")
  yaml_files <- yaml_files[!grepl(paste(exclude, collapse = "|"), yaml_files, ignore.case = TRUE)]

  all_results <- list()
  total_passed <- 0
  total_failed <- 0
  total_missing <- 0

  for (yml_path in yaml_files) {
    spec_name <- tools::file_path_sans_ext(basename(yml_path))

    if (verbose) {
      cat(sprintf("\nValidating: %s\n", spec_name))
    }

    spec <- yaml::read_yaml(yml_path)
    result <- validate_phrases(spec, waves, verbose = FALSE)

    all_results[[spec_name]] <- result
    total_passed <- total_passed + nrow(result$passed)
    total_failed <- total_failed + nrow(result$failed)
    total_missing <- total_missing + nrow(result$missing)

    if (verbose && nrow(result$failed) > 0) {
      cat(sprintf("  ❌ %d failed validations\n", nrow(result$failed)))
      for (i in seq_len(min(5, nrow(result$failed)))) {
        row <- result$failed[i, ]
        cat(sprintf("     - %s (%s): '%s' not found\n",
                    row$var_id, row$wave, row$phrase))
      }
    }
  }

  if (verbose) {
    cat(sprintf("\n=== TOTAL SUMMARY ===\n"))
    cat(sprintf("Specs validated: %d\n", length(yaml_files)))
    cat(sprintf("✅ Passed:  %d\n", total_passed))
    cat(sprintf("❌ Failed:  %d\n", total_failed))
    cat(sprintf("⚠️  Missing: %d\n", total_missing))
  }

  all_results
}


#' Check if recoding functions exist
#'
#' Validates that all r_function harmonization methods have
#' corresponding functions loaded in environment.
#'
#' @param spec List: parsed YAML specification
#'
#' @return List of missing functions, or NULL if all present
#'
#' @export
check_recoding_functions <- function(spec) {

  missing_fns <- character()

  for (var_id in names(spec$variables)) {

    var_spec <- spec$variables[[var_id]]

    # Check default method
    if (var_spec$harmonize$default$method == "r_function") {
      fn_name <- var_spec$harmonize$default$fn

      if (!exists(fn_name, mode = "function")) {
        missing_fns <- c(missing_fns, fn_name)
      }
    }

    # Check wave-specific methods
    for (wave_name in names(var_spec$harmonize$by_wave %||% list())) {

      wave_rule <- var_spec$harmonize$by_wave[[wave_name]]

      if (wave_rule$method == "r_function") {
        fn_name <- wave_rule$fn

        if (!exists(fn_name, mode = "function")) {
          missing_fns <- c(missing_fns, fn_name)
        }
      }
    }
  }

  unique(missing_fns)
}
