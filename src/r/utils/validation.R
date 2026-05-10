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


#' Validate type stability of harmonized values
#'
#' Catches silent coercion of declared-ordinal variables to non-integer numeric.
#' Compares observed storage of `harmonized_vec` against the YAML-declared
#' `type:` and reports mismatches.
#'
#' Rules:
#'   - ordinal / binary: integer storage OR numeric storage where every non-NA
#'     value is whole (|x - round(x)| < 1e-9). Out-of-range values are not
#'     enforced here — that's E4's level-preservation check.
#'   - categorical / nominal: integer or character storage (factor accepted).
#'   - continuous: any numeric storage; status = ok.
#'   - unknown declared_type: status = warn (not error — keeps E3 forward-
#'     compatible if new type strings appear in YAML before the schema lists
#'     them).
#'
#' @param harmonized_vec Harmonized vector
#' @param declared_type Character: "ordinal", "nominal", "continuous", "binary",
#'   "categorical"
#' @return List with status, check, declared_type, observed_storage, message
validate_type_stability <- function(harmonized_vec, declared_type) {

  observed_storage <- if (is.factor(harmonized_vec)) {
    "factor"
  } else if (is.integer(harmonized_vec)) {
    "integer"
  } else if (is.character(harmonized_vec)) {
    "character"
  } else if (is.logical(harmonized_vec)) {
    "logical"
  } else if (is.numeric(harmonized_vec)) {
    "numeric"
  } else {
    typeof(harmonized_vec)
  }

  declared_type <- tolower(as.character(declared_type %||% "ordinal"))

  is_whole_numeric <- function(x) {
    x_nonna <- x[!is.na(x)]
    if (length(x_nonna) == 0) return(TRUE)
    if (!is.numeric(x_nonna)) return(FALSE)
    all(abs(x_nonna - round(x_nonna)) < 1e-9)
  }

  if (declared_type %in% c("ordinal", "binary")) {
    if (observed_storage == "integer") {
      return(list(
        status = "ok", check = "type_stability",
        declared_type = declared_type, observed_storage = observed_storage,
        message = sprintf("Type OK: declared=%s, storage=integer",
                          declared_type)
      ))
    }
    if (observed_storage == "numeric") {
      if (is_whole_numeric(harmonized_vec)) {
        return(list(
          status = "ok", check = "type_stability",
          declared_type = declared_type, observed_storage = observed_storage,
          message = sprintf(
            "Type OK: declared=%s, storage=numeric (all values whole)",
            declared_type
          )
        ))
      }
      n_fractional <- sum(
        !is.na(harmonized_vec) &
          abs(harmonized_vec - round(harmonized_vec)) >= 1e-9
      )
      return(list(
        status = "error", check = "type_stability",
        declared_type = declared_type, observed_storage = observed_storage,
        message = sprintf(
          "Type MISMATCH: declared=%s but %d non-integer values present",
          declared_type, n_fractional
        )
      ))
    }
    if (observed_storage == "factor") {
      return(list(
        status = "ok", check = "type_stability",
        declared_type = declared_type, observed_storage = observed_storage,
        message = sprintf("Type OK: declared=%s, storage=factor",
                          declared_type)
      ))
    }
    return(list(
      status = "error", check = "type_stability",
      declared_type = declared_type, observed_storage = observed_storage,
      message = sprintf(
        "Type MISMATCH: declared=%s but storage is %s",
        declared_type, observed_storage
      )
    ))
  }

  if (declared_type %in% c("nominal", "categorical")) {
    if (observed_storage %in% c("integer", "character", "factor")) {
      return(list(
        status = "ok", check = "type_stability",
        declared_type = declared_type, observed_storage = observed_storage,
        message = sprintf("Type OK: declared=%s, storage=%s",
                          declared_type, observed_storage)
      ))
    }
    if (observed_storage == "numeric" && is_whole_numeric(harmonized_vec)) {
      return(list(
        status = "ok", check = "type_stability",
        declared_type = declared_type, observed_storage = observed_storage,
        message = sprintf(
          "Type OK: declared=%s, storage=numeric (all values whole)",
          declared_type
        )
      ))
    }
    return(list(
      status = "error", check = "type_stability",
      declared_type = declared_type, observed_storage = observed_storage,
      message = sprintf(
        "Type MISMATCH: declared=%s but storage is %s (expected integer/character/factor)",
        declared_type, observed_storage
      )
    ))
  }

  if (declared_type == "continuous") {
    if (observed_storage %in% c("integer", "numeric")) {
      return(list(
        status = "ok", check = "type_stability",
        declared_type = declared_type, observed_storage = observed_storage,
        message = sprintf("Type OK: declared=continuous, storage=%s",
                          observed_storage)
      ))
    }
    return(list(
      status = "error", check = "type_stability",
      declared_type = declared_type, observed_storage = observed_storage,
      message = sprintf(
        "Type MISMATCH: declared=continuous but storage is %s",
        observed_storage
      )
    ))
  }

  list(
    status = "warn", check = "type_stability",
    declared_type = declared_type, observed_storage = observed_storage,
    message = sprintf(
      "Unknown declared_type='%s' (cannot evaluate type stability)",
      declared_type
    )
  )
}


#' Validate level preservation of harmonized values (E4)
#'
#' Distinct from `validate_range`: that check verifies values fall within a
#' tolerance interval defined by `qc.valid_range`; this check verifies that the
#' observed level SET of an ordinal/binary variable matches its declared
#' `scale.min:scale.max`. The difference matters — a 4-pt scale that returns
#' only {2, 3} is range-OK but level-sparse, which is worth surfacing for
#' human review (could be legitimate, could be a mapping bug that collapsed
#' two endpoints).
#'
#' Rules:
#'   - nominal / categorical: skip (level set is open by design).
#'   - continuous: skip (level concept doesn't apply).
#'   - ordinal / binary with declared min & max:
#'       * unexpected = setdiff(observed, min:max) → status = error.
#'       * else if observed levels < declared levels → status = warn (sparse).
#'       * else → status = ok.
#'   - missing scale_min / scale_max → skip ("scale.min/max not declared").
#'   - `qc$skip_level_preservation` honored upstream by the caller; this
#'     function does not see the spec, so the orchestrator branches before
#'     calling.
#'
#' @param harmonized_vec Harmonized vector
#' @param scale_min Declared scale minimum (numeric or NULL/NA)
#' @param scale_max Declared scale maximum (numeric or NULL/NA)
#' @param declared_type Character: "ordinal", "binary", "nominal",
#'   "categorical", "continuous". Drives the skip rules.
#' @return List with status, check, observed_levels, declared_range,
#'   n_unexpected, message
validate_level_preservation <- function(harmonized_vec,
                                        scale_min,
                                        scale_max,
                                        declared_type = "ordinal") {

  declared_type <- tolower(as.character(declared_type %||% "ordinal"))

  if (declared_type %in% c("nominal", "categorical")) {
    return(list(
      status = "skip", check = "level_preservation",
      observed_levels = NA_character_,
      declared_range = NA_character_,
      n_unexpected = 0L,
      message = sprintf("Skipped: declared_type='%s' (level set open by design)",
                        declared_type)
    ))
  }

  if (declared_type == "continuous") {
    return(list(
      status = "skip", check = "level_preservation",
      observed_levels = NA_character_,
      declared_range = NA_character_,
      n_unexpected = 0L,
      message = "Skipped: declared_type='continuous' (level concept N/A)"
    ))
  }

  if (is.null(scale_min) || is.null(scale_max) ||
      length(scale_min) == 0 || length(scale_max) == 0 ||
      is.na(scale_min) || is.na(scale_max)) {
    return(list(
      status = "skip", check = "level_preservation",
      observed_levels = NA_character_,
      declared_range = NA_character_,
      n_unexpected = 0L,
      message = "Skipped: scale.min/max not declared"
    ))
  }

  scale_min_num <- suppressWarnings(as.numeric(scale_min))
  scale_max_num <- suppressWarnings(as.numeric(scale_max))
  if (is.na(scale_min_num) || is.na(scale_max_num)) {
    return(list(
      status = "skip", check = "level_preservation",
      observed_levels = NA_character_,
      declared_range = NA_character_,
      n_unexpected = 0L,
      message = "Skipped: scale.min/max not numeric"
    ))
  }

  # Only meaningful for integer-stepped scales. If declared bounds aren't
  # whole, skip — level-set comparison against seq() would be ill-defined.
  if (abs(scale_min_num - round(scale_min_num)) > 1e-9 ||
      abs(scale_max_num - round(scale_max_num)) > 1e-9) {
    return(list(
      status = "skip", check = "level_preservation",
      observed_levels = NA_character_,
      declared_range = sprintf("[%s, %s]", scale_min_num, scale_max_num),
      n_unexpected = 0L,
      message = "Skipped: scale.min/max not integer-valued"
    ))
  }

  scale_min_int <- as.integer(round(scale_min_num))
  scale_max_int <- as.integer(round(scale_max_num))

  if (scale_max_int < scale_min_int) {
    return(list(
      status = "skip", check = "level_preservation",
      observed_levels = NA_character_,
      declared_range = sprintf("[%d, %d]", scale_min_int, scale_max_int),
      n_unexpected = 0L,
      message = "Skipped: scale.max < scale.min (malformed declaration)"
    ))
  }

  declared_levels <- seq.int(scale_min_int, scale_max_int)

  # Coerce to numeric for comparison; honor NA. Non-numeric storage → skip
  # (E3 already flags the type mismatch; level-set comparison would be moot).
  harm_num <- suppressWarnings(as.numeric(harmonized_vec))
  if (all(is.na(harm_num))) {
    return(list(
      status = "skip", check = "level_preservation",
      observed_levels = "",
      declared_range = sprintf("[%d, %d]", scale_min_int, scale_max_int),
      n_unexpected = 0L,
      message = "Skipped: harmonized vector all-NA (no observed levels)"
    ))
  }

  observed_levels <- sort(unique(harm_num[!is.na(harm_num)]))
  unexpected <- setdiff(observed_levels, declared_levels)

  obs_str <- paste(observed_levels, collapse = ",")
  decl_str <- sprintf("[%d, %d]", scale_min_int, scale_max_int)

  if (length(unexpected) > 0) {
    return(list(
      status = "error", check = "level_preservation",
      observed_levels = obs_str,
      declared_range = decl_str,
      n_unexpected = length(unexpected),
      unexpected_values = paste(unexpected, collapse = ","),
      message = sprintf(
        "%d observed value(s) outside declared %s: {%s}",
        length(unexpected), decl_str,
        paste(unexpected, collapse = ",")
      )
    ))
  }

  if (length(observed_levels) < length(declared_levels)) {
    missing_levels <- setdiff(declared_levels, observed_levels)
    return(list(
      status = "warn", check = "level_preservation",
      observed_levels = obs_str,
      declared_range = decl_str,
      n_unexpected = 0L,
      message = sprintf(
        "Sparse: observed %d of %d declared levels (missing: {%s})",
        length(observed_levels), length(declared_levels),
        paste(missing_levels, collapse = ",")
      )
    ))
  }

  list(
    status = "ok", check = "level_preservation",
    observed_levels = obs_str,
    declared_range = decl_str,
    n_unexpected = 0L,
    message = sprintf("All %d declared levels observed in %s",
                      length(declared_levels), decl_str)
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
# ============================================================================
# validate_variable_wave helpers (private; underscore-prefixed)
# Each helper does one thing so the orchestrator below reads top-to-bottom.
# ============================================================================

# Functions whose transformation can't be checked via correlation
# (categorical recodes, monotonicity-breaking collapses, date extracts).
.vvw_skip_transform_fns <- c(
  "extract_month_from_date", "extract_year_from_date",
  "collapse_5pt_leader_to_3pt", "collapse_10pt_to_6pt",
  "collapse_5pt_to_4pt_then_reverse", "collapse_6pt_to_4pt_reverse",
  "safe_6pt_to_4pt", "recode_w1_discuss", "recode_w6_corruption",
  "middle_identity_5pt", "middle_reverse_5pt"
)

# Existence + length preflight. Returns a complete early-result list
# if validation can't proceed, or NULL to signal "continue".
.vvw_preflight <- function(raw_data, harmonized_data, var_spec, wave_name) {
  var_id <- var_spec$id
  source_var <- var_spec$source[[wave_name]]

  if (is.null(source_var) || !source_var %in% names(raw_data)) {
    return(list(
      var_id = var_id, wave = wave_name, status = "skip",
      message = sprintf("Source variable '%s' not in wave", source_var %||% "NULL"),
      checks = list()
    ))
  }
  if (!var_id %in% names(harmonized_data)) {
    return(list(
      var_id = var_id, wave = wave_name, status = "error",
      message = sprintf("Harmonized variable '%s' not found in output", var_id),
      checks = list()
    ))
  }
  raw_n <- length(raw_data[[source_var]])
  harm_n <- length(harmonized_data[[var_id]])
  if (raw_n != harm_n) {
    return(list(
      var_id = var_id, wave = wave_name, source_var = source_var,
      transform_type = NA_character_, status = "error",
      checks = list(length_check = list(
        status = "error", check = "length",
        message = sprintf("Length mismatch: raw=%d, harmonized=%d", raw_n, harm_n)
      ))
    ))
  }
  NULL
}

# Pure: classifies a wave_rule as identity / reverse / scale_convert / skip.
# "skip" means correlation-based transformation check is meaningless.
.vvw_classify_transform <- function(wave_method, fn_name) {
  if (wave_method == "identity") return("identity")
  if (wave_method %in% c("recode", "derive")) return("skip")
  if (grepl("reverse", fn_name, ignore.case = TRUE)) return("reverse")
  "scale_convert"
}

# Resolves the three "what to compare against" vectors. Defaults to raw_vec;
# `derive` reruns the derive function (so coverage/crosstab compare against
# the same multi-source input the harmonizer used); `extract_*_from_date`
# recomputes raw_for_coverage so coverage compares year/month, not the date.
.vvw_resolve_check_vecs <- function(raw_vec, raw_data, source_var, wave_method,
                                    wave_rule, fn_name, wave_name, missing_codes) {
  out <- list(
    raw_vec_check = raw_vec,
    raw_for_coverage = raw_vec,
    crosstab_missing_codes = missing_codes
  )

  if (wave_method == "derive" && nzchar(fn_name) && exists(fn_name, mode = "function")) {
    derived <- get(fn_name, mode = "function")(
      data = raw_data, wave_name = wave_name, sources = wave_rule$sources %||% NULL
    )
    out$raw_vec_check <- derived
    out$raw_for_coverage <- derived
    out$crosstab_missing_codes <- numeric(0)
  }

  if (fn_name %in% c("extract_month_from_date", "extract_year_from_date") &&
      exists(fn_name, mode = "function")) {
    out$raw_for_coverage <- get(fn_name, mode = "function")(
      raw_vec, data = raw_data, var_name = source_var
    )
  }

  out
}

# Assembles the missing-codes vector used by the coverage check. Pulls in
# wave-agnostic and wave-specific YAML-declared codes, and (for the recode
# method) any source codes that map to NULL/NA — those are intentional drops,
# not coverage loss.
.vvw_collect_coverage_codes <- function(var_spec, wave_name, wave_method,
                                        wave_rule, missing_codes) {
  codes <- missing_codes

  qc_codes <- var_spec$qc[["coverage_missing_codes"]]
  if (!is.null(qc_codes)) {
    codes <- unique(c(codes, as.numeric(qc_codes)))
  }
  qc_codes_wave <- var_spec$qc[["coverage_missing_codes_by_wave"]][[wave_name]]
  if (!is.null(qc_codes_wave)) {
    codes <- unique(c(codes, as.numeric(qc_codes_wave)))
  }

  if (wave_method == "derive") return(numeric(0))

  if (wave_method == "recode" && !is.null(wave_rule$mapping)) {
    drop_mask <- vapply(
      wave_rule$mapping,
      function(v) is.null(v) || (length(v) == 1 && is.na(v)),
      logical(1)
    )
    if (any(drop_mask)) {
      drop_codes <- suppressWarnings(as.numeric(names(wave_rule$mapping)[drop_mask]))
      drop_codes <- drop_codes[!is.na(drop_codes)]
      codes <- unique(c(codes, drop_codes))
    }
  }
  codes
}

# Encapsulates the 5-way branching for the transformation check:
# nominal var, user skip flag, method-derived skip, grouped run, regular run.
.vvw_run_transformation_check <- function(raw_vec_check, harmonized_vec,
                                          var_spec, transform_type, fn_name,
                                          group_vec) {
  is_nominal <- (var_spec$type %||% "ordinal") == "nominal"

  if (is_nominal) {
    return(list(status = "skip", check = "transformation",
                message = "Skipped: nominal/categorical variable (correlation not meaningful)"))
  }
  if (isTRUE(var_spec$qc$skip_transformation_check)) {
    return(list(status = "skip", check = "transformation",
                message = "Skipped: skip_transformation_check set in YAML"))
  }
  if (transform_type == "skip" || fn_name %in% .vvw_skip_transform_fns) {
    return(list(status = "skip", check = "transformation",
                message = "Skipped: transformation not monotonic or not comparable"))
  }
  if (!is.null(group_vec)) {
    return(validate_transformation_grouped(
      raw_vec_check, harmonized_vec, group_vec,
      method = transform_type,
      allow_reverse = isTRUE(var_spec$qc$transformation_allow_reverse)
    ))
  }
  validate_transformation(raw_vec_check, harmonized_vec, transform_type)
}

# ============================================================================

validate_variable_wave <- function(raw_data, harmonized_data, var_spec,
                                   wave_name, missing_codes = c()) {

  early <- .vvw_preflight(raw_data, harmonized_data, var_spec, wave_name)
  if (!is.null(early)) return(early)

  var_id <- var_spec$id
  source_var <- var_spec$source[[wave_name]]
  raw_vec <- raw_data[[source_var]]
  if (inherits(raw_vec, "haven_labelled")) {
    raw_vec <- as.numeric(haven::zap_labels(raw_vec))
  }
  harmonized_vec <- harmonized_data[[var_id]]

  # resolve_wave_rule() lives in src/r/harmonize/harmonize.R; production
  # scripts source _load_harmonize.R before calling validate_variable_wave().
  wave_rule <- resolve_wave_rule(var_spec, wave_name)
  wave_method <- wave_rule$method %||% "identity"
  fn_name <- wave_rule$fn %||% ""
  transform_type <- .vvw_classify_transform(wave_method, fn_name)

  vecs <- .vvw_resolve_check_vecs(
    raw_vec, raw_data, source_var, wave_method,
    wave_rule, fn_name, wave_name, missing_codes
  )

  group_vec <- prepare_group_vec(raw_data, var_spec$qc$group_by %||% NULL)

  coverage_codes <- .vvw_collect_coverage_codes(
    var_spec, wave_name, wave_method, wave_rule, missing_codes
  )

  range_result <- if (isTRUE(var_spec$qc$skip_range_check)) {
    list(status = "skip", check = "range",
         message = "Skipped: skip_range_check set in YAML")
  } else {
    valid_range <- var_spec$qc$valid_range_by_wave[[wave_name]] %||%
                   var_spec$qc$valid_range %||% NULL
    validate_range(harmonized_vec, valid_range)
  }

  checks <- list(
    coverage = if (isTRUE(var_spec$qc$skip_coverage_check)) {
      list(status = "skip", check = "coverage",
           message = "Skipped: skip_coverage_check set in YAML")
    } else {
      validate_coverage(vecs$raw_for_coverage, harmonized_vec, coverage_codes)
    },
    transformation = .vvw_run_transformation_check(
      vecs$raw_vec_check, harmonized_vec, var_spec, transform_type, fn_name, group_vec
    ),
    range = range_result,
    crosstab = if (isTRUE(var_spec$qc$skip_crosstab_check)) {
      list(status = "skip", check = "crosstab",
           message = "Skipped: skip_crosstab_check set in YAML")
    } else if (!is.null(group_vec)) {
      validate_crosstab_grouped(vecs$raw_vec_check, harmonized_vec, group_vec,
                                vecs$crosstab_missing_codes)
    } else {
      validate_crosstab(vecs$raw_vec_check, harmonized_vec, vecs$crosstab_missing_codes)
    },
    type_stability = if (isTRUE(var_spec$qc$skip_type_stability)) {
      list(status = "skip", check = "type_stability",
           message = "Skipped: skip_type_stability set in YAML")
    } else {
      validate_type_stability(harmonized_vec, var_spec$type %||% "ordinal")
    },
    level_preservation = if (isTRUE(var_spec$qc$skip_level_preservation)) {
      list(status = "skip", check = "level_preservation",
           message = "Skipped: skip_level_preservation set in YAML")
    } else {
      validate_level_preservation(
        harmonized_vec,
        scale_min     = var_spec$scale$min,
        scale_max     = var_spec$scale$max,
        declared_type = var_spec$type %||% "ordinal"
      )
    }
  )

  statuses <- vapply(checks, function(x) x$status, character(1))
  overall_status <- if (any(statuses == "error")) "error"
                    else if (any(statuses == "warn")) "warn" else "ok"

  list(
    var_id = var_id, wave = wave_name, source_var = source_var,
    transform_type = transform_type, status = overall_status, checks = checks
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
      crosstab = r$checks$crosstab$status %||% NA_character_,
      type_stability = r$checks$type_stability$status %||% NA_character_,
      level_preservation = r$checks$level_preservation$status %||% NA_character_
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
    lines <- c(lines, "| Wave | Source | Transform | Coverage | Transform | Range | Crosstab | Type | Levels |")
    lines <- c(lines, "|------|--------|-----------|----------|-----------|-------|----------|------|--------|")

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
        "| %s | %s | %s | %s | %s | %s | %s | %s | %s |",
        row$wave,
        row$source %||% "-",
        row$transform %||% "-",
        status_icon(row$coverage),
        status_icon(row$transformation),
        status_icon(row$range),
        status_icon(row$crosstab),
        status_icon(row$type_stability),
        status_icon(row$level_preservation)
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
