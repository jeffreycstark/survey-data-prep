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

# ─────────────────────────────────────────────────────────────────────────────
# detect_sorting — subgroup-gap SORTING along a cleavage. Complements
# detect_polarization: instead of raw spread, it tracks the gap between two
# subgroups (e.g. high- vs low-education) and flags variables where that gap is
# WIDENING (sorting along the cleavage) or NARROWING (converging).
#
# gaps_df needs: country, wave_num, variable, gap [, n]
#   (gap = subgroup_high_mean - subgroup_low_mean, per country x wave x variable)
# returns one row per country x variable with gap_slope + pattern
# (WIDENING | NARROWING | OTHER); writes sorting.csv if out_dir.
# ─────────────────────────────────────────────────────────────────────────────
detect_sorting <- function(gaps_df, out_dir = NULL, min_waves = 3, flat_threshold = 0.05) {
  stopifnot(all(c("country", "wave_num", "variable", "gap") %in% names(gaps_df)))

  g <- gaps_df %>% filter(!is.na(gap)) %>% mutate(abs_gap = abs(gap))
  out <- .pol_slopes(g %>% select(country, wave_num, variable, abs_gap, any_of("n")),
                     abs_gap, min_waves) %>%
    rename(gap_slope = slope) %>%
    filter(!is.na(gap_slope)) %>%
    mutate(pattern = case_when(gap_slope >  flat_threshold ~ "WIDENING",
                               gap_slope < -flat_threshold ~ "NARROWING",
                               TRUE                        ~ "OTHER")) %>%
    arrange(desc(gap_slope))

  if (!is.null(out_dir)) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    write_csv(out, file.path(out_dir, "sorting.csv"))
  }
  out
}

# ─────────────────────────────────────────────────────────────────────────────
# Pass C2 — bimodality / two-camp split via van der Eijk's (2001) agreement A.
#
# .vdeijk_A(freq): A over K ordered categories (positions 1..K). +1 = all mass in
# one category (perfect agreement), 0 = uniform, -1 = 50/50 at the two extremes
# (perfect bimodal polarization). The distribution is peeled into layers (subtract
# the min occupied frequency each pass); each layer's binary presence pattern gets
#   A_layer = U * (1 - (S - 1)/(K - 1)),   0 if S == K,
# where S = occupied categories and U is the unimodality term counting, over all
# triples of positions a<b<c whose OUTER categories are both occupied, a present
# middle (tu) vs an absent middle / "dip" (tdu):
#   U = ((K-2)*tu - (K-1)*tdu) / ((K-2)*(tu+tdu)),   U = 1 when tu == tdu == 0.
# Layers are mass-weighted (m * S) and averaged. Verified against the +1/0/-1
# anchors on K=3 and K=4.
# ─────────────────────────────────────────────────────────────────────────────
.vdeijk_A <- function(freq) {
  freq <- as.numeric(freq)
  K <- length(freq)
  Ntot <- sum(freq)
  if (is.na(Ntot) || Ntot == 0) return(NA_real_)

  layer_A <- function(p) {                 # p: logical presence vector, length K
    S <- sum(p)
    if (S == K) return(0)
    idx <- which(p)
    tu <- 0L; tdu <- 0L
    for (a in idx) for (cc in idx[idx > a + 1L]) {
      for (b in (a + 1L):(cc - 1L)) if (p[b]) tu <- tu + 1L else tdu <- tdu + 1L
    }
    U <- if (tu == 0L && tdu == 0L) 1
         else ((K - 2) * tu - (K - 1) * tdu) / ((K - 2) * (tu + tdu))
    U * (1 - (S - 1) / (K - 1))
  }

  total <- 0; work <- freq
  while (any(work > 0)) {
    occ <- which(work > 0)
    m   <- min(work[occ])
    total <- total + layer_A(work > 0) * (m * length(occ))
    work[occ] <- work[occ] - m
  }
  total / Ntot
}
