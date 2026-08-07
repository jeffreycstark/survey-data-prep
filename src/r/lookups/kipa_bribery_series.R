#' KIPA first-person bribery-experience series (gate-corrected)
#'
#' Returns the per-year rate for the harmonized KIPA Corruption Survey item
#' `corr_bribery_experience_1yr` ("in the past 12 months, did you give
#' money/goods/entertainment to a public official"), computed BOTH ways so the
#' caller cannot accidentally pick the wrong denominator:
#'
#'   * uncond_pct -- numerator = "yes", denominator = the FULL annual sample
#'     (routed-out and refusals treated as structural zeros: no official contact
#'     in the past year implies no bribe given to an official). This is the
#'     population rate, comparable to a full-sample measure such as the ABS
#'     witnessed-corruption item.
#'   * cond_pct -- numerator = "yes", denominator = answerers only (yes + no),
#'     i.e. the naive `mean(x == 1, na.rm = TRUE)`. From 2016 this is CONDITIONAL
#'     on official contact and is NOT comparable across the 2015/2016 boundary.
#'
#' WHY THIS HELPER EXISTS. From 2016 onward (all waves 2016-2021) KIPA routes the
#' bribery question only to respondents who passed a prior official-contact
#' screener; ~50% of the sample is skipped (비해당, stored as -1 -> NA in the
#' harmonized file, indistinguishable there from explicit refusals). The
#' conditional rate therefore runs ~2x the population rate from 2016 on and
#' injects a spurious uptick at the 2015->2016 gate (cond 1.90% -> 3.46% vs
#' uncond 1.90% -> 1.60%). A consumer who writes `mean(x == 1, na.rm = TRUE)`
#' silently gets the inflated, bumpy series. Always prefer uncond_pct for
#' trend/triangulation work. See the variable note in
#' src/config/kipa_corruption/harmonize/core_corruption.yml and
#' results/paper17_kipa_bribery_denominator.R for the underlying analysis.
#'
#' NOTE: KIPA is a specialty sample (corporate employees + self-employed with
#' regular government contact), so even uncond_pct is a within-specialty-frame
#' prevalence, not a general-population rate.

suppressPackageStartupMessages({
  library(dplyr)
  library(here)
})

#' @param data  Either a data frame containing `year` and
#'              `corr_bribery_experience_1yr`, or NULL to read the harmonized
#'              file from `harmonized_path`.
#' @param harmonized_path Path to kipa_corruption_harmonized.rds. Defaults to
#'              here("data/processed/kipa_corruption_harmonized.rds"). Only used
#'              when `data` is NULL.
#' @param var   String name of the bribery-experience column. Default
#'              "corr_bribery_experience_1yr".
#' @param year_col String name of the year column. Default "year".
#' @param max_year Highest wave to include. Default 2021 — the item was
#'              restructured in 2022 and is NA for 2022-2023 in the harmonized
#'              file, so they are excluded by default.
#'
#' @return A tibble, one row per year, with columns: year, n (full annual
#'         sample), yes, no, n_missing (routed-out + refusals), gated (logical),
#'         uncond_pct, cond_pct, and se_uncond (binomial SE of uncond_pct, in
#'         percentage points). Ordered by year. uncond_pct is the rate to use.
#'         The output year column is always named `year`, regardless of
#'         `year_col`.
#'
#'         `se_uncond` is the Wald SE; it degenerates toward 0 as the rate
#'         approaches 0 or 100 (the post-2016 rates sit near 0), so use a Wilson
#'         interval rather than uncond_pct ± 1.96·se_uncond if you need CIs there.
#'
#' @examples
#' \dontrun{
#' series <- kipa_bribery_series()
#' series[, c("year", "n", "yes", "uncond_pct", "cond_pct")]
#' }
kipa_bribery_series <- function(data = NULL,
                                harmonized_path = NULL,
                                var = "corr_bribery_experience_1yr",
                                year_col = "year",
                                max_year = 2021) {

  stopifnot(
    is.character(var),      length(var) == 1,
    is.character(year_col), length(year_col) == 1,
    is.numeric(max_year),   length(max_year) == 1
  )

  if (is.null(data)) {
    if (is.null(harmonized_path)) {
      harmonized_path <- here::here("data", "processed", "kipa_corruption_harmonized.rds")
    }
    if (!file.exists(harmonized_path)) {
      stop("kipa_bribery_series(): harmonized file not found at ", harmonized_path)
    }
    data <- readRDS(harmonized_path)
  }

  if (!is.data.frame(data)) {
    stop("kipa_bribery_series(): `data` must be a data frame or NULL.")
  }
  missing_cols <- setdiff(c(var, year_col), names(data))
  if (length(missing_cols) > 0) {
    stop("kipa_bribery_series(): data is missing column(s): ",
         paste(missing_cols, collapse = ", "))
  }

  out <- data |>
    filter(!is.na(.data[[year_col]]), .data[[year_col]] <= max_year) |>
    group_by(year = .data[[year_col]]) |>
    summarize(
      n         = dplyr::n(),
      yes       = sum(.data[[var]] == 1, na.rm = TRUE),
      no        = sum(.data[[var]] == 2, na.rm = TRUE),
      n_missing = sum(is.na(.data[[var]])),
      .groups   = "drop"
    ) |>
    mutate(
      gated      = n_missing > 0,
      uncond_pct = yes / n * 100,                  # structural-zero / population rate
      cond_pct   = ifelse(yes + no > 0, yes / (yes + no) * 100, NA_real_),
      se_uncond  = sqrt(uncond_pct * (100 - uncond_pct) / n)
    ) |>
    arrange(year)

  out
}
