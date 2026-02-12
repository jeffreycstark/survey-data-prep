# R/utils/data_prep_helpers.R
# Helper functions for data preparation pipeline
# Reduces code duplication in 02_data_preparation scripts

library(tidyverse)
library(psych)
library(assertr)
library(glue)

# ==============================================================================
# RELIABILITY & COMPOSITE CREATION
# ==============================================================================

#' Calculate reliability and create validated composite
#'
#' @param data Dataframe
#' @param vars Character vector of variable names
#' @param composite_name Name for the composite variable
#' @param min_alpha Minimum acceptable Cronbach's alpha (default 0.60)
#' @param method "cronbach" or "spearman_brown" (for 2-item scales)
#' @param min_valid Minimum valid items required (default = all)
#' @return Dataframe with new composite variable added
create_validated_composite <- function(data,
                                      vars,
                                      composite_name,
                                      min_alpha = 0.60,
                                      method = "cronbach",
                                      min_valid = NULL) {

  # Calculate reliability
  if (method == "cronbach") {
    alpha_result <- psych::alpha(data[vars], check.keys = FALSE)
    alpha_value <- alpha_result$total$raw_alpha

    # Hard validation
    if (alpha_value < min_alpha) {
      warning(glue::glue(
        "⚠ {composite_name}: Cronbach's α = {round(alpha_value, 3)} below threshold {min_alpha}"
      ))
    } else {
      cat(glue::glue("✓ {composite_name}: α = {round(alpha_value, 3)}\n"))
    }

  } else if (method == "spearman_brown") {
    # For 2-item scales
    if (length(vars) != 2) stop("Spearman-Brown requires exactly 2 items")

    cor_matrix <- cor(data[vars], use = "pairwise.complete.obs")
    r <- cor_matrix[1, 2]
    alpha_value <- (2 * r) / (1 + r)

    if (alpha_value < min_alpha) {
      warning(glue::glue(
        "⚠ {composite_name}: Spearman-Brown = {round(alpha_value, 3)} below threshold {min_alpha}"
      ))
    } else {
      cat(glue::glue("✓ {composite_name}: Spearman-Brown = {round(alpha_value, 3)}\n"))
    }
  }

  # Create composite
  if (is.null(min_valid)) min_valid <- length(vars)

  data %>%
    rowwise() %>%
    mutate(
      !!composite_name := if_else(
        sum(!is.na(c_across(all_of(vars)))) >= min_valid,
        mean(c_across(all_of(vars)), na.rm = TRUE),
        NA_real_
      )
    ) %>%
    ungroup()
}

# ==============================================================================
# MISSING DATA REPORTING
# ==============================================================================

#' Generate missing data report for variables
#'
#' @param data Dataframe
#' @param vars Character vector of variable names
#' @param by_country Logical, stratify by country_name? (default TRUE)
#' @param label Optional label for the report section
report_missing <- function(data, vars, by_country = TRUE, label = NULL) {

  if (!is.null(label)) {
    cat("\n", rep("=", 60), "\n", sep = "")
    cat("MISSING DATA:", label, "\n")
    cat(rep("=", 60), "\n\n")
  }

  if (by_country && "country_name" %in% names(data)) {
    missing_summary <- data %>%
      group_by(country_name) %>%
      summarise(
        across(
          all_of(vars),
          ~ round(mean(is.na(.)) * 100, 1),
          .names = "{.col}_pct_missing"
        )
      )

    print(missing_summary)

  } else {
    missing_summary <- data %>%
      summarise(
        across(
          all_of(vars),
          ~ round(mean(is.na(.)) * 100, 1),
          .names = "{.col}_pct_missing"
        )
      )

    print(t(missing_summary))
  }

  invisible(missing_summary)
}

# ==============================================================================
# VALIDATION HELPERS
# ==============================================================================

#' Hard validation: Check values are within expected range
#'
#' @param data Dataframe
#' @param vars Character vector of variable names to check
#' @param min Minimum valid value
#' @param max Maximum valid value
#' @param label Optional label for error message
validate_range <- function(data, vars, min, max, label = NULL) {

  for (var in vars) {
    if (!var %in% names(data)) {
      stop(glue::glue("Variable {var} not found in data"))
    }

    invalid <- data %>%
      filter(!is.na(!!sym(var))) %>%
      filter(!!sym(var) < min | !!sym(var) > max)

    if (nrow(invalid) > 0) {
      msg <- if (!is.null(label)) {
        glue::glue("❌ {label}: {var} has {nrow(invalid)} values outside [{min}, {max}]")
      } else {
        glue::glue("❌ {var} has {nrow(invalid)} values outside [{min}, {max}]")
      }
      stop(msg)
    }
  }

  cat(glue::glue("✓ All {length(vars)} variables in valid range [{min}, {max}]\n"))
  invisible(TRUE)
}

#' Batch verify recoding worked correctly
#'
#' @param data Dataframe
#' @param original_vars Character vector of original variable names
#' @param recoded_vars Character vector of recoded variable names
#' @param expected_reversal Logical, should values be reversed?
verify_recoding <- function(data, original_vars, recoded_vars, expected_reversal = TRUE) {

  if (length(original_vars) != length(recoded_vars)) {
    stop("Number of original and recoded variables must match")
  }

  for (i in seq_along(original_vars)) {
    orig <- original_vars[i]
    recode <- recoded_vars[i]

    # Check that valid values were transformed
    n_valid_orig <- sum(!is.na(data[[orig]]))
    n_valid_recode <- sum(!is.na(data[[recode]]))

    if (expected_reversal) {
      # For reversal, check that 1<->4 swap occurred
      sample_check <- data %>%
        filter(!is.na(!!sym(orig)), !is.na(!!sym(recode))) %>%
        slice_head(n = 100) %>%
        mutate(
          sum_check = !!sym(orig) + !!sym(recode)
        )

      # For 4-point scale: orig + recoded should = 5
      # For 3-point scale: orig + recoded should = 4
      expected_sum <- max(data[[orig]], na.rm = TRUE) + 1

      if (!all(abs(sample_check$sum_check - expected_sum) < 0.01, na.rm = TRUE)) {
        warning(glue::glue("⚠ Reversal check failed for {orig} -> {recode}"))
      }
    }

    cat(glue::glue("✓ {orig} -> {recode}: {n_valid_orig} -> {n_valid_recode} valid values\n"))
  }

  invisible(TRUE)
}

# ==============================================================================
# NORMALIZATION HELPERS
# ==============================================================================

#' Min-Max normalization to 0-1 scale
#'
#' @param x Numeric vector
#' @return Normalized vector (0-1 scale)
normalize_0_1 <- function(x) {
  (x - min(x, na.rm = TRUE)) / (max(x, na.rm = TRUE) - min(x, na.rm = TRUE))
}

#' Z-score standardization
#'
#' @param x Numeric vector
#' @return Standardized vector (mean=0, sd=1)
standardize_z <- function(x) {
  (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE)
}

# ==============================================================================
# BATCH OPERATIONS
# ==============================================================================

#' Clean missing codes across multiple variables
#'
#' @param data Dataframe
#' @param vars Character vector of variable names
#' @param missing_codes Numeric vector of codes to convert to NA
#' @return Dataframe with missing codes replaced
batch_clean_missing <- function(data, vars, missing_codes = c(-1, 0, 7, 8, 9)) {
  data %>%
    mutate(
      across(
        all_of(vars),
        ~ if_else(.x %in% missing_codes, NA_real_, .x)
      )
    )
}

#' Create descriptive statistics table by country
#'
#' @param data Dataframe
#' @param vars Character vector of variable names
#' @param label Optional label for table title
describe_by_country <- function(data, vars, label = NULL) {

  if (!is.null(label)) {
    cat("\n", rep("=", 60), "\n", sep = "")
    cat("DESCRIPTIVES:", label, "\n")
    cat(rep("=", 60), "\n\n")
  }

  summary_table <- data %>%
    group_by(country_name) %>%
    summarise(
      N = n(),
      across(
        all_of(vars),
        list(
          mean = ~ round(mean(.x, na.rm = TRUE), 2),
          sd = ~ round(sd(.x, na.rm = TRUE), 2),
          min = ~ round(min(.x, na.rm = TRUE), 2),
          max = ~ round(max(.x, na.rm = TRUE), 2)
        ),
        .names = "{.col}_{.fn}"
      )
    )

  print(summary_table)
  invisible(summary_table)
}
