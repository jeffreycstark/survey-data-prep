# Paper 3 – Task 1: Bounds analysis on dem_country_future W6
# Insert as ```{r bounds-analysis} in paper3.qmd
# Scale: 1–10, higher = more optimistic about democratic future
# W3 baseline = 9.58 (75.8% response rate)
# W6: 63.1% nonresponse → robustness check

suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
})

w3 <- readRDS("outputs/master_w3.rds") |> filter(country == 12)
w6 <- readRDS("outputs/master_w6.rds") |> filter(country == 12)

n3_obs  <- sum(!is.na(w3$dem_country_future))
n3_na   <- sum(is.na(w3$dem_country_future))
w3_mean <- mean(w3$dem_country_future, na.rm = TRUE)

n6_total <- nrow(w6)
n6_obs   <- sum(!is.na(w6$dem_country_future))
n6_na    <- sum(is.na(w6$dem_country_future))
sum6_obs <- sum(w6$dem_country_future, na.rm = TRUE)
w6_obs_mean <- sum6_obs / n6_obs

# Three nonresponse scenarios
bounds <- tibble(
  scenario    = c("W3 baseline (observed)",
                  "W6 observed (respondents only)",
                  "W6 moderate (MAR — equals observed)",
                  "W6 pessimistic (NAs → 10)",
                  "W6 optimistic (NAs → 0)"),
  mean        = c(
    w3_mean,
    w6_obs_mean,
    (sum6_obs + n6_na * w6_obs_mean) / n6_total,  # = w6_obs_mean by definition
    (sum6_obs + n6_na * 10) / n6_total,
    (sum6_obs + n6_na * 0)  / n6_total
  ),
  decline_from_w3 = mean - w3_mean
)

# Key figures for inline text
# bounds$mean[4]  → pessimistic = 8.77 (still below W3 9.58)
# bounds$mean[5]  → optimistic  = 2.46
