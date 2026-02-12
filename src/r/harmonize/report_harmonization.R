# src/r/harmonize/report_harmonization.R
# Reporting and QC functions for harmonized variables

#' Generate harmonization report
#'
#' Creates a detailed report of harmonization results including:
#' - Summary statistics per wave
#' - Missing data patterns
#' - Range violations (if QC bounds specified)
#' - Warnings/errors encountered
#'
#' @param harmonized List result from harmonize_variable() or harmonize_all()
#' @param var_spec Variable specification (for reference)
#' @param return_tbl Logical: return as tibble? Otherwise prints to console
#'
#' @return Invisibly list with summary data (or tibble if return_tbl=TRUE)
#'
#' @export
report_harmonization <- function(harmonized, var_spec = NULL, return_tbl = FALSE) {

  out <- list()

  for (wave_name in names(harmonized)) {

    x <- harmonized[[wave_name]]

    n <- length(x)
    n_valid <- sum(!is.na(x))
    n_missing <- sum(is.na(x))
    pct_missing <- if (n > 0) round(100 * n_missing / n, 1) else NA

    stats <- list(
      wave = wave_name,
      n = n,
      n_valid = n_valid,
      n_missing = n_missing,
      pct_missing = pct_missing,
      mean = round(mean(x, na.rm = TRUE), 3),
      sd = round(sd(x, na.rm = TRUE), 3),
      min = round(min(x, na.rm = TRUE), 3),
      max = round(max(x, na.rm = TRUE), 3)
    )

    out[[wave_name]] <- stats
  }

  if (return_tbl) {
    return(
      dplyr::bind_rows(out) %>%
        dplyr::arrange(wave)
    )
  }

  # Print to console
  cat("\n")
  cat(rep("=", 70), sep = "")
  cat("\nHarmonization Report")
  if (!is.null(var_spec$id)) {
    cat(sprintf(": %s\n", var_spec$id))
  } else {
    cat("\n")
  }

  cat(rep("=", 70), "\n\n")

  tbl <- dplyr::bind_rows(out) %>% dplyr::arrange(wave)

  print(tbl)

  invisible(out)
}

#' Summary of harmonization results across all variables
#'
#' Compares harmonized variables before/after to highlight
#' transformations and data quality changes.
#'
#' @param original_waves List: original wave data before harmonization
#' @param harmonized_list List of lists: result from harmonize_all()
#' @param spec YAML specification
#'
#' @return Data frame with one row per variable per wave showing:
#'   - original and harmonized n_missing, mean, range
#'
#' @export
harmonization_summary <- function(original_waves, harmonized_list, spec) {

  summary_rows <- list()
  row_id <- 1

  for (var_id in names(harmonized_list)) {

    harmonized <- harmonized_list[[var_id]]
    var_spec <- spec$variables[[var_id]]

    for (wave_name in names(harmonized)) {

      df <- original_waves[[wave_name]]
      src <- var_spec$source[[wave_name]]

      # Original variable
      orig_x <- if (!is.null(src) && src %in% names(df)) {
        suppressWarnings(as.numeric(df[[src]]))
      } else {
        NULL
      }

      # Harmonized variable
      harm_x <- harmonized[[wave_name]]

      summary_rows[[row_id]] <- list(
        var_id = var_id,
        concept = var_spec$concept,
        wave = wave_name,
        source_var = src %||% NA,
        
        # Original
        orig_n = if (!is.null(orig_x)) length(orig_x) else NA,
        orig_n_missing = if (!is.null(orig_x)) sum(is.na(orig_x)) else NA,
        orig_mean = if (!is.null(orig_x)) round(mean(orig_x, na.rm = TRUE), 2) else NA,
        orig_range = if (!is.null(orig_x)) {
          sprintf("[%.0f, %.0f]", min(orig_x, na.rm = TRUE), max(orig_x, na.rm = TRUE))
        } else {
          NA
        },
        
        # Harmonized
        harm_n = length(harm_x),
        harm_n_missing = sum(is.na(harm_x)),
        harm_mean = round(mean(harm_x, na.rm = TRUE), 2),
        harm_range = sprintf("[%.0f, %.0f]", min(harm_x, na.rm = TRUE), max(harm_x, na.rm = TRUE))
      )

      row_id <- row_id + 1
    }
  }

  dplyr::bind_rows(summary_rows)
}

#' Validate harmonized variable against QC bounds
#'
#' Checks if harmonized values fall within specified valid ranges.
#' Returns violations without coercing values.
#'
#' @param harmonized List: result from harmonize_variable()
#' @param var_spec Variable specification with qc$valid_range_by_wave
#'
#' @return Data frame with violations (wave, n_violations, values)
#'   or NULL if no violations
#'
#' @export
check_harmonization_bounds <- function(harmonized, var_spec) {

  violations <- list()

  if (is.null(var_spec$qc$valid_range_by_wave)) {
    message("ℹ️  No valid_range_by_wave specified in QC")
    return(NULL)
  }

  for (wave_name in names(harmonized)) {

    vr <- var_spec$qc$valid_range_by_wave[[wave_name]]

    if (is.null(vr)) {
      next
    }

    x <- harmonized[[wave_name]]

    bad_idx <- which(!is.na(x) & (x < vr[1] | x > vr[2]))

    if (length(bad_idx) > 0) {

      violations[[wave_name]] <- list(
        wave = wave_name,
        n_violations = length(bad_idx),
        min_valid = vr[1],
        max_valid = vr[2],
        values_outside_range = x[bad_idx],
        n_below_min = sum(x[bad_idx] < vr[1]),
        n_above_max = sum(x[bad_idx] > vr[2])
      )
    }
  }

  if (length(violations) == 0) {
    message("✓ All values within valid ranges")
    return(NULL)
  }

  # Return as data frame
  dplyr::bind_rows(lapply(violations, function(v) {
    data.frame(
      wave = v$wave,
      n_violations = v$n_violations,
      valid_range = sprintf("[%d, %d]", v$min_valid, v$max_valid),
      n_below_min = v$n_below_min,
      n_above_max = v$n_above_max
    )
  }))
}
