# R/validation.R
# Validation functions for harmonization quality assurance
#
# Two categories:
# 1. General validation utilities (original functions)
# 2. Harmonization-specific validation (new functions for post-hoc validation)

library(dplyr)
library(tidyr)

# ==============================================================================
# GENERAL VALIDATION UTILITIES (Original)
# ==============================================================================

#' Check for unexpected values in variables
#'
#' @param data Data frame
#' @param vars Character vector of variable names
#' @param expected Vector of expected values
#' @return Logical indicating if all values are expected
check_unexpected_values <- function(data, vars, expected) {
  issues_found <- FALSE

  for (var in vars) {
    if (!var %in% names(data)) {
      cat("❌ Variable", var, "not found\n")
      issues_found <- TRUE
      next
    }

    unexpected <- data %>%
      dplyr::filter(!.data[[var]] %in% c(expected, NA))

    if (nrow(unexpected) > 0) {
      cat("⚠️ ", var, ":", nrow(unexpected), "unexpected values\n")
      issues_found <- TRUE
    }
  }

  if (!issues_found) {
    cat("✓ All variables have expected values\n")
  }

  invisible(!issues_found)
}

#' Verify scale reversal via correlation
#'
#' @param original Original vector
#' @param recoded Recoded vector
#' @return Logical indicating correct reversal
verify_reversal <- function(original, recoded) {
  cor_val <- suppressWarnings(cor(original, recoded, use = "complete.obs"))

  if (is.na(cor_val)) {
    cat("⚠️ Cannot compute correlation (insufficient data)\n")
    return(FALSE)
  }

  if (cor_val < -0.99) {
    cat("✓ Reversal correct (r =", round(cor_val, 3), ")\n")
    return(TRUE)
  } else {
    cat("❌ ERROR: Reversal incorrect (r =", round(cor_val, 3), ")\n")
    return(FALSE)
  }
}

#' Create verification table for multiple reversals
#'
#' @param data Data frame
#' @param original_vars Character vector of original variable names
#' @param recoded_vars Character vector of recoded variable names
#' @return Tibble with correlation and validation results
create_verification_table <- function(data, original_vars, recoded_vars) {
  result <- tibble::tibble(
    original = original_vars,
    recoded = recoded_vars
  ) %>%
    dplyr::rowwise() %>%
    dplyr::mutate(
      correlation = suppressWarnings(cor(data[[original]], data[[recoded]],
                                         use = "complete.obs")),
      n_valid = sum(!is.na(data[[original]])),
      reversal_ok = correlation < -0.99
    ) %>%
    dplyr::ungroup()

  invisible(result)
}

#' Verify no invalid codes exist
#'
#' @param data Data frame
#' @param vars Character vector of variable names
#' @param valid_range Numeric vector c(min, max)
#' @return Tibble of variables with out-of-range values
verify_no_invalid_codes <- function(data, vars, valid_range) {
  data %>%
    dplyr::select(dplyr::all_of(vars)) %>%
    dplyr::summarise(
      dplyr::across(
        dplyr::everything(),
        ~sum(. < valid_range[1] | . > valid_range[2], na.rm = TRUE)
      )
    ) %>%
    tidyr::pivot_longer(dplyr::everything()) %>%
    dplyr::filter(value > 0)
}

# ==============================================================================
# HARMONIZATION VALIDATION FUNCTIONS (New)
# ==============================================================================

#' Validate coverage: ensure no values were silently dropped
#'
#' Compares raw non-missing count to harmonized non-missing count,
#' accounting for values that should be treated as missing.
#'
#' @param raw_vec Raw source vector (from original wave data)
#' @param harmonized_vec Harmonized vector (from combined dataset)
#' @param missing_codes Numeric vector of codes to treat as NA
#' @param threshold_warn Warning threshold for coverage loss (default 0.001 = 0.1%)
#' @param threshold_error Error threshold for coverage loss (default 0.01 = 1%)
#' @return List with status, counts, and message
validate_coverage <- function(raw_vec, harmonized_vec, missing_codes = c(),
                              threshold_warn = 0.001, threshold_error = 0.01) {


  # Count raw values (excluding missing codes)
  raw_valid <- sum(!is.na(raw_vec) & !(raw_vec %in% missing_codes))


  # Count harmonized non-NA values
  harmonized_valid <- sum(!is.na(harmonized_vec))


  # Calculate difference
  diff <- raw_valid - harmonized_valid
  pct_loss <- if (raw_valid > 0) diff / raw_valid else 0


  # Determine status
  if (pct_loss > threshold_error) {
    status <- "error"
    message <- sprintf("%.1f%% coverage loss (%d of %d values)",
                       pct_loss * 100, diff, raw_valid)
  } else if (pct_loss > threshold_warn) {
    status <- "warn"
    message <- sprintf("%.2f%% coverage loss (%d values)", pct_loss * 100, diff)
  } else if (pct_loss < -threshold_warn) {
    # More harmonized than raw - something very wrong
    status <- "error"
    message <- sprintf("Gained %d values (harmonized > raw) - check logic", -diff)
  } else {
    status <- "ok"
    message <- sprintf("Coverage OK (%d/%d = %.1f%%)",
                       harmonized_valid, raw_valid,
                       if (raw_valid > 0) harmonized_valid/raw_valid*100 else 100)
  }

  list(
    status = status,
    check = "coverage",
    raw_valid = raw_valid,
    harmonized_valid = harmonized_valid,
    diff = diff,
    pct_loss = pct_loss,
    message = message
  )
}


#' Validate transformation correctness via correlation
#'
#' For identity transforms, correlation should be ~1.0
#' For reversals, correlation should be ~-1.0
#' For scale conversions, Spearman correlation should be ~±1.0
#'
#' @param raw_vec Raw source vector
#' @param harmonized_vec Harmonized vector
#' @param method Character: "identity", "reverse", or "scale_convert"
#' @param threshold Correlation threshold (default 0.99)
#' @return List with status, correlation, and message
validate_transformation <- function(raw_vec, harmonized_vec,
                                    method = "identity",
                                    threshold = 0.99) {

  # Convert to numeric if possible (handles factors, characters)
  raw_numeric <- suppressWarnings(as.numeric(raw_vec))
  harm_numeric <- suppressWarnings(as.numeric(harmonized_vec))

  # Check if we have valid numeric data
  if (all(is.na(raw_numeric)) || all(is.na(harm_numeric))) {
    return(list(
      status = "skip",
      check = "transformation",
      method = method,
      pearson = NA,
      spearman = NA,
      message = "Non-numeric variable (skipping correlation check)"
    ))
  }

  # Compute correlations
  pearson <- suppressWarnings(
    cor(raw_numeric, harm_numeric, use = "complete.obs", method = "pearson")
  )
  spearman <- suppressWarnings(
    cor(raw_numeric, harm_numeric, use = "complete.obs", method = "spearman")
  )

  # Handle insufficient data

if (is.na(pearson) || is.na(spearman)) {
    return(list(
      status = "warn",
      check = "transformation",
      method = method,
      pearson = pearson,
      spearman = spearman,
      message = "Insufficient data for correlation"
    ))
  }

  # Check based on expected transformation
  if (method == "identity") {
    expected_sign <- 1
    actual <- pearson
    check_desc <- "identity (r ≈ +1)"
  } else if (method == "reverse") {
    expected_sign <- -1
    actual <- pearson
    check_desc <- "reversal (r ≈ -1)"
  } else {
    # Scale conversion - use Spearman (monotonic relationship)
    expected_sign <- 1  # Could be -1 if also reversed
    actual <- abs(spearman)  # Check monotonicity regardless of direction
    check_desc <- "scale conversion (|ρ| ≈ 1)"
  }

  # Determine status
  if (method %in% c("identity", "reverse")) {
    correct <- (actual * expected_sign) > threshold
  } else {
    correct <- actual > threshold
  }

  if (correct) {
    status <- "ok"
    message <- sprintf("%s: r=%.3f, ρ=%.3f ✓", check_desc, pearson, spearman)
  } else {
    status <- "error"
    message <- sprintf("%s FAILED: r=%.3f, ρ=%.3f (expected %s%.2f)",
                       check_desc, pearson, spearman,
                       if (expected_sign == 1) ">" else "<",
                       threshold * expected_sign)
  }

  list(
    status = status,
    check = "transformation",
    method = method,
    pearson = pearson,
    spearman = spearman,
    message = message
  )
}

prepare_group_vec <- function(raw_data, group_by) {
  if (is.null(group_by) || length(group_by) == 0) {
    return(NULL)
  }

  group_vars <- as.character(group_by)
  missing_vars <- setdiff(group_vars, names(raw_data))
  if (length(missing_vars) > 0) {
    return(NULL)
  }

  group_list <- lapply(group_vars, function(g) {
    gv <- raw_data[[g]]
    if (inherits(gv, "haven_labelled")) {
      gv <- haven::zap_labels(gv)
    }
    gv
  })

  if (length(group_list) == 1) {
    return(group_list[[1]])
  }

  interaction(group_list, drop = TRUE, sep = "|")
}

validate_transformation_abs <- function(raw_vec, harmonized_vec,
                                        threshold = 0.99) {
  raw_numeric <- suppressWarnings(as.numeric(raw_vec))
  harm_numeric <- suppressWarnings(as.numeric(harmonized_vec))

  if (all(is.na(raw_numeric)) || all(is.na(harm_numeric))) {
    return(list(
      status = "skip",
      check = "transformation",
      method = "abs",
      pearson = NA,
      spearman = NA,
      message = "Non-numeric variable (skipping correlation check)"
    ))
  }

  pearson <- suppressWarnings(
    cor(raw_numeric, harm_numeric, use = "complete.obs", method = "pearson")
  )
  spearman <- suppressWarnings(
    cor(raw_numeric, harm_numeric, use = "complete.obs", method = "spearman")
  )

  if (is.na(pearson) || is.na(spearman)) {
    return(list(
      status = "warn",
      check = "transformation",
      method = "abs",
      pearson = pearson,
      spearman = spearman,
      message = "Insufficient data for correlation check"
    ))
  }

  if (abs(pearson) > threshold && abs(spearman) > threshold) {
    status <- "ok"
    message <- sprintf("Grouped |r|=%.3f, |ρ|=%.3f ✓", pearson, spearman)
  } else {
    status <- "error"
    message <- sprintf("Grouped FAILED: |r|=%.3f, |ρ|=%.3f (expected >%.2f)",
                       pearson, spearman, threshold)
  }

  list(
    status = status,
    check = "transformation",
    method = "abs",
    pearson = pearson,
    spearman = spearman,
    message = message
  )
}

validate_transformation_grouped <- function(raw_vec, harmonized_vec, group_vec,
                                            method = "identity",
                                            threshold = 0.99,
                                            allow_reverse = FALSE) {
  groups <- unique(group_vec[!is.na(group_vec)])
  if (length(groups) == 0) {
    return(list(
      status = "skip",
      check = "transformation",
      method = method,
      message = "No groups with data (skipping grouped transformation)"
    ))
  }

  results <- lapply(groups, function(g) {
    idx <- group_vec == g
    if (allow_reverse) {
      validate_transformation_abs(raw_vec[idx], harmonized_vec[idx], threshold)
    } else {
      validate_transformation(raw_vec[idx], harmonized_vec[idx], method, threshold)
    }
  })

  statuses <- vapply(results, function(r) r$status %||% "skip", character(1))
  n_error <- sum(statuses == "error")
  n_warn <- sum(statuses == "warn")
  n_ok <- sum(statuses == "ok")
  n_skip <- sum(statuses == "skip")

  if (n_error > 0) {
    status <- "error"
  } else if (n_warn > 0) {
    status <- "warn"
  } else if (n_ok > 0) {
    status <- "ok"
  } else {
    status <- "skip"
  }

  err_groups <- groups[statuses == "error"]
  err_preview <- if (length(err_groups) > 0) {
    paste(head(err_groups, 5), collapse = ", ")
  } else {
    ""
  }

  message <- sprintf(
    "Grouped transformation by group: ok=%d, warn=%d, error=%d, skip=%d%s",
    n_ok, n_warn, n_error, n_skip,
    if (nzchar(err_preview)) sprintf(" (examples: %s)", err_preview) else ""
  )

  list(
    status = status,
    check = "transformation",
    method = method,
    message = message
  )
}


#' Create and validate crosstab of raw vs harmonized values
#'
#' Each raw value should map to exactly one harmonized value (or NA).
#' Detects if multiple raw values incorrectly collapse to same output.
#'
#' @param raw_vec Raw source vector
#' @param harmonized_vec Harmonized vector
#' @param missing_codes Codes that should map to NA
#' @return List with status, crosstab, and message
validate_crosstab <- function(raw_vec, harmonized_vec, missing_codes = c()) {

  # Skip if too many unique values (continuous/weight-like variables)
  raw_unique <- length(unique(raw_vec[!is.na(raw_vec)]))
  harm_unique <- length(unique(harmonized_vec[!is.na(harmonized_vec)]))
  if (raw_unique > 100 || harm_unique > 100) {
    return(list(
      status = "skip",
      check = "crosstab",
      n_raw_values = raw_unique,
      multi_output = tibble::tibble(),
      missing_leaked = FALSE,
      crosstab = NULL,
      message = sprintf("Skipped crosstab (too many unique values: raw=%d, harmonized=%d)",
                        raw_unique, harm_unique)
    ))
  }

  # Build crosstab
  df <- tibble::tibble(
    raw = raw_vec,
    harmonized = harmonized_vec
  ) %>%
    dplyr::filter(!is.na(raw))  # Only consider non-NA raw values

  # Get mapping: which harmonized value(s) does each raw value produce?
  mapping <- df %>%
    dplyr::group_by(raw) %>%
    dplyr::summarise(
      harmonized_values = list(unique(harmonized)),
      n_outputs = length(unique(harmonized)),
      .groups = "drop"
    )

  # Check for one-to-many mappings (excluding NA)
  multi_output <- mapping %>%
    dplyr::filter(n_outputs > 1) %>%
    dplyr::filter(!all(sapply(harmonized_values, function(x) all(is.na(x)))))

  # Check for missing codes that didn't become NA
  if (length(missing_codes) > 0) {
    missing_not_na <- df %>%
      dplyr::filter(raw %in% missing_codes, !is.na(harmonized))
    missing_leaked <- nrow(missing_not_na) > 0
  } else {
    missing_leaked <- FALSE
  }

  # Create frequency crosstab for report
  crosstab <- df %>%
    dplyr::count(raw, harmonized) %>%
    tidyr::pivot_wider(
      names_from = harmonized,
      values_from = n,
      values_fill = 0,
      names_repair = "unique"
    )

  # Determine status
  issues <- c()
  if (nrow(multi_output) > 0) {
    issues <- c(issues, sprintf("%d raw values map to multiple outputs", nrow(multi_output)))
  }
  if (missing_leaked) {
    issues <- c(issues, "Missing codes not converted to NA")
  }

  if (length(issues) == 0) {
    status <- "ok"
    message <- sprintf("Crosstab OK: %d unique raw values", nrow(mapping))
  } else {
    status <- "error"
    message <- paste(issues, collapse = "; ")
  }

  list(
    status = status,
    check = "crosstab",
    n_raw_values = nrow(mapping),
    multi_output = multi_output,
    missing_leaked = missing_leaked,
    crosstab = crosstab,
    message = message
  )
}

validate_crosstab_grouped <- function(raw_vec, harmonized_vec, group_vec,
                                      missing_codes = c()) {
  groups <- unique(group_vec[!is.na(group_vec)])
  if (length(groups) == 0) {
    return(list(
      status = "skip",
      check = "crosstab",
      message = "No groups with data (skipping grouped crosstab)"
    ))
  }

  results <- lapply(groups, function(g) {
    idx <- group_vec == g
    validate_crosstab(raw_vec[idx], harmonized_vec[idx], missing_codes)
  })

  statuses <- vapply(results, function(r) r$status %||% "skip", character(1))
  n_error <- sum(statuses == "error")
  n_ok <- sum(statuses == "ok")
  n_skip <- sum(statuses == "skip")

  status <- if (n_error > 0) "error" else if (n_ok > 0) "ok" else "skip"

  err_groups <- groups[statuses == "error"]
  err_preview <- if (length(err_groups) > 0) {
    paste(head(err_groups, 5), collapse = ", ")
  } else {
    ""
  }

  message <- sprintf(
    "Grouped crosstab by group: ok=%d, error=%d, skip=%d%s",
    n_ok, n_error, n_skip,
    if (nzchar(err_preview)) sprintf(" (examples: %s)", err_preview) else ""
  )

  list(
    status = status,
    check = "crosstab",
    message = message
  )
}


#' Validate range bounds of harmonized values
#'
#' @param harmonized_vec Harmonized vector
#' @param valid_range Numeric vector c(min, max)
#' @return List with status and message
validate_range <- function(harmonized_vec, valid_range) {

  if (is.null(valid_range) || length(valid_range) != 2) {
    return(list(
      status = "warn",
      check = "range",
      message = "No valid_range specified in YAML"
    ))
  }

  # Count out-of-range values (excluding NA)
  out_of_range <- sum(
    !is.na(harmonized_vec) &
    (harmonized_vec < valid_range[1] | harmonized_vec > valid_range[2])
  )

  if (out_of_range == 0) {
    status <- "ok"
    message <- sprintf("All values in range [%s, %s]", valid_range[1], valid_range[2])
  } else {
    status <- "error"
    message <- sprintf("%d values outside range [%s, %s]",
                       out_of_range, valid_range[1], valid_range[2])
  }

  list(
    status = status,
    check = "range",
    out_of_range = out_of_range,
    valid_range = valid_range,
    message = message
  )
}


#' Run all validation checks for one variable in one wave
#'
#' @param raw_data Data frame for the wave (raw)
#' @param harmonized_data Data frame with harmonized values for this wave
#' @param var_spec Variable specification from YAML
#' @param wave_name Wave name (e.g., "w1")
#' @param missing_codes Codes to treat as missing
#' @return List with all validation results
validate_variable_wave <- function(raw_data, harmonized_data, var_spec,
                                   wave_name, missing_codes = c()) {

  var_id <- var_spec$id
  source_var <- var_spec$source[[wave_name]]

  # Check if source variable exists in this wave
  if (is.null(source_var) || !source_var %in% names(raw_data)) {
    return(list(
      var_id = var_id,
      wave = wave_name,
      status = "skip",
      message = sprintf("Source variable '%s' not in wave", source_var %||% "NULL"),
      checks = list()
    ))
  }

  # Check if harmonized variable exists
  if (!var_id %in% names(harmonized_data)) {
    return(list(
      var_id = var_id,
      wave = wave_name,
      status = "error",
      message = sprintf("Harmonized variable '%s' not found in output", var_id),
      checks = list()
    ))
  }

  # Extract vectors
  raw_vec <- raw_data[[source_var]]
  harmonized_vec <- harmonized_data[[var_id]]

  if (length(harmonized_vec) != length(raw_vec)) {
    return(list(
      var_id = var_id,
      wave = wave_name,
      source_var = source_var,
      transform_type = NA_character_,
      status = "error",
      checks = list(
        length_check = list(
          status = "error",
          check = "length",
          message = sprintf(
            "Length mismatch: raw=%d, harmonized=%d",
            length(raw_vec), length(harmonized_vec)
          )
        )
      )
    ))
  }

  # Convert haven_labelled if needed
  if (inherits(raw_vec, "haven_labelled")) {
    raw_vec <- as.numeric(haven::zap_labels(raw_vec))
  }

  # Determine transformation method (align with harmonize_variable)
  default_rule <- var_spec$harmonize$default %||% list(method = "identity")
  wave_rule <- var_spec$harmonize$by_wave[[wave_name]] %||%
               var_spec$harmonize$exceptions[[wave_name]] %||%
               var_spec$harmonize[[wave_name]] %||%
               default_rule

  wave_method <- wave_rule$method %||% default_rule$method %||% "identity"
  fn_name <- wave_rule$fn %||% ""

  if (wave_method == "identity") {
    transform_type <- "identity"
  } else if (wave_method %in% c("recode", "derive")) {
    transform_type <- "skip"
  } else if (grepl("reverse", fn_name, ignore.case = TRUE)) {
    transform_type <- "reverse"
  } else {
    transform_type <- "scale_convert"
  }

  # Get valid range
  valid_range <- var_spec$qc$valid_range_by_wave[[wave_name]] %||%
                 var_spec$qc$valid_range %||%
                 NULL

  # Get variable type (nominal variables skip correlation validation)
  var_type <- var_spec$type %||% "ordinal"
  is_nominal <- var_type == "nominal"

  group_by <- var_spec$qc$group_by %||% NULL
  group_vec <- NULL
  if (!is.null(group_by)) {
    group_vec <- prepare_group_vec(raw_data, group_by)
  }

  raw_vec_check <- raw_vec
  raw_for_coverage <- raw_vec
  crosstab_missing_codes <- missing_codes

  if (wave_method == "derive" && nzchar(fn_name) && exists(fn_name, mode = "function")) {
    raw_vec_check <- get(fn_name, mode = "function")(
      data = raw_data,
      wave_name = wave_name,
      sources = wave_rule$sources %||% NULL
    )
    raw_for_coverage <- raw_vec_check
    crosstab_missing_codes <- numeric(0)
  }

  skip_transform_check <- isTRUE(var_spec$qc$skip_transformation_check)
  skip_coverage_check <- isTRUE(var_spec$qc$skip_coverage_check)
  skip_crosstab_check <- isTRUE(var_spec$qc$skip_crosstab_check)
  allow_reverse <- isTRUE(var_spec$qc$transformation_allow_reverse)

  # Run all checks
  # Skip transformation (correlation) check for nominal/categorical variables
  skip_transform_fns <- c(
    "extract_month_from_date",
    "extract_year_from_date",
    "collapse_5pt_leader_to_3pt",
    "collapse_10pt_to_6pt",
    "collapse_5pt_to_4pt_then_reverse",
    "collapse_6pt_to_4pt_reverse",
    "safe_6pt_to_4pt",
    "recode_w1_discuss",
    "recode_w6_corruption",
    "middle_identity_5pt",
    "middle_reverse_5pt"
  )
  if (is_nominal) {
    transformation_result <- list(
      status = "skip",
      check = "transformation",
      message = "Skipped: nominal/categorical variable (correlation not meaningful)"
    )
  } else if (skip_transform_check) {
    transformation_result <- list(
      status = "skip",
      check = "transformation",
      message = "Skipped: skip_transformation_check set in YAML"
    )
  } else if (transform_type == "skip" || fn_name %in% skip_transform_fns) {
    transformation_result <- list(
      status = "skip",
      check = "transformation",
      message = "Skipped: transformation not monotonic or not comparable"
    )
  } else if (!is.null(group_vec)) {
    transformation_result <- validate_transformation_grouped(
      raw_vec_check,
      harmonized_vec,
      group_vec,
      method = transform_type,
      allow_reverse = allow_reverse
    )
  } else {
    transformation_result <- validate_transformation(raw_vec_check, harmonized_vec, transform_type)
  }

  coverage_missing_codes <- missing_codes
  if (!is.null(var_spec$qc[["coverage_missing_codes"]])) {
    coverage_missing_codes <- unique(c(
      coverage_missing_codes,
      as.numeric(var_spec$qc[["coverage_missing_codes"]])
    ))
  }
  if (!is.null(var_spec$qc[["coverage_missing_codes_by_wave"]][[wave_name]])) {
    coverage_missing_codes <- unique(c(
      coverage_missing_codes,
      as.numeric(var_spec$qc[["coverage_missing_codes_by_wave"]][[wave_name]])
    ))
  }
  if (wave_method == "derive") {
    coverage_missing_codes <- numeric(0)
  }
  if (wave_method == "recode" && !is.null(wave_rule$mapping)) {
    mapping <- wave_rule$mapping
    drop_mask <- vapply(
      mapping,
      function(v) is.null(v) || (length(v) == 1 && is.na(v)),
      logical(1)
    )
    if (any(drop_mask)) {
      drop_codes <- suppressWarnings(as.numeric(names(mapping)[drop_mask]))
      drop_codes <- drop_codes[!is.na(drop_codes)]
      coverage_missing_codes <- unique(c(coverage_missing_codes, drop_codes))
    }
  }

  if (fn_name %in% c("extract_month_from_date", "extract_year_from_date")) {
    if (exists(fn_name, mode = "function")) {
      raw_for_coverage <- get(fn_name, mode = "function")(
        raw_vec,
        data = raw_data,
        var_name = source_var
      )
    }
  }

  range_result <- if (isTRUE(var_spec$qc$skip_range_check)) {
    list(
      status = "skip",
      check = "range",
      message = "Skipped: skip_range_check set in YAML"
    )
  } else {
    validate_range(harmonized_vec, valid_range)
  }

  checks <- list(
    coverage = if (skip_coverage_check) {
      list(
        status = "skip",
        check = "coverage",
        message = "Skipped: skip_coverage_check set in YAML"
      )
    } else {
      validate_coverage(raw_for_coverage, harmonized_vec, coverage_missing_codes)
    },
    transformation = transformation_result,
    range = range_result,
    crosstab = if (skip_crosstab_check) {
      list(
        status = "skip",
        check = "crosstab",
        message = "Skipped: skip_crosstab_check set in YAML"
      )
    } else if (!is.null(group_vec)) {
      validate_crosstab_grouped(raw_vec_check, harmonized_vec, group_vec, crosstab_missing_codes)
    } else {
      validate_crosstab(raw_vec_check, harmonized_vec, crosstab_missing_codes)
    }
  )

  # Aggregate status
  statuses <- sapply(checks, function(x) x$status)
  if (any(statuses == "error")) {
    overall_status <- "error"
  } else if (any(statuses == "warn")) {
    overall_status <- "warn"
  } else {
    overall_status <- "ok"
  }

  list(
    var_id = var_id,
    wave = wave_name,
    source_var = source_var,
    transform_type = transform_type,
    status = overall_status,
    checks = checks
  )
}


#' Generate validation summary table
#'
#' @param results List of validation results from validate_variable_wave()
#' @return Tibble with summary
generate_validation_summary <- function(results) {

  purrr::map_dfr(results, function(r) {
    tibble::tibble(
      var_id = r$var_id,
      wave = r$wave,
      source = r$source_var %||% NA_character_,
      transform = r$transform_type %||% NA_character_,
      status = r$status,
      coverage = r$checks$coverage$status %||% NA_character_,
      transformation = r$checks$transformation$status %||% NA_character_,
      range = r$checks$range$status %||% NA_character_,
      crosstab = r$checks$crosstab$status %||% NA_character_
    )
  })
}


#' Generate markdown validation report
#'
#' @param results List of validation results
#' @param output_path Path to write markdown file
#' @return Invisibly returns the report content
generate_validation_report <- function(results, output_path = NULL) {

  summary_df <- generate_validation_summary(results)

  # Count by status
  status_counts <- summary_df %>%
    dplyr::count(status)

  n_ok <- status_counts$n[status_counts$status == "ok"] %||% 0
  n_warn <- status_counts$n[status_counts$status == "warn"] %||% 0
  n_error <- status_counts$n[status_counts$status == "error"] %||% 0
  n_skip <- status_counts$n[status_counts$status == "skip"] %||% 0

  # Build report
  lines <- c(
    "# Harmonization Validation Report",
    "",
    sprintf("Generated: %s", Sys.time()),
    "",
    "## Summary",
    "",
    sprintf("- ✅ OK: %d", n_ok),
    sprintf("- ⚠️ Warnings: %d", n_warn),
    sprintf("- ❌ Errors: %d", n_error),
    sprintf("- ⏭️ Skipped: %d", n_skip),
    "",
    "## Results by Variable",
    ""
  )

  # Group by variable
  vars <- unique(summary_df$var_id)

  for (var in vars) {
    var_results <- summary_df %>% dplyr::filter(var_id == var)

    # Overall status for this variable
    var_status <- if (any(var_results$status == "error")) {
      "❌"
    } else if (any(var_results$status == "warn")) {
      "⚠️"
    } else {
      "✅"
    }

    lines <- c(lines, sprintf("### %s %s", var_status, var))
    lines <- c(lines, "")
    lines <- c(lines, "| Wave | Source | Transform | Coverage | Transform | Range | Crosstab |")
    lines <- c(lines, "|------|--------|-----------|----------|-----------|-------|----------|")

    for (i in seq_len(nrow(var_results))) {
      row <- var_results[i, ]
      status_icon <- function(s) {
        dplyr::case_when(
          s == "ok" ~ "✅",
          s == "warn" ~ "⚠️",
          s == "error" ~ "❌",
          s == "skip" ~ "⏭️",
          TRUE ~ "?"
        )
      }

      lines <- c(lines, sprintf(
        "| %s | %s | %s | %s | %s | %s | %s |",
        row$wave,
        row$source %||% "-",
        row$transform %||% "-",
        status_icon(row$coverage),
        status_icon(row$transformation),
        status_icon(row$range),
        status_icon(row$crosstab)
      ))
    }

    lines <- c(lines, "")
  }

  # Add details for errors and warnings
  problem_results <- results[sapply(results, function(r) r$status %in% c("error", "warn"))]

  if (length(problem_results) > 0) {
    lines <- c(lines, "## Issues Detail", "")

    for (r in problem_results) {
      lines <- c(lines, sprintf("### %s (%s)", r$var_id, r$wave))
      lines <- c(lines, "")

      for (check_name in names(r$checks)) {
        check <- r$checks[[check_name]]
        if (check$status %in% c("error", "warn")) {
          icon <- if (check$status == "error") "❌" else "⚠️"
          lines <- c(lines, sprintf("- %s **%s**: %s", icon, check_name, check$message))
        }
      }

      lines <- c(lines, "")
    }
  }

  report <- paste(lines, collapse = "\n")

  if (!is.null(output_path)) {
    writeLines(report, output_path)
    cat(sprintf("Report saved to: %s\n", output_path))
  }

  invisible(report)
}


# ==============================================================================
# NULL COALESCING OPERATOR
# ==============================================================================

`%||%` <- function(a, b) if (!is.null(a)) a else b


message("✓ Loaded validation functions (enhanced with harmonization validation)")
