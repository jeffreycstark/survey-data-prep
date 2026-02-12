# src/r/harmonize/harmonize.R
# Core functions for cross-wave variable harmonization

# ==============================================================================
# HELPER OPERATORS AND FUNCTIONS
# ==============================================================================

#' Null coalescing operator
#'
#' Returns first non-null value (alternative if left side is NULL)
`%||%` <- function(a, b) {
  if (!is.null(a)) a else b
}

#' Clean missing codes to NA
#'
#' @param x Numeric vector
#' @param missing_codes Codes to treat as NA
#' @return Vector with missing codes converted to NA
apply_missing <- function(x, missing_codes) {
  if (length(missing_codes) == 0) {
    return(x)
  }
  x[x %in% missing_codes] <- NA_real_
  x
}

# ==============================================================================
# MAIN HARMONIZATION ENGINE
# ==============================================================================

#' Harmonize a variable across waves using YAML specification
#'
#' Takes a variable specification (from YAML) and applies harmonization rules
#' to produce a harmonized variable across all waves.
#'
#' @param var_spec List: one YAML variable entry with fields:
#'   - id: variable identifier
#'   - source: list(w1="q001", w2="q1", ...)
#'   - missing: list(use_convention="treat_as_na")
#'   - harmonize: list(default=..., by_wave=...)
#'   - qc: list(valid_range_by_wave=...)
#'
#' @param waves List of named data frames: list(w1=df1, w2=df2, ...)
#'
#' @param missing_conventions Named list of missing code vectors
#'   e.g. list(treat_as_na = c(-1, 0, 7, 8, 9))
#'
#' @return List of harmonized vectors, one per wave:
#'   list(w1 = numeric(n1), w2 = numeric(n2), ...)
#'
#' @details
#' Harmonization workflow:
#' 1. Extract source variable from wave data
#' 2. Convert to numeric, apply missing code handling
#' 3. Select harmonization rule (default or wave-specific)
#' 4. Apply method:
#'    - "identity": pass through
#'    - "r_function": call recoding function (e.g., safe_reverse_5pt)
#' 5. QC: check valid range and coerce out-of-range values to NA
#'
#' @examples
#' \dontrun{
#' # Load YAML spec and wave data
#' spec <- yaml::read_yaml("src/config/harmonize/economy.yml")
#' waves <- list(
#'   w1 = readRDS("data/processed/w1.rds"),
#'   w2 = readRDS("data/processed/w2.rds")
#' )
#'
#' # Harmonize one variable
#' econ <- harmonize_variable(
#'   var_spec = spec$variables[["econ_national_now"]],
#'   waves = waves,
#'   missing_conventions = spec$missing_conventions
#' )
#'
#' # econ$w1, econ$w2, ... are harmonized vectors
#' }
#'
#' @export
harmonize_variable <- function(
  var_spec,
  waves,
  missing_conventions
) {

  out <- list()

  for (wave_name in names(waves)) {

    df <- waves[[wave_name]]

    # ---- extract source variable ----
    src <- var_spec$source[[wave_name]]

    if (is.null(src) || !src %in% names(df)) {
      # Source variable doesn't exist in this wave - return all NA
      out[[wave_name]] <- rep(NA_real_, nrow(df))
      next
    }

    # Convert to numeric (handle haven_labelled from SPSS imports)
    x <- df[[src]]
    if (inherits(x, "haven_labelled")) {
      x <- as.numeric(haven::zap_labels(x))
    } else {
      x <- suppressWarnings(as.numeric(x))
    }

    # ---- apply missing code handling ----
    # First check for variable-specific convention, then use global treat_as_na
    miss_convention_key <- var_spec$missing$use_convention %||% "treat_as_na"
    missing_codes <- numeric(0)

    if (!is.null(missing_conventions[[miss_convention_key]])) {
      convention <- missing_conventions[[miss_convention_key]]
      # Handle both direct vector and nested structure with 'codes' field
      if (is.list(convention) && !is.null(convention$codes)) {
        missing_codes <- as.numeric(convention$codes)
      } else {
        missing_codes <- as.numeric(convention)
      }
    }

    if (!is.null(var_spec$missing$codes)) {
      missing_codes <- unique(c(
        missing_codes,
        as.numeric(var_spec$missing$codes)
      ))
    }

    x <- apply_missing(x, missing_codes)

    # ---- select harmonization rule ----
    default_rule <- var_spec$harmonize$default %||% list(method = "identity")
    # Support multiple YAML formats:
    # - v1: harmonize.by_wave.w1, harmonize.by_wave.w2...
    # - v2: harmonize.exceptions.w1, harmonize.exceptions.w2...
    # - v3: harmonize.w1, harmonize.w2... (direct wave keys)
    wave_rule <- var_spec$harmonize$by_wave[[wave_name]] %||%
                 var_spec$harmonize$exceptions[[wave_name]] %||%
                 var_spec$harmonize[[wave_name]] %||%
                 default_rule

    # ---- apply harmonization method ----
    if (wave_rule$method == "identity") {

      # No transformation
      x_harm <- x

    } else if (wave_rule$method == "r_function") {

      fn_name <- wave_rule$fn
      if (!exists(fn_name, mode = "function")) {
        stop("❌ Recoding function not found: ", fn_name)
      }

      fn <- get(fn_name, mode = "function")

      # Call function with full wave data for semantic validation
      x_harm <- fn(
        x,
        data = df,
        var_name = src,
        validate_all = wave_rule$validate_all %||% NULL
      )

    } else if (wave_rule$method == "recode") {

      # Apply explicit value mapping from YAML
      # mapping: {1: 1, 2: 0, 3: null, 4: null}
      mapping <- wave_rule$mapping
      if (is.null(mapping)) {
        stop("❌ method 'recode' requires a 'mapping' field")
      }

      x_harm <- rep(NA_real_, length(x))

      for (from_val in names(mapping)) {
        to_val <- mapping[[from_val]]
        from_num <- as.numeric(from_val)

        if (is.null(to_val)) {
          # null in YAML means map to NA
          x_harm[x == from_num & !is.na(x)] <- NA_real_
        } else {
          # Map to the specified value
          x_harm[x == from_num & !is.na(x)] <- as.numeric(to_val)
        }
      }

      # Preserve NA from source
      x_harm[is.na(x)] <- NA_real_

    } else if (wave_rule$method == "derive") {

      # Derive method: compute from multiple source columns
      # Uses 'sources' list and 'fn' function name
      fn_name <- wave_rule$fn
      if (!exists(fn_name, mode = "function")) {
        stop("❌ Derive function not found: ", fn_name)
      }

      fn <- get(fn_name, mode = "function")

      # Call function with full wave data (function accesses needed columns)
      x_harm <- fn(
        data = df,
        wave_name = wave_name,
        sources = wave_rule$sources %||% NULL
      )

    } else {
      stop("❌ Unknown harmonization method: ", wave_rule$method)
    }

    # ---- QC: range check and coerce out-of-range to NA ----
    # Check for skip_range_check flag (for IDs and other unconstrained values)
    skip_range <- isTRUE(var_spec$qc$skip_range_check)

    # Check for valid_range (global) or valid_range_by_wave (wave-specific)
    vr <- var_spec$qc$valid_range_by_wave[[wave_name]] %||%
          var_spec$qc$valid_range %||%
          NULL

    if (skip_range) {
      # Explicitly skip range validation - no warning needed
    } else if (is.null(vr)) {
      # Warn if no valid_range specified - may miss bad data
      warning(
        sprintf("⚠️  %s (%s): No valid_range in qc - using defaults may miss bad values",
                var_spec$id, wave_name),
        call. = FALSE
      )
    } else {
      # Count and coerce out-of-range values to NA
      bad <- !is.na(x_harm) & (x_harm < vr[1] | x_harm > vr[2])
      if (any(bad)) {
        message(
          sprintf("   %s (%s): Converting %d out-of-range values to NA [valid: %s-%s]",
                  var_spec$id, wave_name, sum(bad), vr[1], vr[2])
        )
        x_harm[bad] <- NA_real_
      }
    }

    out[[wave_name]] <- x_harm
  }

  out
}

#' Harmonize multiple variables from YAML specification
#'
#' Applies harmonize_variable() to all variables in a YAML spec,
#' returning a list with one element per variable.
#'
#' @param spec List: parsed YAML specification
#' @param waves List of named data frames
#' @param silent Logical: suppress messages?
#'
#' @return List of harmonized variables:
#'   list(econ_national_now = list(w1=..., w2=..., ...),
#'        politics_trust = list(w1=..., w2=..., ...))
#'
#' @export
harmonize_all <- function(spec, waves, silent = FALSE) {

  results <- list()

  var_ids <- names(spec$variables)

  for (var_id in var_ids) {

    if (!silent) {
      message(sprintf("Harmonizing: %s", var_id))
    }

    tryCatch({
      results[[var_id]] <- harmonize_variable(
        var_spec = spec$variables[[var_id]],
        waves = waves,
        missing_conventions = spec$missing_conventions
      )
    }, error = function(e) {
      warning(sprintf("❌ %s: %s", var_id, e$message), call. = FALSE)
    })
  }

  results
}

# ==============================================================================
# DERIVED VARIABLE FUNCTIONS
# Functions for computing variables from multiple source columns
# ==============================================================================

#' Compute procedural preference index from 4-set battery
#'
#' Sums procedural choices across 4 forced-choice sets measuring
#' procedural vs substantive democracy conceptions.
#'
#' @param data Data frame containing source columns
#' @param wave_name Wave identifier (w3, w4, w6)
#' @param sources List of source column names (q85-q88 or q88-q91)
#'
#' @return Numeric vector with 0-4 index (count of procedural choices)
#'
#' @details
#' Recode rules for each set:
#'   Set 1: {2,4}->1 (elections, expression), {1,3}->0 (redistribution, efficiency)
#'   Set 2: {1,3}->1 (oversight, organize), {2,4}->0 (basic needs, services)
#'   Set 3: {2,4}->1 (media, multiparty), {1,3}->0 (law-order, jobs)
#'   Set 4: {1,3}->1 (protests, courts), {2,4}->0 (anticorruption, unemployment)
#'
#' @export
compute_procedural_index <- function(data, wave_name = NULL, sources = NULL) {

  # Get source column names from YAML or use defaults by wave
  if (is.null(sources)) {
    sources <- switch(wave_name,
      w3 = c("q85", "q86", "q87", "q88"),
      w4 = c("q88", "q89", "q90", "q91"),
      w6 = c("q85", "q86", "q87", "q88"),
      stop("Unknown wave for procedural index: ", wave_name)
    )
  }

  # Helper to convert to numeric
  to_num <- function(x) {
    if (inherits(x, "haven_labelled")) {
      as.numeric(haven::zap_labels(x))
    } else {
      suppressWarnings(as.numeric(x))
    }
  }

  # Extract source columns
  s1 <- to_num(data[[sources[1]]])
  s2 <- to_num(data[[sources[2]]])
  s3 <- to_num(data[[sources[3]]])
  s4 <- to_num(data[[sources[4]]])

  # Recode each set: 1 = procedural choice, 0 = substantive choice
  # Set 1: 2,4 = procedural; 1,3 = substantive
  r1 <- dplyr::case_when(s1 %in% c(2, 4) ~ 1L, s1 %in% c(1, 3) ~ 0L, TRUE ~ NA_integer_)
  # Set 2: 1,3 = procedural; 2,4 = substantive
  r2 <- dplyr::case_when(s2 %in% c(1, 3) ~ 1L, s2 %in% c(2, 4) ~ 0L, TRUE ~ NA_integer_)
  # Set 3: 2,4 = procedural; 1,3 = substantive
  r3 <- dplyr::case_when(s3 %in% c(2, 4) ~ 1L, s3 %in% c(1, 3) ~ 0L, TRUE ~ NA_integer_)
  # Set 4: 1,3 = procedural; 2,4 = substantive
  r4 <- dplyr::case_when(s4 %in% c(1, 3) ~ 1L, s4 %in% c(2, 4) ~ 0L, TRUE ~ NA_integer_)

  # Sum: 0-4 index
  index <- r1 + r2 + r3 + r4

  as.numeric(index)
}
