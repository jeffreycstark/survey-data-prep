# Harmonization helper functions
# Simple recoding functions for common patterns

library(dplyr)

#' Reverse a 4-point Likert scale
#'
#' Convert 1→4, 2→3, 3→2, 4→1
#' @param x Numeric vector (1-4)
#' @return Reversed numeric vector
#'
#' @export
safe_reverse_4pt <- function(x) {
  5 - x
}


#' Reverse a 5-point Likert scale
#'
#' Convert 1→5, 2→4, 3→3, 4→2, 5→1
#' @param x Numeric vector (1-5)
#' @return Reversed numeric vector
#'
#' @export
safe_reverse_5pt <- function(x) {
  6 - x
}


#' Recode 5-point to 4-point scale
#'
#' Linear rescaling: (x-1) * (4/5) + 1 with rounding
#' @param x Numeric vector (1-5)
#' @return Rescaled numeric vector (1-4)
#'
#' @export
recode_5pt_to_4pt <- function(x) {
  round((x - 1) * (4 / 5) + 1, 0)
}


#' Recode 3-point to 4-point scale
#'
#' Linear rescaling: (x-1) * (4/3) + 1
#' @param x Numeric vector (1-3)
#' @return Rescaled numeric vector (1-4)
#'
#' @export
recode_3pt_to_4pt <- function(x) {
  round((x - 1) * (4 / 3) + 1, 0)
}


#' Recode 6-point to 4-point scale
#'
#' Linear rescaling: (x-1) * (4/6) + 1 with rounding
#' @param x Numeric vector (1-6)
#' @return Rescaled numeric vector (1-4)
#'
#' @export
recode_6pt_to_4pt <- function(x) {
  round((x - 1) * (4 / 6) + 1, 0)
}


#' Recode 10-point to 4-point scale
#'
#' Linear rescaling: (x-1) * (4/10) + 1 with rounding
#' Maps 1-10 scale to 1-4 scale proportionally
#' @param x Numeric vector (1-10)
#' @return Rescaled numeric vector (1-4)
#'
#' @export
recode_10pt_to_4pt <- function(x) {
  round((x - 1) * (4 / 10) + 1, 0)
}


#' Apply direct harmonization (no transformation)
#'
#' Pass-through function for variables that already use same scale
#' @param x Numeric vector
#' @return Same vector unchanged
#'
#' @export
harmonize_direct <- function(x) {
  x
}


#' Identify and preserve 4-point scale values
#'
#' Remove NA codes (keep only 1-4 values) without transforming
#' Converts out-of-range values to NA_real_
#' @param x Numeric vector containing 1-4 and missing codes
#' @return Numeric vector with missing codes converted to NA_real_
#'
#' @export
safe_identify_4pt <- function(x) {
  ifelse(x >= 1 & x <= 4, x, NA_real_)
}


#' Identify and preserve 5-point scale values
#'
#' Remove NA codes (keep only 1-5 values) without transforming
#' Converts out-of-range values to NA_real_
#' @param x Numeric vector containing 1-5 and missing codes
#' @return Numeric vector with missing codes converted to NA_real_
#'
#' @export
safe_identify_5pt <- function(x) {
  ifelse(x >= 1 & x <= 5, x, NA_real_)
}


#' Identify and preserve 6-point scale values
#'
#' Remove NA codes (keep only 1-6 values) without transforming
#' Converts out-of-range values to NA_real_
#' @param x Numeric vector containing 1-6 and missing codes
#' @return Numeric vector with missing codes converted to NA_real_
#'
#' @export
safe_identify_6pt <- function(x) {
  ifelse(x >= 1 & x <= 6, x, NA_real_)
}


#' Auto-detect scale range from value distribution
#'
#' Uses standard missing code conventions to intelligently detect scale range.
#' Logic:
#'   1. Treat negative codes and special codes as missing (not part of scale)
#'   2. Find continuous positive sequence starting from 1
#'   3. Identify GAP: where continuous sequence breaks (gap > 1)
#'   4. The last value before the gap is the actual scale maximum
#'   5. Values after gap (7-9 for small scales, 97-99 for large) are missing codes
#'
#' Examples:
#'   Values {-1, 1,2,3,4,5,6,7,8,9} → Scale is 1-6 (gap at 7, -1 and 7-9 are missing)
#'   Values {1,2,3,4,5,6,7,8,9,10,97,98,99} → Scale is 1-10 (gap at 97, 97-99 are missing)
#'   Values {1,2,3,4,5,6,97,98,99} → Scale is 1-6 (gap at 97, 97-99 are missing)
#'
#' @param x Numeric vector (raw, with missing codes)
#' @param var_name Variable name (for messages)
#' @return List with detected_scale (integer), missing_codes (vector), real_range (vector)
#'
#' @export
detect_scale <- function(x, var_name = "variable") {
  
  # Remove NA values
  x_clean <- x[!is.na(x)]
  
  if (length(x_clean) == 0) {
    return(list(detected_scale = NA, missing_codes = NA, real_range = c(NA, NA),
                is_categorical = FALSE, logic_status = "OK", categorical_reason = ""))
  }
  
  unique_vals <- sort(unique(x_clean))
  detected_missing <- c()
  detected_scale <- NA
  
  # Separate special/negative codes from potential scale values
  # Special codes: anything < 1 (like -1, -2)
  special_codes <- unique_vals[unique_vals < 1]
  positive_vals <- unique_vals[unique_vals >= 1]
  
  if (length(positive_vals) == 0) {
    return(list(detected_scale = NA, missing_codes = special_codes, real_range = c(NA, NA),
                is_categorical = FALSE, logic_status = "OK", categorical_reason = ""))
  }
  
  # Look for gap in the positive values
  gap_found <- FALSE
  for (i in 1:(length(positive_vals) - 1)) {
    val_i <- positive_vals[i]
    val_i_plus_1 <- positive_vals[i + 1]
    
    # Skip if either value is NA
    if (is.na(val_i) || is.na(val_i_plus_1)) {
      next
    }
    
    # Calculate difference and safely check for gap
    diff <- val_i_plus_1 - val_i
    if (isTRUE(diff > 1)) {
      # GAP FOUND - scale ends at val_i
      detected_scale <- val_i
      detected_missing <- c(special_codes, positive_vals[positive_vals > detected_scale])
      gap_found <- TRUE
      break
    }
  }
  
  # If no gap in positive values, check for reserved missing code patterns
  if (!gap_found) {
    if (any(c(997, 998, 999) %in% positive_vals)) {
      # Large scale missing codes (997, 998, 999) - scale is everything before 997
      detected_scale <- max(positive_vals[positive_vals < 997])
      detected_missing <- c(special_codes, positive_vals[positive_vals >= 997])
    } else if (any(c(97, 98, 99) %in% positive_vals)) {
      # High missing codes present - scale is everything before 97
      detected_scale <- max(positive_vals[positive_vals < 97])
      detected_missing <- c(special_codes, positive_vals[positive_vals >= 97])
    } else if (any(c(7, 8, 9) %in% positive_vals)) {
      # Check if 7, 8, 9 are reserved missing codes for small scales
      # Rule: if max(scale) <= 6 but 7, 8, 9 appear, they're reserved codes
      max_before_789 <- max(positive_vals[positive_vals < 7])
      if (max_before_789 <= 6) {
        # 7, 8, 9 are reserved missing codes
        detected_scale <- max_before_789
        detected_missing <- c(special_codes, positive_vals[positive_vals >= 7])
      } else {
        # 7, 8, 9 are part of scale (scale goes 1-9)
        detected_scale <- max(positive_vals)
        detected_missing <- special_codes
      }
    } else {
      # No gap and no missing code pattern - all positive values are scale
      detected_scale <- max(positive_vals)
      detected_missing <- special_codes
    }
  }
  
  # Check for suspicious patterns (likely categorical, not ordinal)
  is_categorical <- FALSE
  logic_status <- "OK"  # OK, SUSPICIOUS, or LOGIC_BREAKS
  categorical_reason <- ""
  
  if (any(positive_vals > 1000)) {
    # Values in thousands - definitely categorical codes (like party IDs)
    is_categorical <- TRUE
    logic_status <- "LOGIC_BREAKS"
    categorical_reason <- "values in thousands (categorical codes, not scale)"
  } else if (detected_scale > 50 && !any(c(997, 998, 999) %in% positive_vals)) {
    # Very large scale (>50) WITHOUT 997-999 missing codes - likely categorical
    is_categorical <- TRUE
    logic_status <- "SUSPICIOUS"
    categorical_reason <- sprintf("unusually large scale (%d points) without standard missing codes", detected_scale)
  } else if (length(positive_vals) > 50 && detected_scale > 20 && !any(c(97, 98, 99, 997, 998, 999) %in% positive_vals)) {
    # Many unique values with large scale and no missing codes - likely categorical
    is_categorical <- TRUE
    logic_status <- "SUSPICIOUS"
    categorical_reason <- sprintf("%d unique values in %d-point scale without standard missing codes", length(positive_vals), detected_scale)
  }
  
  # Ensure detected_scale is always valid
  if (is.na(detected_scale) || is.null(detected_scale)) {
    detected_scale <- max(positive_vals)
  }
  
  if (logic_status == "LOGIC_BREAKS") {
    cat(sprintf("  🚨 %s: LOGIC_BREAKS - %s\n", var_name, categorical_reason))
  } else if (is_categorical) {
    cat(sprintf("  ⚠️  %s: SUSPICIOUS - %s\n", var_name, categorical_reason))
  } else {
    cat(sprintf("  🔍 %s: Detected %d-point scale (range: 1-%d, missing codes: %s)\n",
                var_name, as.integer(detected_scale), as.integer(detected_scale),
                ifelse(length(detected_missing) > 0, 
                       paste(detected_missing, collapse=", "), 
                       "none")))
  }
  
  return(list(
    detected_scale = as.integer(detected_scale),
    missing_codes = detected_missing,
    real_range = c(1, as.integer(detected_scale)),
    is_categorical = is_categorical,
    logic_status = logic_status,  # OK, SUSPICIOUS, or LOGIC_BREAKS
    categorical_reason = categorical_reason
  ))
}


#' Validate harmonization
#'
#' Check that harmonized vector has expected range and no invalid values
#' @param x Harmonized vector
#' @param expected_min Expected minimum value
#' @param expected_max Expected maximum value
#' @param var_name Variable name (for messages)
#' @return Logical TRUE/FALSE with warnings if issues found
#'
#' @export

#' Handle W6 extended corruption scale (1-5 with special codes)
#'
#' W6 has extended scale with:
#'   1 = Hardly anyone involved
#'   2 = Not a lot of officials are corrupt
#'   3 = Most officials are corrupt
#'   4 = Almost everyone is corrupt
#'   5 = No one is involved (rare response)
#'   0 = Not applicable
#' 
#' Map to standard 1-4 scale by treating 5 and 0 as NA
#' @param x Numeric vector (1-5 with 0=N/A)
#' @return Numeric vector with 5→NA, 0→NA, keeping 1-4
#'
#' @export
harmonize_w6_corruption <- function(x) {
  # Map 5 (No one involved) and 0 (N/A) to NA
  # Keep 1-4 as-is
  ifelse(x >= 1 & x <= 4, x, NA_real_)
}


validate_harmonization <- function(x, expected_min = 1, expected_max = 4, var_name = "variable") {

  valid_count <- sum(!is.na(x))
  missing_count <- sum(is.na(x))
  out_of_range <- sum(!is.na(x) & (x < expected_min | x > expected_max))

  cat(sprintf("\n%s:\n", var_name))
  cat(sprintf("  Valid: %d | Missing: %d | Out of range: %d\n",
              valid_count, missing_count, out_of_range))

  if (out_of_range > 0) {
    cat(sprintf("  ⚠️  Found %d out-of-range values\n", out_of_range))
    return(FALSE)
  } else {
    cat("  ✅ All values within expected range\n")
    return(TRUE)
  }
}


#' Recode voted_last_election W1 and W2
#'
#' W1 and W2 have reversed scale: 1=No, 2=Yes; recode to 0=No, 1=Yes
#' All other values (missing, not applicable) → NA
#' @param x Numeric vector
#' @return Numeric vector (0=No, 1=Yes, others→NA)
#'
#' @export
recode_voted_w1 <- function(x) {
  # W1/W2: 1=No, 2=Yes → target: 0=No, 1=Yes
  dplyr::case_when(
    x == 1 ~ 0,  # No → 0
    x == 2 ~ 1,  # Yes → 1
    TRUE ~ NA_real_
  )
}


#' Recode voted_last_election W2-W6
#'
#' Recode to 0=No, 1=Yes; "not eligible" and proxy voting → NA
#' @param x Numeric vector
#' @return Numeric vector (0=No, 1=Yes, others→NA)
#'
#' @export
recode_voted_default <- function(x) {
  # 1=Yes→1, 2=No→0, 0/3=Not eligible→NA, 1103/1104=proxy voting→NA
  dplyr::case_when(
    x == 0 ~ NA_real_,     # Not applicable/not eligible (W4)
    x == 1 ~ 1,            # Yes → 1
    x == 2 ~ 0,            # No → 0
    x == 3 ~ NA_real_,     # Not yet eligible → NA
    x == 1103 ~ NA_real_,
    x == 1104 ~ NA_real_,
    TRUE ~ NA_real_
  )
}
