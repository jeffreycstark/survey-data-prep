#' Tests for kipa_bribery_series()
#'
#' Run with:
#'   Rscript src/r/lookups/test_kipa_bribery_series.R
#'
#' Two test blocks:
#'   1. Synthetic check: a hand-built data frame with known yes/no/NA counts,
#'      confirming the unconditional (structural-zero) and conditional
#'      denominators are computed correctly, and that NA rows count toward the
#'      unconditional denominator but not the conditional one.
#'   2. Regression check against data/processed/kipa_corruption_harmonized.rds:
#'      anchor years (2004, 2016, 2019), the 2015->2016 gate behaviour, total
#'      yes across 2004-2021, and exclusion of the unmapped 2022-2023 waves.

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
})

source(here::here("src", "r", "lookups", "kipa_bribery_series.R"))

near <- function(a, b, tol = 0.01) isTRUE(abs(a - b) < tol)
fails <- 0
check <- function(label, ok) {
  cat(sprintf("  [%s] %s\n", if (ok) "PASS" else "FAIL", label))
  if (!ok) fails <<- fails + 1
}

cat("=== test 1: synthetic counts ===\n")
# Year 2016-style gated wave: 2 yes, 6 no, 12 NA (routed-out) => n = 20.
#   uncond = 2/20 = 10%;  cond = 2/(2+6) = 25%.
# Year 2010-style ungated wave: 1 yes, 9 no, 0 NA => n = 10.
#   uncond = cond = 10%.
synthetic <- tibble::tibble(
  year = c(rep(2016L, 20), rep(2010L, 10)),
  corr_bribery_experience_1yr = c(
    rep(1, 2), rep(2, 6), rep(NA_real_, 12),   # 2016
    1, rep(2, 9)                                # 2010
  )
)

res1 <- kipa_bribery_series(data = synthetic, max_year = 2021)
r2016 <- res1[res1$year == 2016, ]
r2010 <- res1[res1$year == 2010, ]

check("2016 n = 20 (full sample, NA counted)", r2016$n == 20)
check("2016 yes = 2",                          r2016$yes == 2)
check("2016 n_missing = 12",                   r2016$n_missing == 12)
check("2016 gated = TRUE",                     isTRUE(r2016$gated))
check("2016 uncond_pct = 10 (2/20)",           near(r2016$uncond_pct, 10))
check("2016 cond_pct = 25 (2/8)",              near(r2016$cond_pct, 25))
check("2010 gated = FALSE",                    isFALSE(r2010$gated))
check("2010 uncond == cond (ungated)",         near(r2010$uncond_pct, r2010$cond_pct))

cat("=== test 1b: custom var / year_col names ===\n")
synthetic_renamed <- synthetic |>
  dplyr::rename(yr = year, bribe = corr_bribery_experience_1yr)
res1b <- kipa_bribery_series(data = synthetic_renamed, var = "bribe", year_col = "yr")
check("custom names resolve (2016 uncond = 10)", near(res1b$uncond_pct[res1b$year == 2016], 10))
check("output year column always named 'year'",  "year" %in% names(res1b))

cat("=== test 2: regression vs harmonized RDS ===\n")
rds <- here::here("data", "processed", "kipa_corruption_harmonized.rds")
if (!file.exists(rds)) {
  cat("  [SKIP] harmonized RDS not present at", rds, "\n")
} else {
  s <- kipa_bribery_series()  # defaults: read RDS, max_year = 2021
  g <- function(y, col) s[[col]][s$year == y]

  check("2004 uncond = 13.80 (69/500, ungated)", near(g(2004, "uncond_pct"), 13.80))
  check("2004 uncond == cond (ungated)",         near(g(2004, "uncond_pct"), g(2004, "cond_pct")))
  check("2016 uncond = 1.60 (16/1000)",          near(g(2016, "uncond_pct"), 1.60))
  check("2016 cond  = 3.46 (16/462)",            near(g(2016, "cond_pct"), 3.46))
  check("2016 gate: cond > uncond (artifact)",   g(2016, "cond_pct") > g(2016, "uncond_pct"))
  check("2015 < 2016 on uncond (smooth decline)", g(2015, "uncond_pct") > g(2016, "uncond_pct"))
  check("2015 < 2016 on cond (spurious uptick)",  g(2016, "cond_pct") > g(2015, "cond_pct"))
  check("2019 uncond = 0.70 (7/1000)",           near(g(2019, "uncond_pct"), 0.70))
  check("2019 cond  = 1.55 (7/452)",             near(g(2019, "cond_pct"), 1.55))
  check("total yes 2004-2021 = 531",             sum(s$yes) == 531)
  check("2022-2023 excluded by default",         max(s$year) == 2021)
  check("all gated waves are 2016-2021",         all(s$year[s$gated] >= 2016))
}

cat(sprintf("\n%s — %d failure(s)\n", if (fails == 0) "ALL PASS" else "FAILURES", fails))
if (fails > 0) quit(status = 1)
