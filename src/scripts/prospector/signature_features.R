# Feature builders for the Slope Prospector signature matcher.
suppressMessages({ library(tidyverse); library(strucchange) })

# Estimate the wave at which each significant break occurs.
augment_breaks_with_location <- function(eligible, sig_breaks) {
  targets <- eligible %>% semi_join(sig_breaks, by = c("country","variable"))
  if (nrow(targets) == 0)
    return(tibble(country=character(), variable=character(), break_wave=numeric()))
  targets %>%
    group_by(country, variable) %>%
    group_modify(~ {
      ts <- .x %>% arrange(wave_num)
      wave <- tryCatch({
        # NOTE: break_wave = NA means EITHER no break OR series too short to locate one
        # (breakpoints() with h=3 needs >= 6 observations); downstream `ordered` treats NA as non-firing.
        bp <- strucchange::breakpoints(mean_value ~ wave_num, data = ts, h = 3)
        idx <- bp$breakpoints
        if (length(idx) == 0 || all(is.na(idx))) NA_real_ else ts$wave_num[idx[1]]
      }, error = function(e) NA_real_)
      tibble(break_wave = wave)
    }) %>%
    ungroup()
}

# Build the enriched country×group feature frame: magnitude, shape,
# ends_level, and broke_at_wave, joined onto group_coherence.
build_group_features <- function(group_coherence, harmonized_data, acceleration,
                                 breaks_located, group_lookup, thr,
                                 var_curvature = NULL) {
  gc <- group_coherence %>% mutate(country = as.character(country))

  # magnitude
  gc <- gc %>% mutate(magnitude_tier = if_else(abs(mean_slope) > thr$FAST, "FAST", "SLOW"))

  # coherence (do members move together?) and volatility (do members change at
  # wildly different rates?) — both reuse columns group_coherence already has.
  # DIVERGENT means a GENUINE split: at least one member clearly rising AND at
  # least one clearly falling (past FLAT_THRESHOLD). This is deliberately
  # stricter than group_coherence$coherence_flag, whose all-same-sign test flags
  # DIVERGENT on tiny sign noise around zero and so fires almost everywhere.
  gc <- gc %>% mutate(
    coherence  = if_else(n_rising > 0 & n_falling > 0, "DIVERGENT", "COHERENT"),
    volatility = if_else(!is.na(sd_slope) & sd_slope > thr$VOLATILE, "VOLATILE", "STABLE")
  )

  # endpoint level: last-wave normalized value per member, averaged per group
  last_vals <- harmonized_data %>%
    mutate(country = as.character(country)) %>%
    group_by(country, variable) %>%
    slice_max(wave_num, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(country, variable, end_val = mean_value) %>%
    inner_join(group_lookup, by = "variable", relationship = "many-to-many") %>%
    group_by(country, group) %>%
    summarise(end_level = mean(end_val, na.rm = TRUE), .groups = "drop") %>%
    mutate(ends_level = case_when(end_level > thr$ENDS_HIGH ~ "HIGH",
                                  end_level < thr$ENDS_LOW  ~ "LOW",
                                  TRUE                      ~ "MID"))

  # shape: aggregate acceleration over group members with a quorum
  shape_tbl <- acceleration %>%
    mutate(country = as.character(country)) %>%
    inner_join(group_lookup, by = "variable", relationship = "many-to-many") %>%
    group_by(country, group) %>%
    summarise(
      rev_up   = mean(direction_change & early_slope <= 0 & late_slope > 0),
      rev_down = mean(direction_change & early_slope >= 0 & late_slope < 0),
      accel    = mean(!direction_change & abs(late_slope) > abs(early_slope)),
      decel    = mean(!direction_change & abs(late_slope) < abs(early_slope)),
      .groups = "drop"
    ) %>%
    mutate(shape = case_when(
      rev_up   >= thr$SHAPE_QUORUM ~ "REVERSED_UP",
      rev_down >= thr$SHAPE_QUORUM ~ "REVERSED_DOWN",
      accel    >= thr$SHAPE_QUORUM ~ "ACCELERATING",
      decel    >= thr$SHAPE_QUORUM ~ "DECELERATING",
      TRUE                         ~ "STEADY"
    )) %>%
    select(country, group, shape)

  # broke_at_wave: modal member break wave
  broke_tbl <- breaks_located %>%
    mutate(country = as.character(country)) %>%
    inner_join(group_lookup, by = "variable") %>%
    filter(!is.na(break_wave)) %>%
    group_by(country, group) %>%
    summarise(broke_at_wave = as.numeric(names(sort(table(break_wave), decreasing = TRUE))[1]),
              .groups = "drop")

  # curvature: fraction of ALL group members that show a significant quadratic
  # bend of a given sign (quad_term > 0 = CONVEX / U-shape; < 0 = CONCAVE / hump).
  # var_curvature is the per-variable `slopes` subset (country, variable,
  # quad_term, nonlinear); NULL -> every group defaults to LINEAR.
  curv_tbl <- if (!is.null(var_curvature) && nrow(var_curvature) > 0) {
    var_curvature %>%
      mutate(country = as.character(country)) %>%
      inner_join(group_lookup, by = "variable", relationship = "many-to-many") %>%
      group_by(country, group) %>%
      summarise(convex  = mean(nonlinear & quad_term > 0, na.rm = TRUE),
                concave = mean(nonlinear & quad_term < 0, na.rm = TRUE),
                .groups = "drop") %>%
      mutate(curvature = case_when(convex  >= thr$CURVE_QUORUM ~ "CONVEX",
                                   concave >= thr$CURVE_QUORUM ~ "CONCAVE",
                                   TRUE                        ~ "LINEAR")) %>%
      select(country, group, curvature)
  } else {
    tibble(country = character(), group = character(), curvature = character())
  }

  gc %>%
    left_join(last_vals  %>% select(country, group, ends_level), by = c("country","group")) %>%
    left_join(shape_tbl,  by = c("country","group")) %>%
    left_join(broke_tbl,  by = c("country","group")) %>%
    left_join(curv_tbl,   by = c("country","group")) %>%
    mutate(ends_level = replace_na(ends_level, "MID"),
           shape      = replace_na(shape, "STEADY"),
           curvature  = replace_na(curvature, "LINEAR"))
}
