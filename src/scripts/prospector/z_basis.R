# Slope z-score standardisation for the Slope Prospector.
#
# A slope is "an outlier" only relative to some reference distribution, and the
# right reference depends on the dataset:
#
#   cross_country  — for each variable, compare a country's slope against the
#                    other countries' slopes on that same variable. This is the
#                    multi-country reading ("Korea's trust fell faster than
#                    anywhere else") and is what ABS-style runs want.
#   cross_variable — for each country, compare a variable against that country's
#                    other variables. This is the single-country reading ("of
#                    everything this survey measures, that moved most") and is
#                    the only one available when there is one country.
#
# NOTE: the two bases are NOT interchangeable. A z of 2.5 means "unusual among
# countries" under one and "unusual among variables" under the other, so every
# frame this returns carries a `z_basis` column and callers must surface it.
#
# WHAT GETS STANDARDISED (cross_variable only; cross_country always uses the
# raw slope, so multi-country behaviour is untouched). Slopes reach here per wave unit on each variable's own
# min-max-normalized range, so the largest slope a series can possibly have is
# 1/span: a 3-wave series over 4 years tops out at 0.25/yr while a 17-wave series
# over 22 years tops out at 0.045/yr. Comparing raw slopes ACROSS VARIABLES
# therefore ranks series length as much as movement — a variable that inched
# across a two-decade window loses to a short one that wobbled. So under
# cross_variable the standardised quantity is the TRAVERSAL, slope x wave_span:
# the share of its own observed range the fitted line actually covered, which
# has the same 0-1 ceiling for every variable. Under cross_country the
# comparison is already like-for-like (same variable, same normalization,
# broadly the same waves), so the raw slope is standardised unscaled.
#
# Under cross_variable there are two statistics, best first:
#
#   sd_units   slope x norm_range x wave_span / sd_typ — the change across the
#              observed window expressed in respondent-level SDs. Comparable
#              across items of any scale and any series length. Needs the means
#              table to carry a respondent-level SD column.
#   traversal  slope x wave_span — the share of its own observed range the
#              series covered. Used when no SD is available. Because per-variable
#              min-max normalization stretches every series to [0, 1], this is
#              really a monotonicity measure: it says how steadily a variable
#              moved, NOT how far. Rankings under it are weak; the run says so.
#
# Columns returned: z_input (the quantity standardised), z_scale (its multiplier
# on `slope`), z_stat (which statistic), mean_ref / sd_ref / n_ref (the reference
# distribution), z_slope, z_basis.

Z_BASIS_CHOICES <- c("auto", "cross_country", "cross_variable")

# Resolve "auto" against the data: one country in the frame leaves cross_country
# with a single-element reference distribution, which can never flag an outlier.
resolve_z_basis <- function(slopes, basis = "auto") {
  if (length(basis) != 1 || !basis %in% Z_BASIS_CHOICES)
    stop(sprintf("Z_BASIS must be one of %s (got: %s)",
                 paste(Z_BASIS_CHOICES, collapse = "/"), paste(basis, collapse = ",")))
  if (basis != "auto") return(basis)
  if (dplyr::n_distinct(slopes$country) > 1) "cross_country" else "cross_variable"
}

# Add z_input / z_scale / mean_ref / sd_ref / n_ref / z_slope / z_basis,
# standardising within whichever grouping the resolved basis implies. A
# reference distribution with fewer than 2 members or zero variance yields
# z = 0 (not NaN); n_ref exposes that case rather than hiding it.
compute_slope_z <- function(slopes, basis = "auto") {
  resolved <- resolve_z_basis(slopes, basis)
  if (resolved == "cross_variable" && !"wave_span" %in% names(slopes))
    stop("compute_slope_z(basis = 'cross_variable') needs a `wave_span` column: ",
         "comparing raw slopes across variables ranks series length, not movement.")

  has_sd <- resolved == "cross_variable" &&
            all(c("norm_range", "sd_typ") %in% names(slopes)) &&
            any(is.finite(slopes$sd_typ) & slopes$sd_typ > 0)
  stat <- if (resolved == "cross_country") "raw_slope" else if (has_sd) "sd_units" else "traversal"

  key <- if (resolved == "cross_country") "variable" else "country"
  slopes %>%
    dplyr::mutate(
      z_scale = switch(stat,
        raw_slope = 1,
        sd_units  = .data$norm_range * .data$wave_span / .data$sd_typ,
        traversal = .data$wave_span),
      z_input = slope * z_scale
    ) %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(key))) %>%
    dplyr::mutate(
      n_ref    = dplyr::n(),
      mean_ref = mean(z_input, na.rm = TRUE),
      sd_ref   = stats::sd(z_input, na.rm = TRUE),
      z_slope  = dplyr::if_else(!is.na(sd_ref) & sd_ref > 0 & n_ref > 1,
                                (z_input - mean_ref) / sd_ref, 0)
    ) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(z_basis = resolved, z_stat = stat)
}

# ── Direction ────────────────────────────────────────────────────────────────
#
# `direction` (RISING/FALLING/FLAT) answers "is this variable moving?", and the
# default rule answers it in WAVE units: |slope| against FLAT_THRESHOLD. Those
# units differ by survey — 0.05 is 5% of a variable's range per four years in
# ABS and per one year in KGSS — and per-variable min-max normalization caps the
# slope at 1/span, so a variable observed across a long window cannot clear a
# bar calibrated on a short one. KGSS `pride_social_security` runs 1.92 -> 2.89
# on a 1-4 scale between 2003 and 2025, a shift of 1.39 respondent SDs, and its
# per-year slope of 0.0465 still reads FLAT.
#
# The sd_units rule asks the same question as a magnitude: how far did the
# variable move across its observed window, in respondent-level SDs. That is
# comparable across response scales and across series lengths, and it reads in
# plain language ("moved at least a fifth of a standard deviation").

DIRECTION_BASIS_CHOICES <- c("slope", "sd_units")

# Signed change across the observed window in respondent-level SD units.
# NA where the inputs are missing or the item has no respondent variance.
compute_change_sd <- function(slopes) {
  needed <- c("wave_span", "norm_range", "sd_typ")
  missing <- setdiff(needed, names(slopes))
  if (length(missing) > 0)
    stop("compute_change_sd() needs column(s): ", paste(missing, collapse = ", "))
  sd_ok <- is.finite(slopes$sd_typ) & slopes$sd_typ > 0
  dplyr::if_else(sd_ok, slopes$slope * slopes$norm_range * slopes$wave_span / slopes$sd_typ,
                 NA_real_)
}

# Returns a character vector, one label per row. Rows the chosen rule cannot
# score (no respondent variance, say) are FLAT — callers report how many.
classify_direction <- function(slopes, basis = "slope",
                               flat_threshold = 0.05, sd_threshold = 0.2) {
  if (length(basis) != 1 || !basis %in% DIRECTION_BASIS_CHOICES)
    stop(sprintf("DIRECTION_BASIS must be one of %s (got: %s)",
                 paste(DIRECTION_BASIS_CHOICES, collapse = "/"), paste(basis, collapse = ",")))
  if (basis == "slope") {
    x <- slopes$slope; thr <- flat_threshold
  } else {
    x <- compute_change_sd(slopes); thr <- sd_threshold
  }
  dplyr::case_when(!is.na(x) & x >  thr ~ "RISING",
                   !is.na(x) & x < -thr ~ "FALLING",
                   TRUE                 ~ "FLAT")
}

# Country-variable pairs whose reference distribution could not produce a z.
n_unscoreable <- function(scored) {
  sum(scored$n_ref < 2 | is.na(scored$sd_ref) | scored$sd_ref == 0)
}
