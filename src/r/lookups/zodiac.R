# Chinese zodiac assignment from CFPS birth year + month — paper-time lookup.
#
# Deliberately NOT baked into cfps_harmonized.rds (same policy as the party
# crosswalk): the analytic choice of how to treat lunar-boundary births belongs
# to the paper, not the data file.
#
# THE BOUNDARY PROBLEM. Zodiac years begin at Chinese New Year (late January to
# mid-February), not January 1. A birth in March-December of calendar year Y is
# unambiguously in Y's zodiac year. A birth in January or February of Y may
# belong to Y-1's animal, and resolving it needs the CNY date for Y AND the
# birth DAY — which the public CFPS files do not release (year + month only).
# So even with a CNY date table, a birth in the CNY month itself cannot be
# assigned. Policy here:
#
#   month 3-12          -> calendar-year animal (safe)
#   month 1-2 (or NA)   -> assigned by calendar year BUT flagged
#                          zodiac_boundary = TRUE (may be prior animal)
#
# Papers should run robustness with boundary births (i) excluded, (ii) assigned
# to Y, (iii) assigned to Y-1. For dragons specifically the exposure is births
# in Jan-Feb of dragon years (may be rabbits) and Jan-Feb of the FOLLOWING year
# (snakes-by-calendar who may be dragons); `dragon_boundary_wide` flags both.
#
# Animal cycle anchor: 1900 = Rat (子鼠). Dragon years: ..., 1952, 1964, 1976,
# 1988, 2000, 2012.

.ZODIAC_ANIMALS <- c("Rat", "Ox", "Tiger", "Rabbit", "Dragon", "Snake",
                     "Horse", "Goat", "Monkey", "Rooster", "Dog", "Pig")

#' Zodiac animal for a calendar year (ignoring the CNY boundary).
zodiac_of_year <- function(year) {
  idx <- ((as.integer(year) - 1900) %% 12) + 1
  .ZODIAC_ANIMALS[idx]
}

#' Add zodiac columns to a data frame with birth_year / birth_month columns.
#'
#' Adds:
#'   zodiac            calendar-year animal (chr)
#'   zodiac_boundary   TRUE when birth month is Jan/Feb or missing — the
#'                     calendar-year animal may be wrong by one
#'   dragon            1 if calendar-year animal is Dragon, else 0
#'   dragon_boundary_wide  TRUE for any birth that could plausibly be a Dragon
#'                     under the boundary: Jan-Feb (or NA-month) births in a
#'                     dragon year OR in the year after a dragon year
#'
#' @param df data frame (e.g. cfps_harmonized)
#' @param year_col,month_col column names (default CFPS harmonized names)
add_zodiac <- function(df,
                       year_col = "birth_year",
                       month_col = "birth_month") {
  by <- df[[year_col]]
  bm <- if (month_col %in% names(df)) df[[month_col]] else rep(NA_real_, nrow(df))

  zod <- ifelse(is.na(by), NA_character_, zodiac_of_year(by))
  boundary <- !is.na(by) & (is.na(bm) | bm <= 2)

  prev_is_dragon <- !is.na(by) & zodiac_of_year(by - 1) == "Dragon"

  df$zodiac <- zod
  df$zodiac_boundary <- boundary
  df$dragon <- ifelse(is.na(zod), NA_integer_, as.integer(zod == "Dragon"))
  df$dragon_boundary_wide <- boundary & (
    (!is.na(zod) & zod == "Dragon") | prev_is_dragon
  )
  df
}
