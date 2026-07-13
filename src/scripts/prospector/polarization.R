# ─────────────────────────────────────────────────────────────────────────────
# polarization.R — dispersion / polarization detection for the Slope Prospector.
#
# The prospector is otherwise MEANS-ONLY, so "the country's average held but its
# people pulled apart" is invisible. This module takes a long table that also
# carries a within-country-wave dispersion statistic (`sd_value`) and flags
# variables whose MEAN is flat/stable while their DISPERSION is rising
# (consensus fracturing) or falling (converging).
#
# detect_polarization(df, out_dir=, min_waves=, flat_threshold=) -> tibble
#   df needs: country, wave_num, variable, mean_value, sd_value [, n]
#   returns one row per country x variable with mean_slope, sd_slope, pattern
#   (POLARIZING | DEPOLARIZING | OTHER), and writes polarization.csv if out_dir.
# ─────────────────────────────────────────────────────────────────────────────
suppressMessages({ library(tidyverse); library(broom) })

# Per country x variable slope of `value_col`, on a per-variable min-max [0,1]
# normalization so slopes are scale-comparable (matches the prospector's own
# normalization). WLS by `n` when present.
.pol_slopes <- function(df, value_col, min_waves) {
  df %>%
    rename(v = {{ value_col }}) %>%
    group_by(variable) %>%
    mutate(lo = min(v, na.rm = TRUE), hi = max(v, na.rm = TRUE),
           v  = if_else(hi > lo, (v - lo) / (hi - lo), 0)) %>%
    ungroup() %>%
    group_by(country, variable) %>%
    filter(sum(!is.na(v)) >= min_waves) %>%
    group_modify(~ {
      w <- if ("n" %in% names(.x)) .x$n else NULL
      fit <- tryCatch(suppressWarnings(broom::tidy(lm(v ~ wave_num, data = .x, weights = w))),
                      error = function(e) tibble(term = character(), estimate = numeric()))
      s <- fit$estimate[fit$term == "wave_num"]
      tibble(slope = if (length(s) == 1) s else NA_real_)
    }) %>%
    ungroup()
}

detect_polarization <- function(df, out_dir = NULL, min_waves = 3, flat_threshold = 0.05) {
  stopifnot(all(c("country", "wave_num", "variable", "mean_value", "sd_value") %in% names(df)))

  mean_s <- .pol_slopes(df %>% select(country, wave_num, variable, mean_value, any_of("n")),
                        mean_value, min_waves) %>% rename(mean_slope = slope)
  sd_s   <- .pol_slopes(df %>% filter(!is.na(sd_value)) %>%
                          select(country, wave_num, variable, sd_value, any_of("n")),
                        sd_value, min_waves) %>% rename(sd_slope = slope)

  inner_join(mean_s, sd_s, by = c("country", "variable")) %>%
    filter(!is.na(mean_slope), !is.na(sd_slope)) %>%
    mutate(pattern = case_when(
      abs(mean_slope) <= flat_threshold & sd_slope >  flat_threshold ~ "POLARIZING",
      abs(mean_slope) <= flat_threshold & sd_slope < -flat_threshold ~ "DEPOLARIZING",
      TRUE                                                           ~ "OTHER"
    )) %>%
    arrange(desc(sd_slope)) -> out

  if (!is.null(out_dir)) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    write_csv(out, file.path(out_dir, "polarization.csv"))
  }
  out
}
